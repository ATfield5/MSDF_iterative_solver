#!/usr/bin/env python3
"""
Summarize Vivado reports for iter_dense_small_runtime_top.

The script scans generated/vivado_iter_dense_small_runtime_top_* directories,
extracts timing/resource/power metrics, and writes a compact Markdown/JSON
report. It is intentionally report-only: Vivado runs are still launched by Tcl.
"""

from __future__ import annotations

import argparse
import json
import re
from dataclasses import asdict, dataclass
from pathlib import Path
from typing import Iterable, List, Optional


RUN_RE = re.compile(
    r"vivado_iter_dense_small_runtime_top_"
    r"part(?P<part>.+?)_"
    r"ntc(?P<ntc>\d+)_"
    r"nc(?P<nc>\d+)_"
    r"nr(?P<nr>\d+)_"
    r"deg(?P<deg>\d+)_"
    r"bw(?P<bw>\d+)_"
    r"bound(?P<bound>\d+)_"
    r"cw(?P<cw>\d+)_"
    r"acc(?P<acc>\d+)_"
    r"blk(?P<blk>\d+)_"
    r"data(?P<data>\d+)_"
    r"mem(?P<mem>\d+)_"
    r"(?:src(?P<src>\d+)_"
    r"global(?P<global>\d+)"
    r"(?:_halo(?P<halo>\d+)_hr(?P<hr>\d+)(?:_hreg(?P<hreg>\d+))?(?:_cpipe(?P<cpipe>\d+))?(?:_opipe(?P<opipe>\d+))?(?:_cmpipe(?P<cmpipe>\d+))?)?_)?"
    r"ooc(?P<ooc>\d+)_"
    r"clk(?P<clk>[0-9.]+)_"
    r"route(?P<route>\d+)$"
)


@dataclass
class RuntimeTopReport:
    directory: str
    part: str
    num_total_clusters: int
    num_clusters: int
    num_rows: int
    degree: int
    bit_width: int
    bound_width: int
    coeff_width: int
    acc_width: int
    block_size: int
    data_width: int
    runtime_mem_style: int
    src_idx_width: int
    global_source_replay: int
    halo_source_replay: int
    halo_cluster_radius: int
    halo_replay_output_register: int
    cert_product_pipeline: int
    cert_operand_pipeline: int
    cert_compare_pipeline: int
    ooc: int
    clk_ns: float
    stage: str
    wns_ns: Optional[float]
    lut: Optional[float]
    lutram: Optional[float]
    ff: Optional[float]
    carry8: Optional[float]
    dsp: Optional[float]
    bram: Optional[float]
    uram: Optional[float]
    dynamic_w: Optional[float]
    total_w: Optional[float]


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


def parse_run_dir(path: Path) -> Optional[RuntimeTopReport]:
    match = RUN_RE.match(path.name)
    if not match:
        return None
    info = match.groupdict()
    stage = "routed" if info["route"] == "1" else "synth"
    timing = read_text(path / f"timing_summary_{stage}.rpt")
    util = read_text(path / f"utilization_{stage}.rpt")
    power = read_text(path / f"power_{stage}.rpt")
    if not timing or not util:
        return None
    return RuntimeTopReport(
        directory=str(path),
        part=info["part"],
        num_total_clusters=int(info["ntc"]),
        num_clusters=int(info["nc"]),
        num_rows=int(info["nr"]),
        degree=int(info["deg"]),
        bit_width=int(info["bw"]),
        bound_width=int(info["bound"]),
        coeff_width=int(info["cw"]),
        acc_width=int(info["acc"]),
        block_size=int(info["blk"]),
        data_width=int(info["data"]),
        runtime_mem_style=int(info["mem"]),
        src_idx_width=int(info["src"]) if info.get("src") is not None else (
            1 if int(info["nr"]) <= 2 else int((int(info["nr"]) - 1).bit_length())
        ),
        global_source_replay=int(info["global"]) if info.get("global") is not None else 0,
        halo_source_replay=int(info["halo"]) if info.get("halo") is not None else 0,
        halo_cluster_radius=int(info["hr"]) if info.get("hr") is not None else 0,
        halo_replay_output_register=int(info["hreg"]) if info.get("hreg") is not None else 0,
        cert_product_pipeline=int(info["cpipe"]) if info.get("cpipe") is not None else 0,
        cert_operand_pipeline=int(info["opipe"]) if info.get("opipe") is not None else 0,
        cert_compare_pipeline=int(info["cmpipe"]) if info.get("cmpipe") is not None else 0,
        ooc=int(info["ooc"]),
        clk_ns=float(info["clk"]),
        stage=stage,
        wns_ns=extract_wns(timing),
        lut=extract_util(util, "CLB LUTs"),
        lutram=extract_util(util, "LUT as Memory"),
        ff=extract_util(util, "CLB Registers"),
        carry8=extract_util(util, "CARRY8"),
        dsp=extract_util(util, "DSPs"),
        bram=extract_util(util, "Block RAM Tile"),
        uram=extract_util(util, "URAM"),
        dynamic_w=extract_power(power, "Dynamic (W)"),
        total_w=extract_power(power, "Total On-Chip Power (W)"),
    )


def fmt(value: Optional[float], places: int = 3) -> str:
    if value is None:
        return "NA"
    if abs(value - round(value)) < 1e-9:
        return str(int(round(value)))
    return f"{value:.{places}f}"


def build_table(rows: Iterable[RuntimeTopReport]) -> List[str]:
    lines = [
        "| NTC | NC | rows/cluster | degree | mem | src | global | halo | hr | hreg | cpipe | opipe | cmpipe | stage | WNS | LUT | LUTRAM | FF | CARRY8 | DSP | BRAM | URAM | Dynamic W | Total W |",
        "| ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |",
    ]
    for row in rows:
        lines.append(
            f"| {row.num_total_clusters} | {row.num_clusters} | {row.num_rows} | {row.degree} | "
            f"{row.runtime_mem_style} | {row.src_idx_width} | {row.global_source_replay} | "
            f"{row.halo_source_replay} | {row.halo_cluster_radius} | {row.halo_replay_output_register} | "
            f"{row.cert_product_pipeline} | {row.cert_operand_pipeline} | "
            f"{row.cert_compare_pipeline} | {row.stage} | {fmt(row.wns_ns)} | {fmt(row.lut)} | "
            f"{fmt(row.lutram)} | {fmt(row.ff)} | {fmt(row.carry8)} | {fmt(row.dsp)} | "
            f"{fmt(row.bram)} | {fmt(row.uram)} | {fmt(row.dynamic_w)} | {fmt(row.total_w)} |"
        )
    return lines


def build_markdown(rows: List[RuntimeTopReport]) -> str:
    rows = sorted(
        rows,
        key=lambda r: (
            r.num_clusters,
            r.num_total_clusters,
            r.runtime_mem_style,
            0 if r.stage == "routed" else 1,
        ),
    )
    depth_rows = [
        r
        for r in rows
        if r.num_clusters == 2 and r.runtime_mem_style == 1 and r.stage in {"routed", "synth"}
        and r.global_source_replay == 0
        and r.halo_source_replay == 0
    ]
    mem_rows = [
        r
        for r in rows
        if r.num_clusters == 2
        and r.num_total_clusters == 2
        and r.stage == "routed"
        and r.runtime_mem_style in {0, 1}
        and r.global_source_replay == 0
        and r.halo_source_replay == 0
    ]
    physical_candidates = [
        r
        for r in rows
        if r.runtime_mem_style == 1
        and r.num_total_clusters == r.num_clusters
        and r.global_source_replay == 0
        and r.halo_source_replay == 0
    ]
    physical_rows = prefer_routed(physical_candidates)
    global_rows = prefer_routed([
        r
        for r in rows
        if r.runtime_mem_style == 1
        and r.num_total_clusters == r.num_clusters
        and r.global_source_replay == 1
        and r.halo_source_replay == 0
    ])
    halo_rows = prefer_routed([
        r
        for r in rows
        if r.runtime_mem_style == 1
        and r.num_total_clusters == r.num_clusters
        and r.global_source_replay == 0
        and r.halo_source_replay == 1
    ])

    lines: List[str] = []
    lines.append("# Runtime Top Automated Resource Report")
    lines.append("")
    lines.append("This report is generated from Vivado report files for `iter_dense_small_runtime_top`.")
    lines.append("")
    lines.append("## Memory Style")
    lines.append("")
    lines.append("- `runtime_mem_style=0`: distributed RAM, intended for tiny regression.")
    lines.append("- `runtime_mem_style=1`: block RAM, default capacity-mode checkpoint.")
    lines.append("- `runtime_mem_style=2`: UltraRAM, reserved for later larger-memory experiments.")
    lines.append("")
    lines.append("## Storage-Depth Sweep")
    lines.append("")
    lines.extend(build_table(depth_rows))
    lines.append("")
    lines.append("## Memory-Style Check")
    lines.append("")
    lines.extend(build_table(mem_rows))
    lines.append("")
    lines.append("## Physical Active-Cluster Sweep")
    lines.append("")
    lines.extend(build_table(physical_rows))
    lines.append("")
    lines.append("## Global-Source Replay Checkpoint")
    lines.append("")
    lines.extend(build_table(global_rows))
    lines.append("")
    lines.append("## Halo-Window Replay Checkpoint")
    lines.append("")
    lines.extend(build_table(halo_rows))
    lines.append("")
    lines.append("## Interpretation")
    lines.append("")
    lines.append("- The storage-depth sweep changes `NUM_TOTAL_CLUSTERS` while keeping `NUM_CLUSTERS=2`; it tests memory capacity scaling.")
    lines.append("- The physical active-cluster sweep changes `NUM_CLUSTERS`; it tests datapath replication and is the relevant trend for larger Jacobi row-cluster throughput.")
    lines.append("- The memory-style check confirms whether tiny regression and capacity-mode storage are physically different.")
    lines.append("- The global-source replay checkpoint is a functional inter-cluster routing baseline; it is expected to be more expensive than the optimized cluster-local path.")
    lines.append("- The halo-window replay checkpoint restricts each cluster to a bounded neighboring-cluster source window; it is the intended replacement for the global-source mux on banded workloads.")
    routed_physical = [r for r in physical_rows if r.stage == "routed"]
    if routed_physical:
        max_nc = max(r.num_clusters for r in routed_physical)
        max_row = next(r for r in routed_physical if r.num_clusters == max_nc)
        lines.append(
            f"- Current routed physical scaling reaches `NUM_CLUSTERS={max_nc}` "
            f"({max_nc * max_row.num_rows} active rows) at WNS `{fmt(max_row.wns_ns)}` ns."
        )
    routed_global = [r for r in global_rows if r.stage == "routed"]
    if routed_global:
        max_nc = max(r.num_clusters for r in routed_global)
        max_row = next(r for r in routed_global if r.num_clusters == max_nc)
        lines.append(
            f"- Current routed global-source checkpoint reaches `NUM_CLUSTERS={max_nc}` "
            f"({max_nc * max_row.num_rows} active rows) at WNS `{fmt(max_row.wns_ns)}` ns."
        )
    routed_halo = [r for r in halo_rows if r.stage == "routed"]
    if routed_halo:
        max_nc = max(r.num_clusters for r in routed_halo)
        max_row = max(
            (r for r in routed_halo if r.num_clusters == max_nc),
            key=lambda r: r.wns_ns if r.wns_ns is not None else -999.0,
        )
        lines.append(
            f"- Current routed halo-window checkpoint reaches `NUM_CLUSTERS={max_nc}` "
            f"({max_nc * max_row.num_rows} active rows) at WNS `{fmt(max_row.wns_ns)}` ns."
        )
    lines.append("")
    return "\n".join(lines)


def prefer_routed(rows: Iterable[RuntimeTopReport]) -> List[RuntimeTopReport]:
    best = {}
    for row in rows:
        key = (
            row.num_total_clusters,
            row.num_clusters,
            row.num_rows,
            row.degree,
            row.runtime_mem_style,
            row.src_idx_width,
            row.global_source_replay,
            row.halo_source_replay,
            row.halo_cluster_radius,
            row.halo_replay_output_register,
            row.cert_product_pipeline,
            row.cert_operand_pipeline,
            row.cert_compare_pipeline,
        )
        old = best.get(key)
        if old is None or (old.stage != "routed" and row.stage == "routed"):
            best[key] = row
    return sorted(
        best.values(),
        key=lambda r: (r.num_clusters, r.num_total_clusters, 0 if r.stage == "routed" else 1),
    )


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--generated-dir", type=Path, default=Path("MSDF_iterative_solver/generated"))
    parser.add_argument("--output-md", type=Path, default=Path("MSDF_iterative_solver/generated/runtime_top_auto_report.md"))
    parser.add_argument("--output-json", type=Path, default=Path("MSDF_iterative_solver/generated/runtime_top_auto_report.json"))
    args = parser.parse_args()

    rows = []
    for path in sorted(args.generated_dir.glob("vivado_iter_dense_small_runtime_top_*")):
        if path.is_dir():
            parsed = parse_run_dir(path)
            if parsed is not None:
                rows.append(parsed)

    args.output_md.parent.mkdir(parents=True, exist_ok=True)
    args.output_json.parent.mkdir(parents=True, exist_ok=True)
    args.output_md.write_text(build_markdown(rows), encoding="utf-8")
    args.output_json.write_text(json.dumps([asdict(row) for row in rows], indent=2), encoding="utf-8")

    print(f"Wrote {args.output_md}")
    print(f"Wrote {args.output_json}")
    print(f"Parsed {len(rows)} report directories")


if __name__ == "__main__":
    main()
