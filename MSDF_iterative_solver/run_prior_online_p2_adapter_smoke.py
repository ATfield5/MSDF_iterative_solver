#!/usr/bin/env python3
"""Run P2 prior-online adapter and word-assembler smoke tests."""

from __future__ import annotations

import subprocess
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SRC = ROOT / "MSDF_operator_srcs/MSDF_Operators/MSDF_Operators/MSDF_Operators.srcs/sources_1/new"
ADAPTER_OUT = Path("/tmp/tb_prior_online_p2_adapter.vvp")
WORD_OUT = Path("/tmp/tb_prior_online_p2_word.vvp")
CLUSTER_OUT = Path("/tmp/tb_prior_online_p2_cluster.vvp")
SEMANTICS_OUT = Path("/tmp/tb_prior_online_p2_semantics.vvp")
RUNTIME_OUT = Path("/tmp/tb_prior_online_p2_runtime.vvp")
FRACTIONAL_RUNTIME_OUT = Path("/tmp/tb_prior_online_p2_fractional_runtime.vvp")
REPORT = ROOT / "MSDF_iterative_solver/generated/prior_online_p2_adapter_smoke_report.md"

ORIG_SOURCES = [
    "DFF.v",
    "full_adder.v",
    "parallel_online_adder_block.v",
    "parallel_online_adder.v",
    "parallel_online_adder_4.v",
    "parallel_online_adder_4_with_obuf.v",
    "vector_append.v",
    "selector.v",
    "append_and_select.v",
    "output_and_update.v",
    "MSDF_MUL_ADD_8.v",
]


def run(cmd: list[str]) -> subprocess.CompletedProcess[str]:
    return subprocess.run(cmd, cwd=ROOT, check=True, capture_output=True, text=True)


def main() -> None:
    adapter_compile_cmd = [
        "iverilog",
        "-g2012",
        "-o",
        str(ADAPTER_OUT),
        *[str(SRC / name) for name in ORIG_SOURCES],
        "MSDF_iterative_solver/prior_rtl/iter_prior_online_mma8_row_kernel.v",
        "MSDF_iterative_solver/tb/tb_iter_prior_online_mma8_row_kernel.v",
    ]
    word_compile_cmd = [
        "iverilog",
        "-g2012",
        "-o",
        str(WORD_OUT),
        *[str(SRC / name) for name in ORIG_SOURCES],
        "MSDF_iterative_solver/prior_rtl/iter_prior_online_mma8_row_kernel.v",
        "MSDF_iterative_solver/prior_rtl/iter_prior_online_mma8_word_assembler.v",
        "MSDF_iterative_solver/tb/tb_iter_prior_online_mma8_word_assembler.v",
    ]
    cluster_compile_cmd = [
        "iverilog",
        "-g2012",
        "-o",
        str(CLUSTER_OUT),
        *[str(SRC / name) for name in ORIG_SOURCES],
        "MSDF_iterative_solver/rtl/block_bound_max_pool.v",
        "MSDF_iterative_solver/rtl/block_h_cert_engine.v",
        "MSDF_iterative_solver/rtl/online_row_cluster_block_cert.v",
        "MSDF_iterative_solver/prior_rtl/iter_prior_online_mma8_row_kernel.v",
        "MSDF_iterative_solver/prior_rtl/iter_prior_online_mma8_word_assembler.v",
        "MSDF_iterative_solver/prior_rtl/iter_prior_online_mma8_row_cluster_delta_cert.v",
        "MSDF_iterative_solver/tb/tb_iter_prior_online_mma8_row_cluster_delta_cert.v",
    ]
    semantics_compile_cmd = [
        "iverilog",
        "-g2012",
        "-o",
        str(SEMANTICS_OUT),
        *[str(SRC / name) for name in ORIG_SOURCES],
        "MSDF_iterative_solver/prior_rtl/iter_prior_online_mma8_row_kernel.v",
        "MSDF_iterative_solver/prior_rtl/iter_prior_online_mma8_word_assembler.v",
        "MSDF_iterative_solver/tb/tb_iter_prior_online_mma8_semantics.v",
    ]
    runtime_compile_cmd = [
        "iverilog",
        "-g2012",
        "-I",
        "MSDF_iterative_solver/tb",
        "-o",
        str(RUNTIME_OUT),
        *[str(SRC / name) for name in ORIG_SOURCES],
        *[str(path) for path in sorted((ROOT / "MSDF_iterative_solver/rtl").glob("*.v"))],
        "MSDF_iterative_solver/prior_rtl/iter_prior_online_mma8_row_kernel.v",
        "MSDF_iterative_solver/prior_rtl/iter_prior_online_mma8_word_assembler.v",
        "MSDF_iterative_solver/prior_rtl/iter_prior_online_mma8_row_cluster_delta_cert.v",
        "MSDF_iterative_solver/tb/tb_iter_dense_runtime_pagerank32_global_prior_online_multi.v",
    ]
    fractional_runtime_compile_cmd = [
        "iverilog",
        "-g2012",
        "-I",
        "MSDF_iterative_solver/tb",
        "-o",
        str(FRACTIONAL_RUNTIME_OUT),
        *[str(SRC / name) for name in ORIG_SOURCES],
        *[str(path) for path in sorted((ROOT / "MSDF_iterative_solver/rtl").glob("*.v"))],
        "MSDF_iterative_solver/prior_rtl/iter_prior_online_mma8_row_kernel.v",
        "MSDF_iterative_solver/prior_rtl/iter_prior_online_mma8_word_assembler.v",
        "MSDF_iterative_solver/prior_rtl/iter_prior_online_mma8_row_cluster_delta_cert.v",
        "MSDF_iterative_solver/tb/tb_iter_dense_runtime_pagerank32_global_prior_fractional_multi.v",
    ]
    run(adapter_compile_cmd)
    adapter_sim = run(["vvp", str(ADAPTER_OUT)])
    run(word_compile_cmd)
    word_sim = run(["vvp", str(WORD_OUT)])
    run(cluster_compile_cmd)
    cluster_sim = run(["vvp", str(CLUSTER_OUT)])
    run(semantics_compile_cmd)
    semantics_sim = run(["vvp", str(SEMANTICS_OUT)])
    run(runtime_compile_cmd)
    runtime_sim = run(["vvp", str(RUNTIME_OUT)])
    run([
        sys.executable,
        "MSDF_iterative_solver/make_pagerank_prior_fractional_vectors.py",
        "--num-iters",
        "4",
    ])
    run(fractional_runtime_compile_cmd)
    fractional_runtime_sim = run(["vvp", str(FRACTIONAL_RUNTIME_OUT)])

    REPORT.parent.mkdir(parents=True, exist_ok=True)
    REPORT.write_text(
        "\n".join(
            [
                "# Prior Online P2 Adapter Smoke Report",
                "",
                "This report validates the first same-shell prior-online adapter boundaries.",
                "`iter_prior_online_mma8_row_kernel` maps the current fixed-degree row",
                "digit interface onto the original `MSDF_MUL_ADD_8` operator.",
                "`iter_prior_online_mma8_word_assembler` adds the explicit full-word",
                "assembly boundary needed by the P2 prior-online baseline.",
                "`iter_prior_online_mma8_row_cluster_delta_cert` adds row-parallel",
                "assembly, full-word delta, and cluster certification.",
                "`ROW_DATAPATH_MODE=5` connects that wrapper into the same",
                "PageRank runtime shell as a relaxed same-shell smoke.",
                "`tb_iter_prior_online_mma8_semantics` records the native",
                "operator scaling so the P2 baseline does not silently become",
                "a different arithmetic operation.",
                "`tb_iter_dense_runtime_pagerank32_global_prior_fractional_multi`",
                "uses a prior-compatible fractional fixture and bounded LSB",
                "tolerance for original online selection rounding.",
                "",
                "## Row-Kernel Adapter Icarus Output",
                "",
                "```text",
                adapter_sim.stdout.strip(),
                "```",
                "",
                "## Word-Assembler Icarus Output",
                "",
                "```text",
                word_sim.stdout.strip(),
                "```",
                "",
                "## Cluster Wrapper Icarus Output",
                "",
                "```text",
                cluster_sim.stdout.strip(),
                "```",
                "",
                "## Operator Semantics Icarus Output",
                "",
                "```text",
                semantics_sim.stdout.strip(),
                "```",
                "",
                "## Runtime-Shell P2 Smoke Icarus Output",
                "",
                "```text",
                runtime_sim.stdout.strip(),
                "```",
                "",
                "## Prior-Compatible Fractional Runtime Icarus Output",
                "",
                "```text",
                fractional_runtime_sim.stdout.strip(),
                "```",
                "",
                "## Status",
                "",
                "- Adapter compile/smoke: PASS.",
                "- Word assembler compile/smoke: PASS.",
                "- Cluster delta/certification wrapper smoke: PASS.",
                "- Operator semantics sweep: PASS.",
                "- Runtime shell integration smoke: PASS.",
                "- Prior-compatible fractional runtime: PASS.",
                "- Runtime-shell smoke uses relaxed numerical checks; it proves",
                "  scheduling/state/certification integration, not final PageRank",
                "  numerical equivalence.",
                "- Fractional runtime uses `BIT_WIDTH=11`, `DATA_WIDTH=14`,",
                "  fraction-only capture, and `<=4 LSB` tolerance for the",
                "  prior operator's online selection/rounding behavior.",
                "- The original operator is not a plain integer MAC. The observed",
                "  product path follows the operator's fractional online scaling",
                "  and delay, so strict P2 requires a prior-compatible fixed-point",
                "  fixture or an explicit bias/product alignment bridge.",
                "",
            ]
        ),
        encoding="utf-8",
    )
    print(adapter_sim.stdout, end="")
    print(word_sim.stdout, end="")
    print(cluster_sim.stdout, end="")
    print(semantics_sim.stdout, end="")
    print(runtime_sim.stdout, end="")
    print(fractional_runtime_sim.stdout, end="")
    print(f"Wrote {REPORT}")


if __name__ == "__main__":
    main()
