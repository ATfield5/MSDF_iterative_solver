#!/usr/bin/env python3
"""Generate paper-facing bound/precision sweep for the parallel-in operator."""

from __future__ import annotations

import csv
import json
import math
import subprocess
import sys
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[1]
ITER = ROOT / "MSDF_iterative_solver"
GEN = ITER / "generated"
OUT_ROOT = GEN / "rtl_vectors/paper_parallel_in_bound_sweep"
JSON_OUT = GEN / "parallel_in_bound_sweep.json"
CSV_OUT = GEN / "parallel_in_bound_sweep.csv"
MD_OUT = GEN / "parallel_in_bound_sweep.md"


DEGREES = [4, 8, 32]
DATA_WIDTHS = [16, 24, 32]
BETAS = [0.85, 0.95]
NUM_ITERS = 8


def run(cmd: list[str]) -> subprocess.CompletedProcess[str]:
    return subprocess.run(cmd, cwd=ROOT, check=True, capture_output=True, text=True)


def git_commit() -> str:
    try:
        return run(["git", "rev-parse", "HEAD"]).stdout.strip()
    except Exception:
        return "unknown"


def signed_digit_value(p_word: int, n_word: int, data_width: int) -> int:
    value = 0
    for digit_idx in range(data_width):
        bit_sel = data_width - 1 - digit_idx
        value <<= 1
        p_bit = (p_word >> bit_sel) & 1
        n_bit = (n_word >> bit_sel) & 1
        if p_bit and not n_bit:
            value += 1
        elif n_bit and not p_bit:
            value -= 1
    return value


def flatten_final(summary: dict[str, Any], key: str) -> list[tuple[int, int]]:
    final_record = summary[key][-1]
    out: list[tuple[int, int]] = []
    for cluster in final_record["clusters"]:
        for p_word, n_word in zip(cluster["state_p_rows"], cluster["state_n_rows"]):
            out.append((int(p_word), int(n_word)))
    return out


def first_converged_iter(records: list[dict[str, Any]]) -> int | None:
    for record in records:
        if int(record.get("converged", 0)):
            return int(record["iter"])
    return None


def run_case(degree: int, data_width: int, beta: float) -> dict[str, Any]:
    coeff_bit_width = max(1, data_width - 2)
    beta_tag = str(beta).replace(".", "p")
    out_dir = OUT_ROOT / f"deg{degree}_data{data_width}_beta{beta_tag}"
    cmd = [
        sys.executable,
        "MSDF_iterative_solver/make_pagerank_parallel_in_fractional_vectors.py",
        "--out-dir",
        str(out_dir),
        "--num-iters",
        str(NUM_ITERS),
        "--degree",
        str(degree),
        "--beta",
        str(beta),
        "--data-width",
        str(data_width),
        "--bit-width",
        str(coeff_bit_width),
        "--acc-width",
        "64",
        "--force-delay",
        "2",
    ]
    try:
        proc = run(cmd)
    except subprocess.CalledProcessError as exc:
        return {
            "degree": degree,
            "data_width": data_width,
            "coeff_bit_width": coeff_bit_width,
            "beta": beta,
            "valid": False,
            "error": (exc.stderr or exc.stdout).strip(),
            "command": " ".join(cmd),
        }

    summary = json.loads((out_dir / "summary.json").read_text())
    meta = json.loads((out_dir / "sp_delay_metadata.json").read_text())
    p3_final = flatten_final(summary, "iterations")
    p4_final = flatten_final(summary, "conv_iterations")

    max_abs = 0
    sum_abs = 0
    for (p3_p, p3_n), (p4_p, p4_n) in zip(p3_final, p4_final):
        p3_value = signed_digit_value(p3_p, p3_n, data_width)
        p4_value = p4_p - p4_n
        delta = abs(p3_value - p4_value)
        max_abs = max(max_abs, delta)
        sum_abs += delta
    mean_abs = sum_abs / max(1, len(p3_final))
    scale = float(1 << (data_width - 1))

    return {
        "degree": degree,
        "data_width": data_width,
        "coeff_bit_width": coeff_bit_width,
        "beta": beta,
        "valid": True,
        "command": " ".join(cmd),
        "fixture_dir": str(out_dir),
        "max_ai_plus_bi": float(meta["max_bound"]),
        "derived_delay": int(meta["derived_delay"]),
        "implemented_delay": int(meta["online_delay"]),
        "delta2_safe": int(meta["derived_delay"]) <= 2,
        "bit_width_min": int(meta["bit_width_min"]),
        "bias_width_min": int(meta["bias_width_min"]),
        "acc_width_min": int(meta["acc_width_min"]),
        "final_iter": NUM_ITERS - 1,
        "p3_final_global_l1_delta": int(summary["iterations"][-1]["global_l1_delta"]),
        "p3_final_global_linf_delta": int(summary["iterations"][-1]["global_linf_delta"]),
        "p4_final_global_l1_delta": int(summary["conv_iterations"][-1]["global_l1_delta"]),
        "p4_final_global_linf_delta": int(summary["conv_iterations"][-1]["global_linf_delta"]),
        "p3_converged_iter": first_converged_iter(summary["iterations"]),
        "p4_converged_iter": first_converged_iter(summary["conv_iterations"]),
        "p3_vs_p4_max_abs_raw": max_abs,
        "p3_vs_p4_mean_abs_raw": mean_abs,
        "p3_vs_p4_max_abs_real": max_abs / scale,
        "p3_vs_p4_mean_abs_real": mean_abs / scale,
        "generator_stdout": proc.stdout.strip(),
    }


def write_reports(rows: list[dict[str, Any]]) -> None:
    GEN.mkdir(parents=True, exist_ok=True)
    payload = {
        "title": "Parallel-In Bound Sweep",
        "git_commit": git_commit(),
        "command": "conda run -n qas python MSDF_iterative_solver/run_parallel_in_bound_sweep.py",
        "scope": "mathematical bound and fixed-point model sweep",
        "num_iters": NUM_ITERS,
        "rows": rows,
    }
    JSON_OUT.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n")

    fieldnames = [
        "degree",
        "data_width",
        "coeff_bit_width",
        "beta",
        "valid",
        "max_ai_plus_bi",
        "derived_delay",
        "implemented_delay",
        "delta2_safe",
        "acc_width_min",
        "p3_vs_p4_max_abs_raw",
        "p3_vs_p4_max_abs_real",
        "p3_final_global_linf_delta",
        "p4_final_global_linf_delta",
        "p3_converged_iter",
        "p4_converged_iter",
        "fixture_dir",
    ]
    with CSV_OUT.open("w", newline="", encoding="utf-8") as fp:
        writer = csv.DictWriter(fp, fieldnames=fieldnames, lineterminator="\n")
        writer.writeheader()
        for row in rows:
            writer.writerow({name: row.get(name, "") for name in fieldnames})

    lines = [
        "# Parallel-In Bound Sweep",
        "",
        "Purpose: validate the paper math for the parallel-in online affine operator.",
        "This is a fixed-point model sweep, not a routed hardware report.",
        "",
        f"- git commit: `{payload['git_commit']}`",
        f"- command: `{payload['command']}`",
        f"- iterations generated per case: `{NUM_ITERS}`",
        "",
        "| degree | data width | coeff width | beta | max_i(A_i+B_i) | derived delay | impl delay | delta=2 safe | acc min | max drift raw | max drift real | final Linf P3/P4 |",
        "| ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | --- |",
    ]
    for row in rows:
        if not row.get("valid"):
            lines.append(
                f"| {row['degree']} | {row['data_width']} | {row['coeff_bit_width']} | {row['beta']} | NA | NA | NA | 0 | NA | NA | NA | invalid |"
            )
            continue
        lines.append(
            f"| {row['degree']} | {row['data_width']} | {row['coeff_bit_width']} | {row['beta']:.2f} | "
            f"{row['max_ai_plus_bi']:.8f} | {row['derived_delay']} | {row['implemented_delay']} | "
            f"{1 if row['delta2_safe'] else 0} | {row['acc_width_min']} | "
            f"{row['p3_vs_p4_max_abs_raw']} | {row['p3_vs_p4_max_abs_real']:.6e} | "
            f"{row['p3_final_global_linf_delta']} / {row['p4_final_global_linf_delta']} |"
        )

    invalid = [row for row in rows if not row.get("valid")]
    if invalid:
        lines += ["", "## Invalid Cases", ""]
        for row in invalid:
            lines.append(f"- degree={row['degree']} data_width={row['data_width']} beta={row['beta']}: `{row.get('error', '')}`")

    lines += [
        "",
        "Interpretation:",
        "",
        "- `derived delay <= 2` means the workload satisfies the current implementation's `online_delay=2` contract.",
        "- `max drift` compares the generated parallel-in signed-digit model against the generated conventional rounded fixed-point model for the same fixture.",
        "- This report is used for the paper math table; it does not claim routed FPGA timing.",
        "",
        f"Machine-readable files: `{JSON_OUT}` and `{CSV_OUT}`.",
        "",
    ]
    MD_OUT.write_text("\n".join(lines))


def main() -> None:
    rows = [run_case(degree, data_width, beta) for degree in DEGREES for data_width in DATA_WIDTHS for beta in BETAS]
    write_reports(rows)
    print(f"Wrote {MD_OUT}")
    print(f"Wrote {JSON_OUT}")
    print(f"Wrote {CSV_OUT}")


if __name__ == "__main__":
    main()
