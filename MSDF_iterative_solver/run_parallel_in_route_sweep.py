#!/usr/bin/env python3
"""Run U55C OOC route sweep for P3-SP/P4-SP standalone datapaths."""

from __future__ import annotations

import argparse
import os
import re
import subprocess
from dataclasses import dataclass
from pathlib import Path
from typing import Optional


ROOT = Path(__file__).resolve().parents[1]
ITER = ROOT / "MSDF_iterative_solver"
REPORT = ITER / "generated/parallel_in_route_sweep.md"
VIVADO_SETTINGS = "/tools/Xilinx/Vitis/2023.2/settings64.sh"
TCL = "MSDF_iterative_solver/synth_parallel_in_wavefront_top.tcl"


@dataclass
class RouteRow:
    kind: str
    k: int
    status: int
    log: str
    out_dir: Optional[str]
    wns: Optional[float]
    lut: Optional[float]
    ff: Optional[float]
    carry8: Optional[float]
    dsp: Optional[float]
    bram: Optional[float]
    dynamic_w: Optional[float]
    route_status: str
    first_error: str


def read_text(path: Path) -> str:
    return path.read_text(encoding="utf-8", errors="ignore") if path.exists() else ""


def extract_wns(text: str) -> Optional[float]:
    match = re.search(r"WNS\(ns\).*?\n\s*-+.*?\n\s*([+-]?\d+(?:\.\d+)?)", text, re.S)
    return float(match.group(1)) if match else None


def extract_util(text: str, name: str) -> Optional[float]:
    match = re.search(rf"\|\s*{re.escape(name)}\*?\s*\|\s*([0-9.]+)\s*\|", text)
    return float(match.group(1)) if match else None


def extract_power(text: str, name: str) -> Optional[float]:
    match = re.search(rf"\|\s*{re.escape(name)}\s*\|\s*([0-9.]+)", text)
    return float(match.group(1)) if match else None


def extract_out_dir(log_text: str) -> Optional[str]:
    matches = re.findall(r"OUT_DIR=(.+)", log_text)
    return matches[-1].strip() if matches else None


def extract_first_error(log_text: str) -> str:
    for line in log_text.splitlines():
        if "ERROR:" in line or "FATAL" in line:
            return line.strip()
    return ""


def extract_route_status(text: str) -> str:
    routed = re.search(r"# of fully routed nets\.+\s*:\s*(\d+)", text)
    errors = re.search(r"# of nets with routing errors\.+\s*:\s*(\d+)", text)
    if routed and errors:
        return f"fully routed={routed.group(1)}, errors={errors.group(1)}"
    return "NA"


def fmt(value: Optional[float], places: int = 3) -> str:
    if value is None:
        return "NA"
    if abs(value - round(value)) < 1e-9:
        return str(int(round(value)))
    return f"{value:.{places}f}"


def run_case(
    kind: str,
    k: int,
    clk_ns: float,
    degree: int,
    physical_degree: int,
    data_width: int,
    p3_bit_width: int,
    p4_bit_width: int,
) -> RouteRow:
    fast2_core = 1 if kind.endswith("fast2") else 0
    base_kind = kind[:-5] if fast2_core else kind
    if base_kind == "p3sp":
        top = "iter_parallel_in_online_mma8_global_wavefront_top"
    elif base_kind == "p3spfb":
        top = "iter_parallel_in_online_mma8_global_feedback_top"
    elif base_kind == "p4sp":
        top = "iter_parallel_in_conv_mma8_parallel_rows_top"
    else:
        raise ValueError(f"unknown kind {kind}")

    log_dir = ROOT / "logs"
    log_dir.mkdir(parents=True, exist_ok=True)
    est_selector = os.environ.get("MSDF_EST_SELECTOR", "0")
    est_frac_bits = os.environ.get("MSDF_EST_FRAC_BITS", "6")
    est_guard_bits = os.environ.get("MSDF_EST_GUARD_BITS", "2")
    split_estimate = os.environ.get("MSDF_SPLIT_ESTIMATE", "1")
    redundant_residual = os.environ.get("MSDF_REDUNDANT_RESIDUAL", "0")
    nonnegative_coeff = os.environ.get("MSDF_NONNEGATIVE_COEFF", "0")
    nonnegative_bias = os.environ.get("MSDF_NONNEGATIVE_BIAS", "0")
    grouped_stage_broadcast = os.environ.get("MSDF_GROUPED_STAGE_BROADCAST", "0")
    source_onehot = os.environ.get("MSDF_SOURCE_ONEHOT", "0")
    est_tag = ""
    if est_selector != "0":
        est_tag = f"_est{est_frac_bits}g{est_guard_bits}"
        if split_estimate == "0":
            est_tag += "_exactu"
    if redundant_residual != "0":
        est_tag += "_red"
    if nonnegative_coeff != "0":
        est_tag += "_nonneg"
    if nonnegative_bias != "0":
        est_tag += "_nonnegbias"
    if grouped_stage_broadcast != "0":
        est_tag += "_gbcast"
    if source_onehot != "0":
        est_tag += "_onehot"
    run_tag = (
        f"{kind}_k{k}_deg{degree}_pdeg{physical_degree}_"
        f"data{data_width}_u55c_clk{clk_ns:.3f}_route1_mt2{est_tag}"
    )
    log_path = log_dir / f"parallel_in_route_{run_tag}.log"
    env = os.environ.copy()
    env.update({
        "MSDF_TOP_KIND": base_kind,
        "MSDF_TOP": top,
        "MSDF_NUM_STAGES": str(k),
        "MSDF_DEGREE": str(degree),
        "MSDF_PHYSICAL_DEGREE": str(physical_degree),
        "MSDF_BIT_WIDTH": str(p3_bit_width if base_kind in {"p3sp", "p3spfb"} else p4_bit_width),
        "MSDF_DATA_WIDTH": str(data_width),
        "MSDF_BIAS_WIDTH": str(data_width),
        "MSDF_ACC_WIDTH": "64" if base_kind == "p3spfb" else ("33" if base_kind == "p3sp" else "40"),
        "MSDF_CORE_ACC_WIDTH": os.environ.get("MSDF_CORE_ACC_WIDTH", "33"),
        "MSDF_FAST2_CORE": str(fast2_core),
        "MSDF_EST_SELECTOR": est_selector,
        "MSDF_EST_FRAC_BITS": est_frac_bits,
        "MSDF_EST_GUARD_BITS": est_guard_bits,
        "MSDF_SPLIT_ESTIMATE": split_estimate,
        "MSDF_REDUNDANT_RESIDUAL": redundant_residual,
        "MSDF_NONNEGATIVE_COEFF": nonnegative_coeff,
        "MSDF_NONNEGATIVE_BIAS": nonnegative_bias,
        "MSDF_GROUPED_STAGE_BROADCAST": grouped_stage_broadcast,
        "MSDF_SOURCE_ONEHOT": source_onehot,
        "MSDF_SKIP_SYNTH_REPORTS": "1",
        "MSDF_VIVADO_MAX_THREADS": os.environ.get("MSDF_VIVADO_MAX_THREADS", "2"),
        "MSDF_PLACE_DIRECTIVE": os.environ.get("MSDF_PLACE_DIRECTIVE", ""),
        "MSDF_ROUTE_DIRECTIVE": os.environ.get("MSDF_ROUTE_DIRECTIVE", ""),
        "MSDF_POST_ROUTE_PHYS_OPT_DIRECTIVE": os.environ.get(
            "MSDF_POST_ROUTE_PHYS_OPT_DIRECTIVE", "AggressiveExplore"
        ),
        "MSDF_FEEDBACK_FIFO_DEPTH": os.environ.get("MSDF_FEEDBACK_FIFO_DEPTH", "32"),
        "MSDF_PRODUCT_WIDTH": str(data_width + p4_bit_width + 2),
        "MSDF_PRODUCT_SHIFT": str(data_width),
        "MSDF_RUN_ROUTE": "1",
        "MSDF_OOC": "1",
        "MSDF_CLK_PERIOD_NS": f"{clk_ns:.3f}",
        "MSDF_PART": "xcu55c-fsvh2892-2L-e",
        "MSDF_RUN_TAG": run_tag,
    })

    cmd = f"source {VIVADO_SETTINGS} && vivado -mode batch -source {TCL}"
    with log_path.open("w", encoding="utf-8") as log_fp:
        proc = subprocess.run(
            ["bash", "-lc", cmd],
            cwd=ROOT,
            env=env,
            stdout=log_fp,
            stderr=subprocess.STDOUT,
            text=True,
        )

    log_text = read_text(log_path)
    out_dir_text = extract_out_dir(log_text)
    out_dir = Path(out_dir_text) if out_dir_text else None
    timing = read_text(out_dir / "timing_summary_routed.rpt") if out_dir else ""
    util = read_text(out_dir / "utilization_routed.rpt") if out_dir else ""
    power = read_text(out_dir / "power_routed.rpt") if out_dir else ""
    route = read_text(out_dir / "route_status_routed.rpt") if out_dir else ""

    return RouteRow(
        kind=kind,
        k=k,
        status=proc.returncode,
        log=str(log_path),
        out_dir=str(out_dir) if out_dir else None,
        wns=extract_wns(timing),
        lut=extract_util(util, "CLB LUTs"),
        ff=extract_util(util, "CLB Registers"),
        carry8=extract_util(util, "CARRY8"),
        dsp=extract_util(util, "DSPs"),
        bram=extract_util(util, "Block RAM Tile"),
        dynamic_w=extract_power(power, "Dynamic (W)"),
        route_status=extract_route_status(route),
        first_error=extract_first_error(log_text),
    )


def write_report(rows: list[RouteRow], clk_ns: float) -> None:
    REPORT.parent.mkdir(parents=True, exist_ok=True)
    lines: list[str] = [
        "# Parallel-In P3-SP/P4-SP U55C Route Sweep",
        "",
        f"Vivado/Vitis: `2023.2`; part: `xcu55c-fsvh2892-2L-e`; clock target: `{clk_ns:.3f} ns`.",
        "This is a standalone OOC route sweep for the P3-SP wavefront/feedback datapaths and the P4-SP one-stage conventional baseline.",
        "Current P3-SP default contract is `DATA_WIDTH=32`, `BIT_WIDTH=30`, `BIAS_WIDTH=32`, `ACC_WIDTH=33`, `ONLINE_DELAY=2`.",
        "Current P3-SP feedback kind is `p3spfb`: same four-stage online wavefront plus feedback FIFO and `L∞ <= 1 LSB` termination datapath.",
        "Current P4-SP baseline is one-stage conventional: `32` row lanes in parallel, `8` full-word MAC slots per row, no K-stage physical expansion, `DATA_WIDTH=32`, `ACC_WIDTH=40`, `PRODUCT_WIDTH=66`, `PRODUCT_SHIFT=32`.",
        "",
        "| kind | K | status | WNS ns | LUT | FF | CARRY8 | DSP | BRAM | Dynamic W | route status | log |",
        "| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | --- | --- |",
    ]
    for row in rows:
        lines.append(
            f"| {row.kind} | {row.k} | {row.status} | {fmt(row.wns)} | "
            f"{fmt(row.lut)} | {fmt(row.ff)} | {fmt(row.carry8)} | {fmt(row.dsp)} | "
            f"{fmt(row.bram)} | {fmt(row.dynamic_w)} | {row.route_status} | `{row.log}` |"
        )

    failures = [row for row in rows if row.status != 0 or row.first_error]
    if failures:
        lines += ["", "## Failures", ""]
        for row in failures:
            lines.append(f"- `{row.kind} K={row.k}` status `{row.status}`: {row.first_error or 'see log'}")

    lines += [
        "",
        "## Notes",
        "",
        "- P3-SP keeps state as MSB-first digit stream and has one online stage per K level.",
        "- P3-SP currently keeps direct stage-to-stage digit cascading, uses a contribution register before residual update, and implements contribution as an explicit balanced tree.",
        "- P4-SP is no longer the historical same-shape full-unrolled wavefront.  It is a one-stage conventional baseline: 32 rows run in parallel and each row has eight full-word MAC slots.",
        "- The P4-SP route entry therefore measures a one-iteration 32-row datapath, not a K-stage wavefront.",
        "- `p3spfb` includes feedback FIFO and Linf certification control; `p3sp` intentionally excludes them.",
        "- This report intentionally excludes runtime loader and external state memory.",
        "",
    ]
    REPORT.write_text("\n".join(lines), encoding="utf-8")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--stages", type=int, nargs="+", default=[4])
    parser.add_argument("--kinds", nargs="+", default=["p3sp", "p4sp"])
    parser.add_argument("--clk-ns", type=float, default=5.0)
    parser.add_argument("--degree", type=int, default=4)
    parser.add_argument("--physical-degree", type=int, default=8)
    parser.add_argument("--data-width", type=int, default=32)
    parser.add_argument("--p3-bit-width", type=int, default=30)
    parser.add_argument("--p4-bit-width", type=int, default=32)
    args = parser.parse_args()

    rows: list[RouteRow] = []
    for kind in args.kinds:
        for k in args.stages:
            row = run_case(
                kind=kind,
                k=k,
                clk_ns=args.clk_ns,
                degree=args.degree,
                physical_degree=args.physical_degree,
                data_width=args.data_width,
                p3_bit_width=args.p3_bit_width,
                p4_bit_width=args.p4_bit_width,
            )
            rows.append(row)
            write_report(rows, clk_ns=args.clk_ns)
            print(
                f"{kind} K={k} status={row.status} "
                f"WNS={fmt(row.wns)} LUT={fmt(row.lut)} FF={fmt(row.ff)} DSP={fmt(row.dsp)}"
            )

    write_report(rows, clk_ns=args.clk_ns)
    print(f"Wrote {REPORT}")


if __name__ == "__main__":
    main()
