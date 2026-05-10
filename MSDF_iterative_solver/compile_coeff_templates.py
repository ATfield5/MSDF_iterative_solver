#!/usr/bin/env python3
"""
Compile fixed-point matrix coefficients into template-oriented metadata for the
specialized iterative-solver RTL path.

This compiler is still lightweight, but it now makes the intended RTL contract
explicit:

- coefficients are quantized to signed fixed-point integers;
- each nonzero emits a rail-coded vector view for direct contribution replay;
- each nonzero also emits a bounded signed-digit template for
  constant-coefficient specialization studies;
- per-row summary metadata is emitted for fixed-degree / structured-sparse
  bring-up.
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Dict, List, Tuple

import numpy as np


def int_to_rail_vec(value: int, bit_width: int) -> Dict[str, str]:
    mask = (1 << bit_width) - 1
    signed = int(value)
    if signed >= 0:
        mag = signed & mask
        vec_p = format(mag, f"0{bit_width}b")
        vec_n = "0" * bit_width
    else:
        mag = (-signed) & mask
        vec_p = "0" * bit_width
        vec_n = format(mag, f"0{bit_width}b")
    return {"vec_p": vec_p, "vec_n": vec_n}


def csd_digits(value: int) -> List[Dict[str, int]]:
    x = abs(int(value))
    sign = -1 if value < 0 else 1
    shift = 0
    terms: List[Dict[str, int]] = []
    while x > 0:
        if x & 1:
            digit = 2 - (x & 3)
            x -= digit
            terms.append({"sign": sign * digit, "shift": shift})
        x >>= 1
        shift += 1
    return terms


def truncate_terms(terms: List[Dict[str, int]], max_terms: int) -> Tuple[List[Dict[str, int]], int]:
    if max_terms <= 0 or len(terms) <= max_terms:
        return terms, 0
    kept = terms[:max_terms]
    dropped = len(terms) - len(kept)
    return kept, dropped


def compile_matrix(
    g: np.ndarray,
    c: np.ndarray,
    frac_bits: int,
    bit_width: int,
    max_terms: int,
    fixed_degree: int,
) -> Dict[str, object]:
    scale = 1 << frac_bits
    n = g.shape[0]
    rows: List[Dict[str, object]] = []
    total_nnz = 0
    total_terms_full = 0
    total_terms_kept = 0
    dropped_terms = 0
    row_degrees: List[int] = []

    for i in range(n):
        row_terms: List[Dict[str, object]] = []
        for j in range(n):
            coeff = float(g[i, j])
            if coeff == 0.0:
                continue
            total_nnz += 1
            quant = int(np.rint(coeff * scale))
            rail = int_to_rail_vec(quant, bit_width)
            csd_full = csd_digits(quant)
            csd_kept, dropped = truncate_terms(csd_full, max_terms=max_terms)
            total_terms_full += len(csd_full)
            total_terms_kept += len(csd_kept)
            dropped_terms += dropped
            row_terms.append(
                {
                    "col": j,
                    "value": coeff,
                    "quant": quant,
                    "rail": rail,
                    "csd_terms_full": csd_full,
                    "template_terms": csd_kept,
                    "dropped_terms": dropped,
                }
            )

        row_degrees.append(len(row_terms))
        if len(row_terms) > fixed_degree:
            raise ValueError(
                f"row {i} degree {len(row_terms)} exceeds fixed_degree {fixed_degree}"
            )

        bias_quant = int(np.rint(float(c[i]) * scale))
        bias_full = csd_digits(bias_quant)
        bias_kept, bias_dropped = truncate_terms(bias_full, max_terms=max_terms)
        fixed_degree_terms: List[Dict[str, object]] = []
        for term in row_terms:
            fixed_degree_terms.append(
                {
                    "valid": 1,
                    "col": term["col"],
                    "quant": term["quant"],
                    "rail": term["rail"],
                    "template_terms": term["template_terms"],
                }
            )
        while len(fixed_degree_terms) < fixed_degree:
            fixed_degree_terms.append(
                {
                    "valid": 0,
                    "col": 0,
                    "quant": 0,
                    "rail": int_to_rail_vec(0, bit_width),
                    "template_terms": [],
                }
            )
        rows.append(
            {
                "row": i,
                "degree": len(row_terms),
                "terms": row_terms,
                "fixed_degree_terms": fixed_degree_terms,
                "bias": {
                    "value": float(c[i]),
                    "quant": bias_quant,
                    "rail": int_to_rail_vec(bias_quant, bit_width + 2),
                    "csd_terms_full": bias_full,
                    "template_terms": bias_kept,
                    "dropped_terms": bias_dropped,
                },
            }
        )

    return {
        "frac_bits": frac_bits,
        "bit_width": bit_width,
        "max_terms": max_terms,
        "fixed_degree": fixed_degree,
        "n": n,
        "summary": {
            "total_nnz": total_nnz,
            "avg_degree": float(np.mean(row_degrees)) if row_degrees else 0.0,
            "max_degree": int(max(row_degrees)) if row_degrees else 0,
            "avg_terms_full": float(total_terms_full) / float(total_nnz) if total_nnz else 0.0,
            "avg_terms_kept": float(total_terms_kept) / float(total_nnz) if total_nnz else 0.0,
            "dropped_terms_total": dropped_terms,
        },
        "rows": rows,
    }


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--matrix-json", type=Path, required=True, help="JSON file with keys G and c.")
    parser.add_argument("--frac-bits", type=int, default=16)
    parser.add_argument("--bit-width", type=int, default=16)
    parser.add_argument("--max-terms", type=int, default=4)
    parser.add_argument("--fixed-degree", type=int, default=4)
    parser.add_argument("--output-json", type=Path, required=True)
    args = parser.parse_args()

    data = json.loads(args.matrix_json.read_text(encoding="utf-8"))
    g = np.asarray(data["G"], dtype=np.float64)
    c = np.asarray(data["c"], dtype=np.float64)
    compiled = compile_matrix(
        g,
        c,
        frac_bits=args.frac_bits,
        bit_width=args.bit_width,
        max_terms=args.max_terms,
        fixed_degree=args.fixed_degree,
    )

    args.output_json.parent.mkdir(parents=True, exist_ok=True)
    args.output_json.write_text(json.dumps(compiled, indent=2), encoding="utf-8")
    print(f"Wrote {args.output_json}")


if __name__ == "__main__":
    main()
