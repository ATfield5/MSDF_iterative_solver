#!/usr/bin/env python3
"""Benchmark NumPy/OpenBLAS PageRank throughput on the local CPU.

The script intentionally mirrors the current dense PageRank fixture used by the
parallel-in online experiments: N=32, dense 32-term rows, and repeated PageRank
matrix-vector updates.
"""

from __future__ import annotations

import argparse
import json
import os
import pathlib
import statistics
import time
from typing import Any

# These must be set before importing NumPy so OpenBLAS sees the requested
# thread count when the library is initialized.
DEFAULT_THREADS = "32"
os.environ.setdefault("OPENBLAS_NUM_THREADS", DEFAULT_THREADS)
os.environ.setdefault("OMP_NUM_THREADS", DEFAULT_THREADS)
os.environ.setdefault("MKL_NUM_THREADS", DEFAULT_THREADS)
os.environ.setdefault("NUMEXPR_NUM_THREADS", DEFAULT_THREADS)

import numpy as np

try:
    from threadpoolctl import threadpool_info
except Exception:  # pragma: no cover - optional dependency
    threadpool_info = lambda: []  # type: ignore


def _rail_to_int(rail: dict[str, Any]) -> int:
    return int(rail.get("vec_p", "0"), 2) - int(rail.get("vec_n", "0"), 2)


def load_fixture(path: pathlib.Path) -> tuple[np.ndarray, np.ndarray, dict[str, Any]]:
    coeff_templates = json.loads((path / "coeff_templates.json").read_text())
    summary = json.loads((path / "summary.json").read_text())
    n = int(coeff_templates["n"])
    frac_bits = int(coeff_templates["frac_bits"])
    scale = float(1 << frac_bits)

    matrix = np.zeros((n, n), dtype=np.float64)
    bias = np.zeros(n, dtype=np.float64)
    for row in coeff_templates["rows"]:
        row_idx = int(row["row"])
        for term in row["fixed_degree_terms"]:
            if int(term.get("valid", 0)):
                matrix[row_idx, int(term["col"])] += int(term["quant"]) / scale

        raw_bias = row.get("bias", {})
        if isinstance(raw_bias, dict):
            if "quant" in raw_bias:
                bias[row_idx] = int(raw_bias["quant"]) / scale
            elif "rail" in raw_bias:
                bias[row_idx] = _rail_to_int(raw_bias["rail"]) / scale
        elif raw_bias:
            bias[row_idx] = float(raw_bias) / scale

    if not np.any(bias):
        beta = float(summary.get("beta", 0.85))
        bias[:] = (1.0 - beta) / float(n)

    return matrix, bias, summary


def bench(args: argparse.Namespace) -> dict[str, Any]:
    matrix, bias, summary = load_fixture(args.fixture_dir)
    n = matrix.shape[0]
    iters = int(args.iters)
    term_ops_per_iter = n * n
    flop_per_iter = 2 * n * n + n

    r0 = np.full(n, 1.0 / n, dtype=np.float64)

    # Warm up BLAS dispatch, caches, and branch predictors.
    r = r0.copy()
    for _ in range(args.warmup):
        r = matrix @ r + bias

    full_times: list[float] = []
    checksum = 0.0
    for _ in range(args.repeats):
        start = time.perf_counter_ns()
        for _ in range(args.inner_runs):
            r = r0.copy()
            for _ in range(iters):
                r = matrix @ r + bias
            checksum += float(r[0])
        stop = time.perf_counter_ns()
        full_times.append((stop - start) / args.inner_runs / 1e9)

    kernel_times: list[float] = []
    r = r0.copy()
    for _ in range(args.kernel_repeats):
        start = time.perf_counter_ns()
        for _ in range(args.kernel_inner):
            r = matrix @ r + bias
        stop = time.perf_counter_ns()
        kernel_times.append((stop - start) / args.kernel_inner / 1e9)
        checksum += float(r[0])

    full_mean = statistics.mean(full_times)
    full_stdev = statistics.stdev(full_times) if len(full_times) > 1 else 0.0
    kernel_mean = statistics.mean(kernel_times)
    kernel_stdev = statistics.stdev(kernel_times) if len(kernel_times) > 1 else 0.0

    cpu_model = "unknown"
    try:
        text = pathlib.Path("/proc/cpuinfo").read_text()
        cpu_model = text.split("model name", 1)[1].split("\n", 1)[0].split(":", 1)[1].strip()
    except Exception:
        pass

    return {
        "cpu_model": cpu_model,
        "env_threads": {
            name: os.environ.get(name)
            for name in ["OPENBLAS_NUM_THREADS", "OMP_NUM_THREADS", "MKL_NUM_THREADS", "NUMEXPR_NUM_THREADS"]
        },
        "threadpool_info": threadpool_info(),
        "fixture": str(args.fixture_dir),
        "summary_fixture": summary.get("fixture"),
        "n": n,
        "iters_per_pagerank_run": iters,
        "term_ops_per_iter": term_ops_per_iter,
        "flop_per_iter_est": flop_per_iter,
        "row_sum_min": float(matrix.sum(axis=1).min()),
        "row_sum_max": float(matrix.sum(axis=1).max()),
        "bias_sum": float(bias.sum()),
        "full_13iter_mean_s": full_mean,
        "full_13iter_stdev_s": full_stdev,
        "full_repeats": args.repeats,
        "full_inner_runs": args.inner_runs,
        "full_pagerank_runs_per_s": 1.0 / full_mean,
        "full_iterations_per_s": iters / full_mean,
        "full_term_ops_per_s": iters * term_ops_per_iter / full_mean,
        "full_gterm_ops_per_s": iters * term_ops_per_iter / full_mean / 1e9,
        "full_gflops_est": iters * flop_per_iter / full_mean / 1e9,
        "kernel_iter_mean_s": kernel_mean,
        "kernel_iter_stdev_s": kernel_stdev,
        "kernel_repeats": args.kernel_repeats,
        "kernel_inner": args.kernel_inner,
        "kernel_iterations_per_s": 1.0 / kernel_mean,
        "kernel_term_ops_per_s": term_ops_per_iter / kernel_mean,
        "kernel_gterm_ops_per_s": term_ops_per_iter / kernel_mean / 1e9,
        "kernel_gflops_est": flop_per_iter / kernel_mean / 1e9,
        "checksum": checksum,
    }


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--fixture-dir",
        type=pathlib.Path,
        default=pathlib.Path("MSDF_iterative_solver/generated/rtl_vectors/pagerank32_global_parallel_in_fractional_deg32"),
    )
    parser.add_argument("--iters", type=int, default=13)
    parser.add_argument("--warmup", type=int, default=2000)
    parser.add_argument("--repeats", type=int, default=30)
    parser.add_argument("--inner-runs", type=int, default=2000)
    parser.add_argument("--kernel-repeats", type=int, default=30)
    parser.add_argument("--kernel-inner", type=int, default=100000)
    parser.add_argument("--json-out", type=pathlib.Path, default=None)
    parser.add_argument(
        "--md-out",
        type=pathlib.Path,
        default=pathlib.Path("MSDF_iterative_solver/generated/numpy_pagerank_cpu_32thread_benchmark.md"),
    )
    args = parser.parse_args()

    result = bench(args)
    print(json.dumps(result, indent=2, sort_keys=True))
    if args.json_out is not None:
        args.json_out.parent.mkdir(parents=True, exist_ok=True)
        args.json_out.write_text(json.dumps(result, indent=2, sort_keys=True) + "\n")
    if args.md_out is not None:
        args.md_out.parent.mkdir(parents=True, exist_ok=True)
        args.md_out.write_text(
            "\n".join(
                [
                    "# NumPy 32-Thread PageRank CPU Throughput Benchmark",
                    "",
                    "This report records the local CPU software baseline for the dense PageRank32 fixture.",
                    "It is a software reference only; it must not be mixed with FPGA LUT/DSP resource rows.",
                    "",
                    "## Platform",
                    "",
                    "| Item | Value |",
                    "| --- | --- |",
                    f"| CPU | {result['cpu_model']} |",
                    "| Logical threads | 32 |",
                    "| NumPy | measured in `benchmark_numpy_pagerank_cpu.py` runtime environment |",
                    "| BLAS | NumPy/OpenBLAS through current conda `qas` environment |",
                    f"| Thread env | `{result['env_threads']}` |",
                    f"| Fixture | `{pathlib.Path(str(result['fixture'])).name}` |",
                    f"| Matrix shape | dense `{result['n']} x {result['n']}` |",
                    f"| Terms per iteration | `{result['term_ops_per_iter']}` |",
                    f"| Estimated FLOPs per iteration | `{result['flop_per_iter_est']}` |",
                    "",
                    "## Measured CPU Throughput",
                    "",
                    "| CPU measurement | Mean time | Throughput |",
                    "| --- | ---: | ---: |",
                    f"| Full {result['iters_per_pagerank_run']}-iteration PageRank run | `{result['full_13iter_mean_s']:.9e} s` | `{result['full_pagerank_runs_per_s']:.3f} runs/s` |",
                    f"| Full-run iteration throughput | same run | `{result['full_iterations_per_s']:.6e} iter/s` |",
                    f"| Full-run term throughput | same run | `{result['full_gterm_ops_per_s']:.6f} Gterm/s` |",
                    f"| Full-run estimated FLOP throughput | same run | `{result['full_gflops_est']:.6f} GFLOP/s` |",
                    f"| Repeated single-iteration kernel | `{result['kernel_iter_mean_s']:.9e} s/iter` | `{result['kernel_iterations_per_s']:.6e} iter/s` |",
                    f"| Kernel term throughput | same kernel | `{result['kernel_gterm_ops_per_s']:.6f} Gterm/s` |",
                    f"| Kernel estimated FLOP throughput | same kernel | `{result['kernel_gflops_est']:.6f} GFLOP/s` |",
                    "",
                    "## Notes",
                    "",
                    "The benchmark repeats:",
                    "",
                    "$$",
                    "r^{(k+1)} = A r^{(k)} + b",
                    "$$",
                    "",
                    "For this small `32 x 32` matrix, Python/NumPy call overhead remains visible even with 32 OpenBLAS threads.",
                    "",
                ]
            ),
            encoding="utf-8",
        )


if __name__ == "__main__":
    main()
