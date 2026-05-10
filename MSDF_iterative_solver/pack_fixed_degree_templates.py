#!/usr/bin/env python3
"""
Pack fixed-degree template JSON into memory-friendly cluster payload words.

Default scope is intentionally narrow:
- one payload word per cluster;
- each cluster contains `num_rows` consecutive rows;
- source-row indices are converted to cluster-local row indices;
- payload layout matches `iter_fixed_degree_template_unpack.v`.

The optional source-index modes are:
- `global`: keep absolute source-row indices in the active window;
- `halo`: encode each cluster against a bounded source window ordered as
  previous halo clusters, current cluster, next halo clusters.
"""

from __future__ import annotations

import argparse
import json
import math
from pathlib import Path
from typing import Dict, List


def rail_to_uint(rail: Dict[str, str], key: str) -> int:
    return int(rail[key], 2)


def set_field(bits: int, field_value: int, field_idx: int, field_width: int) -> int:
    return bits | (int(field_value) << (field_idx * field_width))


def pack_cluster(
    rows: List[Dict[str, object]],
    cluster_base: int,
    num_rows: int,
    degree: int,
    bit_width: int,
    src_index_mode: str,
    src_index_width: int,
    halo_cluster_radius: int,
) -> int:
    bias_width = bit_width + 2

    valid_width = num_rows * degree
    src_width = num_rows * degree * src_index_width
    coeff_width = num_rows * degree * bit_width
    bias_vec_width = num_rows * bias_width

    valid_bits = 0
    src_bits = 0
    coeff_p_bits = 0
    coeff_n_bits = 0
    bias_p_bits = 0
    bias_n_bits = 0

    if len(rows) != num_rows:
        raise ValueError(f"expected {num_rows} rows, got {len(rows)}")

    for local_row, row in enumerate(rows):
        fixed_terms = row["fixed_degree_terms"]
        if len(fixed_terms) != degree:
            raise ValueError(
                f"row {row['row']} fixed_degree_terms len {len(fixed_terms)} != degree {degree}"
            )
        bias = row["bias"]
        bias_p_bits = set_field(
            bias_p_bits, rail_to_uint(bias["rail"], "vec_p"), local_row, bias_width
        )
        bias_n_bits = set_field(
            bias_n_bits, rail_to_uint(bias["rail"], "vec_n"), local_row, bias_width
        )

        for term_idx, term in enumerate(fixed_terms):
            flat_idx = local_row * degree + term_idx
            valid = int(term["valid"])
            valid_bits |= (valid << flat_idx)

            if valid:
                global_col = int(term["col"])
                if src_index_mode == "local":
                    if not (cluster_base <= global_col < cluster_base + num_rows):
                        raise ValueError(
                            f"row {row['row']} term {term_idx} col {global_col} "
                            f"falls outside cluster [{cluster_base}, {cluster_base + num_rows})"
                        )
                    src_col = global_col - cluster_base
                elif src_index_mode == "global":
                    src_col = global_col
                else:
                    halo_base = cluster_base - halo_cluster_radius * num_rows
                    halo_source_rows = num_rows * (2 * halo_cluster_radius + 1)
                    src_col = global_col - halo_base
                    if not (0 <= src_col < halo_source_rows):
                        raise ValueError(
                            f"row {row['row']} term {term_idx} col {global_col} "
                            f"falls outside halo window [{halo_base}, "
                            f"{halo_base + halo_source_rows})"
                        )
                coeff_p = rail_to_uint(term["rail"], "vec_p")
                coeff_n = rail_to_uint(term["rail"], "vec_n")
            else:
                src_col = 0
                coeff_p = 0
                coeff_n = 0

            if src_col >= (1 << src_index_width):
                raise ValueError(
                    f"row {row['row']} term {term_idx} source index {src_col} "
                    f"does not fit width {src_index_width}"
                )

            src_bits = set_field(src_bits, src_col, flat_idx, src_index_width)
            coeff_p_bits = set_field(coeff_p_bits, coeff_p, flat_idx, bit_width)
            coeff_n_bits = set_field(coeff_n_bits, coeff_n, flat_idx, bit_width)

    payload = valid_bits
    payload |= src_bits << valid_width
    payload |= coeff_p_bits << (valid_width + src_width)
    payload |= coeff_n_bits << (valid_width + src_width + coeff_width)
    payload |= bias_p_bits << (valid_width + src_width + 2 * coeff_width)
    payload |= bias_n_bits << (valid_width + src_width + 2 * coeff_width + bias_vec_width)
    return payload


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--compiled-json", type=Path, required=True)
    parser.add_argument("--num-clusters", type=int, required=True)
    parser.add_argument("--num-rows", type=int, required=True)
    parser.add_argument("--degree", type=int, required=True)
    parser.add_argument("--bit-width", type=int, required=True)
    parser.add_argument("--row-start", type=int, default=0)
    parser.add_argument("--src-index-mode", choices=["local", "global", "halo"], default="local")
    parser.add_argument("--src-index-width", type=int, default=0)
    parser.add_argument("--halo-cluster-radius", type=int, default=1)
    parser.add_argument("--output-memh", type=Path, required=True)
    args = parser.parse_args()

    data = json.loads(args.compiled_json.read_text(encoding="utf-8"))
    rows = data["rows"]
    if args.src_index_width > 0:
        src_index_width = args.src_index_width
    elif args.src_index_mode == "local":
        src_index_width = 1 if args.num_rows <= 2 else math.ceil(math.log2(args.num_rows))
    elif args.src_index_mode == "global":
        total_rows = args.num_clusters * args.num_rows
        src_index_width = 1 if total_rows <= 2 else math.ceil(math.log2(total_rows))
    else:
        halo_source_rows = args.num_rows * (2 * args.halo_cluster_radius + 1)
        src_index_width = 1 if halo_source_rows <= 2 else math.ceil(math.log2(halo_source_rows))
    bias_width = args.bit_width + 2
    payload_width = (
        args.num_rows * args.degree
        + args.num_rows * args.degree * src_index_width
        + 2 * args.num_rows * args.degree * args.bit_width
        + 2 * args.num_rows * bias_width
    )
    hex_width = (payload_width + 3) // 4

    packed_lines: List[str] = []
    for cluster_idx in range(args.num_clusters):
        cluster_base = args.row_start + cluster_idx * args.num_rows
        cluster_rows = rows[cluster_base : cluster_base + args.num_rows]
        payload = pack_cluster(
            rows=cluster_rows,
            cluster_base=cluster_base,
            num_rows=args.num_rows,
            degree=args.degree,
            bit_width=args.bit_width,
            src_index_mode=args.src_index_mode,
            src_index_width=src_index_width,
            halo_cluster_radius=args.halo_cluster_radius,
        )
        packed_lines.append(f"{payload:0{hex_width}x}")

    args.output_memh.parent.mkdir(parents=True, exist_ok=True)
    args.output_memh.write_text("\n".join(packed_lines) + "\n", encoding="utf-8")
    print(f"Wrote {args.output_memh}")


if __name__ == "__main__":
    main()
