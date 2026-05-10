#!/usr/bin/env python3
"""Run same-fixture PageRank fractional baselines.

This script fixes the first strict P2/P4 comparison point:

- P2: prior-online `MSDF_MUL_ADD_8` adapter in the runtime shell.
- P4: conventional DSP-MAC row update in the same runtime shell.

Both consume `pagerank32_global_prior_fractional`, so the comparison is over
the same graph, coefficient/bias quantization, PageRank L1 certification, and
runtime controller.
"""

from __future__ import annotations

import subprocess
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SRC = ROOT / "MSDF_operator_srcs/MSDF_Operators/MSDF_Operators/MSDF_Operators.srcs/sources_1/new"
REPORT = ROOT / "MSDF_iterative_solver/generated/pagerank_fractional_same_scope_eval.md"
P2_OUT = Path("/tmp/tb_pagerank_p2_fractional_same_scope.vvp")
P2_PROXY_OUT = Path("/tmp/tb_pagerank_p2_proxy_fractional_same_scope.vvp")
P3_PRIOR_STREAM_OUT = Path("/tmp/tb_pagerank_p3_prior_stream_fractional_same_scope.vvp")
P3_PRIOR_WAVEFRONT_OUT = Path("/tmp/tb_pagerank_p3_prior_wavefront_fractional_same_scope.vvp")
P4_OUT = Path("/tmp/tb_pagerank_p4_fractional_same_scope.vvp")
P4_CLEAN_OUT = Path("/tmp/tb_pagerank_p4_fractional_clean_same_scope.vvp")

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


def counter_line(text: str) -> str:
    for line in text.splitlines():
        if line.startswith("COUNTERS "):
            return line
    raise RuntimeError("missing COUNTERS line")


def parse_counters(line: str) -> dict[str, int | str]:
    fields = line.split()
    parsed: dict[str, int | str] = {"label": fields[1]}
    for field in fields[2:]:
        key, value = field.split("=", 1)
        parsed[key] = int(value, 0)
    return parsed


def speedup(a: int, b: int) -> float:
    return float(a) / float(b) if b else 0.0


def core_cycles(counters: dict[str, int | str]) -> int:
    """Cycle count used in the performance table.

    It intentionally excludes runtime configuration, state preload, window
    load, and idle/testbench control.  The remaining window is:
    input/issue + main compute + output/commit/certification wait.
    """
    return int(counters["issue"]) + int(counters["cert_wait"])


def setup_cycles(counters: dict[str, int | str]) -> int:
    return (
        int(counters["cfg_template"]) +
        int(counters["cfg_cert"]) +
        int(counters["cfg_state"])
    )


def window_overhead_cycles(counters: dict[str, int | str]) -> int:
    return int(counters["window_load"]) + int(counters["window_busy"])


def non_compute_overhead_cycles(counters: dict[str, int | str]) -> int:
    return int(counters["total"]) - core_cycles(counters)


def perf_row(
    name: str,
    counters: dict[str, int | str],
    notes: str,
) -> str:
    return (
        f"| {name} | yes | {core_cycles(counters)} | {counters['issue']} | "
        f"{counters['cert_wait']} | {counters['total']} | {notes} |"
    )


def overhead_row(name: str, counters: dict[str, int | str]) -> str:
    return (
        f"| {name} | {non_compute_overhead_cycles(counters)} | "
        f"{counters['cfg_template']} | {counters['cfg_cert']} | "
        f"{counters['cfg_state']} | {counters['window_load']} | "
        f"{counters['window_busy']} |"
    )


def main() -> None:
    run([
        sys.executable,
        "MSDF_iterative_solver/make_pagerank_prior_fractional_vectors.py",
        "--num-iters",
        "4",
    ])

    rtl_sources = [str(path) for path in sorted((ROOT / "MSDF_iterative_solver/rtl").glob("*.v"))]
    prior_sources = [
        "MSDF_iterative_solver/prior_rtl/iter_prior_online_mma8_row_kernel.v",
        "MSDF_iterative_solver/prior_rtl/iter_prior_online_mma8_word_assembler.v",
        "MSDF_iterative_solver/prior_rtl/iter_prior_online_mma8_row_cluster_delta_cert.v",
    ]
    prior_stream_sources = [
        "MSDF_iterative_solver/prior_rtl/iter_prior_online_mma8_row_kernel.v",
        "MSDF_iterative_solver/prior_rtl/iter_prior_online_mma8_digit_stream_cluster_delta_cert.v",
    ]
    prior_wavefront_sources = [
        "MSDF_iterative_solver/prior_rtl/iter_prior_online_mma8_row_kernel.v",
        "MSDF_iterative_solver/prior_rtl/iter_prior_online_mma8_stream_stage_cluster.v",
        "MSDF_iterative_solver/prior_rtl/iter_prior_online_mma8_global_wavefront_top.v",
    ]

    p2_compile = [
        "iverilog",
        "-g2012",
        "-I",
        "MSDF_iterative_solver/tb",
        "-o",
        str(P2_OUT),
        *[str(SRC / name) for name in ORIG_SOURCES],
        *rtl_sources,
        *prior_sources,
        "MSDF_iterative_solver/tb/tb_iter_dense_runtime_pagerank32_global_prior_fractional_multi.v",
    ]
    p2_proxy_compile = [
        "iverilog",
        "-g2012",
        "-I",
        "MSDF_iterative_solver/tb",
        "-o",
        str(P2_PROXY_OUT),
        *rtl_sources,
        "MSDF_iterative_solver/tb/tb_iter_dense_runtime_pagerank32_global_full_digit_fractional_multi.v",
    ]
    p3_prior_stream_compile = [
        "iverilog",
        "-g2012",
        "-I",
        "MSDF_iterative_solver/tb",
        "-o",
        str(P3_PRIOR_STREAM_OUT),
        *[str(SRC / name) for name in ORIG_SOURCES],
        *rtl_sources,
        *prior_stream_sources,
        "MSDF_iterative_solver/tb/tb_iter_dense_runtime_pagerank32_global_prior_digit_stream_fractional_multi.v",
    ]
    p3_prior_wavefront_compile = [
        "iverilog",
        "-g2012",
        "-I",
        "MSDF_iterative_solver/tb",
        "-o",
        str(P3_PRIOR_WAVEFRONT_OUT),
        *[str(SRC / name) for name in ORIG_SOURCES],
        *rtl_sources,
        *prior_wavefront_sources,
        "MSDF_iterative_solver/tb/tb_iter_dense_runtime_pagerank32_global_prior_wavefront_fractional.v",
    ]
    p4_compile = [
        "iverilog",
        "-g2012",
        "-I",
        "MSDF_iterative_solver/tb",
        "-o",
        str(P4_OUT),
        *rtl_sources,
        "MSDF_iterative_solver/tb/tb_iter_dense_runtime_pagerank32_global_conv_fractional_multi.v",
    ]
    p4_clean_compile = [
        "iverilog",
        "-g2012",
        "-I",
        "MSDF_iterative_solver/tb",
        "-DJACOBI32_GLOBAL_REG",
        "-DJACOBI32_CONV_ROUND_PIPE",
        "-o",
        str(P4_CLEAN_OUT),
        *rtl_sources,
        "MSDF_iterative_solver/tb/tb_iter_dense_runtime_pagerank32_global_conv_fractional_multi.v",
    ]

    run(p2_compile)
    p2_sim = run(["vvp", str(P2_OUT)])
    run(p2_proxy_compile)
    p2_proxy_sim = run(["vvp", str(P2_PROXY_OUT)])
    run(p3_prior_stream_compile)
    p3_prior_stream_sim = run(["vvp", str(P3_PRIOR_STREAM_OUT)])
    run(p3_prior_wavefront_compile)
    p3_prior_wavefront_sim = run(["vvp", str(P3_PRIOR_WAVEFRONT_OUT)])
    run(p4_compile)
    p4_sim = run(["vvp", str(P4_OUT)])
    run(p4_clean_compile)
    p4_clean_sim = run(["vvp", str(P4_CLEAN_OUT)])

    p2_line = counter_line(p2_sim.stdout)
    p2_proxy_line = counter_line(p2_proxy_sim.stdout)
    p3_prior_stream_line = counter_line(p3_prior_stream_sim.stdout)
    p3_prior_wavefront_line = counter_line(p3_prior_wavefront_sim.stdout)
    p4_line = counter_line(p4_sim.stdout)
    p4_clean_line = counter_line(p4_clean_sim.stdout)
    p2 = parse_counters(p2_line)
    p2_proxy = parse_counters(p2_proxy_line)
    p3_prior_stream = parse_counters(p3_prior_stream_line)
    p3_prior_wavefront = parse_counters(p3_prior_wavefront_line)
    p4 = parse_counters(p4_line)
    p4_clean = parse_counters(p4_clean_line)
    total_ratio = speedup(core_cycles(p2), core_cycles(p4))
    proxy_total_ratio = speedup(core_cycles(p2_proxy), core_cycles(p4))
    stream_total_ratio = speedup(core_cycles(p3_prior_stream), core_cycles(p4))
    wavefront_total_ratio = speedup(core_cycles(p3_prior_wavefront), core_cycles(p4))
    wavefront_clean_total_ratio = speedup(
        core_cycles(p3_prior_wavefront),
        core_cycles(p4_clean),
    )
    wavefront_vs_stream_ratio = speedup(
        core_cycles(p3_prior_stream),
        core_cycles(p3_prior_wavefront),
    )
    cert_ratio = speedup(int(p2["cert_wait"]), int(p4["cert_wait"]))
    observed_wavefront_clean_total_ratio = speedup(
        int(p3_prior_wavefront["total"]),
        int(p4_clean["total"]),
    )

    REPORT.parent.mkdir(parents=True, exist_ok=True)
    REPORT.write_text(
        "\n".join(
            [
                "# PageRank Fractional Same-Scope Evaluation",
                "",
                "This report compares strict fractional PageRank runtime entries.",
                "All entries use `pagerank32_global_prior_fractional`: same graph,",
                "same coefficient/bias quantization, same product scaling target,",
                "same runtime loader/state/controller, and same global L1 decision.",
                "",
                "Cycle policy: the performance table uses `compute cycles = issue + cert_wait`.",
                "Configuration, state preload, window load, and idle/control overhead are reported separately.",
                "",
                "| entry | pass | compute cycles | input/issue | main+output wait | observed total | notes |",
                "| --- | ---: | ---: | ---: | ---: | ---: | --- |",
                perf_row(
                    "P2 prior-online fractional",
                    p2,
                    "original `MSDF_MUL_ADD_8`, fraction-only capture, <=4 LSB tolerance",
                ),
                perf_row(
                    "P2-proxy full-digit fractional",
                    p2_proxy,
                    "digit-serial bridge, per-term rounded product shift",
                ),
                perf_row(
                    "P3 prior digit-stream fractional",
                    p3_prior_stream,
                    "prior operator output digits committed directly to state bank",
                ),
                perf_row(
                    "P3 prior K=4 wavefront fractional",
                    p3_prior_wavefront,
                    "four prior-operator stages cascaded; final delta is x^(k+4)-x^(k+3)",
                ),
                perf_row(
                    "P4 conventional fractional",
                    p4,
                    "DSP-MAC with round((state*coeff)/2^DATA_WIDTH)",
                ),
                perf_row(
                    "P4 timing-clean conventional fractional",
                    p4_clean,
                    "global replay register + product-rounding pipeline",
                ),
                "",
                "Non-compute overhead and setup/window activity counters:",
                "",
                "The setup/window fields are raw activity counters, not a mutually exclusive cycle partition.",
                "",
                "| entry | non-compute overhead | cfg_template | cfg_cert | cfg_state | window_load | window_busy |",
                "| --- | ---: | ---: | ---: | ---: | ---: | ---: |",
                overhead_row("P2 prior-online fractional", p2),
                overhead_row("P2-proxy full-digit fractional", p2_proxy),
                overhead_row("P3 prior digit-stream fractional", p3_prior_stream),
                overhead_row("P3 prior K=4 wavefront fractional", p3_prior_wavefront),
                overhead_row("P4 conventional fractional", p4),
                overhead_row("P4 timing-clean conventional fractional", p4_clean),
                "",
                "Derived compute-cycle ratios:",
                "",
                f"- P2/P4 compute-cycle ratio: `{total_ratio:.3f}x`.",
                f"- P2-proxy/P4 compute-cycle ratio: `{proxy_total_ratio:.3f}x`.",
                f"- P3-prior-stream/P4 compute-cycle ratio: `{stream_total_ratio:.3f}x`.",
                f"- P3-prior-wavefront/P4 compute-cycle ratio: `{wavefront_total_ratio:.3f}x`.",
                f"- P3-prior-wavefront/P4 timing-clean compute-cycle ratio: `{wavefront_clean_total_ratio:.3f}x`.",
                f"- P3-prior-stream/P3-prior-wavefront compute speedup: `{wavefront_vs_stream_ratio:.3f}x`.",
                f"- P2/P4 cert-wait ratio: `{cert_ratio:.3f}x`.",
                f"- P3-prior-wavefront/P4 timing-clean observed-total ratio, including overhead, is `{observed_wavefront_clean_total_ratio:.3f}x`.",
                f"- Common setup writes: `{setup_cycles(p4_clean)}` cycles "
                "(`cfg_template + cfg_cert + cfg_state`).",
                (
                    f"- P4 conventional uses four one-cycle iteration launches: "
                    f"`issue={p4['issue']}`, `cert_wait={p4['cert_wait']}`."
                ),
                (
                    f"- P4 timing-clean conventional uses the same launches but adds "
                    f"pipeline wait: `issue={p4_clean['issue']}`, "
                    f"`cert_wait={p4_clean['cert_wait']}`."
                ),
                (
                    f"- P3 prior K=4 wavefront uses one 14-digit launch: "
                    f"`issue={p3_prior_wavefront['issue']}`, "
                    f"`cert_wait={p3_prior_wavefront['cert_wait']}`."
                ),
                "",
                "Interpretation: this is a strict same-fixture baseline check, not a",
                "final architecture claim.  It shows the original prior-online operator",
                "boundary is slower than the clean conventional DSP-MAC runtime under",
                "this PageRank fractional contract.  The new solver-level digit-stream",
                "architecture must therefore beat P4, not only P2.",
                "The K=4 prior wavefront is the first same-shell result where",
                "the original prior operator benefits from solver-level digit",
                "streaming; it fuses four PageRank iterations into one runtime",
                "super-step while preserving last-step certification semantics.",
                "The remaining gap to P4 is mainly backend latency: the fused",
                "prior path reduces iteration-boundary restart cost but still pays",
                "a longer prior-operator feed/capture/flush and last-delta wait.",
                "",
                "## P2 Icarus Output",
                "",
                "```text",
                p2_sim.stdout.strip(),
                "```",
                "",
                "## P2-Proxy Full-Digit Icarus Output",
                "",
                "```text",
                p2_proxy_sim.stdout.strip(),
                "```",
                "",
                "## P3 Prior Digit-Stream Icarus Output",
                "",
                "```text",
                p3_prior_stream_sim.stdout.strip(),
                "```",
                "",
                "## P3 Prior K=4 Wavefront Icarus Output",
                "",
                "```text",
                p3_prior_wavefront_sim.stdout.strip(),
                "```",
                "",
                "## P4 Icarus Output",
                "",
                "```text",
                p4_sim.stdout.strip(),
                "```",
                "",
                "## P4 Timing-Clean Icarus Output",
                "",
                "```text",
                p4_clean_sim.stdout.strip(),
                "```",
                "",
            ]
        ),
        encoding="utf-8",
    )
    print(p2_sim.stdout, end="")
    print(p2_proxy_sim.stdout, end="")
    print(p3_prior_stream_sim.stdout, end="")
    print(p3_prior_wavefront_sim.stdout, end="")
    print(p4_sim.stdout, end="")
    print(p4_clean_sim.stdout, end="")
    print(f"Wrote {REPORT}")


if __name__ == "__main__":
    main()
