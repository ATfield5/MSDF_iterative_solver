#!/usr/bin/env python3
"""Assemble paper-facing reports from existing parallel-in experiment outputs."""

from __future__ import annotations

import csv
import json
import re
import subprocess
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[1]
ITER = ROOT / "MSDF_iterative_solver"
GEN = ITER / "generated"

CORRECTNESS_MD = GEN / "parallel_in_correctness_sweep.md"
CORRECTNESS_JSON = GEN / "parallel_in_correctness_sweep.json"
CYCLE_MD = GEN / "parallel_in_cycle_ablation.md"
CYCLE_JSON = GEN / "parallel_in_cycle_ablation.json"
CYCLE_CSV = GEN / "parallel_in_cycle_ablation.csv"
ROUTE_MD = GEN / "parallel_in_routed_main_results.md"
ROUTE_JSON = GEN / "parallel_in_routed_main_results.json"
FAIRNESS_MD = GEN / "paper_baseline_fairness_table.md"
FAIRNESS_JSON = GEN / "paper_baseline_fairness_table.json"

CLOCK_HZ = 200_000_000.0


def read_text(path: Path) -> str:
    return path.read_text(encoding="utf-8", errors="ignore") if path.exists() else ""


def git_commit() -> str:
    try:
        return subprocess.run(["git", "rev-parse", "HEAD"], cwd=ROOT, check=True, capture_output=True, text=True).stdout.strip()
    except Exception:
        return "unknown"


def extract_first(pattern: str, text: str, default: Any = None, flags: int = 0) -> Any:
    match = re.search(pattern, text, flags)
    if not match:
        return default
    if len(match.groups()) == 1:
        return match.group(1)
    return match.groups()


def extract_wns(text: str) -> float | None:
    value = extract_first(r"WNS\(ns\).*?\n\s*-+.*?\n\s*([+-]?\d+(?:\.\d+)?)", text, None, re.S)
    return float(value) if value is not None else None


def extract_util(text: str, name: str) -> float | None:
    value = extract_first(rf"\|\s*{re.escape(name)}\*?\s*\|\s*([0-9.]+)\s*\|", text)
    return float(value) if value is not None else None


def extract_power(text: str) -> float | None:
    value = extract_first(r"\|\s*Dynamic \(W\)\s*\|\s*([0-9.]+)", text)
    return float(value) if value is not None else None


def fmt(value: Any, places: int = 3) -> str:
    if value is None:
        return "NA"
    if isinstance(value, float):
        if abs(value - round(value)) < 1e-9:
            return str(int(round(value)))
        return f"{value:.{places}f}"
    return str(value)


def vivado_metrics(label: str, out_dir: str, kind: str, routed: bool) -> dict[str, Any]:
    base = GEN / out_dir
    timing = read_text(base / ("timing_summary_routed.rpt" if routed else "timing_summary_synth.rpt"))
    util = read_text(base / ("utilization_routed.rpt" if routed else "utilization_synth.rpt"))
    power = read_text(base / ("power_routed.rpt" if routed else "power_synth.rpt"))
    if not timing and routed:
        timing = read_text(base / "timing_summary_synth.rpt")
    if not util and routed:
        util = read_text(base / "utilization_synth.rpt")
    if not power and routed:
        power = read_text(base / "power_synth.rpt")
    wns_ns = extract_wns(timing)
    if routed and wns_ns is not None:
        result_type = "routed-pass" if wns_ns >= 0.0 else "routed-fail"
    else:
        result_type = "routed" if routed else "synth-only"
    return {
        "label": label,
        "kind": kind,
        "result_type": result_type,
        "out_dir": str(base),
        "exists": base.exists(),
        "wns_ns": wns_ns,
        "lut": extract_util(util, "CLB LUTs"),
        "ff": extract_util(util, "CLB Registers"),
        "carry8": extract_util(util, "CARRY8"),
        "dsp": extract_util(util, "DSPs"),
        "bram": extract_util(util, "Block RAM Tile"),
        "dynamic_w": extract_power(power),
    }


def parse_cycle_inputs() -> dict[str, Any]:
    parallel_md = read_text(GEN / "parallel_in_fractional_eval.md")
    dense_md = read_text(GEN / "parallel_in_dense32_eval.md")
    prior32_md = read_text(GEN / "prior_fractional_wavefront_deg32_bw29_sweep.md")
    cpu_json_path = GEN / "numpy_pagerank_cpu_32thread_benchmark.json"
    cpu = json.loads(cpu_json_path.read_text()) if cpu_json_path.exists() else {}

    online_total = int(extract_first(r"\| P3-SP parallel-in online wavefront \| yes \| [^|]+ \| (\d+) \|", parallel_md, 0))
    feedback_groups = extract_first(
        r"\| P3-SP feedback loop pipeline \| yes \| [^|]+ \| (\d+) \| (\d+) supersteps / (\d+) final-stage digits",
        parallel_md,
        (0, 0, 0),
    )
    p4_groups = extract_first(
        r"\| P4-SP conventional 32-row parallel DSP-MAC \| yes \| (\d+) feedback iterations.*?\| (\d+) \|",
        parallel_md,
        (0, 0),
    )
    p4_deg8_groups = extract_first(
        r"\| P4-SP conventional degree8 32-row parallel DSP-MAC \| yes \| (\d+) feedback iterations.*?\| (\d+) \|",
        parallel_md,
        (0, 0),
    )
    prior_groups = extract_first(r"\| 4 \| (\d+) \| 32 \| ([0-9.]+) \|", prior32_md, (0, 0.0))
    dense_total = int(extract_first(r"\| total cycles \| (\d+) \|", dense_md, 0))
    dense_supersteps = int(extract_first(r"\| final supersteps \| (\d+) \|", dense_md, 0))

    return {
        "online_total": online_total,
        "feedback_total": int(feedback_groups[0]),
        "feedback_supersteps": int(feedback_groups[1]),
        "feedback_capture": int(feedback_groups[2]),
        "p4_iterations": int(p4_groups[0]),
        "p4_total": int(p4_groups[1]),
        "p4_deg8_iterations": int(p4_deg8_groups[0]),
        "p4_deg8_total": int(p4_deg8_groups[1]),
        "prior32_total": int(prior_groups[0]),
        "prior32_cycles_per_iter": float(prior_groups[1]),
        "dense_total": dense_total,
        "dense_supersteps": dense_supersteps,
        "cpu": cpu,
    }


def cycle_row(name: str, scope: str, degree: int, iterations: int, cycles: float, status: str) -> dict[str, Any]:
    cycles_per_iter = cycles / iterations if iterations else None
    term_ops_per_iter = 32 * degree
    if cycles_per_iter:
        iterations_per_s = CLOCK_HZ / cycles_per_iter
        term_ops_per_s = iterations_per_s * term_ops_per_iter
    else:
        iterations_per_s = None
        term_ops_per_s = None
    return {
        "name": name,
        "scope": scope,
        "degree": degree,
        "iterations": iterations,
        "cycles": cycles,
        "cycles_per_iter": cycles_per_iter,
        "iterations_per_s_at_200mhz": iterations_per_s,
        "term_ops_per_s_at_200mhz": term_ops_per_s,
        "gterm_ops_per_s_at_200mhz": term_ops_per_s / 1e9 if term_ops_per_s is not None else None,
        "status": status,
    }


def write_correctness_report(cycle_inputs: dict[str, Any]) -> None:
    parallel_md = read_text(GEN / "parallel_in_fractional_eval.md")
    bound_json = json.loads((GEN / "parallel_in_bound_sweep.json").read_text()) if (GEN / "parallel_in_bound_sweep.json").exists() else {"rows": []}
    drift = extract_first(r"\| max absolute raw-state drift \| (\d+) \|", parallel_md, "NA")
    sum_drift = extract_first(r"\| sum absolute raw-state drift \| (\d+) \|", parallel_md, "NA")
    rows = [
        {"entry": "P2 parallel-in online wavefront", "status": "PASS" if "PASS tb_iter_parallel_in_online_mma8_global_wavefront_top" in parallel_md else "UNKNOWN", "evidence": "parallel_in_fractional_eval.md"},
        {"entry": "P3 feedback loop", "status": "PASS" if "PASS tb_iter_parallel_in_online_mma8_global_feedback_top" in parallel_md else "UNKNOWN", "evidence": "parallel_in_fractional_eval.md"},
        {"entry": "P4 conventional DSP-MAC", "status": "PASS" if "PASS tb_iter_parallel_in_conv_mma8_parallel_rows_top" in parallel_md else "UNKNOWN", "evidence": "parallel_in_fractional_eval.md"},
        {"entry": "E1 bound sweep", "status": "PASS" if bound_json.get("rows") and all(row.get("valid") for row in bound_json["rows"]) else "CHECK", "evidence": "parallel_in_bound_sweep.json"},
    ]
    payload = {
        "git_commit": git_commit(),
        "scope": "RTL/model correctness summary",
        "p3_vs_p4_max_abs_raw": drift,
        "p3_vs_p4_sum_abs_raw": sum_drift,
        "rows": rows,
    }
    CORRECTNESS_JSON.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n")
    lines = [
        "# Parallel-In Correctness Sweep",
        "",
        "Purpose: collect paper-facing PASS/fail status for P2/P3/P4 and the bound sweep.",
        "This report is not a routed resource report.",
        "",
        f"- git commit: `{payload['git_commit']}`",
        f"- P3/P4 model max absolute raw-state drift: `{drift}`",
        f"- P3/P4 model sum absolute raw-state drift: `{sum_drift}`",
        "",
        "| entry | status | evidence |",
        "| --- | --- | --- |",
    ]
    for row in rows:
        lines.append(f"| {row['entry']} | {row['status']} | `{row['evidence']}` |")
    lines += [
        "",
        "The drift row compares generated P3 signed-digit model output with the generated conventional fixed-point model in the same fixture.  The P4 RTL test compares against `conv_gold_state_*` directly.",
        "",
    ]
    CORRECTNESS_MD.write_text("\n".join(lines))


def write_cycle_report(cycle_inputs: dict[str, Any]) -> list[dict[str, Any]]:
    rows = [
        cycle_row("P1 native serial-serial prior32", "measured RTL sim, standalone K=4", 32, 4, cycle_inputs["prior32_total"], "PASS; not routed; native32 synth exceeds U55C LUT budget"),
        cycle_row("P2 parallel-in online wavefront", "measured RTL sim, degree4 default", 4, 4, cycle_inputs["online_total"], "PASS"),
        cycle_row("P3 parallel-in feedback", "measured RTL sim, degree4 default", 4, 4 * cycle_inputs["feedback_supersteps"], cycle_inputs["feedback_total"], "PASS"),
        cycle_row("P3 dense32 feedback", "measured RTL sim + synth-only resource", 32, 4 * cycle_inputs["dense_supersteps"], cycle_inputs["dense_total"], "PASS; synth-only"),
        cycle_row("P4 conventional DSP-MAC", "measured RTL sim, one-stage degree4/physical8", 4, cycle_inputs["p4_iterations"], cycle_inputs["p4_total"], "PASS; not same physical wavefront shape"),
        cycle_row("P4 conventional DSP-MAC degree8/physical8", "measured RTL sim, one-stage degree8/physical8", 8, cycle_inputs["p4_deg8_iterations"], cycle_inputs["p4_deg8_total"], "PASS; same 8-MAC/row physical datapath as routed P4 degree8"),
    ]
    cpu = cycle_inputs["cpu"]
    if cpu:
        rows.append({
            "name": "CPU NumPy/OpenBLAS 32-thread",
            "scope": "CPU measured kernel",
            "degree": 32,
            "iterations": "measured",
            "cycles": "NA",
            "cycles_per_iter": "NA",
            "iterations_per_s_at_200mhz": cpu.get("kernel_iterations_per_s"),
            "term_ops_per_s_at_200mhz": cpu.get("kernel_term_ops_per_s"),
            "gterm_ops_per_s_at_200mhz": cpu.get("kernel_gterm_ops_per_s"),
            "status": "software reference; no FPGA resource comparison",
        })

    payload = {
        "git_commit": git_commit(),
        "clock_hz_for_hw_cycle_model": CLOCK_HZ,
        "rows": rows,
    }
    CYCLE_JSON.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n")
    with CYCLE_CSV.open("w", newline="", encoding="utf-8") as fp:
        writer = csv.DictWriter(fp, fieldnames=list(rows[0].keys()), lineterminator="\n")
        writer.writeheader()
        writer.writerows(rows)

    lines = [
        "# Parallel-In Cycle And Throughput Ablation",
        "",
        "Purpose: collect the current cycle/throughput evidence for P1-P4 and CPU.",
        "Rows marked `synth-only` or `CPU measured` must not be mixed with routed FPGA rows.",
        "",
        f"- git commit: `{payload['git_commit']}`",
        f"- hardware cycle-model clock: `{CLOCK_HZ/1e6:.0f} MHz`",
        "",
        "| entry | scope | degree | iterations | cycles | cycles/iter | iter/s @200MHz | Gterm/s @200MHz | status |",
        "| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | --- |",
    ]
    for row in rows:
        lines.append(
            f"| {row['name']} | {row['scope']} | {row['degree']} | {row['iterations']} | "
            f"{fmt(row['cycles'])} | {fmt(row['cycles_per_iter'])} | "
            f"{fmt(row['iterations_per_s_at_200mhz'])} | {fmt(row['gterm_ops_per_s_at_200mhz'])} | {row['status']} |"
        )
    lines += [
        "",
        "Interpretation:",
        "",
        "- P1 and dense32 P3 are the direct dense 32-term operator scalability rows.",
        "- P4 is a conventional DSP-MAC arithmetic baseline, but the current route-clean row is a one-stage datapath rather than a K-stage online wavefront.",
        "- CPU is measured software throughput and is included only as an application reference.",
        "",
    ]
    CYCLE_MD.write_text("\n".join(lines))
    return rows


def write_route_report() -> list[dict[str, Any]]:
    rows = [
        vivado_metrics("P1 native prior32", "vivado_prior32_native_k4_rows32_deg32_bw29_data32_synth", "native serial-serial 32-input online", False),
        vivado_metrics("P2 p3sp K4 degree4/physical8", "vivado_parallel_in_wavefront_p3sp_k4_u55c_clk5.000_route1", "parallel-in wavefront", True),
        vivado_metrics("P2 p3sp K4 degree8/physical8", "vivado_parallel_in_wavefront_p3sp_k4_deg8_pdeg8_data32_synth", "parallel-in wavefront degree8 trend", False),
        vivado_metrics("P2 p3sp K4 degree8/physical8 routed probe", "vivado_parallel_in_wavefront_p3sp_k4_deg8_pdeg8_data32_u55c_clk5.000_route1_mt2", "parallel-in wavefront degree8 trend", True),
        vivado_metrics("P2 p3sp K4 degree8/physical8 nonnegative+maxfanout", "vivado_parallel_in_wavefront_p3sp_k4_deg8_pdeg8_data32_nonneg_mf_route", "parallel-in wavefront degree8 optimized", True),
        vivado_metrics("P3 p3sp feedback route-clean", "vivado_parallel_in_wavefront_p3spfb_k4_4cycle_fifo32_core33_route", "parallel-in feedback", True),
        vivado_metrics("P3 dense32 feedback", "vivado_parallel_in_wavefront_p3spfbfast2_k4_deg32_pdeg32_u55c_synth", "dense32 parallel-in feedback", False),
        vivado_metrics("P4 conventional one-stage", "vivado_parallel_in_wavefront_p4sp_k4_u55c_clk5.000_route1", "conventional DSP-MAC", True),
        vivado_metrics("P4 conventional degree8/physical8 one-stage", "vivado_parallel_in_wavefront_p4sp_k4_deg8_pdeg8_data32_u55c_clk5.000_route1_mt2", "conventional DSP-MAC degree8", True),
    ]
    payload = {
        "git_commit": git_commit(),
        "device": "xcu55c-fsvh2892-2L-e",
        "vivado": "2023.2",
        "clock_target_ns": 5.0,
        "rows": rows,
    }
    incomplete_logs = []
    for log_path in sorted((ROOT / "logs").glob("parallel_in_route_p3sp_k4_deg8_pdeg8_data32_u55c_clk5.000_route1_mt2*.log")):
        log_text = read_text(log_path)
        if "OUT_DIR=" not in log_text:
            tail_lines = [line for line in log_text.strip().splitlines()[-8:] if line.strip()]
            observed_wns = re.findall(r"WNS=([+-]?\d+(?:\.\d+)?)", log_text)
            incomplete_logs.append({
                "log": str(log_path),
                "last_observed_wns_ns": float(observed_wns[-1]) if observed_wns else None,
                "last_lines": tail_lines,
            })
    payload["incomplete_route_probes"] = incomplete_logs
    ROUTE_JSON.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n")
    lines = [
        "# Parallel-In Routed Main Results",
        "",
        "Purpose: collect current U55C implementation evidence.  This report separates routed rows from synth-only rows.",
        "",
        f"- git commit: `{payload['git_commit']}`",
        "- device: `xcu55c-fsvh2892-2L-e`",
        "- Vivado/Vitis: `2023.2`",
        "- clock target: `5 ns`",
        "",
        "| entry | type | result | WNS ns | LUT | FF | CARRY8 | DSP | BRAM | Dynamic W | out dir |",
        "| --- | --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | --- |",
    ]
    for row in rows:
        lines.append(
            f"| {row['label']} | {row['kind']} | {row['result_type']} | {fmt(row['wns_ns'])} | "
            f"{fmt(row['lut'])} | {fmt(row['ff'])} | {fmt(row['carry8'])} | {fmt(row['dsp'])} | "
            f"{fmt(row['bram'])} | {fmt(row['dynamic_w'])} | `{row['out_dir']}` |"
        )
    lines += [
        "",
        "Paper-use rules:",
        "",
        "- `routed-pass` rows can enter hardware implementation tables.",
        "- `routed-fail` rows are implementation evidence but cannot be used as timing-clean main results.",
        "- Synth-only rows can only support scalability/resource-trend claims.",
        "- Dense32 P3 is not a routed timing claim yet.",
        "- P1 native prior32 exceeds the U55C LUT budget in synthesis and should not be routed as a main result.",
        "",
    ]
    if incomplete_logs:
        lines += [
            "## Incomplete Route Probes",
            "",
            "The following long route probes were started but did not reach a reportable `OUT_DIR=` summary.  They are recorded for traceability and are not used in the routed result table.",
            "",
        ]
        for item in incomplete_logs:
            lines.append(f"- `{item['log']}`; last observed WNS: `{fmt(item.get('last_observed_wns_ns'))} ns`")
            if item["last_lines"]:
                lines.append("")
                lines.append("```text")
                lines.extend(item["last_lines"])
                lines.append("```")
                lines.append("")
    ROUTE_MD.write_text("\n".join(lines))
    return rows


def write_fairness_report(cycle_rows: list[dict[str, Any]], route_rows: list[dict[str, Any]]) -> None:
    route_by_label = {row["label"]: row for row in route_rows}
    cycle_by_name = {row["name"]: row for row in cycle_rows}

    def route_brief(label: str) -> str:
        row = route_by_label.get(label)
        if not row:
            return "not available"
        return (
            f"{row['result_type']} WNS {fmt(row['wns_ns'])} ns / "
            f"{fmt(row['lut'])} LUT / {fmt(row['ff'])} FF / {fmt(row['dsp'])} DSP"
        )

    def cpu_brief() -> str:
        row = cycle_by_name.get("CPU NumPy/OpenBLAS 32-thread")
        if not row or not isinstance(row.get("iterations_per_s_at_200mhz"), (int, float)):
            return "not available"
        return f"kernel {row['iterations_per_s_at_200mhz'] / 1e6:.3f} Miter/s on Ryzen 9 9950X"

    rows = [
        {
            "id": "P0",
            "entry": "Original paper integrated online inner product",
            "scope": "operator-level only",
            "primary_data": "n=32,m=32: integrated 10194 LUT / 6153 FF; cascaded 11195 LUT / 7202 FF",
            "paper_use": "prior-work reference; not directly comparable to full wavefront/runtime top",
        },
        {
            "id": "P1",
            "entry": "Native serial-serial 32-input online operator",
            "scope": "same-repo prior-style scalability baseline",
            "primary_data": "K=4 degree32 DATA_WIDTH=32: 86 cycles; synth 1,438,937 LUT / 782,614 FF / 0 DSP",
            "paper_use": "shows direct native32 scaling is resource-infeasible on U55C",
        },
        {
            "id": "P2",
            "entry": "Parallel-in online affine operator",
            "scope": "operator/wavefront",
            "primary_data": (
                "degree4 K=4: 50 cycles; "
                f"{route_brief('P2 p3sp K4 degree4/physical8')}; "
                f"degree8 optimized: {route_brief('P2 p3sp K4 degree8/physical8 nonnegative+maxfanout')}"
            ),
            "paper_use": "operator contribution and online-delay reduction evidence",
        },
        {
            "id": "P3",
            "entry": "Parallel-in digit-wavefront / feedback",
            "scope": "wavefront-level",
            "primary_data": (
                f"degree4 feedback: {route_brief('P3 p3sp feedback route-clean')}; "
                "dense32 88 cycles/8 iter synth-only"
            ),
            "paper_use": "main architecture contribution; dense32 needs route before timing claim",
        },
        {
            "id": "P4",
            "entry": "Conventional DSP-MAC affine baseline",
            "scope": "hardware arithmetic baseline",
            "primary_data": f"one-stage 32-row x 8-MAC degree8/physical8: {route_brief('P4 conventional degree8/physical8 one-stage')}",
            "paper_use": "fair FPGA arithmetic baseline; not CPU and not prior-online",
        },
        {
            "id": "CPU",
            "entry": "NumPy/OpenBLAS 32-thread",
            "scope": "software application baseline",
            "primary_data": cpu_brief(),
            "paper_use": "application reference only; no LUT/DSP comparison",
        },
    ]
    FAIRNESS_JSON.write_text(json.dumps({"git_commit": git_commit(), "rows": rows}, indent=2, sort_keys=True) + "\n")
    lines = [
        "# Paper Baseline Fairness Table",
        "",
        "Purpose: define which rows can be compared and which rows are only references.",
        "",
        "| ID | entry | scope | primary data | paper use |",
        "| --- | --- | --- | --- | --- |",
    ]
    for row in rows:
        lines.append(f"| {row['id']} | {row['entry']} | {row['scope']} | {row['primary_data']} | {row['paper_use']} |")
    lines += [
        "",
        "Comparison rules:",
        "",
        "- P0 operator-level LUT/FF must not be mixed with P2/P3 full wavefront/runtime resource rows.",
        "- P1 vs P3 is valid for native serial-serial scaling versus parallel-in scaling, but only at the same stated shape/result type.",
        "- P4 is the conventional FPGA arithmetic baseline; its DSP usage is part of the comparison, not a weakness in the baseline.",
        "- CPU is a software throughput reference only.",
        "",
    ]
    FAIRNESS_MD.write_text("\n".join(lines))


def main() -> None:
    GEN.mkdir(parents=True, exist_ok=True)
    cycle_inputs = parse_cycle_inputs()
    write_correctness_report(cycle_inputs)
    cycle_rows = write_cycle_report(cycle_inputs)
    route_rows = write_route_report()
    write_fairness_report(cycle_rows, route_rows)
    print(f"Wrote {CORRECTNESS_MD}")
    print(f"Wrote {CYCLE_MD}")
    print(f"Wrote {ROUTE_MD}")
    print(f"Wrote {FAIRNESS_MD}")


if __name__ == "__main__":
    main()
