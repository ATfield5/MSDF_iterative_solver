#!/usr/bin/env python3
"""
Unified pre-RTL comparison for the current solver mainline.

It compares:

- B1: cascaded online
- B2: conventional FPGA proxy
- Ours-A: current generic iteration-fused proxy
- Ours-B: constant-coefficient-specialized proxy
- Ours-C: Ours-B + block_H certification
"""

from __future__ import annotations

import argparse
import json
import math
from dataclasses import asdict, dataclass
from pathlib import Path
from typing import List, Optional

import numpy as np

from run_const_coeff_specialization_eval import evaluate_case as eval_const_case
from run_iterative_solver_model import (
    CycleModelParams,
    alpha_at,
    delta_ip,
    earliest_certified_digit,
    make_jacobi_case,
    prefix_proxy,
    safe_norm,
    theta_row_conventional,
)
from run_local_cert_sweep import build_block_weights, earliest_certified_digit_blockwise


@dataclass
class StackEvalCase:
    case: str
    n: int
    rho_bound: float
    exact_true_stop_iter: int
    generic_stop_iter: Optional[int]
    block_stop_iter: Optional[int]
    avg_j_generic: float
    avg_j_block: float
    cycles_b1: int
    cycles_b2: int
    cycles_ours_a: Optional[int]
    cycles_ours_b: Optional[int]
    cycles_ours_c: Optional[int]
    speedup_a_vs_b1: Optional[float]
    speedup_b_vs_b1: Optional[float]
    speedup_c_vs_b1: Optional[float]
    speedup_c_vs_b2: Optional[float]


def simulate_stack_case(
    name: str,
    g: np.ndarray,
    c: np.ndarray,
    rho_bound: float,
    params: CycleModelParams,
    block_size: int,
) -> StackEvalCase:
    n = g.shape[0]
    x = np.zeros(n, dtype=np.float64)
    x_star = np.linalg.solve(np.eye(n, dtype=np.float64) - g, c)
    h_abs = np.abs(g @ np.linalg.inv(np.eye(n, dtype=np.float64) - g))
    block_weights = build_block_weights(h_abs, block_size)

    avg_nu = float(np.mean(np.count_nonzero(g, axis=1)))
    nu_model = max(1, int(round(avg_nu)))
    b_r = math.ceil(n / params.row_engines)
    b_r_conv = math.ceil(n / params.row_engines_conv)

    theta_cas = 1 + params.delta_mult + 1 + (params.delta_add + 1) * math.ceil(math.log2(nu_model + 1))
    theta_conv = theta_row_conventional(nu_model, params)
    const_proxy = eval_const_case(name=name, g=g, rho_bound=rho_bound, q=params.q)
    theta_ours_a = const_proxy.theta_row_generic_proxy
    theta_ours_b = const_proxy.theta_row_const_proxy

    per_iter_b1 = b_r * (
        theta_cas + params.q + params.t_fmt + params.t_delta + params.t_chk + params.t_restart
    )
    per_iter_b2 = b_r_conv * (
        theta_conv + params.t_store_conv + params.t_delta_conv + params.t_chk_conv
    )

    eps_d = params.eta * (1.0 - rho_bound) / rho_bound if 0.0 < rho_bound < 1.0 else 0.0

    exact_true_stop_iter: Optional[int] = None
    generic_stop_iter: Optional[int] = None
    block_stop_iter: Optional[int] = None
    cert_j_generic_hist: List[Optional[int]] = []
    cert_j_block_hist: List[Optional[int]] = []

    for k in range(1, params.max_iters + 1):
        x_next = g @ x + c
        d = x_next - x
        err_next = safe_norm(x_next - x_star, "linf")

        cert_j_generic = earliest_certified_digit(d, eps_d, params.q, "linf")
        cert_j_block = earliest_certified_digit_blockwise(
            d=d,
            block_weights=block_weights,
            eta=params.eta,
            q=params.q,
            block_size=block_size,
        )

        cert_j_generic_hist.append(cert_j_generic)
        cert_j_block_hist.append(cert_j_block)

        if exact_true_stop_iter is None and err_next <= params.eta:
            exact_true_stop_iter = k
        if generic_stop_iter is None and cert_j_generic is not None:
            generic_stop_iter = k
        if block_stop_iter is None and cert_j_block is not None:
            block_stop_iter = k

        x = x_next

    if exact_true_stop_iter is None:
        exact_true_stop_iter = params.max_iters

    total_cycles_b1 = per_iter_b1 * exact_true_stop_iter
    total_cycles_b2 = per_iter_b2 * exact_true_stop_iter

    cycles_a = None
    if generic_stop_iter is not None:
        cycles_a = 0
        for cert_j in cert_j_generic_hist[:generic_stop_iter]:
            eff_j = cert_j if cert_j is not None else params.q
            cycles_a += b_r * (theta_ours_a + eff_j + params.t_handoff)

    cycles_b = None
    if generic_stop_iter is not None:
        cycles_b = 0
        for cert_j in cert_j_generic_hist[:generic_stop_iter]:
            eff_j = cert_j if cert_j is not None else params.q
            cycles_b += b_r * (theta_ours_b + eff_j + params.t_handoff)

    cycles_c = None
    if block_stop_iter is not None:
        cycles_c = 0
        for cert_j in cert_j_block_hist[:block_stop_iter]:
            eff_j = cert_j if cert_j is not None else params.q
            cycles_c += b_r * (theta_ours_b + eff_j + params.t_handoff)

    def ratio(base: int, new: Optional[int]) -> Optional[float]:
        if new is None or new <= 0:
            return None
        return float(base) / float(new)

    generic_digits = [j for j in cert_j_generic_hist[:exact_true_stop_iter] if j is not None]
    block_digits = [j for j in cert_j_block_hist[:exact_true_stop_iter] if j is not None]

    return StackEvalCase(
        case=name,
        n=n,
        rho_bound=rho_bound,
        exact_true_stop_iter=exact_true_stop_iter,
        generic_stop_iter=generic_stop_iter,
        block_stop_iter=block_stop_iter,
        avg_j_generic=float(np.mean(generic_digits)) if generic_digits else float(params.q),
        avg_j_block=float(np.mean(block_digits)) if block_digits else float(params.q),
        cycles_b1=total_cycles_b1,
        cycles_b2=total_cycles_b2,
        cycles_ours_a=cycles_a,
        cycles_ours_b=cycles_b,
        cycles_ours_c=cycles_c,
        speedup_a_vs_b1=ratio(total_cycles_b1, cycles_a),
        speedup_b_vs_b1=ratio(total_cycles_b1, cycles_b),
        speedup_c_vs_b1=ratio(total_cycles_b1, cycles_c),
        speedup_c_vs_b2=ratio(total_cycles_b2, cycles_c),
    )


def build_markdown(cases: List[StackEvalCase], block_size: int) -> str:
    lines: List[str] = []
    lines.append("# Specialized Solver Stack Evaluation")
    lines.append("")
    lines.append("This report compares the current solver-mainline variants before RTL.")
    lines.append("")
    lines.append("## Variants")
    lines.append("")
    lines.append("- `B1`: cascaded online")
    lines.append("- `B2`: conventional FPGA proxy")
    lines.append("- `Ours-A`: generic-front-end iteration-fused proxy")
    lines.append("- `Ours-B`: constant-coefficient-specialized row proxy + global certification")
    lines.append(f"- `Ours-C`: Ours-B + `block_H` certification with `block_size={block_size}`")
    lines.append("")
    lines.append("## Case Table")
    lines.append("")
    lines.append("| case | n | rho | exact stop | generic stop | block stop | avg j generic | avg j block | cycles B1 | cycles B2 | cycles A | cycles B | cycles C | A vs B1 | B vs B1 | C vs B1 | C vs B2 |")
    lines.append("| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |")
    for case in cases:
        lines.append(
            f"| `{case.case}` | {case.n} | {case.rho_bound:.3f} | {case.exact_true_stop_iter} | "
            f"{case.generic_stop_iter if case.generic_stop_iter is not None else 'NA'} | "
            f"{case.block_stop_iter if case.block_stop_iter is not None else 'NA'} | "
            f"{case.avg_j_generic:.2f} | {case.avg_j_block:.2f} | "
            f"{case.cycles_b1} | {case.cycles_b2} | "
            f"{case.cycles_ours_a if case.cycles_ours_a is not None else 'NA'} | "
            f"{case.cycles_ours_b if case.cycles_ours_b is not None else 'NA'} | "
            f"{case.cycles_ours_c if case.cycles_ours_c is not None else 'NA'} | "
            f"{(f'{case.speedup_a_vs_b1:.3f}' if case.speedup_a_vs_b1 is not None else 'NA')} | "
            f"{(f'{case.speedup_b_vs_b1:.3f}' if case.speedup_b_vs_b1 is not None else 'NA')} | "
            f"{(f'{case.speedup_c_vs_b1:.3f}' if case.speedup_c_vs_b1 is not None else 'NA')} | "
            f"{(f'{case.speedup_c_vs_b2:.3f}' if case.speedup_c_vs_b2 is not None else 'NA')} |"
        )
    lines.append("")
    lines.append("## Interpretation")
    lines.append("")
    lines.append("- `Ours-B vs Ours-A` isolates the value of constant-matrix specialization in the row-update front-end.")
    lines.append("- `Ours-C vs Ours-B` isolates the value of stronger `block_H` certification.")
    lines.append("- `C vs B2` is still a model-level proxy and must not be promoted to a final hardware claim.")
    lines.append("")
    return "\n".join(lines)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--seed", type=int, default=98765)
    parser.add_argument("--block-size", type=int, default=4)
    parser.add_argument("--output-md", type=Path, default=Path("MSDF_iterative_solver/generated/specialized_stack_eval.md"))
    parser.add_argument("--output-json", type=Path, default=Path("MSDF_iterative_solver/generated/specialized_stack_eval.json"))
    args = parser.parse_args()

    params = CycleModelParams(q=24, eta=1e-6, max_iters=256)
    ns = [32, 64, 128]
    rho_targets = [0.5, 0.7, 0.9]
    avg_degrees = [4, 8]

    cases: List[StackEvalCase] = []
    seed_counter = args.seed
    for n in ns:
        for rho_target in rho_targets:
            for deg in avg_degrees:
                g, c, rho, _stop_norm, _avg_nu, _dummy, _max_nu = make_jacobi_case(
                    n=n,
                    rho_target=rho_target,
                    avg_degree=deg,
                    seed=seed_counter,
                    structured=True,
                    bandwidth=max(1, deg // 2),
                )
                seed_counter += 1
                cases.append(
                    simulate_stack_case(
                        name=f"jacobi_n{n}_rho{rho_target:.2f}_deg{deg}",
                        g=g,
                        c=c,
                        rho_bound=rho,
                        params=params,
                        block_size=min(args.block_size, n),
                    )
                )

    args.output_md.parent.mkdir(parents=True, exist_ok=True)
    args.output_json.parent.mkdir(parents=True, exist_ok=True)
    args.output_md.write_text(build_markdown(cases, args.block_size), encoding="utf-8")
    args.output_json.write_text(json.dumps({"cases": [asdict(case) for case in cases]}, indent=2), encoding="utf-8")
    print(f"Wrote {args.output_md}")
    print(f"Wrote {args.output_json}")


if __name__ == "__main__":
    main()
