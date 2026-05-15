#!/usr/bin/env python3
"""Run strict prior-fractional PageRank wavefront stage sweeps.

This is the strictest current check for solver-level digit streaming:
the original MSDF_MUL_ADD_8 prior operator is instantiated once per
row/stage, and committed output digits from stage k feed stage k+1 directly.
The test is standalone by design; it excludes runtime loader/cert overhead.
"""

from __future__ import annotations

import argparse
import pathlib
import re
import subprocess
import sys


ROOT = pathlib.Path(__file__).resolve().parents[1]
ITER = ROOT / "MSDF_iterative_solver"
SRC = ROOT / "MSDF_operator_srcs/MSDF_Operators/MSDF_Operators/MSDF_Operators.srcs/sources_1/new"
REPORT = ITER / "generated/prior_fractional_wavefront_sweep.md"

ORIG_SOURCES = [
    "DFF.v",
    "full_adder.v",
    "serial_online_adder_block.v",
    "parallel_online_adder_block.v",
    "parallel_online_adder.v",
    "parallel_online_adder_4.v",
    "parallel_online_adder_4_with_obuf.v",
    "vector_append.v",
    "selector.v",
    "append_and_select.v",
    "output_and_update.v",
    "MSDF_ADD.v",
    "MSDF_MUL_ADD_8.v",
]

COUNTER_RE = re.compile(
    r"COUNTERS prior_wavefront K=(?P<k>\d+) total=(?P<total>\d+) "
    r"capture=(?P<capture>\d+) stage_counts=(?P<stage_counts>[0-9a-fA-F]+) "
    r"overlap=(?P<overlap>[01xXzZ]+)"
)


def run(cmd: list[str]) -> subprocess.CompletedProcess[str]:
    return subprocess.run(cmd, cwd=ROOT, check=True, capture_output=True, text=True)


def fixture_dir(degree: int, bit_width: int) -> pathlib.Path:
    if degree == 4 and bit_width == 11:
        return ITER / "generated/rtl_vectors/pagerank32_global_prior_fractional"
    return ITER / f"generated/rtl_vectors/pagerank32_global_prior_fractional_deg{degree}_bw{bit_width}"


def run_case(
    k: int,
    use_mma4: bool = False,
    degree: int = 4,
    bit_width: int = 11,
    tolerance: int = 4,
) -> dict[str, int | str | float]:
    out_dir = fixture_dir(degree, bit_width)
    run([
        sys.executable,
        "MSDF_iterative_solver/make_pagerank_prior_fractional_vectors.py",
        "--num-iters",
        str(k),
        "--degree",
        str(degree),
        "--bit-width",
        str(bit_width),
        "--out-dir",
        str(out_dir),
    ])
    out = pathlib.Path("/tmp") / f"tb_prior_fractional_wavefront_k{k}_deg{degree}_bw{bit_width}.vvp"
    experimental_sources = [
        "MSDF_iterative_solver/prior_rtl/iter_pagerank_online_mma4_frac_core.v",
        "MSDF_iterative_solver/prior_rtl/iter_pagerank_online_mma4_frac_stage_cluster.v",
    ] if use_mma4 else []
    compile_cmd = [
        "iverilog",
        "-g2012",
        "-I",
        "MSDF_iterative_solver/tb",
        f"-DPRIOR_WAVEFRONT_STAGES_VALUE={k}",
        f"-DPRIOR_WAVEFRONT_USE_MMA4_VALUE={1 if use_mma4 else 0}",
        f"-DPRIOR_WAVEFRONT_DEGREE_VALUE={degree}",
        f"-DPRIOR_WAVEFRONT_BIT_WIDTH_VALUE={bit_width}",
        f"-DPRIOR_WAVEFRONT_TOLERANCE_VALUE={tolerance}",
        f'-DPRIOR_WAVEFRONT_TEMPLATE_MEMH="{out_dir / "templates.memh"}"',
        f'-DPRIOR_WAVEFRONT_GOLD_STATE_P_MEMH="{out_dir / "gold_state_p_iters.memh"}"',
        f'-DPRIOR_WAVEFRONT_GOLD_STATE_N_MEMH="{out_dir / "gold_state_n_iters.memh"}"',
        "-o",
        str(out),
        *[str(SRC / name) for name in ORIG_SOURCES],
        "MSDF_iterative_solver/rtl/iter_fixed_degree_template_unpack.v",
        "MSDF_iterative_solver/prior_rtl/MSDF_MUL_ADD_32_NATIVE.v",
        "MSDF_iterative_solver/prior_rtl/iter_prior_online_mma8_row_kernel.v",
        "MSDF_iterative_solver/prior_rtl/iter_prior_online_mma32_row_kernel.v",
        "MSDF_iterative_solver/prior_rtl/iter_prior_online_mma32_native_row_kernel.v",
        "MSDF_iterative_solver/prior_rtl/iter_prior_online_mma8_stream_stage_cluster.v",
        *experimental_sources,
        "MSDF_iterative_solver/prior_rtl/iter_prior_online_mma8_global_wavefront_top.v",
        "MSDF_iterative_solver/tb/tb_iter_prior_online_mma8_global_wavefront_top.v",
    ]
    run(compile_cmd)
    sim = run(["vvp", str(out)])
    match = COUNTER_RE.search(sim.stdout)
    if not match:
        raise RuntimeError(f"missing counter line for K={k}\n{sim.stdout}")
    total = int(match.group("total"))
    capture = int(match.group("capture"))
    return {
        "k": k,
        "total": total,
        "capture": capture,
        "stage_counts": match.group("stage_counts"),
        "overlap": match.group("overlap"),
        "cycles_per_fused_iter": total / k,
        "stdout": sim.stdout.strip(),
        "use_mma4": use_mma4,
        "degree": degree,
        "bit_width": bit_width,
        "data_width": bit_width + 3,
        "tolerance": tolerance,
    }


def write_report(
    rows: list[dict[str, int | str | float]],
    use_mma4: bool = False,
    degree: int = 4,
    bit_width: int = 11,
) -> pathlib.Path:
    if use_mma4:
        report = ITER / "generated/prior_fractional_wavefront_mma4_sweep.md"
    elif degree == 4 and bit_width == 11:
        report = REPORT
    else:
        report = ITER / f"generated/prior_fractional_wavefront_deg{degree}_bw{bit_width}_sweep.md"
    report.parent.mkdir(parents=True, exist_ok=True)
    lines = [
        "# Prior-Fractional PageRank Wavefront Sweep",
        "",
        "This report is generated by `run_prior_fractional_wavefront_sweep.py`.",
        "It uses the selected prior-compatible operator and the strict",
        "`pagerank32_global_prior_fractional` fixture.  The test is standalone:",
        "it validates stage-to-stage digit streaming and excludes runtime",
        "loader/certification overhead.",
        "",
        f"Core variant: `{'pagerank_mma4_frac' if use_mma4 else 'prior_mma8'}`.",
        f"Degree: `{degree}`.  Operator bit width: `{bit_width}`.  Data width: `{bit_width + 3}`.",
        f"Tolerance: `{rows[0].get('tolerance', 4)}` LSB.",
        "",
        "| K stages | total cycles | captured digits | cycles / fused iter | overlap flags | notes |",
        "| ---: | ---: | ---: | ---: | --- | --- |",
    ]
    for row in rows:
        lines.append(
            f"| {row['k']} | {row['total']} | {row['capture']} | "
            f"{row['cycles_per_fused_iter']:.2f} | `{row['overlap']}` | "
            f"final state matches fractional golden within <={row.get('tolerance', 4)} LSB |"
        )
    lines.extend(
        [
            "",
            "Interpretation:",
            "",
            "- `overlap=1...1` means each later stage starts before the previous stage has completed all committed digits.",
            f"- The captured digit count stays at `DATA_WIDTH={bit_width + 3}`, not `K*DATA_WIDTH`, so the cascade consumes one input word stream and propagates committed digits internally.",
            "- This proves the prior operator can be used in a solver-level digit-stream wavefront, but it is not yet a same-shell runtime result.",
            "- The optional PageRank 4-term core is experimental and is only compiled when `--use-mma4` is explicitly set.",
        "- Mainline P3 remains the original `MSDF_MUL_ADD_8` strict prior operator.",
            "",
            "## Raw Outputs",
            "",
        ]
    )
    for row in rows:
        lines.extend(
            [
                f"### K={row['k']}",
                "",
                "```text",
                str(row["stdout"]),
                "```",
                "",
            ]
        )
    report.write_text("\n".join(lines), encoding="utf-8")
    return report


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--stages", type=int, action="append")
    parser.add_argument("--degree", type=int, default=4)
    parser.add_argument("--bit-width", type=int, default=11)
    parser.add_argument("--tolerance", type=int, default=4)
    parser.add_argument("--use-mma4", action="store_true", help="Use the PageRank-specialized 4-term fractional core")
    args = parser.parse_args()

    stages = args.stages if args.stages else [2, 3, 4]
    rows = [
        run_case(
            k,
            args.use_mma4,
            degree=args.degree,
            bit_width=args.bit_width,
            tolerance=args.tolerance,
        )
        for k in stages
    ]
    report = write_report(rows, args.use_mma4, args.degree, args.bit_width)
    for row in rows:
        print(
            f"K={row['k']} total={row['total']} capture={row['capture']} "
            f"cycles_per_fused_iter={row['cycles_per_fused_iter']:.2f} "
            f"overlap={row['overlap']}"
        )
    print(f"Wrote {report}")


if __name__ == "__main__":
    main()
