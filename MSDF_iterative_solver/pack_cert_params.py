#!/usr/bin/env python3
"""
Pack block-H certification parameters into one-word-per-cluster payloads.

Payload layout, from LSB to MSB:
  [block_weights][eta]
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import List


def set_field(bits: int, field_value: int, field_idx: int, field_width: int) -> int:
    return bits | (int(field_value) << (field_idx * field_width))


def pack_cluster(block_weights: List[int], eta: int, coeff_width: int, acc_width: int) -> int:
    block_bits = 0
    for idx, value in enumerate(block_weights):
        block_bits = set_field(block_bits, value, idx, coeff_width)
    return block_bits | (int(eta) << (len(block_weights) * coeff_width))


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--cert-json", type=Path, required=True)
    parser.add_argument("--num-clusters", type=int, required=True)
    parser.add_argument("--num-rows", type=int, required=True)
    parser.add_argument("--num-blocks", type=int, required=True)
    parser.add_argument("--coeff-width", type=int, required=True)
    parser.add_argument("--acc-width", type=int, required=True)
    parser.add_argument("--cluster-start", type=int, default=0)
    parser.add_argument("--output-memh", type=Path, required=True)
    args = parser.parse_args()

    data = json.loads(args.cert_json.read_text(encoding="utf-8"))
    clusters = data["clusters"]
    weights_per_cluster = args.num_rows * args.num_blocks
    payload_width = weights_per_cluster * args.coeff_width + args.acc_width
    hex_width = (payload_width + 3) // 4

    lines: List[str] = []
    for cluster_idx in range(args.cluster_start, args.cluster_start + args.num_clusters):
        cluster = clusters[cluster_idx]
        block_weights = [int(v) for v in cluster["block_weights"]]
        if len(block_weights) != weights_per_cluster:
            raise ValueError(
                f"cluster {cluster_idx} has {len(block_weights)} weights, "
                f"expected {weights_per_cluster}"
            )
        payload = pack_cluster(
            block_weights=block_weights,
            eta=int(cluster["eta"]),
            coeff_width=args.coeff_width,
            acc_width=args.acc_width,
        )
        lines.append(f"{payload:0{hex_width}x}")

    args.output_memh.parent.mkdir(parents=True, exist_ok=True)
    args.output_memh.write_text("\n".join(lines) + "\n", encoding="utf-8")
    print(f"Wrote {args.output_memh}")


if __name__ == "__main__":
    main()
