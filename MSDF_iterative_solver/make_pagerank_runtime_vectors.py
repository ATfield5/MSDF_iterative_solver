#!/usr/bin/env python3
"""
Generate PageRank-style global-source runtime vectors.

This is the first same-shell PageRank fixture for the solver-native MSDF
runtime.  It intentionally uses a bounded-degree circulant graph so every row
has the same static number of incoming source IDs and the RTL can reuse the
fixed-degree template path.

The generated RTL contract is the current rail-coded integer affine recurrence
used by the existing runtime tops.  The JSON summary also records the PageRank
floating-point parameters and the quantized values so later work can replace
this bridge with the original paper's fractional online arithmetic semantics.
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

from make_jacobi32_blockdiag_full_digit_runtime_vectors import (
    conv_cluster_iteration,
)
from run_iter_rtl_vector_gen import pack_fields, write_scalar_memh


def run(cmd: List[str]) -> None:
    subprocess.run(cmd, check=True)


def build_pagerank_matrix(
    n: int,
    degree: int,
    beta: float,
    frac_bits: int,
    teleport_lsb: int,
) -> tuple[np.ndarray, np.ndarray, Dict[str, object]]:
    if degree <= 0:
        raise ValueError("degree must be positive")
    if n % degree != 0 and degree > n:
        raise ValueError("degree must not exceed n")

    scale = 1 << frac_bits
    # Deterministic bounded-degree graph.  Source j points to
    # j + offsets[t], so row i receives from i - offsets[t].
    base_offsets = [0, 1, 5, 13, 17, 23, 29, 31]
    if degree <= len(base_offsets):
        offsets = [base_offsets[i] % n for i in range(degree)]
        if len(set(offsets)) != degree:
            offsets = list(range(degree))
    else:
        offsets = list(range(degree))

    ideal_coeff = beta / float(degree)
    coeff_quant = max(1, int(round(ideal_coeff * scale)))
    coeff_value = coeff_quant / float(scale)
    teleport_value = float(teleport_lsb) / float(scale)

    g = np.zeros((n, n), dtype=np.float64)
    c = np.full(n, teleport_value, dtype=np.float64)
    incoming_sources: List[List[int]] = []
    for row in range(n):
        srcs = [int((row - off) % n) for off in offsets]
        incoming_sources.append(srcs)
        for src in srcs:
            g[row, src] = coeff_value

    meta: Dict[str, object] = {
        "graph": "circulant_bounded_degree",
        "n": n,
        "degree": degree,
        "beta": beta,
        "offsets": offsets,
        "ideal_coeff": ideal_coeff,
        "coeff_quant": coeff_quant,
        "coeff_value": coeff_value,
        "teleport_lsb": teleport_lsb,
        "teleport_value": teleport_value,
        "incoming_sources": incoming_sources,
        "note": (
            "RTL vectors use the current integer rail affine contract. "
            "This preserves global-source PageRank topology and same-shell "
            "control, but it is not yet the final fractional PageRank datapath."
        ),
    }
    return g, c, meta


def build_l1_cert_params(
    num_clusters: int,
    rows_per_cluster: int,
    num_blocks: int,
    eta: int,
) -> Dict[str, object]:
    # block_size=1 is required for exact per-cluster L1(delta): the existing
    # block cert engine first forms block maxima, then a weighted row sum, then
    # max over rows.  With one row per block and all weights=1, every row's
    # weighted sum equals the local L1 sum.
    weights = [1 for _ in range(rows_per_cluster * num_blocks)]
    return {
        "mode": "pagerank_l1_local_sum",
        "global_eta": int(eta),
        "clusters": [
            {"block_weights": weights, "eta": int(eta)}
            for _ in range(num_clusters)
        ],
    }


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--out-dir", type=Path, default=Path("MSDF_iterative_solver/generated/rtl_vectors/pagerank32_global_full_digit"))
    parser.add_argument("--num-clusters", type=int, default=8)
    parser.add_argument("--num-rows", type=int, default=4)
    parser.add_argument("--degree", type=int, default=4)
    parser.add_argument("--num-iters", type=int, default=6)
    parser.add_argument("--beta", type=float, default=0.85)
    parser.add_argument("--bit-width", type=int, default=8)
    parser.add_argument("--frac-bits", type=int, default=2)
    parser.add_argument("--bound-width", type=int, default=13)
    parser.add_argument("--coeff-width", type=int, default=8)
    parser.add_argument("--acc-width", type=int, default=24)
    parser.add_argument("--block-size", type=int, default=1)
    parser.add_argument("--l1-eta", type=int, default=256)
    parser.add_argument("--tail-bound", type=int, default=1)
    parser.add_argument("--teleport-lsb", type=int, default=1)
    args = parser.parse_args()

    if args.block_size != 1:
        raise ValueError("PageRank L1 certification v1 requires --block-size 1")

    args.out_dir.mkdir(parents=True, exist_ok=True)
    total_rows = args.num_clusters * args.num_rows
    data_width = args.bit_width + 3
    src_idx_width = max(1, int(math.ceil(math.log2(total_rows))))
    num_blocks = (args.num_rows + args.block_size - 1) // args.block_size
    py = sys.executable

    g, c, graph_meta = build_pagerank_matrix(
        n=total_rows,
        degree=args.degree,
        beta=args.beta,
        frac_bits=args.frac_bits,
        teleport_lsb=args.teleport_lsb,
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
        str(args.frac_bits),
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
        "fixture": "pagerank32_global",
        "num_clusters": args.num_clusters,
        "num_rows": args.num_rows,
        "total_rows": total_rows,
        "degree": args.degree,
        "num_iters": args.num_iters,
        "bit_width": args.bit_width,
        "frac_bits": args.frac_bits,
        "bound_width": args.bound_width,
        "coeff_width": args.coeff_width,
        "acc_width": args.acc_width,
        "block_size": args.block_size,
        "num_blocks": num_blocks,
        "data_width": data_width,
        "src_idx_width": src_idx_width,
        "l1_eta": args.l1_eta,
        "tail_bound": args.tail_bound,
        "template_memh": str(template_memh),
        "cert_memh": str(cert_memh),
        "graph": graph_meta,
        "iterations": iter_records,
    }
    (args.out_dir / "summary.json").write_text(json.dumps(summary, indent=2), encoding="utf-8")
    print(f"Wrote {args.out_dir}")
    print("global_l1_by_iter=" + json.dumps([r["global_l1_delta"] for r in iter_records]))
    print("converged_by_iter=" + json.dumps([r["converged"] for r in iter_records]))


if __name__ == "__main__":
    main()
