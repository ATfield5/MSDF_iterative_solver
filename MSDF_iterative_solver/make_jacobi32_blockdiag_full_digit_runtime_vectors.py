#!/usr/bin/env python3
"""
Generate full-digit block-diagonal Jacobi32 runtime vectors.

The earlier ``jacobi32_blockdiag_multi`` fixture was a one-digit-slice runtime
demo: every iteration selected one configured replay digit and committed that
slice-level row update.  ROW_DATAPATH_MODE=3 is a solver-native full digit-stream
path, so it needs a different golden contract:

    state_next = bias + sum_t coeff_t * state_src_t

using the complete committed state word from the previous iteration.
"""

from __future__ import annotations

import argparse
import json
import subprocess
import sys
from pathlib import Path
from typing import Dict, List

from make_jacobi32_blockdiag_runtime_vectors import build_cert_params, build_matrix
from run_iter_rtl_vector_gen import pack_fields, rail_to_uint, write_scalar_memh


def run(cmd: List[str]) -> None:
    subprocess.run(cmd, check=True)


def rail_value(rail: Dict[str, str]) -> int:
    return rail_to_uint(rail, "vec_p") - rail_to_uint(rail, "vec_n")


def saturate_unsigned(value: int, width: int) -> int:
    if value <= 0:
        return 0
    return min(value, (1 << width) - 1)


def conv_cluster_iteration(
    rows: List[Dict[str, object]],
    cert_cluster: Dict[str, object],
    old_p_global: List[int],
    old_n_global: List[int],
    cluster_base: int,
    num_rows: int,
    degree: int,
    data_width: int,
    bound_width: int,
    block_size: int,
    num_blocks: int,
    tail_bound: int,
) -> Dict[str, object]:
    state_p_rows: List[int] = []
    state_n_rows: List[int] = []
    abs_upper_rows: List[int] = []
    bound_max = (1 << bound_width) - 1

    for local_row, row in enumerate(rows):
        row_sum = rail_value(row["bias"]["rail"])
        for term in row["fixed_degree_terms"][:degree]:
            if not int(term["valid"]):
                continue
            src_global = int(term["col"])
            state_term = int(old_p_global[src_global]) - int(old_n_global[src_global])
            coeff_term = rail_value(term["rail"])
            row_sum += coeff_term * state_term

        old_idx = cluster_base + local_row
        old_state = int(old_p_global[old_idx]) - int(old_n_global[old_idx])
        abs_upper_rows.append(min(abs(row_sum - old_state) + int(tail_bound), bound_max))

        if row_sum >= 0:
            state_p_rows.append(saturate_unsigned(row_sum, data_width))
            state_n_rows.append(0)
        else:
            state_p_rows.append(0)
            state_n_rows.append(saturate_unsigned(-row_sum, data_width))

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
        "state_p_rows": state_p_rows,
        "state_n_rows": state_n_rows,
        "abs_upper_rows": abs_upper_rows,
        "block_bounds": block_bounds,
        "max_error": max_error,
        "certified": int(max_error <= eta),
        "packed": {
            "state_p_rows": pack_fields(state_p_rows, data_width),
            "state_n_rows": pack_fields(state_n_rows, data_width),
            "abs_upper_rows": pack_fields(abs_upper_rows, bound_width),
            "block_bounds": pack_fields(block_bounds, bound_width),
        },
    }


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--out-dir",
        type=Path,
        default=Path("MSDF_iterative_solver/generated/rtl_vectors/jacobi32_blockdiag_full_digit"),
    )
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
    args = parser.parse_args()

    args.out_dir.mkdir(parents=True, exist_ok=True)
    g, c = build_matrix(args.num_clusters, args.num_rows)
    matrix_json = args.out_dir / "matrix.json"
    cert_json = args.out_dir / "cert_params.json"
    compiled_json = args.out_dir / "coeff_templates.json"
    template_memh = args.out_dir / "templates.memh"
    cert_memh = args.out_dir / "cert_params.memh"
    num_blocks = (args.num_rows + args.block_size - 1) // args.block_size
    data_width = args.bit_width + 3
    total_rows = args.num_clusters * args.num_rows
    py = sys.executable

    matrix_json.write_text(json.dumps({"G": g.tolist(), "c": c.tolist()}, indent=2), encoding="utf-8")
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
            rec = conv_cluster_iteration(
                rows=rows,
                cert_cluster=cert_data["clusters"][cluster_idx],
                old_p_global=state_p_global,
                old_n_global=state_n_global,
                cluster_base=base,
                num_rows=args.num_rows,
                degree=args.degree,
                data_width=data_width,
                bound_width=args.bound_width,
                block_size=args.block_size,
                num_blocks=num_blocks,
                tail_bound=args.tail_bound,
            )
            cluster_records.append(rec)
            for row in range(args.num_rows):
                next_p[base + row] = int(rec["state_p_rows"][row])
                next_n[base + row] = int(rec["state_n_rows"][row])
        state_p_global = next_p
        state_n_global = next_n
        all_certified = all(int(c["certified"]) for c in cluster_records)
        iter_records.append(
            {
                "iter": iter_idx,
                "clusters": cluster_records,
                "converged": int(all_certified),
                "continue": int(not all_certified),
            }
        )

    write_scalar_memh(
        args.out_dir / "gold_state_p_iters.memh",
        [cluster["packed"]["state_p_rows"] for record in iter_records for cluster in record["clusters"]],
        args.num_rows * data_width,
    )
    write_scalar_memh(
        args.out_dir / "gold_state_n_iters.memh",
        [cluster["packed"]["state_n_rows"] for record in iter_records for cluster in record["clusters"]],
        args.num_rows * data_width,
    )
    write_scalar_memh(
        args.out_dir / "gold_max_error_iters.memh",
        [cluster["max_error"] for record in iter_records for cluster in record["clusters"]],
        args.acc_width,
    )
    write_scalar_memh(
        args.out_dir / "gold_certified_iters.memh",
        [cluster["certified"] for record in iter_records for cluster in record["clusters"]],
        1,
    )
    write_scalar_memh(
        args.out_dir / "gold_iter_converged.memh",
        [record["converged"] for record in iter_records],
        1,
    )
    write_scalar_memh(
        args.out_dir / "gold_iter_continue.memh",
        [record["continue"] for record in iter_records],
        1,
    )

    summary = {
        "contract": "full_digit_blockdiag",
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
        "tail_bound": args.tail_bound,
        "template_memh": str(template_memh),
        "cert_memh": str(cert_memh),
        "iterations": iter_records,
    }
    (args.out_dir / "summary.json").write_text(json.dumps(summary, indent=2), encoding="utf-8")
    print(f"Wrote {args.out_dir}")


if __name__ == "__main__":
    main()
