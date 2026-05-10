#!/usr/bin/env python3
"""
Focused Jacobi certification sweep for the iteration-fused solver direction.
"""

from __future__ import annotations

import argparse
import json
from dataclasses import asdict
from pathlib import Path
from typing import List

from run_iterative_solver_model import (
    CycleModelParams,
    WorkloadCase,
    make_jacobi_case,
    simulate_case,
)


def build_jacobi_markdown(cases: List[WorkloadCase], q_values: List[int], eta_values: List[float], rho_targets: List[float], n_values: List[int]) -> str:
    lines: List[str] = []
    lines.append("# Jacobi Certification Sweep")
    lines.append("")
    lines.append("This report focuses on the certification behavior of the Jacobi-style workload.")
    lines.append("")
    lines.append("## Configuration")
    lines.append("")
    lines.append(f"- q sweep: `{q_values}`")
    lines.append(f"- eta sweep: `{eta_values}`")
    lines.append(f"- rho_target sweep: `{rho_targets}`")
    lines.append(f"- n sweep: `{n_values}`")
    lines.append("")
    lines.append("## Case Table")
    lines.append("")
    lines.append("| case | n | rho | exact stop iter | fused stop iter | avg j* | min j* | max j* | certified frac | cycles B1 | cycles fused | speedup vs B1 | cycles B2 | speedup vs B2 |")
    lines.append("| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |")
    for case in cases:
        lines.append(
            f"| `{case.name}` | {case.n} | {case.rho_bound:.3f} | {case.exact_stop_iter} | "
            f"{case.fused_stop_iter if case.fused_stop_iter is not None else 'NA'} | "
            f"{case.avg_certified_digits:.2f} | "
            f"{case.min_certified_digits if case.min_certified_digits is not None else 'NA'} | "
            f"{case.max_certified_digits if case.max_certified_digits is not None else 'NA'} | "
            f"{case.certified_fraction:.2f} | {case.total_cycles_b1} | "
            f"{case.total_cycles_fused if case.total_cycles_fused is not None else 'NA'} | "
            f"{(f'{case.speedup_fused_vs_b1:.3f}' if case.speedup_fused_vs_b1 is not None else 'NA')} | "
            f"{case.total_cycles_b2} | "
            f"{(f'{case.speedup_fused_vs_b2:.3f}' if case.speedup_fused_vs_b2 is not None else 'NA')} |"
        )
    lines.append("")
    lines.append("## Interpretation")
    lines.append("")
    lines.append("- Lower `avg j*` means stronger solver-level certification benefit.")
    lines.append("- If `fused stop iter` equals `exact stop iter`, the gain comes only from within-iteration digit-depth reduction.")
    lines.append("- If `speedup vs B1` stays above `1`, iteration-fused remains justified against cascaded online.")
    lines.append("- `speedup vs B2` is still only a proxy and should not be used as a final hardware claim.")
    lines.append("")
    return "\n".join(lines)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--seed", type=int, default=24680)
    parser.add_argument("--output-md", type=Path, default=Path("MSDF_iterative_solver/generated/jacobi_cert_sweep.md"))
    parser.add_argument("--output-json", type=Path, default=Path("MSDF_iterative_solver/generated/jacobi_cert_sweep.json"))
    args = parser.parse_args()

    ns = [32, 64, 128]
    qs = [16, 20, 24, 28]
    etas = [1e-4, 1e-6, 1e-8]
    rho_targets = [0.5, 0.7, 0.9]
    avg_degrees = [4, 8]

    cases: List[WorkloadCase] = []
    seed_counter = args.seed
    for q in qs:
        for eta in etas:
            params = CycleModelParams(q=q, eta=eta, max_iters=256)
            for n in ns:
                for rho_target in rho_targets:
                    for deg in avg_degrees:
                        g, c, rho, stop_norm, avg_nu, _dummy, max_nu = make_jacobi_case(
                            n=n,
                            rho_target=rho_target,
                            avg_degree=deg,
                            seed=seed_counter,
                            structured=True,
                            bandwidth=max(1, deg // 2),
                        )
                        seed_counter += 1
                        cases.append(
                            simulate_case(
                                family="jacobi_cert_sweep",
                                name=f"jacobi_n{n}_rho{rho_target:.2f}_deg{deg}_q{q}_eta{eta:.0e}",
                                g=g,
                                c=c,
                                rho_bound=rho,
                                stop_norm=stop_norm,
                                avg_nu=avg_nu,
                                max_nu=max_nu,
                                params=params,
                            )
                        )

    args.output_md.parent.mkdir(parents=True, exist_ok=True)
    args.output_json.parent.mkdir(parents=True, exist_ok=True)

    args.output_md.write_text(
        build_jacobi_markdown(cases, qs, etas, rho_targets, ns),
        encoding="utf-8",
    )
    args.output_json.write_text(
        json.dumps({"cases": [asdict(case) for case in cases]}, indent=2),
        encoding="utf-8",
    )

    print(f"Wrote {args.output_md}")
    print(f"Wrote {args.output_json}")


if __name__ == "__main__":
    main()
