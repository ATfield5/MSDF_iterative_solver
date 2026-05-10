#!/usr/bin/env python3
"""
Generate file-driven RTL vectors for the current iteration-fused solver slice.

The current RTL row-update path is functional-first and rail-coded. This script
therefore generates golden values for the observable RTL contract:
- packed fixed-degree template memh;
- packed certification-parameter memh;
- one-cycle input digit vectors;
- expected row sums, delta bounds, block bounds, max-error, and cert flag.
"""

from __future__ import annotations

import argparse
import json
import subprocess
from pathlib import Path
from typing import Dict, List, Tuple


def run(cmd: List[str]) -> None:
    subprocess.run(cmd, check=True)


def rail_to_int(rail: Dict[str, str]) -> int:
    return int(rail["vec_p"], 2) - int(rail["vec_n"], 2)


def rail_to_uint(rail: Dict[str, str], key: str) -> int:
    return int(rail[key], 2)


def int_to_unsigned(value: int, width: int) -> int:
    if value < 0:
        raise ValueError(f"negative value {value} cannot be encoded as unsigned rail magnitude")
    mask = (1 << width) - 1
    if value > mask:
        raise ValueError(f"value {value} exceeds width {width}")
    return value


def bit(value: int, idx: int) -> int:
    return (value >> idx) & 1


def mask(width: int) -> int:
    return (1 << width) - 1


def poa_block(x_p: int, x_n: int, y_p: int, y_n: int, c_p: int) -> Tuple[int, int, int]:
    # Mirrors iter_parallel_online_adder_block.v.
    sum0 = (x_p & 1) + ((~x_n) & 1) + (y_p & 1)
    c0 = (sum0 >> 1) & 1
    s0 = sum0 & 1
    sum1 = s0 + ((~y_n) & 1) + (c_p & 1)
    c1 = (sum1 >> 1) & 1
    z_p = sum1 & 1
    z_n_carry = (~c1) & 1
    return c0, z_n_carry, z_p


def poa(x_p: int, x_n: int, y_p: int, y_n: int, width: int, c_p: int = 0, c_n: int = 0) -> Tuple[int, int, int, int]:
    # Mirrors iter_parallel_online_adder.v exactly.
    z_p = 0
    z_n = c_n & 1
    carry_p = c_p & 1
    carry_n_vec = []
    for idx in range(width):
        carry_p_out, carry_n_out, z_p_bit = poa_block(
            bit(x_p, idx), bit(x_n, idx), bit(y_p, idx), bit(y_n, idx), carry_p
        )
        z_p |= z_p_bit << idx
        carry_n_vec.append(carry_n_out)
        if idx > 0:
            z_n |= carry_n_vec[idx - 1] << idx
        carry_p = carry_p_out
    o_c_p = carry_p
    o_c_n = carry_n_vec[-1]
    return z_p & mask(width), z_n & mask(width), o_c_p, o_c_n


def poa4(inputs: List[Tuple[int, int]], width: int) -> Tuple[int, int]:
    # Mirrors iter_parallel_online_adder_4.v.
    t00_p, t00_n, c00_p, c00_n = poa(inputs[0][0], inputs[0][1], inputs[1][0], inputs[1][1], width)
    t01_p, t01_n, c01_p, c01_n = poa(inputs[2][0], inputs[2][1], inputs[3][0], inputs[3][1], width)
    t10_p = t00_p | (c00_p << width)
    t10_n = t00_n | (c00_n << width)
    t11_p = t01_p | (c01_p << width)
    t11_n = t01_n | (c01_n << width)
    z_p, z_n, c_p, c_n = poa(t10_p, t10_n, t11_p, t11_n, width + 1)
    return z_p | (c_p << (width + 1)), z_n | (c_n << (width + 1))


def contrib_from_digit(digit: int, coeff_p: int, coeff_n: int, width: int) -> Tuple[int, int]:
    # Mirrors online_const_coeff_contrib.v for positive source digits.
    if digit > 0:
        return coeff_p, coeff_n
    if digit < 0:
        return (~coeff_p) & mask(width), (~coeff_n) & mask(width)
    return 0, 0


def rtl_row_update(
    coeff_terms: List[Dict[str, object]],
    bias_rail: Dict[str, str],
    x_terms: List[int],
    bit_width: int,
) -> Tuple[int, int]:
    contribs: List[Tuple[int, int]] = []
    for term, digit in zip(coeff_terms, x_terms):
        coeff_p = rail_to_uint(term["rail"], "vec_p")
        coeff_n = rail_to_uint(term["rail"], "vec_n")
        contribs.append(contrib_from_digit(digit, coeff_p, coeff_n, bit_width))
    while len(contribs) < 4:
        contribs.append((0, 0))
    sum4_p, sum4_n = poa4(contribs[:4], bit_width)
    bias_p = rail_to_uint(bias_rail, "vec_p")
    bias_n = rail_to_uint(bias_rail, "vec_n")
    z_p, z_n, c_p, c_n = poa(sum4_p, sum4_n, bias_p, bias_n, bit_width + 2)
    return z_p | (c_p << (bit_width + 2)), z_n | (c_n << (bit_width + 2))


def pack_fields(values: List[int], field_width: int) -> int:
    out = 0
    for idx, value in enumerate(values):
        out |= int(value) << (idx * field_width)
    return out


def row_inputs_for_case(num_rows: int, degree: int) -> List[List[int]]:
    # Matches the existing small-top TB pattern:
    # x0=1, x1=1, x2=0, x3 only rows 0/3 are 1.
    x_by_term: List[List[int]] = []
    x_by_term.append([1 for _ in range(num_rows)])
    x_by_term.append([1 for _ in range(num_rows)])
    x_by_term.append([0 for _ in range(num_rows)])
    x_by_term.append([1 if row in (0, num_rows - 1) else 0 for row in range(num_rows)])
    while len(x_by_term) < degree:
        x_by_term.append([0 for _ in range(num_rows)])
    return x_by_term[:degree]


def compute_cluster_golden(
    rows: List[Dict[str, object]],
    cert_cluster: Dict[str, object],
    num_rows: int,
    degree: int,
    bit_width: int,
    bound_width: int,
    block_size: int,
    num_blocks: int,
    data_width: int,
) -> Dict[str, object]:
    x_by_term = row_inputs_for_case(num_rows=num_rows, degree=degree)
    sum_p: List[int] = []
    sum_n: List[int] = []
    abs_upper: List[int] = []

    for row_idx, row in enumerate(rows):
        x_terms = [x_by_term[term_idx][row_idx] for term_idx in range(degree)]
        row_sum_p, row_sum_n = rtl_row_update(
            coeff_terms=row["fixed_degree_terms"],
            bias_rail=row["bias"]["rail"],
            x_terms=x_terms,
            bit_width=bit_width,
        )
        sum_p.append(row_sum_p)
        sum_n.append(row_sum_n)
        abs_upper.append(abs(row_sum_p - row_sum_n) + 1)

    block_bounds: List[int] = []
    for block_idx in range(num_blocks):
        start = block_idx * block_size
        stop = min(start + block_size, num_rows)
        block_bounds.append(max(abs_upper[start:stop]))

    weights = [int(v) for v in cert_cluster["block_weights"]]
    eta = int(cert_cluster["eta"])
    max_error = 0
    for row_idx in range(num_rows):
        row_error = 0
        for block_idx in range(num_blocks):
            row_error += block_bounds[block_idx] * weights[row_idx * num_blocks + block_idx]
        max_error = max(max_error, row_error)

    return {
        "x_by_term": x_by_term,
        "sum_p_rows": sum_p,
        "sum_n_rows": sum_n,
        "abs_upper_rows": abs_upper,
        "block_bounds": block_bounds,
        "eta": eta,
        "max_error": max_error,
        "certified": int(max_error <= eta),
        "packed": {
            "x0_p": pack_fields(x_by_term[0], 1),
            "x1_p": pack_fields(x_by_term[1], 1),
            "x2_p": pack_fields(x_by_term[2], 1),
            "x3_p": pack_fields(x_by_term[3], 1),
            "sum_p_rows": pack_fields(sum_p, data_width),
            "sum_n_rows": pack_fields(sum_n, data_width),
            "abs_upper_rows": pack_fields(abs_upper, bound_width),
            "block_bounds": pack_fields(block_bounds, bound_width),
        },
    }


def write_scalar_memh(path: Path, values: List[int], width: int) -> None:
    hex_width = (width + 3) // 4
    path.write_text("\n".join(f"{value:0{hex_width}x}" for value in values) + "\n", encoding="utf-8")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--matrix-json", type=Path, default=Path("MSDF_iterative_solver/testdata/blockdiag8_matrix.json"))
    parser.add_argument("--cert-json", type=Path, default=Path("MSDF_iterative_solver/testdata/blockdiag8_cert_params.json"))
    parser.add_argument("--out-dir", type=Path, default=Path("MSDF_iterative_solver/generated/rtl_vectors/blockdiag8"))
    parser.add_argument("--num-clusters", type=int, default=2)
    parser.add_argument("--num-rows", type=int, default=4)
    parser.add_argument("--degree", type=int, default=4)
    parser.add_argument("--bit-width", type=int, default=8)
    parser.add_argument("--frac-bits", type=int, default=6)
    parser.add_argument("--bound-width", type=int, default=13)
    parser.add_argument("--coeff-width", type=int, default=8)
    parser.add_argument("--acc-width", type=int, default=24)
    parser.add_argument("--block-size", type=int, default=2)
    parser.add_argument("--max-terms", type=int, default=4)
    args = parser.parse_args()

    args.out_dir.mkdir(parents=True, exist_ok=True)
    compiled_json = args.out_dir / "coeff_templates.json"
    template_memh = args.out_dir / "templates.memh"
    cert_memh = args.out_dir / "cert_params.memh"

    run(
        [
            "conda",
            "run",
            "-n",
            "qas",
            "python",
            "MSDF_iterative_solver/compile_coeff_templates.py",
            "--matrix-json",
            str(args.matrix_json),
            "--frac-bits",
            str(args.frac_bits),
            "--bit-width",
            str(args.bit_width),
            "--max-terms",
            str(args.max_terms),
            "--fixed-degree",
            str(args.degree),
            "--output-json",
            str(compiled_json),
        ]
    )
    run(
        [
            "conda",
            "run",
            "-n",
            "qas",
            "python",
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
            "conda",
            "run",
            "-n",
            "qas",
            "python",
            "MSDF_iterative_solver/pack_cert_params.py",
            "--cert-json",
            str(args.cert_json),
            "--num-clusters",
            str(args.num_clusters),
            "--num-rows",
            str(args.num_rows),
            "--num-blocks",
            str((args.num_rows + args.block_size - 1) // args.block_size),
            "--coeff-width",
            str(args.coeff_width),
            "--acc-width",
            str(args.acc_width),
            "--output-memh",
            str(cert_memh),
        ]
    )

    compiled = json.loads(compiled_json.read_text(encoding="utf-8"))
    cert_data = json.loads(args.cert_json.read_text(encoding="utf-8"))
    num_blocks = (args.num_rows + args.block_size - 1) // args.block_size
    data_width = args.bit_width + 3

    cluster_golden = []
    for cluster_idx in range(args.num_clusters):
        base = cluster_idx * args.num_rows
        rows = compiled["rows"][base : base + args.num_rows]
        cluster_golden.append(
            compute_cluster_golden(
                rows=rows,
                cert_cluster=cert_data["clusters"][cluster_idx],
                num_rows=args.num_rows,
                degree=args.degree,
                bit_width=args.bit_width,
                bound_width=args.bound_width,
                block_size=args.block_size,
                num_blocks=num_blocks,
                data_width=data_width,
            )
        )

    write_scalar_memh(args.out_dir / "x0_p.memh", [g["packed"]["x0_p"] for g in cluster_golden], args.num_rows)
    write_scalar_memh(args.out_dir / "x1_p.memh", [g["packed"]["x1_p"] for g in cluster_golden], args.num_rows)
    write_scalar_memh(args.out_dir / "x2_p.memh", [g["packed"]["x2_p"] for g in cluster_golden], args.num_rows)
    write_scalar_memh(args.out_dir / "x3_p.memh", [g["packed"]["x3_p"] for g in cluster_golden], args.num_rows)
    write_scalar_memh(
        args.out_dir / "gold_sum_p_rows.memh",
        [g["packed"]["sum_p_rows"] for g in cluster_golden],
        args.num_rows * data_width,
    )
    write_scalar_memh(
        args.out_dir / "gold_sum_n_rows.memh",
        [g["packed"]["sum_n_rows"] for g in cluster_golden],
        args.num_rows * data_width,
    )
    write_scalar_memh(
        args.out_dir / "gold_block_bounds.memh",
        [g["packed"]["block_bounds"] for g in cluster_golden],
        num_blocks * args.bound_width,
    )
    write_scalar_memh(
        args.out_dir / "gold_max_error.memh",
        [g["max_error"] for g in cluster_golden],
        args.acc_width,
    )
    write_scalar_memh(
        args.out_dir / "gold_certified.memh",
        [g["certified"] for g in cluster_golden],
        1,
    )

    summary = {
        "num_clusters": args.num_clusters,
        "num_rows": args.num_rows,
        "degree": args.degree,
        "bit_width": args.bit_width,
        "bound_width": args.bound_width,
        "coeff_width": args.coeff_width,
        "acc_width": args.acc_width,
        "block_size": args.block_size,
        "num_blocks": num_blocks,
        "data_width": data_width,
        "template_memh": str(template_memh),
        "cert_memh": str(cert_memh),
        "clusters": cluster_golden,
    }
    (args.out_dir / "summary.json").write_text(json.dumps(summary, indent=2), encoding="utf-8")
    print(f"Wrote {args.out_dir}")


if __name__ == "__main__":
    main()
