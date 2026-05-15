#!/usr/bin/env python3
"""Generate PageRank vectors for the parallel-in online MAC contract."""

from __future__ import annotations

import argparse
import json
import math
import subprocess
import sys
from pathlib import Path
from typing import Dict, List, Tuple

import numpy as np

from make_pagerank_runtime_vectors import build_l1_cert_params, build_pagerank_matrix
from run_iter_rtl_vector_gen import pack_fields, write_scalar_memh
from compile_coeff_templates import int_to_rail_vec


def run(cmd: List[str]) -> None:
    subprocess.run(cmd, check=True)


def rail_value(rail: Dict[str, str]) -> int:
    return int(rail["vec_p"], 2) - int(rail["vec_n"], 2)


def saturate_unsigned(value: int, width: int) -> int:
    if value <= 0:
        return 0
    return min(value, (1 << width) - 1)


def rail_from_signed(value: int, width: int) -> Tuple[int, int]:
    mag_max = (1 << width) - 1
    if value >= 0:
        return saturate_unsigned(value, width), 0
    return 0, saturate_unsigned(-value, width)


def signed_digit_value(p_word: int, n_word: int, data_width: int) -> int:
    value = 0
    for digit_idx in range(data_width):
        bit_sel = data_width - 1 - digit_idx
        value <<= 1
        p = (p_word >> bit_sel) & 1
        n = (n_word >> bit_sel) & 1
        if p and not n:
            value += 1
        elif n and not p:
            value -= 1
    return value


def sp_delay_from_bound(bound: float) -> int:
    if bound <= 0.0:
        return 2
    return max(2, int(math.ceil(math.log2(bound / 3.0))) + 3)


def round_shift_signed(value: int, shift: int) -> int:
    if shift <= 0:
        return int(value)
    if value >= 0:
        return (int(value) + (1 << (shift - 1))) >> shift
    return -(((-int(value)) + (1 << (shift - 1))) >> shift)


def sp_row_update(
    row: Dict[str, object],
    old_p_global: List[int],
    old_n_global: List[int],
    data_width: int,
    frac_bits: int,
    online_delay: int,
    degree: int,
) -> Tuple[int, int, int]:
    scale = 1 << frac_bits
    half_scale = scale >> 1
    w = 0
    out_p = 0
    out_n = 0
    capture_idx = 0

    terms = row["fixed_degree_terms"][:degree]
    bias_p = int(row["bias"]["rail"]["vec_p"], 2)
    bias_n = int(row["bias"]["rail"]["vec_n"], 2)

    for feed_idx in range(data_width + online_delay):
        contrib = 0
        if feed_idx < data_width:
            bit_sel = data_width - 1 - feed_idx
            for term in terms:
                if not int(term["valid"]):
                    continue
                src = int(term["col"])
                xp = (old_p_global[src] >> bit_sel) & 1
                xn = (old_n_global[src] >> bit_sel) & 1
                digit = 1 if xp and not xn else (-1 if xn and not xp else 0)
                coeff = rail_value(term["rail"])
                contrib += coeff * digit
            bp = (bias_p >> bit_sel) & 1
            bn = (bias_n >> bit_sel) & 1
            bias_digit = 1 if bp and not bn else (-1 if bn and not bp else 0)
            contrib += bias_digit * scale

        v = (w << 1) + (contrib >> online_delay)
        if feed_idx < online_delay:
            w = v
            continue

        if v >= half_scale:
            z = 1
            w = v - scale
        elif v <= -half_scale:
            z = -1
            w = v + scale
        else:
            z = 0
            w = v

        if capture_idx < data_width:
            bit_sel = data_width - 1 - capture_idx
            if z > 0:
                out_p |= 1 << bit_sel
            elif z < 0:
                out_n |= 1 << bit_sel
            capture_idx += 1

    return out_p, out_n, signed_digit_value(out_p, out_n, data_width)


def conv_row_update(
    row: Dict[str, object],
    old_p_global: List[int],
    old_n_global: List[int],
    data_width: int,
    product_shift: int,
    degree: int,
) -> Tuple[int, int, int]:
    row_sum = rail_value(row["bias"]["rail"])
    for term in row["fixed_degree_terms"][:degree]:
        if not int(term["valid"]):
            continue
        src = int(term["col"])
        state_term = int(old_p_global[src]) - int(old_n_global[src])
        coeff_term = rail_value(term["rail"])
        row_sum += round_shift_signed(state_term * coeff_term, product_shift)
    out_p, out_n = rail_from_signed(row_sum, data_width)
    return out_p, out_n, int(out_p) - int(out_n)


def sp_cluster_iteration(
    rows: List[Dict[str, object]],
    cert_cluster: Dict[str, object],
    old_p_global: List[int],
    old_n_global: List[int],
    cluster_base: int,
    num_rows: int,
    degree: int,
    data_width: int,
    frac_bits: int,
    online_delay: int,
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
        out_p, out_n, out_value = sp_row_update(
            row=row,
            old_p_global=old_p_global,
            old_n_global=old_n_global,
            data_width=data_width,
            frac_bits=frac_bits,
            online_delay=online_delay,
            degree=degree,
        )
        old_idx = cluster_base + local_row
        old_value = signed_digit_value(old_p_global[old_idx], old_n_global[old_idx], data_width)
        state_p_rows.append(out_p)
        state_n_rows.append(out_n)
        abs_upper_rows.append(min(abs(out_value - old_value) + int(tail_bound), bound_max))

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


def conv_cluster_iteration(
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
        out_p, out_n, out_value = conv_row_update(
            row=row,
            old_p_global=old_p_global,
            old_n_global=old_n_global,
            data_width=data_width,
            product_shift=product_shift,
            degree=degree,
        )
        old_idx = cluster_base + local_row
        old_value = int(old_p_global[old_idx]) - int(old_n_global[old_idx])
        state_p_rows.append(out_p)
        state_n_rows.append(out_n)
        abs_upper_rows.append(min(abs(out_value - old_value) + int(tail_bound), bound_max))

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
    parser.add_argument("--out-dir", type=Path, default=Path("MSDF_iterative_solver/generated/rtl_vectors/pagerank32_global_parallel_in_fractional"))
    parser.add_argument("--num-clusters", type=int, default=8)
    parser.add_argument("--num-rows", type=int, default=4)
    parser.add_argument("--degree", type=int, default=4)
    parser.add_argument("--num-iters", type=int, default=4)
    parser.add_argument("--beta", type=float, default=0.85)
    parser.add_argument("--bit-width", type=int, default=30)
    parser.add_argument("--data-width", type=int, default=32)
    parser.add_argument("--bound-width", type=int, default=16)
    parser.add_argument("--coeff-width", type=int, default=8)
    parser.add_argument("--acc-width", type=int, default=64)
    parser.add_argument("--block-size", type=int, default=1)
    parser.add_argument("--l1-eta", type=int, default=64)
    parser.add_argument("--linf-eta", type=int, default=1)
    parser.add_argument("--tail-bound", type=int, default=1)
    parser.add_argument("--force-delay", type=int, default=2)
    args = parser.parse_args()

    if args.block_size != 1:
        raise ValueError("PageRank L1 certification v1 requires --block-size 1")

    args.out_dir.mkdir(parents=True, exist_ok=True)
    total_rows = args.num_clusters * args.num_rows
    data_width = args.data_width
    if args.bit_width + 2 < data_width:
        raise ValueError(
            "parallel-in fixture packs bias with width bit_width+2; "
            f"bit_width={args.bit_width} is too small for data_width={data_width}"
        )
    frac_bits = data_width - 1
    # Conventional P4-SP keeps the existing strict fractional PageRank product
    # contract: round((state * coeff) / 2^DATA_WIDTH).  It is generated in the
    # same fixture so accuracy drift versus the P3-SP recurrence can be reported
    # without mixing graph/topology parameters.
    conv_product_shift = data_width
    src_idx_width = max(1, int(math.ceil(math.log2(total_rows))))
    num_blocks = (args.num_rows + args.block_size - 1) // args.block_size
    py = sys.executable

    teleport_lsb = max(1, int(round(((1.0 - args.beta) / float(total_rows)) * (1 << frac_bits))))
    g, c, graph_meta = build_pagerank_matrix(
        n=total_rows,
        degree=args.degree,
        beta=args.beta,
        frac_bits=frac_bits,
        teleport_lsb=teleport_lsb,
    )

    row_bounds = [float(np.sum(np.abs(g[i, :]))) + abs(float(c[i])) for i in range(total_rows)]
    max_bound = max(row_bounds) if row_bounds else 0.0
    derived_delay = sp_delay_from_bound(max_bound)
    if args.force_delay > 0 and derived_delay > args.force_delay:
        raise ValueError(
            f"forced online delay {args.force_delay} is unsafe for max bound {max_bound:.8f}; "
            f"derived delay is {derived_delay}"
        )
    online_delay = args.force_delay if args.force_delay > 0 else derived_delay

    matrix_json = args.out_dir / "matrix.json"
    cert_json = args.out_dir / "cert_params.json"
    compiled_json = args.out_dir / "coeff_templates.json"
    template_memh = args.out_dir / "templates.memh"
    cert_memh = args.out_dir / "cert_params.memh"

    matrix_json.write_text(json.dumps({"G": g.tolist(), "c": c.tolist(), "pagerank": graph_meta}, indent=2), encoding="utf-8")
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
        "--matrix-json", str(matrix_json),
        "--frac-bits", str(frac_bits),
        "--bit-width", str(args.bit_width),
        "--max-terms", str(args.degree),
        "--fixed-degree", str(args.degree),
        "--output-json", str(compiled_json),
    ])
    run([
        py,
        "MSDF_iterative_solver/pack_fixed_degree_templates.py",
        "--compiled-json", str(compiled_json),
        "--num-clusters", str(args.num_clusters),
        "--num-rows", str(args.num_rows),
        "--degree", str(args.degree),
        "--bit-width", str(args.bit_width),
        "--src-index-mode", "global",
        "--src-index-width", str(src_idx_width),
        "--output-memh", str(template_memh),
    ])
    run([
        py,
        "MSDF_iterative_solver/pack_cert_params.py",
        "--cert-json", str(cert_json),
        "--num-clusters", str(args.num_clusters),
        "--num-rows", str(args.num_rows),
        "--num-blocks", str(num_blocks),
        "--coeff-width", str(args.coeff_width),
        "--acc-width", str(args.acc_width),
        "--output-memh", str(cert_memh),
    ])

    compiled = json.loads(compiled_json.read_text(encoding="utf-8"))
    cert_data = json.loads(cert_json.read_text(encoding="utf-8"))
    max_coeff_sum_q = 0
    max_coeff_abs_q = 0
    for row in compiled["rows"]:
        coeff_sum = 0
        for term in row["fixed_degree_terms"][: args.degree]:
            if int(term["valid"]):
                coeff_q = abs(rail_value(term["rail"]))
                coeff_sum += coeff_q
                max_coeff_abs_q = max(max_coeff_abs_q, coeff_q)
        max_coeff_sum_q = max(max_coeff_sum_q, coeff_sum)
    scale_q = 1 << frac_bits
    cmax_q = max_coeff_sum_q + scale_q
    umax_q = (cmax_q + (1 << online_delay) - 1) >> online_delay
    mmax_q = max(cmax_q, scale_q + umax_q, scale_q)
    acc_width_min = 1 + int(math.ceil(math.log2(mmax_q + 1)))
    bit_width_min = max(1, int(math.ceil(math.log2(max_coeff_abs_q + 1))))
    bias_width_min = max(1, int(math.ceil(math.log2(teleport_lsb + 1))))
    state_p_global = [0 for _ in range(total_rows)]
    state_n_global = [0 for _ in range(total_rows)]
    conv_state_p_global = [0 for _ in range(total_rows)]
    conv_state_n_global = [0 for _ in range(total_rows)]
    iter_records: List[Dict[str, object]] = []
    conv_iter_records: List[Dict[str, object]] = []

    for iter_idx in range(args.num_iters):
        cluster_records: List[Dict[str, object]] = []
        next_p = [0 for _ in range(total_rows)]
        next_n = [0 for _ in range(total_rows)]
        for cluster_idx in range(args.num_clusters):
            base = cluster_idx * args.num_rows
            rows = compiled["rows"][base : base + args.num_rows]
            rec = sp_cluster_iteration(
                rows=rows,
                cert_cluster=cert_data["clusters"][cluster_idx],
                old_p_global=state_p_global,
                old_n_global=state_n_global,
                cluster_base=base,
                num_rows=args.num_rows,
                degree=args.degree,
                data_width=data_width,
                frac_bits=frac_bits,
                online_delay=online_delay,
                bound_width=args.bound_width,
                block_size=args.block_size,
                num_blocks=num_blocks,
                tail_bound=args.tail_bound,
            )
            cluster_records.append(rec)
            for row in range(args.num_rows):
                next_p[base + row] = int(rec["state_p_rows"][row])
                next_n[base + row] = int(rec["state_n_rows"][row])
        global_linf = 0
        for row_idx in range(total_rows):
            new_value = signed_digit_value(next_p[row_idx], next_n[row_idx], data_width)
            old_value = signed_digit_value(state_p_global[row_idx], state_n_global[row_idx], data_width)
            global_linf = max(global_linf, abs(new_value - old_value))
        state_p_global = next_p
        state_n_global = next_n
        local_l1 = [int(c_rec["max_error"]) for c_rec in cluster_records]
        global_l1 = int(sum(local_l1))
        iter_records.append({
            "iter": iter_idx,
            "clusters": cluster_records,
            "local_l1_by_cluster": local_l1,
            "global_l1_delta": global_l1,
            "global_linf_delta": global_linf,
            "converged": int(global_linf <= args.linf_eta),
            "continue": int(global_linf > args.linf_eta),
        })

        conv_cluster_records: List[Dict[str, object]] = []
        conv_next_p = [0 for _ in range(total_rows)]
        conv_next_n = [0 for _ in range(total_rows)]
        for cluster_idx in range(args.num_clusters):
            base = cluster_idx * args.num_rows
            rows = compiled["rows"][base : base + args.num_rows]
            rec = conv_cluster_iteration(
                rows=rows,
                cert_cluster=cert_data["clusters"][cluster_idx],
                old_p_global=conv_state_p_global,
                old_n_global=conv_state_n_global,
                cluster_base=base,
                num_rows=args.num_rows,
                degree=args.degree,
                data_width=data_width,
                product_shift=conv_product_shift,
                bound_width=args.bound_width,
                block_size=args.block_size,
                num_blocks=num_blocks,
                tail_bound=args.tail_bound,
            )
            conv_cluster_records.append(rec)
            for row in range(args.num_rows):
                conv_next_p[base + row] = int(rec["state_p_rows"][row])
                conv_next_n[base + row] = int(rec["state_n_rows"][row])
        conv_global_linf = 0
        for row_idx in range(total_rows):
            new_value = int(conv_next_p[row_idx]) - int(conv_next_n[row_idx])
            old_value = int(conv_state_p_global[row_idx]) - int(conv_state_n_global[row_idx])
            conv_global_linf = max(conv_global_linf, abs(new_value - old_value))
        conv_state_p_global = conv_next_p
        conv_state_n_global = conv_next_n
        conv_local_l1 = [int(c_rec["max_error"]) for c_rec in conv_cluster_records]
        conv_global_l1 = int(sum(conv_local_l1))
        conv_iter_records.append({
            "iter": iter_idx,
            "clusters": conv_cluster_records,
            "local_l1_by_cluster": conv_local_l1,
            "global_l1_delta": conv_global_l1,
            "global_linf_delta": conv_global_linf,
            "converged": int(conv_global_linf <= args.linf_eta),
            "continue": int(conv_global_linf > args.linf_eta),
        })

    write_scalar_memh(args.out_dir / "gold_state_p_iters.memh", [cluster["packed"]["state_p_rows"] for record in iter_records for cluster in record["clusters"]], args.num_rows * data_width)
    write_scalar_memh(args.out_dir / "gold_state_n_iters.memh", [cluster["packed"]["state_n_rows"] for record in iter_records for cluster in record["clusters"]], args.num_rows * data_width)
    write_scalar_memh(args.out_dir / "conv_gold_state_p_iters.memh", [cluster["packed"]["state_p_rows"] for record in conv_iter_records for cluster in record["clusters"]], args.num_rows * data_width)
    write_scalar_memh(args.out_dir / "conv_gold_state_n_iters.memh", [cluster["packed"]["state_n_rows"] for record in conv_iter_records for cluster in record["clusters"]], args.num_rows * data_width)
    write_scalar_memh(args.out_dir / "conv_gold_max_error_iters.memh", [cluster["max_error"] for record in conv_iter_records for cluster in record["clusters"]], args.acc_width)
    write_scalar_memh(args.out_dir / "conv_gold_global_l1_delta.memh", [record["global_l1_delta"] for record in conv_iter_records], args.acc_width)
    write_scalar_memh(args.out_dir / "conv_gold_global_linf_delta.memh", [record["global_linf_delta"] for record in conv_iter_records], args.acc_width)
    write_scalar_memh(args.out_dir / "gold_max_error_iters.memh", [cluster["max_error"] for record in iter_records for cluster in record["clusters"]], args.acc_width)
    write_scalar_memh(args.out_dir / "gold_certified_iters.memh", [cluster["certified"] for record in iter_records for cluster in record["clusters"]], 1)
    write_scalar_memh(args.out_dir / "gold_iter_converged.memh", [record["converged"] for record in iter_records], 1)
    write_scalar_memh(args.out_dir / "gold_iter_continue.memh", [record["continue"] for record in iter_records], 1)
    write_scalar_memh(args.out_dir / "gold_global_l1_delta.memh", [record["global_l1_delta"] for record in iter_records], args.acc_width)
    write_scalar_memh(args.out_dir / "gold_global_linf_delta.memh", [record["global_linf_delta"] for record in iter_records], args.acc_width)

    delay_meta = {
        "formula": "max(2, ceil(log2(max_i(A_i+B_i)/3))+3)",
        "row_bounds": row_bounds,
        "max_bound": max_bound,
        "derived_delay": derived_delay,
        "online_delay": online_delay,
        "forced_delay": args.force_delay,
        "frac_bits": frac_bits,
        "data_width": data_width,
        "bit_width": args.bit_width,
        "bias_width": args.bit_width + 2,
        "scale_q": scale_q,
        "teleport_lsb": teleport_lsb,
        "max_coeff_abs_q": max_coeff_abs_q,
        "max_coeff_sum_q": max_coeff_sum_q,
        "cmax_q": cmax_q,
        "umax_q": umax_q,
        "mmax_q": mmax_q,
        "bit_width_min": bit_width_min,
        "bias_width_min": bias_width_min,
        "acc_width_min": acc_width_min,
        "acc_width_impl": 36,
    }
    (args.out_dir / "sp_delay_metadata.json").write_text(json.dumps(delay_meta, indent=2), encoding="utf-8")

    summary = {
        "fixture": f"pagerank32_global_parallel_in_fractional_deg{args.degree}",
        "num_clusters": args.num_clusters,
        "num_rows": args.num_rows,
        "total_rows": total_rows,
        "degree": args.degree,
        "num_iters": args.num_iters,
        "bit_width": args.bit_width,
        "data_width": data_width,
        "bias_width": args.bit_width + 2,
        "frac_bits": frac_bits,
        "online_delay": online_delay,
        "derived_delay": derived_delay,
        "conv_product_shift": conv_product_shift,
        "bound_width": args.bound_width,
        "coeff_width": args.coeff_width,
        "acc_width": args.acc_width,
        "l1_eta": args.l1_eta,
        "linf_eta": args.linf_eta,
        "termination_norm": "linf",
        "termination_condition": "max_i |r_i(k+1)-r_i(k)| <= 2^-q, represented as <= 1 raw LSB",
        "tail_bound": args.tail_bound,
        "template_memh": str(template_memh),
        "cert_memh": str(cert_memh),
        "graph": graph_meta,
        "delay_metadata": delay_meta,
        "iterations": iter_records,
        "conv_iterations": conv_iter_records,
    }
    (args.out_dir / "summary.json").write_text(json.dumps(summary, indent=2), encoding="utf-8")
    print(
        f"Wrote {args.out_dir}; delay={online_delay}; max_bound={max_bound:.8f}; "
        f"global L1 by iter: {[record['global_l1_delta'] for record in iter_records]}; "
        f"global Linf by iter: {[record['global_linf_delta'] for record in iter_records]}"
    )


if __name__ == "__main__":
    main()
