#!/usr/bin/env python3
"""Run the P3-SP/P4-SP parallel-in PageRank operator checkpoint."""

from __future__ import annotations

import json
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
REPORT = ROOT / "MSDF_iterative_solver/generated/parallel_in_fractional_eval.md"
ONLINE_OUT = Path("/tmp/tb_parallel_in_wavefront.vvp")
FEEDBACK_OUT = Path("/tmp/tb_parallel_in_feedback.vvp")
FEEDBACK_STOP_OUT = Path("/tmp/tb_parallel_in_feedback_stop.vvp")
CONV_OUT = Path("/tmp/tb_parallel_in_conv_wavefront.vvp")
CONV_DEG8_OUT = Path("/tmp/tb_parallel_in_conv_wavefront_deg8.vvp")
DEG8_VECTOR_DIR = Path("MSDF_iterative_solver/generated/rtl_vectors/pagerank32_global_parallel_in_fractional_deg8")


def run(cmd: list[str]) -> subprocess.CompletedProcess[str]:
    return subprocess.run(cmd, cwd=ROOT, check=True, capture_output=True, text=True)


def counter_line(text: str) -> str:
    for line in text.splitlines():
        if line.startswith("COUNTERS "):
            return line
    raise RuntimeError("missing COUNTERS line")


def parse_counter_value(line: str, key: str) -> int:
    for field in line.split():
        if field.startswith(key + "="):
            return int(field.split("=", 1)[1], 0)
    raise RuntimeError(f"missing {key} in {line}")


def signed_digit_value(p_word: int, n_word: int, data_width: int) -> int:
    value = 0
    for digit_idx in range(data_width):
        bit_sel = data_width - 1 - digit_idx
        value <<= 1
        p = (p_word >> bit_sel) & 1
        n = (n_word >> bit_sel) & 1
        if p and not n:
            value += 1
        elif n and not p:
            value -= 1
    return value


def final_state_drift(summary: dict) -> tuple[int, int]:
    data_width = int(summary["data_width"])
    final_iter = int(summary["num_iters"]) - 1
    p3_clusters = summary["iterations"][final_iter]["clusters"]
    p4_clusters = summary["conv_iterations"][final_iter]["clusters"]
    max_abs = 0
    sum_abs = 0
    for p3_cluster, p4_cluster in zip(p3_clusters, p4_clusters):
        for p3_p, p3_n, p4_p, p4_n in zip(
            p3_cluster["state_p_rows"],
            p3_cluster["state_n_rows"],
            p4_cluster["state_p_rows"],
            p4_cluster["state_n_rows"],
        ):
            p3_value = signed_digit_value(int(p3_p), int(p3_n), data_width)
            p4_value = int(p4_p) - int(p4_n)
            delta = abs(p3_value - p4_value)
            max_abs = max(max_abs, delta)
            sum_abs += delta
    return max_abs, sum_abs


def main() -> None:
    run([
        sys.executable,
        "MSDF_iterative_solver/make_pagerank_parallel_in_fractional_vectors.py",
        "--num-iters",
        "8",
        "--force-delay",
        "2",
        "--data-width",
        "32",
        "--bit-width",
        "30",
        "--acc-width",
        "64",
    ])

    online_sources = [
        "MSDF_iterative_solver/rtl/iter_fixed_degree_template_unpack.v",
        "MSDF_iterative_solver/prior_rtl/iter_parallel_in_online_mma8_frac_core.v",
        "MSDF_iterative_solver/prior_rtl/iter_parallel_in_online_mma8_stage_cluster.v",
        "MSDF_iterative_solver/prior_rtl/iter_parallel_in_online_mma8_global_wavefront_top.v",
        "MSDF_iterative_solver/tb/tb_iter_parallel_in_online_mma8_global_wavefront_top.v",
    ]
    run([
        "iverilog",
        "-g2012",
        "-I",
        "MSDF_iterative_solver/tb",
        "-o",
        str(ONLINE_OUT),
        *online_sources,
    ])
    online_sim = run(["vvp", str(ONLINE_OUT)])
    online_line = counter_line(online_sim.stdout)
    online_total = parse_counter_value(online_line, "total")
    capture = parse_counter_value(online_line, "capture")
    delay = parse_counter_value(online_line, "delay")

    feedback_sources = [
        "MSDF_iterative_solver/rtl/iter_fixed_degree_template_unpack.v",
        "MSDF_iterative_solver/prior_rtl/iter_parallel_in_online_mma8_frac_core.v",
        "MSDF_iterative_solver/prior_rtl/iter_parallel_in_online_mma8_stage_cluster.v",
        "MSDF_iterative_solver/prior_rtl/iter_parallel_in_online_mma8_global_feedback_top.v",
        "MSDF_iterative_solver/tb/tb_iter_parallel_in_online_mma8_global_feedback_top.v",
    ]
    run([
        "iverilog",
        "-g2012",
        "-I",
        "MSDF_iterative_solver/tb",
        "-o",
        str(FEEDBACK_OUT),
        *feedback_sources,
    ])
    feedback_sim = run(["vvp", str(FEEDBACK_OUT)])
    feedback_line = counter_line(feedback_sim.stdout)
    feedback_total = parse_counter_value(feedback_line, "total")
    feedback_supersteps = parse_counter_value(feedback_line, "final_supersteps")
    feedback_capture = parse_counter_value(feedback_line, "capture")
    feedback_linf_eta = parse_counter_value(feedback_line, "linf_eta")
    feedback_converged = parse_counter_value(feedback_line, "converged")

    run([
        "iverilog",
        "-g2012",
        "-I",
        "MSDF_iterative_solver/tb",
        "-DPARALLEL_IN_FEEDBACK_EXPECT_CONVERGED_VALUE=1",
        "-DPARALLEL_IN_FEEDBACK_LINF_ETA_VALUE=2147483647",
        "-o",
        str(FEEDBACK_STOP_OUT),
        *feedback_sources,
    ])
    feedback_stop_sim = run(["vvp", str(FEEDBACK_STOP_OUT)])
    feedback_stop_line = counter_line(feedback_stop_sim.stdout)
    feedback_stop_total = parse_counter_value(feedback_stop_line, "total")
    feedback_stop_converged = parse_counter_value(feedback_stop_line, "converged")
    feedback_stop_kill = parse_counter_value(feedback_stop_line, "kill")

    conv_sources = [
        "MSDF_iterative_solver/rtl/iter_fixed_degree_template_unpack.v",
        "MSDF_iterative_solver/rtl/conv_signed_row_update_delta_slice_pipe.v",
        "MSDF_iterative_solver/prior_rtl/iter_parallel_in_conv_mma8_parallel_rows_top.v",
        "MSDF_iterative_solver/tb/tb_iter_parallel_in_conv_mma8_parallel_rows_top.v",
    ]
    run([
        "iverilog",
        "-g2012",
        "-I",
        "MSDF_iterative_solver/tb",
        "-o",
        str(CONV_OUT),
        *conv_sources,
    ])
    conv_sim = run(["vvp", str(CONV_OUT)])
    conv_line = counter_line(conv_sim.stdout)
    conv_total = parse_counter_value(conv_line, "total_compute")
    conv_iterations = parse_counter_value(conv_line, "iterations")
    conv_row_lanes = parse_counter_value(conv_line, "row_lanes")
    conv_macs_per_row = parse_counter_value(conv_line, "macs_per_row")
    product_shift = parse_counter_value(conv_line, "product_shift")

    run([
        sys.executable,
        "MSDF_iterative_solver/make_pagerank_parallel_in_fractional_vectors.py",
        "--out-dir",
        str(DEG8_VECTOR_DIR),
        "--num-iters",
        "8",
        "--degree",
        "8",
        "--force-delay",
        "2",
        "--data-width",
        "32",
        "--bit-width",
        "30",
        "--acc-width",
        "64",
    ])
    run([
        "iverilog",
        "-g2012",
        "-I",
        "MSDF_iterative_solver/tb",
        "-DPARALLEL_IN_DEGREE_VALUE=8",
        f'-DPARALLEL_IN_VECTOR_DIR="{DEG8_VECTOR_DIR}"',
        "-o",
        str(CONV_DEG8_OUT),
        *conv_sources,
    ])
    conv_deg8_sim = run(["vvp", str(CONV_DEG8_OUT)])
    conv_deg8_line = counter_line(conv_deg8_sim.stdout)
    conv_deg8_total = parse_counter_value(conv_deg8_line, "total_compute")
    conv_deg8_iterations = parse_counter_value(conv_deg8_line, "iterations")
    conv_deg8_row_lanes = parse_counter_value(conv_deg8_line, "row_lanes")
    conv_deg8_macs_per_row = parse_counter_value(conv_deg8_line, "macs_per_row")

    meta_path = ROOT / "MSDF_iterative_solver/generated/rtl_vectors/pagerank32_global_parallel_in_fractional/sp_delay_metadata.json"
    summary_path = ROOT / "MSDF_iterative_solver/generated/rtl_vectors/pagerank32_global_parallel_in_fractional/summary.json"
    meta = json.loads(meta_path.read_text(encoding="utf-8"))
    summary = json.loads(summary_path.read_text(encoding="utf-8"))
    row_bounds = meta["row_bounds"]
    p3_internal_acc_width = 33
    p4_acc_width = 40
    p4_product_width = 66
    drift_max_abs, drift_sum_abs = final_state_drift(summary)

    REPORT.parent.mkdir(parents=True, exist_ok=True)
    REPORT.write_text(
        "\n".join([
            "# Parallel-In Fractional P3-SP vs P4-SP Checkpoint",
            "",
            "This report is the standalone checkpoint for the 32-bit P3-SP parallel-in PageRank wavefront and the P4-SP one-stage conventional baseline.",
            "P3-SP keeps the K-stage online wavefront. P4-SP follows the conventional baseline policy requested here: 32 rows run in parallel, each row has 8 full-word MAC slots, and K stages are not physically expanded.",
            "",
            "## Delay Bound",
            "",
            f"- Formula: `{meta['formula']}`",
            f"- max_i(A_i+B_i): `{meta['max_bound']:.8f}`",
            f"- derived delay: `{meta['derived_delay']}`",
            f"- implemented global delay: `{meta['online_delay']}`",
            f"- min/max row bound: `{min(row_bounds):.8f}` / `{max(row_bounds):.8f}`",
            f"- external DATA_WIDTH: `{summary['data_width']}`",
            f"- external coefficient BIT_WIDTH: `{summary['bit_width']}`",
            f"- packed bias width: `{summary['bias_width']}`",
            f"- P3-SP internal accumulator width: `{p3_internal_acc_width}`",
            f"- P4-SP product width: `{p4_product_width}`",
            f"- P4-SP accumulator width: `{p4_acc_width}`",
            f"- minimum coefficient width: `{meta['bit_width_min']}`",
            f"- minimum bias magnitude width: `{meta['bias_width_min']}`",
            f"- minimum residual accumulator width: `{meta['acc_width_min']}`",
            "",
            "## Functional / Cycle Checkpoint",
            "",
            "| entry | pass | physical shape | observed cycles | output form | fixture |",
            "| --- | ---: | --- | ---: | --- | --- |",
            f"| P3-SP parallel-in online wavefront | yes | 4 K-stages x 32 rows x 8 coeff-select slots | {online_total} | {capture} streamed digits | {summary['fixture']} |",
            f"| P3-SP feedback loop pipeline | yes | 4 reusable K-stages x 32 rows x 8 coeff-select slots, feedback FIFO, Linf stop check | {feedback_total} | {feedback_supersteps} supersteps / {feedback_capture} final-stage digits | {summary['fixture']} |",
            f"| P3-SP feedback forced-stop smoke | yes | same feedback RTL, relaxed Linf eta to verify stop/kill control | {feedback_stop_total} | converged={feedback_stop_converged}, killed_digits={feedback_stop_kill} | {summary['fixture']} |",
            f"| P4-SP conventional 32-row parallel DSP-MAC | yes | {conv_iterations} feedback iterations on 1 stage x {conv_row_lanes} row lanes x {conv_macs_per_row} parallel 32x32 MAC slots/row | {conv_total} | 32-bit full-word p/n rails | {summary['fixture']} |",
            f"| P4-SP conventional degree8 32-row parallel DSP-MAC | yes | {conv_deg8_iterations} feedback iterations on 1 stage x {conv_deg8_row_lanes} row lanes x {conv_deg8_macs_per_row} parallel 32x32 MAC slots/row | {conv_deg8_total} | 32-bit full-word p/n rails | pagerank32_global_parallel_in_fractional_deg8 |",
            "",
            "## Software P3/P4 Model Drift",
            "",
            "| metric | value |",
            "| --- | ---: |",
            f"| max absolute raw-state drift | {drift_max_abs} |",
            f"| sum absolute raw-state drift | {drift_sum_abs} |",
            f"| P4 product shift | {product_shift} |",
            "",
            "This drift is computed from the Python P3/P4 K=4 models in the shared fixture.",
            "The parallel-row P4-SP RTL test itself checks four consecutive conventional feedback iterations over all 32 rows against `conv_gold_state_*`.",
            "",
            "## Numeric Contract Note",
            "",
            "The P3-SP external state/output contract is now a 32-digit MSB-first signed-digit stream.",
            "The 33-bit internal accumulator is derived from the instantaneous coefficient-digit and bias-digit bound; it is not the output precision.",
            "P4-SP uses 32 parallel row lanes.  Each row lane has eight parallel 32-bit x 32-bit signed MAC slots, 66-bit product guards, and a 40-bit accumulator; each product is rounded by `2^32` before row summation.",
            "",
            "The P3-SP standalone total starts after reset release and includes the one 32-digit input launch plus wavefront drain.",
            "The P4-SP total is four feedback iterations over all 32 rows using the same one-stage datapath repeatedly; it is not a K-stage physical wavefront.",
            "Runtime configuration/state preload overhead is intentionally outside this checkpoint.",
            "",
            "## Feedback Loop / Termination",
            "",
            "The feedback loop uses the same convergence predicate as the original PageRank algorithm in the paper:",
            "",
            "$$",
            "\\max_i |r_i^{(k+1)}-r_i^{(k)}| \\le 2^{-q}",
            "$$",
            "",
            f"For this `{summary['data_width']}`-digit fixed-point fixture, the hardware threshold is `{feedback_linf_eta}` raw LSB.",
            f"The default test drives two K-stage supersteps and reports `converged={feedback_converged}`; it does not force early stop unless the Linf predicate is actually true.",
            f"A separate forced-stop smoke sets a relaxed threshold and confirms the stop path with `converged={feedback_stop_converged}` and `killed_digits={feedback_stop_kill}`.",
            "",
            "## Icarus Output",
            "",
            "```text",
            online_sim.stdout.strip(),
            "```",
            "",
            "## Icarus Output: P3-SP Feedback",
            "",
            "```text",
            feedback_sim.stdout.strip(),
            "```",
            "",
            "## Icarus Output: P3-SP Feedback Forced Stop",
            "",
            "```text",
            feedback_stop_sim.stdout.strip(),
            "```",
            "",
            "## Icarus Output: P4-SP",
            "",
            "```text",
            conv_sim.stdout.strip(),
            "```",
            "",
            "## Icarus Output: P4-SP Degree8",
            "",
            "```text",
            conv_deg8_sim.stdout.strip(),
            "```",
            "",
        ]),
        encoding="utf-8",
    )
    print(online_sim.stdout, end="")
    print(feedback_sim.stdout, end="")
    print(feedback_stop_sim.stdout, end="")
    print(conv_sim.stdout, end="")
    print(conv_deg8_sim.stdout, end="")
    print(f"Wrote {REPORT}")


if __name__ == "__main__":
    main()
