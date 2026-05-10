#!/usr/bin/env python3
"""
Generate a 32-row Jacobi-family runtime-vector fixture for the current RTL top.

The current runtime top supports cluster-local source row indices. A generic
banded Jacobi32 matrix has cross-cluster dependencies and therefore requires a
future inter-cluster source router. This fixture is a block-diagonal Jacobi
case with 8 clusters x 4 rows, so it exercises the routed 32-active-row runtime
top without violating the current hardware contract.
"""

from __future__ import annotations

import argparse
import json
import math
import subprocess
from pathlib import Path
from typing import List

import numpy as np


def run(cmd: List[str]) -> None:
    subprocess.run(cmd, check=True)


def build_matrix(num_clusters: int, rows_per_cluster: int) -> tuple[np.ndarray, np.ndarray]:
    if rows_per_cluster != 4:
        raise ValueError("this fixture is intentionally fixed to 4 rows/cluster")

    base_block = np.array(
        [
            [0.0, 0.18, -0.07, 0.05],
            [-0.10, 0.0, 0.16, -0.04],
            [0.06, -0.13, 0.0, 0.14],
            [-0.05, 0.08, -0.12, 0.0],
        ],
        dtype=np.float64,
    )
    n = num_clusters * rows_per_cluster
    g = np.zeros((n, n), dtype=np.float64)
    c = np.zeros(n, dtype=np.float64)
    for cluster in range(num_clusters):
        scale = 0.82 + 0.02 * float(cluster % 5)
        lo = cluster * rows_per_cluster
        hi = lo + rows_per_cluster
        g[lo:hi, lo:hi] = scale * base_block
        for row in range(rows_per_cluster):
            sign = -1.0 if (cluster + row) % 2 else 1.0
            c[lo + row] = sign * (0.035 + 0.004 * row + 0.002 * cluster)
    return g, c


def build_cert_params(
    g: np.ndarray,
    num_clusters: int,
    rows_per_cluster: int,
    block_size: int,
    weight_scale: int,
    eta: int,
    coeff_width: int,
) -> dict:
    n = g.shape[0]
    h_abs = np.abs(g @ np.linalg.inv(np.eye(n, dtype=np.float64) - g))
    num_blocks = math.ceil(rows_per_cluster / block_size)
    max_weight = (1 << coeff_width) - 1
    clusters = []
    for cluster in range(num_clusters):
        lo = cluster * rows_per_cluster
        hi = lo + rows_per_cluster
        weights: List[int] = []
        for row in range(lo, hi):
            for block in range(num_blocks):
                blo = lo + block * block_size
                bhi = min(lo + (block + 1) * block_size, hi)
                q = int(math.ceil(float(np.sum(h_abs[row, blo:bhi])) * weight_scale))
                weights.append(max(1, min(max_weight, q)))
        clusters.append({"block_weights": weights, "eta": int(eta)})
    return {"clusters": clusters}


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--out-dir", type=Path, default=Path("MSDF_iterative_solver/generated/rtl_vectors/jacobi32_blockdiag"))
    parser.add_argument("--num-clusters", type=int, default=8)
    parser.add_argument("--num-rows", type=int, default=4)
    parser.add_argument("--degree", type=int, default=4)
    parser.add_argument("--bit-width", type=int, default=8)
    parser.add_argument("--frac-bits", type=int, default=6)
    parser.add_argument("--bound-width", type=int, default=13)
    parser.add_argument("--coeff-width", type=int, default=8)
    parser.add_argument("--acc-width", type=int, default=24)
    parser.add_argument("--block-size", type=int, default=2)
    parser.add_argument("--cert-weight-scale", type=int, default=16)
    parser.add_argument("--cert-eta", type=int, default=4095)
    args = parser.parse_args()

    args.out_dir.mkdir(parents=True, exist_ok=True)
    g, c = build_matrix(args.num_clusters, args.num_rows)
    matrix_json = args.out_dir / "matrix.json"
    cert_json = args.out_dir / "cert_params.json"
    matrix_json.write_text(
        json.dumps({"G": g.tolist(), "c": c.tolist()}, indent=2),
        encoding="utf-8",
    )
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
            "conda",
            "run",
            "-n",
            "qas",
            "python",
            "MSDF_iterative_solver/run_iter_rtl_vector_gen.py",
            "--matrix-json",
            str(matrix_json),
            "--cert-json",
            str(cert_json),
            "--out-dir",
            str(args.out_dir),
            "--num-clusters",
            str(args.num_clusters),
            "--num-rows",
            str(args.num_rows),
            "--degree",
            str(args.degree),
            "--bit-width",
            str(args.bit_width),
            "--frac-bits",
            str(args.frac_bits),
            "--bound-width",
            str(args.bound_width),
            "--coeff-width",
            str(args.coeff_width),
            "--acc-width",
            str(args.acc_width),
            "--block-size",
            str(args.block_size),
        ]
    )
    print(f"Wrote {args.out_dir}")


if __name__ == "__main__":
    main()
