#!/usr/bin/env python3
"""
Software golden model and cycle estimator for the iteration-fused online
arithmetic solver direction.

This script does not emulate exact signed-digit streams. Instead, it uses an
arithmetic-agnostic prefix proxy:

    prefix_j(x) = trunc(x * 2^j) / 2^j

with a conservative tail bound 2^-j.

That is enough to instantiate the solver-level certification equations in
ITERATION_FUSED_MATH.md and the cycle formulas in CYCLE_RESOURCE_MODEL.md.
"""

from __future__ import annotations

import argparse
import json
import math
from dataclasses import asdict, dataclass
from pathlib import Path
from typing import Dict, List, Optional, Sequence, Tuple

import numpy as np


@dataclass
class CycleModelParams:
    q: int = 24
    row_engines: int = 1
    row_engines_conv: int = 1
    delta_mult: int = 3
    delta_add: int = 2
    t_fmt: int = 2
    t_delta: int = 1
    t_chk: int = 1
    t_restart: int = 2
    t_handoff: int = 1
    theta_mac_fill: int = 4
    theta_bias: int = 1
    t_store_conv: int = 1
    t_delta_conv: int = 1
    t_chk_conv: int = 1
    p_mac_max: int = 8
    eta: float = 1e-6
    max_iters: int = 256


@dataclass
class WorkloadCase:
    family: str
    name: str
    n: int
    avg_nu: float
    max_nu: int
    rho_bound: float
    stop_norm: str
    q: int
    exact_stop_iter: int
    fused_stop_iter: Optional[int]
    exact_stop_error: float
    fused_stop_error: Optional[float]
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


def safe_norm(vec: np.ndarray, which: str) -> float:
    if which == "l1":
        return float(np.sum(np.abs(vec)))
    if which == "linf":
        return float(np.max(np.abs(vec)))
    raise ValueError(f"unsupported norm {which}")


def prefix_proxy(vec: np.ndarray, j: int) -> np.ndarray:
    scale = float(1 << j)
    return np.trunc(vec * scale) / scale


def certification_bounds(vec: np.ndarray, j: int, which: str) -> Tuple[float, float]:
    pref = prefix_proxy(vec, j)
    tail = 2.0 ** (-j)
    abs_pref = np.abs(pref)
    if which == "l1":
        upper = float(np.sum(abs_pref) + vec.size * tail)
        lower = float(max(0.0, np.sum(abs_pref) - vec.size * tail))
        return lower, upper
    if which == "linf":
        upper = float(np.max(abs_pref) + tail)
        lower = float(np.max(np.maximum(0.0, abs_pref - tail)))
        return lower, upper
    raise ValueError(f"unsupported norm {which}")


def earliest_certified_digit(vec: np.ndarray, eps_d: float, q: int, which: str) -> Optional[int]:
    for j in range(1, q + 1):
        _lower, upper = certification_bounds(vec, j, which)
        if upper <= eps_d:
            return j
    return None


def make_pagerank_case(
    n: int,
    beta: float,
    avg_degree: int,
    seed: int,
) -> Tuple[np.ndarray, np.ndarray, float, str, float, float, int]:
    rng = np.random.default_rng(seed)
    p = min(1.0, float(avg_degree) / max(1, n - 1))
    adj = rng.random((n, n)) < p
    np.fill_diagonal(adj, False)

    out_deg = np.sum(adj, axis=0)
    mtx = np.zeros((n, n), dtype=np.float64)
    for col in range(n):
        if out_deg[col] == 0:
            mtx[:, col] = 1.0 / n
        else:
            mtx[:, col] = adj[:, col].astype(np.float64) / float(out_deg[col])

    g = beta * mtx
    c = np.full(n, (1.0 - beta) / n, dtype=np.float64)
    avg_nu = float(np.mean(np.count_nonzero(mtx, axis=1)))
    max_nu = int(np.max(np.count_nonzero(mtx, axis=1)))
    rho_bound = beta
    return g, c, rho_bound, "l1", avg_nu, float(max_nu), max_nu


def make_jacobi_case(
    n: int,
    rho_target: float,
    avg_degree: int,
    seed: int,
    structured: bool = False,
    bandwidth: Optional[int] = None,
) -> Tuple[np.ndarray, np.ndarray, float, str, float, float, int]:
    rng = np.random.default_rng(seed)
    offdiag = np.zeros((n, n), dtype=np.float64)

    if structured:
        bw = bandwidth if bandwidth is not None else max(1, avg_degree // 2)
        for i in range(n):
            lo = max(0, i - bw)
            hi = min(n, i + bw + 1)
            for j in range(lo, hi):
                if i != j:
                    offdiag[i, j] = rng.uniform(-0.5, 0.5)
    else:
        p = min(1.0, float(avg_degree) / max(1, n - 1))
        mask = rng.random((n, n)) < p
        np.fill_diagonal(mask, False)
        offdiag[mask] = rng.uniform(-0.5, 0.5, size=int(np.sum(mask)))

    row_abs = np.sum(np.abs(offdiag), axis=1)
    row_targets = rho_target * (0.6 + 0.4 * rng.random(n))
    row_targets = np.clip(row_targets, 0.05, rho_target)
    diag = np.where(row_abs > 0.0, row_abs / row_targets, 1.0)
    a = np.diag(diag) + offdiag
    b = rng.uniform(-0.5, 0.5, size=n)

    g = np.zeros_like(a)
    for i in range(n):
        g[i, :] = -a[i, :] / diag[i]
        g[i, i] = 0.0
    c = b / diag

    rho_bound = float(np.max(np.sum(np.abs(g), axis=1)))
    avg_nu = float(np.mean(np.count_nonzero(g, axis=1)))
    max_nu = int(np.max(np.count_nonzero(g, axis=1)))
    return g, c, rho_bound, "linf", avg_nu, float(max_nu), max_nu


def delta_threshold(eta: float, rho_bound: float) -> float:
    if rho_bound <= 0.0:
        return math.inf
    if rho_bound >= 1.0:
        return 0.0
    return eta * (1.0 - rho_bound) / rho_bound


def delta_ip(nu: int) -> int:
    return math.ceil(math.log2((2 * nu + 1) / 3.0)) + 3


def alpha_at(nu: int) -> int:
    return math.ceil(math.ceil(math.log2(nu + 1)) / 2.0) - 1


def theta_row_cascaded(nu: int, params: CycleModelParams) -> int:
    return 1 + params.delta_mult + 1 + (params.delta_add + 1) * math.ceil(math.log2(nu + 1))


def theta_row_integrated(nu: int) -> int:
    return 1 + delta_ip(nu) + alpha_at(nu) + 1


def theta_row_conventional(nu: int, params: CycleModelParams) -> int:
    p_mac = min(max(1, nu), params.p_mac_max)
    mac_cycles = math.ceil(nu / p_mac)
    red_cycles = math.ceil(math.log2(max(1, p_mac)))
    return params.theta_mac_fill + mac_cycles + red_cycles + params.theta_bias


def simulate_case(
    family: str,
    name: str,
    g: np.ndarray,
    c: np.ndarray,
    rho_bound: float,
    stop_norm: str,
    avg_nu: float,
    max_nu: int,
    params: CycleModelParams,
) -> WorkloadCase:
    n = g.shape[0]
    x = np.zeros(n, dtype=np.float64)
    x_star = np.linalg.solve(np.eye(n, dtype=np.float64) - g, c)
    eps_d = delta_threshold(params.eta, rho_bound)

    b_r = math.ceil(n / params.row_engines)
    b_r_conv = math.ceil(n / params.row_engines_conv)
    nu_model = max(1, int(round(avg_nu)))

    theta_cas = theta_row_cascaded(nu_model, params)
    theta_int = theta_row_integrated(nu_model)
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
    err_history: List[float] = []
    exact_stop_iter: Optional[int] = None
    fused_stop_iter: Optional[int] = None
    exact_stop_error = math.inf
    fused_stop_error: Optional[float] = None

    for k in range(1, params.max_iters + 1):
        x_next = g @ x + c
        d = x_next - x
        err_next = safe_norm(x_next - x_star, stop_norm)
        d_norm = safe_norm(d, stop_norm)

        cert_j = earliest_certified_digit(d, eps_d, params.q, stop_norm)
        cert_j_history.append(cert_j)
        err_history.append(err_next)

        if exact_stop_iter is None and d_norm <= eps_d:
            exact_stop_iter = k
            exact_stop_error = err_next

        if fused_stop_iter is None and cert_j is not None:
            fused_stop_iter = k
            fused_stop_error = err_next

        x = x_next

    if exact_stop_iter is None:
        exact_stop_iter = params.max_iters
        exact_stop_error = safe_norm(x - x_star, stop_norm)

    if fused_stop_iter is not None and fused_stop_error is not None and fused_stop_error > params.eta:
        false_stop_count = 1
    else:
        false_stop_count = 0

    relevant_cert_digits = [j for j in cert_j_history[:exact_stop_iter] if j is not None]
    certified_fraction = float(len(relevant_cert_digits)) / float(exact_stop_iter)
    avg_certified_digits = float(np.mean(relevant_cert_digits)) if relevant_cert_digits else float(params.q)
    min_certified_digits = int(min(relevant_cert_digits)) if relevant_cert_digits else None
    max_certified_digits = int(max(relevant_cert_digits)) if relevant_cert_digits else None

    total_cycles_b1 = per_iter_b1 * exact_stop_iter
    total_cycles_b2 = per_iter_b2 * exact_stop_iter
    if fused_stop_iter is not None:
        total_cycles_fused = 0
        for cert_j in cert_j_history[:fused_stop_iter]:
            eff_j = cert_j if cert_j is not None else params.q
            total_cycles_fused += b_r * (theta_int + eff_j + params.t_handoff)
    else:
        total_cycles_fused = None

    speedup_b1 = None
    speedup_b2 = None
    if fused_stop_iter is not None and total_cycles_fused is not None and total_cycles_fused > 0:
        speedup_b1 = float(total_cycles_b1) / float(total_cycles_fused)
        speedup_b2 = float(total_cycles_b2) / float(total_cycles_fused)

    return WorkloadCase(
        family=family,
        name=name,
        n=n,
        avg_nu=avg_nu,
        max_nu=max_nu,
        rho_bound=rho_bound,
        stop_norm=stop_norm,
        q=params.q,
        exact_stop_iter=exact_stop_iter,
        fused_stop_iter=fused_stop_iter,
        exact_stop_error=exact_stop_error,
        fused_stop_error=fused_stop_error,
        avg_certified_digits=avg_certified_digits,
        min_certified_digits=min_certified_digits,
        max_certified_digits=max_certified_digits,
        certified_fraction=certified_fraction,
        false_stop_count=false_stop_count,
        total_cycles_b1=total_cycles_b1,
        total_cycles_fused=total_cycles_fused,
        total_cycles_b2=total_cycles_b2,
        speedup_fused_vs_b1=speedup_b1,
        speedup_fused_vs_b2=speedup_b2,
    )


def run_profile(profile: str, params: CycleModelParams, seed: int) -> List[WorkloadCase]:
    cases: List[WorkloadCase] = []
    rng = np.random.default_rng(seed)

    if profile == "quick":
        pagerank_dense_n = [8, 32, 64]
        pagerank_betas = [0.85, 0.95]
        pagerank_sparse_n = [64, 128]
        pagerank_sparse_deg = [4, 8]
        jacobi_dense_n = [8, 32, 64]
        jacobi_rho = [0.5, 0.9]
        jacobi_sparse_n = [64, 128]
        jacobi_sparse_deg = [4, 8]
    else:
        pagerank_dense_n = [8, 16, 32, 64]
        pagerank_betas = [0.85, 0.90, 0.95]
        pagerank_sparse_n = [64, 128, 256]
        pagerank_sparse_deg = [4, 8, 16]
        jacobi_dense_n = [8, 16, 32, 64]
        jacobi_rho = [0.5, 0.7, 0.9]
        jacobi_sparse_n = [64, 128, 256]
        jacobi_sparse_deg = [4, 8, 16]

    for n in pagerank_dense_n:
        for beta in pagerank_betas:
            deg = max(2, n // 2)
            g, c, rho, stop_norm, avg_nu, _max_nu_f, max_nu = make_pagerank_case(
                n=n,
                beta=beta,
                avg_degree=deg,
                seed=int(rng.integers(1 << 30)),
            )
            cases.append(
                simulate_case(
                    family="pagerank_dense",
                    name=f"pr_dense_n{n}_beta{beta:.2f}",
                    g=g,
                    c=c,
                    rho_bound=rho,
                    stop_norm=stop_norm,
                    avg_nu=avg_nu,
                    max_nu=max_nu,
                    params=params,
                )
            )

    for n in pagerank_sparse_n:
        for deg in pagerank_sparse_deg:
            beta = 0.90
            g, c, rho, stop_norm, avg_nu, _max_nu_f, max_nu = make_pagerank_case(
                n=n,
                beta=beta,
                avg_degree=deg,
                seed=int(rng.integers(1 << 30)),
            )
            cases.append(
                simulate_case(
                    family="pagerank_sparse",
                    name=f"pr_sparse_n{n}_deg{deg}",
                    g=g,
                    c=c,
                    rho_bound=rho,
                    stop_norm=stop_norm,
                    avg_nu=avg_nu,
                    max_nu=max_nu,
                    params=params,
                )
            )

    for n in jacobi_dense_n:
        for rho_t in jacobi_rho:
            deg = max(2, n // 2)
            g, c, rho, stop_norm, avg_nu, _max_nu_f, max_nu = make_jacobi_case(
                n=n,
                rho_target=rho_t,
                avg_degree=deg,
                seed=int(rng.integers(1 << 30)),
                structured=False,
            )
            cases.append(
                simulate_case(
                    family="jacobi_dense",
                    name=f"jacobi_dense_n{n}_rho{rho_t:.2f}",
                    g=g,
                    c=c,
                    rho_bound=rho,
                    stop_norm=stop_norm,
                    avg_nu=avg_nu,
                    max_nu=max_nu,
                    params=params,
                )
            )

    for n in jacobi_sparse_n:
        for deg in jacobi_sparse_deg:
            rho_t = 0.80
            g, c, rho, stop_norm, avg_nu, _max_nu_f, max_nu = make_jacobi_case(
                n=n,
                rho_target=rho_t,
                avg_degree=deg,
                seed=int(rng.integers(1 << 30)),
                structured=True,
                bandwidth=max(1, deg // 2),
            )
            cases.append(
                simulate_case(
                    family="jacobi_sparse",
                    name=f"jacobi_sparse_n{n}_deg{deg}",
                    g=g,
                    c=c,
                    rho_bound=rho,
                    stop_norm=stop_norm,
                    avg_nu=avg_nu,
                    max_nu=max_nu,
                    params=params,
                )
            )

    return cases


def format_float(value: Optional[float], digits: int = 3) -> str:
    if value is None:
        return "NA"
    return f"{value:.{digits}f}"


def summarize_gate(cases: Sequence[WorkloadCase]) -> Dict[str, bool]:
    gate1 = any(case.avg_certified_digits < case.q - 1.0 for case in cases)
    gate2 = any(
        case.total_cycles_fused is not None and case.speedup_fused_vs_b1 is not None and case.speedup_fused_vs_b1 > 1.0
        for case in cases
    )
    gate3 = any(
        case.total_cycles_fused is not None
        and case.speedup_fused_vs_b2 is not None
        and case.speedup_fused_vs_b2 > 1.0
        for case in cases
    )
    return {"gate1_certification_matters": gate1, "gate2_fused_beats_b1": gate2, "gate3_fused_beats_b2": gate3}


def build_markdown(cases: Sequence[WorkloadCase], params: CycleModelParams, profile: str) -> str:
    gates = summarize_gate(cases)
    lines: List[str] = []
    lines.append("# Iteration-Fused Solver Software Model Report")
    lines.append("")
    lines.append("This report instantiates the mathematical and cycle models for the new iterative-solver mainline.")
    lines.append("")
    lines.append("## Configuration")
    lines.append("")
    lines.append(f"- profile: `{profile}`")
    lines.append(f"- q: `{params.q}` fractional digits")
    lines.append(f"- eta: `{params.eta}`")
    lines.append(f"- max iterations: `{params.max_iters}`")
    lines.append(f"- row engines R: `{params.row_engines}`")
    lines.append(f"- conventional row engines R_conv: `{params.row_engines_conv}`")
    lines.append(f"- conventional P_MAC max proxy: `{params.p_mac_max}`")
    lines.append("")
    lines.append("## Gate Summary")
    lines.append("")
    for key, value in gates.items():
        lines.append(f"- `{key}`: `{value}`")
    lines.append("")
    lines.append("## Case Table")
    lines.append("")
    lines.append("| case | family | n | rho | norm | exact stop iter | fused stop iter | avg j* | certified frac | false stop | cycles B1 | cycles fused | speedup vs B1 | cycles B2 | speedup vs B2 |")
    lines.append("| --- | --- | ---: | ---: | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |")
    for case in cases:
        lines.append(
            f"| `{case.name}` | `{case.family}` | {case.n} | {case.rho_bound:.3f} | `{case.stop_norm}` | "
            f"{case.exact_stop_iter} | {case.fused_stop_iter if case.fused_stop_iter is not None else 'NA'} | "
            f"{case.avg_certified_digits:.2f} | {case.certified_fraction:.2f} | {case.false_stop_count} | "
            f"{case.total_cycles_b1} | {case.total_cycles_fused if case.total_cycles_fused is not None else 'NA'} | "
            f"{format_float(case.speedup_fused_vs_b1)} | {case.total_cycles_b2} | {format_float(case.speedup_fused_vs_b2)} |"
        )
    lines.append("")
    lines.append("## Reading Guide")
    lines.append("")
    lines.append("- `exact stop iter` uses the full-width delta criterion with the same solver-level threshold.")
    lines.append("- `fused stop iter` is the first iteration whose online upper bound certifies convergence within `q` digits.")
    lines.append("- `avg j*` is the average earliest certified digit among certified iterations. Lower is better.")
    lines.append("- `false stop` must remain `0`; otherwise the certification rule is invalid.")
    lines.append("- `B2` is still only a cycle proxy, not a routed hardware result.")
    lines.append("")
    lines.append("## First Interpretation")
    lines.append("")
    if gates["gate1_certification_matters"]:
        lines.append("- Gate 1 passes in this profile: at least one workload certifies materially before full `q` digits.")
    else:
        lines.append("- Gate 1 does not pass yet in this profile: certification depth stays too close to full `q`.")
    if gates["gate2_fused_beats_b1"]:
        lines.append("- Gate 2 passes in this profile: iteration-fused beats cascaded online in total cycles for at least one case.")
    else:
        lines.append("- Gate 2 does not pass yet in this profile: the current model does not justify moving beyond cascaded-online comparison.")
    if gates["gate3_fused_beats_b2"]:
        lines.append("- Gate 3 passes in this profile: fused online already beats the optimistic conventional proxy in at least one case.")
    else:
        lines.append("- Gate 3 does not pass yet in this profile: relative value versus conventional FPGA still needs to come from storage/DSP/system arguments or later hardware results.")
    lines.append("")
    lines.append("## Next Step")
    lines.append("")
    lines.append("- If Gate 1 and Gate 2 both pass, the next action is to keep this script as the software golden model backbone and add more systematic sweeps.")
    lines.append("- If Gate 3 does not pass, the next document should focus on microarchitecture and storage arguments before RTL, not on claiming raw cycle wins versus conventional FPGA.")
    lines.append("")
    return "\n".join(lines)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--profile", choices=["quick", "full"], default="quick")
    parser.add_argument("--seed", type=int, default=12345)
    parser.add_argument("--q", type=int, default=24)
    parser.add_argument("--eta", type=float, default=1e-6)
    parser.add_argument("--max-iters", type=int, default=256)
    parser.add_argument("--output-md", type=Path, default=Path("MSDF_iterative_solver/generated/iterative_solver_model_report.md"))
    parser.add_argument("--output-json", type=Path, default=Path("MSDF_iterative_solver/generated/iterative_solver_model_report.json"))
    args = parser.parse_args()

    params = CycleModelParams(q=args.q, eta=args.eta, max_iters=args.max_iters)
    cases = run_profile(args.profile, params, args.seed)

    args.output_md.parent.mkdir(parents=True, exist_ok=True)
    args.output_json.parent.mkdir(parents=True, exist_ok=True)

    markdown = build_markdown(cases, params, args.profile)
    args.output_md.write_text(markdown, encoding="utf-8")
    payload = {
        "profile": args.profile,
        "params": asdict(params),
        "gate_summary": summarize_gate(cases),
        "cases": [asdict(case) for case in cases],
    }
    args.output_json.write_text(json.dumps(payload, indent=2), encoding="utf-8")

    print(f"Wrote {args.output_md}")
    print(f"Wrote {args.output_json}")


if __name__ == "__main__":
    main()
