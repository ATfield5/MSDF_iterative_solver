#!/usr/bin/env python3
"""
Rigorous local/block-wise certification sweep for the iterative-solver mainline.

The key bound is:

    e^(k+1) = -G (I - G)^(-1) d^(k)

Hence a sufficient certificate is obtained from:

    |e^(k+1)| <= |H| |d^(k)|,   H = G (I - G)^(-1)

Block-wise certification groups components of d^(k), computes upper bounds per
block from prefix digits, and contracts them through precomputed block weights.
"""

from __future__ import annotations

import argparse
import json
import math
from dataclasses import asdict, dataclass
from pathlib import Path
from typing import List, Optional, Sequence

import numpy as np

from run_iterative_solver_model import (
    CycleModelParams,
    alpha_at,
    certification_bounds,
    delta_ip,
    earliest_certified_digit,
    make_jacobi_case,
    prefix_proxy,
    safe_norm,
    theta_row_conventional,
)


@dataclass
class CertModeCase:
    mode: str
    case: str
    n: int
    rho_bound: float
    block_size: int
    exact_true_stop_iter: int
    cert_stop_iter: Optional[int]
    cert_stop_error: Optional[float]
    avg_certified_digits: float
    min_certified_digits: Optional[int]
    max_certified_digits: Optional[int]
    certified_fraction: float
    false_stop_count: int
    total_cycles_b1: int
    total_cycles_fused: Optional[int]
    total_cycles_b2: int
    speedup_fused_vs_b1: Optional[float]
    speedup_fused_vs_b2: Optional[float]


def build_block_weights(h_abs: np.ndarray, block_size: int) -> np.ndarray:
    n = h_abs.shape[1]
    num_blocks = math.ceil(n / block_size)
    weights = np.zeros((h_abs.shape[0], num_blocks), dtype=np.float64)
    for b in range(num_blocks):
        lo = b * block_size
        hi = min(n, (b + 1) * block_size)
        weights[:, b] = np.sum(h_abs[:, lo:hi], axis=1)
    return weights


def earliest_certified_digit_blockwise(
    d: np.ndarray,
    block_weights: np.ndarray,
    eta: float,
    q: int,
    block_size: int,
) -> Optional[int]:
    n = d.size
    num_blocks = math.ceil(n / block_size)
    for j in range(1, q + 1):
        pref = prefix_proxy(d, j)
        tail = 2.0 ** (-j)
        ub = np.abs(pref) + tail
        block_ub = np.zeros(num_blocks, dtype=np.float64)
        for b in range(num_blocks):
            lo = b * block_size
            hi = min(n, (b + 1) * block_size)
            block_ub[b] = float(np.max(ub[lo:hi]))
        err_ub = block_weights @ block_ub
        if float(np.max(err_ub)) <= eta:
            return j
    return None


def simulate_cert_mode(
    name: str,
    g: np.ndarray,
    c: np.ndarray,
    rho_bound: float,
    params: CycleModelParams,
    mode: str,
    block_size: int,
) -> CertModeCase:
    n = g.shape[0]
    x = np.zeros(n, dtype=np.float64)
    x_star = np.linalg.solve(np.eye(n, dtype=np.float64) - g, c)
    h_abs = np.abs(g @ np.linalg.inv(np.eye(n, dtype=np.float64) - g))
    block_weights = build_block_weights(h_abs, block_size)

    avg_nu = float(np.mean(np.count_nonzero(g, axis=1)))
    b_r = math.ceil(n / params.row_engines)
    b_r_conv = math.ceil(n / params.row_engines_conv)
    nu_model = max(1, int(round(avg_nu)))
    theta_int = 1 + delta_ip(nu_model) + alpha_at(nu_model) + 1
    theta_cas = 1 + params.delta_mult + 1 + (params.delta_add + 1) * math.ceil(math.log2(nu_model + 1))
    theta_conv = theta_row_conventional(nu_model, params)

    per_iter_b1 = b_r * (
        theta_cas
        + params.q
        + params.t_fmt
        + params.t_delta
        + params.t_chk
        + params.t_restart
    )
    per_iter_b2 = b_r_conv * (
        theta_conv + params.t_store_conv + params.t_delta_conv + params.t_chk_conv
    )

    cert_j_history: List[Optional[int]] = []
    exact_true_stop_iter: Optional[int] = None
    cert_stop_iter: Optional[int] = None
    cert_stop_error: Optional[float] = None

    eps_d = params.eta * (1.0 - rho_bound) / rho_bound if 0.0 < rho_bound < 1.0 else 0.0

    for k in range(1, params.max_iters + 1):
        x_next = g @ x + c
        d = x_next - x
        err_next = safe_norm(x_next - x_star, "linf")

        if mode == "global_rho":
            cert_j = earliest_certified_digit(d, eps_d, params.q, "linf")
        else:
            cert_j = earliest_certified_digit_blockwise(
                d=d,
                block_weights=block_weights,
                eta=params.eta,
                q=params.q,
                block_size=block_size,
            )

        cert_j_history.append(cert_j)

        if exact_true_stop_iter is None and err_next <= params.eta:
            exact_true_stop_iter = k

        if cert_stop_iter is None and cert_j is not None:
            cert_stop_iter = k
            cert_stop_error = err_next

        x = x_next

    if exact_true_stop_iter is None:
        exact_true_stop_iter = params.max_iters

    relevant_cert_digits = [j for j in cert_j_history[:exact_true_stop_iter] if j is not None]
    certified_fraction = float(len(relevant_cert_digits)) / float(exact_true_stop_iter)
    avg_certified_digits = float(np.mean(relevant_cert_digits)) if relevant_cert_digits else float(params.q)
    min_certified_digits = int(min(relevant_cert_digits)) if relevant_cert_digits else None
    max_certified_digits = int(max(relevant_cert_digits)) if relevant_cert_digits else None

    total_cycles_b1 = per_iter_b1 * exact_true_stop_iter
    total_cycles_b2 = per_iter_b2 * exact_true_stop_iter
    total_cycles_fused = None
    if cert_stop_iter is not None:
        total_cycles_fused = 0
        for cert_j in cert_j_history[:cert_stop_iter]:
            eff_j = cert_j if cert_j is not None else params.q
            total_cycles_fused += b_r * (theta_int + eff_j + params.t_handoff)

    false_stop = 0
    if cert_stop_iter is not None and cert_stop_error is not None and cert_stop_error > params.eta:
        false_stop = 1

    speedup_b1 = None
    speedup_b2 = None
    if total_cycles_fused is not None and total_cycles_fused > 0:
        speedup_b1 = float(total_cycles_b1) / float(total_cycles_fused)
        speedup_b2 = float(total_cycles_b2) / float(total_cycles_fused)

    return CertModeCase(
        mode=mode,
        case=name,
        n=n,
        rho_bound=rho_bound,
        block_size=block_size,
        exact_true_stop_iter=exact_true_stop_iter,
        cert_stop_iter=cert_stop_iter,
        cert_stop_error=cert_stop_error,
        avg_certified_digits=avg_certified_digits,
        min_certified_digits=min_certified_digits,
        max_certified_digits=max_certified_digits,
        certified_fraction=certified_fraction,
        false_stop_count=false_stop,
        total_cycles_b1=total_cycles_b1,
        total_cycles_fused=total_cycles_fused,
        total_cycles_b2=total_cycles_b2,
        speedup_fused_vs_b1=speedup_b1,
        speedup_fused_vs_b2=speedup_b2,
    )


def build_markdown(cases: Sequence[CertModeCase], block_sizes: Sequence[int]) -> str:
    lines: List[str] = []
    lines.append("# Local and Block-Wise Certification Sweep")
    lines.append("")
    lines.append("This report compares the original global certification proxy against rigorous block-wise sensitivity certificates.")
    lines.append("")
    lines.append("## Methods")
    lines.append("")
    lines.append("- `global_rho`: original coarse bound based on `rho / (1-rho)` and a global `L_inf` delta threshold.")
    lines.append("- `block_H`: rigorous block-wise bound using `H = G (I-G)^(-1)` and block upper bounds of the online delta prefix.")
    lines.append("- `block_size = 1` is the strongest row-wise form.")
    lines.append("- `block_size = n` is a one-block sensitivity certificate.")
    lines.append("")
    lines.append("## Configuration")
    lines.append("")
    lines.append(f"- block sizes: `{list(block_sizes)}`")
    lines.append("")
    lines.append("## Case Table")
    lines.append("")
    lines.append("| case | mode | block | n | rho | exact true stop | cert stop | avg j* | min j* | max j* | certified frac | false stop | cycles B1 | cycles fused | speedup vs B1 | cycles B2 | speedup vs B2 |")
    lines.append("| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |")
    for case in cases:
        lines.append(
            f"| `{case.case}` | `{case.mode}` | {case.block_size} | {case.n} | {case.rho_bound:.3f} | "
            f"{case.exact_true_stop_iter} | {case.cert_stop_iter if case.cert_stop_iter is not None else 'NA'} | "
            f"{case.avg_certified_digits:.2f} | "
            f"{case.min_certified_digits if case.min_certified_digits is not None else 'NA'} | "
            f"{case.max_certified_digits if case.max_certified_digits is not None else 'NA'} | "
            f"{case.certified_fraction:.2f} | {case.false_stop_count} | {case.total_cycles_b1} | "
            f"{case.total_cycles_fused if case.total_cycles_fused is not None else 'NA'} | "
            f"{(f'{case.speedup_fused_vs_b1:.3f}' if case.speedup_fused_vs_b1 is not None else 'NA')} | "
            f"{case.total_cycles_b2} | "
            f"{(f'{case.speedup_fused_vs_b2:.3f}' if case.speedup_fused_vs_b2 is not None else 'NA')} |"
        )
    lines.append("")
    lines.append("## Interpretation")
    lines.append("")
    lines.append("- Lower `avg j*` means stronger prefix-level certification.")
    lines.append("- `false stop` must remain `0`; otherwise the certificate is not rigorous.")
    lines.append("- If smaller block size reduces `avg j*` or `cert stop`, block-wise certification is worth implementing.")
    lines.append("- `speedup vs B2` remains a model-level proxy, not a routed hardware claim.")
    lines.append("")
    return "\n".join(lines)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--seed", type=int, default=424242)
    parser.add_argument("--output-md", type=Path, default=Path("MSDF_iterative_solver/generated/local_cert_sweep.md"))
    parser.add_argument("--output-json", type=Path, default=Path("MSDF_iterative_solver/generated/local_cert_sweep.json"))
    args = parser.parse_args()

    params = CycleModelParams(q=24, eta=1e-6, max_iters=256)
    ns = [32, 64, 128]
    rho_targets = [0.5, 0.7, 0.9]
    avg_degrees = [4, 8]
    block_sizes = [1, 4, 8, 16]

    cases: List[CertModeCase] = []
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
                base_name = f"jacobi_n{n}_rho{rho_target:.2f}_deg{deg}"
                cases.append(
                    simulate_cert_mode(
                        name=base_name,
                        g=g,
                        c=c,
                        rho_bound=rho,
                        params=params,
                        mode="global_rho",
                        block_size=n,
                    )
                )
                for block_size in block_sizes:
                    eff_block = min(block_size, n)
                    cases.append(
                        simulate_cert_mode(
                            name=base_name,
                            g=g,
                            c=c,
                            rho_bound=rho,
                            params=params,
                            mode="block_H",
                            block_size=eff_block,
                        )
                    )

    args.output_md.parent.mkdir(parents=True, exist_ok=True)
    args.output_json.parent.mkdir(parents=True, exist_ok=True)

    args.output_md.write_text(build_markdown(cases, block_sizes), encoding="utf-8")
    args.output_json.write_text(
        json.dumps({"cases": [asdict(case) for case in cases]}, indent=2),
        encoding="utf-8",
    )

    print(f"Wrote {args.output_md}")
    print(f"Wrote {args.output_json}")


if __name__ == "__main__":
    main()
