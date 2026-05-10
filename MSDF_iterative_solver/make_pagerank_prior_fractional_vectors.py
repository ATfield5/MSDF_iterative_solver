#!/usr/bin/env python3
"""Generate PageRank vectors for the original prior-online fractional contract.

The earlier ``pagerank32_global_full_digit`` fixture uses the integer affine
contract of the bring-up runtime:

    x_next = bias + sum(coeff * x_old)

The original paper's ``MSDF_MUL_ADD_8`` instead consumes fraction digit streams.
For a word with ``DATA_WIDTH`` fraction digits, the row product is modeled as:

    frac_mul(x, a) = round((x * a) / 2^DATA_WIDTH)

This generator keeps the same bounded-degree PageRank topology and runtime
memory layout, but quantizes coefficients/biases into the prior fractional
format.  It is the strict P2 fixture for the same-shell prior-online baseline.
"""

from __future__ import annotations

import argparse
import json
import math
import subprocess
import sys
from pathlib import Path
from typing import Dict, List

import numpy as np

from make_pagerank_runtime_vectors import build_l1_cert_params, build_pagerank_matrix
from run_iter_rtl_vector_gen import pack_fields, write_scalar_memh


def run(cmd: List[str]) -> None:
    subprocess.run(cmd, check=True)


def rail_value(rail: Dict[str, str]) -> int:
    return int(rail["vec_p"], 2) - int(rail["vec_n"], 2)


def saturate_unsigned(value: int, width: int) -> int:
    if value <= 0:
        return 0
    return min(value, (1 << width) - 1)


def prior_frac_mul(state_term: int, coeff_term: int, product_shift: int) -> int:
    product = int(state_term) * int(coeff_term)
    if product >= 0:
        return (product + (1 << (product_shift - 1))) >> product_shift
    return -(((-product) + (1 << (product_shift - 1))) >> product_shift)


def prior_cluster_iteration(
    rows: List[Dict[str, object]],
    cert_cluster: Dict[str, object],
    old_p_global: List[int],
    old_n_global: List[int],
    cluster_base: int,
    num_rows: int,
    degree: int,
    data_width: int,
    product_shift: int,
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
            row_sum += prior_frac_mul(state_term, coeff_term, product_shift)

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
    parser.add_argument("--out-dir", type=Path, default=Path("MSDF_iterative_solver/generated/rtl_vectors/pagerank32_global_prior_fractional"))
    parser.add_argument("--num-clusters", type=int, default=8)
    parser.add_argument("--num-rows", type=int, default=4)
    parser.add_argument("--degree", type=int, default=4)
    parser.add_argument("--num-iters", type=int, default=4)
    parser.add_argument("--beta", type=float, default=0.85)
    parser.add_argument("--bit-width", type=int, default=11)
    parser.add_argument("--bound-width", type=int, default=16)
    parser.add_argument("--coeff-width", type=int, default=8)
    parser.add_argument("--acc-width", type=int, default=24)
    parser.add_argument("--block-size", type=int, default=1)
    parser.add_argument("--l1-eta", type=int, default=64)
    parser.add_argument("--tail-bound", type=int, default=1)
    args = parser.parse_args()

    if args.block_size != 1:
        raise ValueError("PageRank L1 certification v1 requires --block-size 1")

    args.out_dir.mkdir(parents=True, exist_ok=True)
    total_rows = args.num_clusters * args.num_rows
    data_width = args.bit_width + 3
    # Coefficients/biases are quantized as fraction words with the MSB carrying
    # the first fractional digit.  The characterized MSDF_MUL_ADD_8 product
    # output has one additional online-delay shift, so product accumulation uses
    # DATA_WIDTH as the right shift.
    frac_bits = data_width - 1
    product_shift = data_width
    src_idx_width = max(1, int(math.ceil(math.log2(total_rows))))
    num_blocks = (args.num_rows + args.block_size - 1) // args.block_size
    py = sys.executable

    # build_pagerank_matrix can be reused by passing the target fractional
    # precision and a real PageRank teleport term.
    teleport_lsb = max(1, int(round(((1.0 - args.beta) / float(total_rows)) * (1 << frac_bits))))
    g, c, graph_meta = build_pagerank_matrix(
        n=total_rows,
        degree=args.degree,
        beta=args.beta,
        frac_bits=frac_bits,
        teleport_lsb=teleport_lsb,
    )

    matrix_json = args.out_dir / "matrix.json"
    cert_json = args.out_dir / "cert_params.json"
    compiled_json = args.out_dir / "coeff_templates.json"
    template_memh = args.out_dir / "templates.memh"
    cert_memh = args.out_dir / "cert_params.memh"

    matrix_json.write_text(
        json.dumps({"G": g.tolist(), "c": c.tolist(), "pagerank": graph_meta}, indent=2),
        encoding="utf-8",
    )
    cert_json.write_text(
        json.dumps(
            build_l1_cert_params(
                num_clusters=args.num_clusters,
                rows_per_cluster=args.num_rows,
                num_blocks=num_blocks,
                eta=args.l1_eta,
            ),
            indent=2,
        ),
        encoding="utf-8",
    )

    run([
        py,
        "MSDF_iterative_solver/compile_coeff_templates.py",
        "--matrix-json",
        str(matrix_json),
        "--frac-bits",
        str(frac_bits),
        "--bit-width",
        str(args.bit_width),
        "--max-terms",
        str(args.degree),
        "--fixed-degree",
        str(args.degree),
        "--output-json",
        str(compiled_json),
    ])
    run([
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
    ])
    run([
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
    ])

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
            rec = prior_cluster_iteration(
                rows=rows,
                cert_cluster=cert_data["clusters"][cluster_idx],
                old_p_global=state_p_global,
                old_n_global=state_n_global,
                cluster_base=base,
                num_rows=args.num_rows,
                degree=args.degree,
                data_width=data_width,
                product_shift=product_shift,
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
        local_l1 = [int(c_rec["max_error"]) for c_rec in cluster_records]
        global_l1 = int(sum(local_l1))
        iter_records.append(
            {
                "iter": iter_idx,
                "clusters": cluster_records,
                "local_l1_by_cluster": local_l1,
                "global_l1_delta": global_l1,
                "converged": int(global_l1 <= args.l1_eta),
                "continue": int(global_l1 > args.l1_eta),
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
    write_scalar_memh(
        args.out_dir / "gold_global_l1_delta.memh",
        [record["global_l1_delta"] for record in iter_records],
        args.acc_width,
    )

    summary = {
        "fixture": "pagerank32_global_prior_fractional",
        "num_clusters": args.num_clusters,
        "num_rows": args.num_rows,
        "total_rows": total_rows,
        "degree": args.degree,
        "num_iters": args.num_iters,
        "bit_width": args.bit_width,
        "data_width": data_width,
        "frac_bits": frac_bits,
        "product_shift": product_shift,
        "bound_width": args.bound_width,
        "coeff_width": args.coeff_width,
        "acc_width": args.acc_width,
        "l1_eta": args.l1_eta,
        "tail_bound": args.tail_bound,
        "template_memh": str(template_memh),
        "cert_memh": str(cert_memh),
        "graph": graph_meta,
        "iterations": iter_records,
    }
    (args.out_dir / "summary.json").write_text(json.dumps(summary, indent=2), encoding="utf-8")
    print(
        f"Wrote {args.out_dir}; global L1 by iter: "
        f"{[record['global_l1_delta'] for record in iter_records]}"
    )


if __name__ == "__main__":
    main()
