#!/usr/bin/env python3
"""
Generate runtime vectors for the first inter-cluster Jacobi32 checkpoint.

Unlike the block-diagonal fixtures, this uses the existing banded 32x32 matrix
and packs source-row indices as active-window global row indices. The RTL
therefore has to replay source digits from any row in the 32-row active window.
"""

from __future__ import annotations

import argparse
import json
import subprocess
import sys
from pathlib import Path
from typing import Dict, List

import numpy as np

from make_jacobi32_blockdiag_runtime_vectors import build_cert_params
from run_iter_rtl_vector_gen import pack_fields, rtl_row_update, write_scalar_memh


def run(cmd: List[str]) -> None:
    subprocess.run(cmd, check=True)


def bit(value: int, idx: int) -> int:
    return (value >> idx) & 1


def compute_cluster_iteration(
    rows: List[Dict[str, object]],
    cert_cluster: Dict[str, object],
    old_p_global: List[int],
    old_n_global: List[int],
    cluster_base: int,
    num_rows: int,
    degree: int,
    bit_width: int,
    data_width: int,
    bound_width: int,
    block_size: int,
    num_blocks: int,
    replay_digit_idx: int,
    tail_bound: int,
) -> Dict[str, object]:
    bit_sel = data_width - 1 - replay_digit_idx
    sum_p_rows: List[int] = []
    sum_n_rows: List[int] = []
    abs_upper_rows: List[int] = []

    for local_row, row in enumerate(rows):
        x_terms: List[int] = []
        for term in row["fixed_degree_terms"][:degree]:
            if not int(term["valid"]):
                x_terms.append(0)
                continue
            src_global = int(term["col"])
            digit_p = bit(old_p_global[src_global], bit_sel)
            digit_n = bit(old_n_global[src_global], bit_sel)
            x_terms.append(digit_p - digit_n)

        while len(x_terms) < degree:
            x_terms.append(0)

        row_sum_p, row_sum_n = rtl_row_update(
            coeff_terms=row["fixed_degree_terms"],
            bias_rail=row["bias"]["rail"],
            x_terms=x_terms,
            bit_width=bit_width,
        )
        sum_p_rows.append(row_sum_p)
        sum_n_rows.append(row_sum_n)

        old_idx = cluster_base + local_row
        delta_word = (row_sum_p - row_sum_n) - (old_p_global[old_idx] - old_n_global[old_idx])
        abs_upper_rows.append(abs(delta_word) + tail_bound)

    block_bounds: List[int] = []
    for block_idx in range(num_blocks):
        start = block_idx * block_size
        stop = min(start + block_size, num_rows)
        block_bounds.append(max(abs_upper_rows[start:stop]))

    weights = [int(v) for v in cert_cluster["block_weights"]]
    eta = int(cert_cluster["eta"])
    max_error = 0
    for row_idx in range(num_rows):
        row_error = 0
        for block_idx in range(num_blocks):
            row_error += block_bounds[block_idx] * weights[row_idx * num_blocks + block_idx]
        max_error = max(max_error, row_error)

    return {
        "state_p_rows": sum_p_rows,
        "state_n_rows": sum_n_rows,
        "abs_upper_rows": abs_upper_rows,
        "block_bounds": block_bounds,
        "max_error": max_error,
        "certified": int(max_error <= eta),
        "packed": {
            "state_p_rows": pack_fields(sum_p_rows, data_width),
            "state_n_rows": pack_fields(sum_n_rows, data_width),
            "abs_upper_rows": pack_fields(abs_upper_rows, bound_width),
            "block_bounds": pack_fields(block_bounds, bound_width),
        },
    }


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--matrix-json", type=Path, default=Path("MSDF_iterative_solver/generated/jacobi32_matrix.json"))
    parser.add_argument("--out-dir", type=Path, default=Path("MSDF_iterative_solver/generated/rtl_vectors/jacobi32_global"))
    parser.add_argument("--num-clusters", type=int, default=8)
    parser.add_argument("--num-rows", type=int, default=4)
    parser.add_argument("--degree", type=int, default=4)
    parser.add_argument("--num-iters", type=int, default=6)
    parser.add_argument("--bit-width", type=int, default=8)
    parser.add_argument("--frac-bits", type=int, default=6)
    parser.add_argument("--bound-width", type=int, default=13)
    parser.add_argument("--coeff-width", type=int, default=8)
    parser.add_argument("--acc-width", type=int, default=24)
    parser.add_argument("--block-size", type=int, default=2)
    parser.add_argument("--cert-weight-scale", type=int, default=16)
    parser.add_argument("--cert-eta", type=int, default=4095)
    parser.add_argument("--tail-bound", type=int, default=1)
    parser.add_argument("--replay-digit-idx", type=int, default=10)
    args = parser.parse_args()

    args.out_dir.mkdir(parents=True, exist_ok=True)
    matrix = json.loads(args.matrix_json.read_text(encoding="utf-8"))
    g = np.asarray(matrix["G"], dtype=np.float64)
    c = np.asarray(matrix["c"], dtype=np.float64)

    total_rows = args.num_clusters * args.num_rows
    if g.shape != (total_rows, total_rows):
        raise ValueError(f"expected {total_rows}x{total_rows} matrix, got {g.shape}")
    src_idx_width = max(1, int(np.ceil(np.log2(total_rows))))
    num_blocks = (args.num_rows + args.block_size - 1) // args.block_size
    data_width = args.bit_width + 3
    py = sys.executable

    matrix_json = args.out_dir / "matrix.json"
    cert_json = args.out_dir / "cert_params.json"
    compiled_json = args.out_dir / "coeff_templates.json"
    template_memh = args.out_dir / "templates.memh"
    cert_memh = args.out_dir / "cert_params.memh"
    matrix_json.write_text(json.dumps(matrix, indent=2), encoding="utf-8")
    cert_json.write_text(
        json.dumps(
            build_cert_params(
                g=g,
                num_clusters=args.num_clusters,
                rows_per_cluster=args.num_rows,
                block_size=args.block_size,
                weight_scale=args.cert_weight_scale,
                eta=args.cert_eta,
                coeff_width=args.coeff_width,
            ),
            indent=2,
        ),
        encoding="utf-8",
    )

    run(
        [
            py,
            "MSDF_iterative_solver/compile_coeff_templates.py",
            "--matrix-json",
            str(matrix_json),
            "--frac-bits",
            str(args.frac_bits),
            "--bit-width",
            str(args.bit_width),
            "--max-terms",
            str(args.degree),
            "--fixed-degree",
            str(args.degree),
            "--output-json",
            str(compiled_json),
        ]
    )
    run(
        [
            py,
            "MSDF_iterative_solver/pack_fixed_degree_templates.py",
            "--compiled-json",
            str(compiled_json),
            "--num-clusters",
            str(args.num_clusters),
            "--num-rows",
            str(args.num_rows),
            "--degree",
            str(args.degree),
            "--bit-width",
            str(args.bit_width),
            "--src-index-mode",
            "global",
            "--src-index-width",
            str(src_idx_width),
            "--output-memh",
            str(template_memh),
        ]
    )
    run(
        [
            py,
            "MSDF_iterative_solver/pack_cert_params.py",
            "--cert-json",
            str(cert_json),
            "--num-clusters",
            str(args.num_clusters),
            "--num-rows",
            str(args.num_rows),
            "--num-blocks",
            str(num_blocks),
            "--coeff-width",
            str(args.coeff_width),
            "--acc-width",
            str(args.acc_width),
            "--output-memh",
            str(cert_memh),
        ]
    )

    compiled = json.loads(compiled_json.read_text(encoding="utf-8"))
    cert_data = json.loads(cert_json.read_text(encoding="utf-8"))
    state_p_global = [0 for _ in range(total_rows)]
    state_n_global = [0 for _ in range(total_rows)]
    iter_records: List[Dict[str, object]] = []

    for iter_idx in range(args.num_iters):
        cluster_records: List[Dict[str, object]] = []
        next_p = [0 for _ in range(total_rows)]
        next_n = [0 for _ in range(total_rows)]
        for cluster_idx in range(args.num_clusters):
            base = cluster_idx * args.num_rows
            rows = compiled["rows"][base : base + args.num_rows]
            rec = compute_cluster_iteration(
                rows=rows,
                cert_cluster=cert_data["clusters"][cluster_idx],
                old_p_global=state_p_global,
                old_n_global=state_n_global,
                cluster_base=base,
                num_rows=args.num_rows,
                degree=args.degree,
                bit_width=args.bit_width,
                data_width=data_width,
                bound_width=args.bound_width,
                block_size=args.block_size,
                num_blocks=num_blocks,
                replay_digit_idx=args.replay_digit_idx,
                tail_bound=args.tail_bound,
            )
            cluster_records.append(rec)
            for row in range(args.num_rows):
                next_p[base + row] = int(rec["state_p_rows"][row])
                next_n[base + row] = int(rec["state_n_rows"][row])
        state_p_global = next_p
        state_n_global = next_n
        iter_records.append(
            {
                "iter": iter_idx,
                "clusters": cluster_records,
                "converged": int(all(int(c["certified"]) for c in cluster_records)),
                "continue": int(not all(int(c["certified"]) for c in cluster_records)),
            }
        )

    flat_state_p = []
    flat_state_n = []
    flat_max_error = []
    flat_certified = []
    for iter_rec in iter_records:
        for cluster_rec in iter_rec["clusters"]:
            flat_state_p.append(cluster_rec["packed"]["state_p_rows"])
            flat_state_n.append(cluster_rec["packed"]["state_n_rows"])
            flat_max_error.append(cluster_rec["max_error"])
            flat_certified.append(cluster_rec["certified"])

    write_scalar_memh(args.out_dir / "gold_state_p_iters.memh", flat_state_p, args.num_rows * data_width)
    write_scalar_memh(args.out_dir / "gold_state_n_iters.memh", flat_state_n, args.num_rows * data_width)
    write_scalar_memh(args.out_dir / "gold_max_error_iters.memh", flat_max_error, args.acc_width)
    write_scalar_memh(args.out_dir / "gold_certified_iters.memh", flat_certified, 1)
    write_scalar_memh(args.out_dir / "gold_iter_converged.memh", [r["converged"] for r in iter_records], 1)
    write_scalar_memh(args.out_dir / "gold_iter_continue.memh", [r["continue"] for r in iter_records], 1)

    summary = {
        "num_clusters": args.num_clusters,
        "num_rows": args.num_rows,
        "degree": args.degree,
        "num_iters": args.num_iters,
        "bit_width": args.bit_width,
        "bound_width": args.bound_width,
        "coeff_width": args.coeff_width,
        "acc_width": args.acc_width,
        "block_size": args.block_size,
        "num_blocks": num_blocks,
        "data_width": data_width,
        "src_idx_width": src_idx_width,
        "tail_bound": args.tail_bound,
        "replay_digit_idx": args.replay_digit_idx,
        "template_memh": str(template_memh),
        "cert_memh": str(cert_memh),
        "iterations": iter_records,
    }
    (args.out_dir / "summary.json").write_text(json.dumps(summary, indent=2), encoding="utf-8")
    print(f"Wrote {args.out_dir}")
    print("max_error_by_iter=" + json.dumps([[c["max_error"] for c in r["clusters"]] for r in iter_records]))
    print("converged_by_iter=" + json.dumps([r["converged"] for r in iter_records]))


if __name__ == "__main__":
    main()
