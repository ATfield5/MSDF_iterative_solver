#!/usr/bin/env python3
"""
Proxy evaluation for constant-matrix specialization.

This script does not claim exact RTL timing. It quantifies two structural
effects that the current generic online row-update model does not exploit:

1. fixed coefficients can be encoded as compact signed-digit templates;
2. the variable-by-variable selector front-end can be replaced by a shallower
   constant-coefficient contribution generator.
"""

from __future__ import annotations

import argparse
import json
import math
from dataclasses import asdict, dataclass
from pathlib import Path
from typing import List

import numpy as np

from run_iterative_solver_model import (
    alpha_at,
    delta_ip,
    make_jacobi_case,
)


@dataclass
class ConstCoeffCase:
    name: str
    n: int
    rho_bound: float
    avg_nu: float
    max_nu: int
    q: int
    nnz: int
    avg_csd_terms: float
    max_csd_terms: int
    coeff_bits_generic: int
    coeff_bits_template: int
    coeff_storage_ratio: float
    theta_row_generic_proxy: int
    theta_row_const_proxy: int
    row_speedup_const_vs_generic: float


def csd_term_count(value: int) -> int:
    """Return the nonzero-term count of the NAF/CSD-like signed-digit form."""
    x = abs(int(value))
    if x == 0:
        return 0

    count = 0
    while x > 0:
        if x & 1:
            digit = 2 - (x & 3)
            x -= digit
            count += 1
        x >>= 1
    return count


def estimate_template_bits(term_count: int, shift_bits: int) -> int:
    if term_count <= 0:
        return 1
    count_bits = max(1, math.ceil(math.log2(term_count + 1)))
    return 1 + count_bits + term_count * (1 + shift_bits)


def evaluate_case(name: str, g: np.ndarray, rho_bound: float, q: int) -> ConstCoeffCase:
    nz_mask = g != 0.0
    nnz = int(np.count_nonzero(nz_mask))
    nu_rows = np.count_nonzero(nz_mask, axis=1)
    avg_nu = float(np.mean(nu_rows))
    max_nu = int(np.max(nu_rows))

    scale = 1 << q
    shift_bits = max(1, math.ceil(math.log2(q + 1)))

    csd_counts: List[int] = []
    coeff_bits_template = 0
    for coeff in g[nz_mask]:
        quant = int(np.rint(float(coeff) * scale))
        terms = csd_term_count(quant)
        csd_counts.append(terms)
        coeff_bits_template += estimate_template_bits(terms, shift_bits)

    avg_csd_terms = float(np.mean(csd_counts)) if csd_counts else 0.0
    max_csd_terms = int(max(csd_counts)) if csd_counts else 0
    coeff_bits_generic = nnz * (q + 1)
    coeff_storage_ratio = (
        float(coeff_bits_generic) / float(coeff_bits_template)
        if coeff_bits_template > 0
        else math.inf
    )

    nu_model = max(1, int(round(avg_nu)))

    # Front-end-aware row-delay proxy:
    # - generic variable-by-variable path pays a selector/append front-end
    # - constant specialization pays a local constant-coefficient generator depth
    t_varsel = max(1, math.ceil(math.log2(q + 1))) + 2
    t_const_coeff = max(1, math.ceil(math.log2(max(1, max_csd_terms) + 1)))

    theta_row_generic_proxy = 1 + t_varsel + delta_ip(nu_model) + alpha_at(nu_model) + 1
    theta_row_const_proxy = 1 + t_const_coeff + delta_ip(nu_model) + alpha_at(nu_model) + 1
    row_speedup = float(theta_row_generic_proxy) / float(theta_row_const_proxy)

    return ConstCoeffCase(
        name=name,
        n=g.shape[0],
        rho_bound=rho_bound,
        avg_nu=avg_nu,
        max_nu=max_nu,
        q=q,
        nnz=nnz,
        avg_csd_terms=avg_csd_terms,
        max_csd_terms=max_csd_terms,
        coeff_bits_generic=coeff_bits_generic,
        coeff_bits_template=coeff_bits_template,
        coeff_storage_ratio=coeff_storage_ratio,
        theta_row_generic_proxy=theta_row_generic_proxy,
        theta_row_const_proxy=theta_row_const_proxy,
        row_speedup_const_vs_generic=row_speedup,
    )


def build_markdown(cases: List[ConstCoeffCase], q_values: List[int]) -> str:
    lines: List[str] = []
    lines.append("# Constant-Coefficient Specialization Proxy Report")
    lines.append("")
    lines.append("This report estimates whether fixed-matrix specialization is structurally promising before RTL.")
    lines.append("")
    lines.append("## Model Scope")
    lines.append("")
    lines.append("- Coefficients are quantized to `q` fractional bits and converted to a signed-digit form.")
    lines.append("- `coeff_bits_generic` is the baseline storage proxy for directly storing `q+1` signed bits per nonzero coefficient.")
    lines.append("- `coeff_bits_template` is the template-storage proxy for signed-digit terms plus shift metadata.")
    lines.append("- `theta_row_generic_proxy` adds a variable-selector front-end depth to the integrated row-update proxy.")
    lines.append("- `theta_row_const_proxy` replaces that front-end with a local constant-coefficient contribution-generator depth.")
    lines.append("- These are architecture proxies, not post-route timing claims.")
    lines.append("")
    lines.append("## Configuration")
    lines.append("")
    lines.append(f"- q sweep: `{q_values}`")
    lines.append("")
    lines.append("## Case Table")
    lines.append("")
    lines.append("| case | n | rho | avg nu | max nu | q | avg CSD terms | max CSD terms | generic coeff bits | template coeff bits | storage ratio | generic row proxy | const row proxy | row speedup |")
    lines.append("| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |")
    for case in cases:
        lines.append(
            f"| `{case.name}` | {case.n} | {case.rho_bound:.3f} | {case.avg_nu:.2f} | {case.max_nu} | {case.q} | "
            f"{case.avg_csd_terms:.2f} | {case.max_csd_terms} | {case.coeff_bits_generic} | "
            f"{case.coeff_bits_template} | {case.coeff_storage_ratio:.3f} | "
            f"{case.theta_row_generic_proxy} | {case.theta_row_const_proxy} | "
            f"{case.row_speedup_const_vs_generic:.3f} |"
        )
    lines.append("")
    lines.append("## Interpretation")
    lines.append("")
    lines.append("- `storage ratio > 1` means signed-digit coefficient templates reduce coefficient storage/bandwidth versus direct `q`-bit storage.")
    lines.append("- `row speedup > 1` means the constant-coefficient front-end is shallower than the generic variable-by-variable selector front-end in this proxy.")
    lines.append("- This report is only intended to answer whether constant specialization is worth modeling and then implementing in RTL.")
    lines.append("")
    return "\n".join(lines)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--seed", type=int, default=13579)
    parser.add_argument("--output-md", type=Path, default=Path("MSDF_iterative_solver/generated/const_coeff_specialization_report.md"))
    parser.add_argument("--output-json", type=Path, default=Path("MSDF_iterative_solver/generated/const_coeff_specialization_report.json"))
    args = parser.parse_args()

    q_values = [16, 20, 24]
    ns = [32, 64, 128]
    rho_targets = [0.5, 0.7, 0.9]
    avg_degrees = [4, 8]

    cases: List[ConstCoeffCase] = []
    seed_counter = args.seed
    for q in q_values:
        for n in ns:
            for rho_target in rho_targets:
                for deg in avg_degrees:
                    g, _c, rho, _stop_norm, _avg_nu, _dummy, _max_nu = make_jacobi_case(
                        n=n,
                        rho_target=rho_target,
                        avg_degree=deg,
                        seed=seed_counter,
                        structured=True,
                        bandwidth=max(1, deg // 2),
                    )
                    seed_counter += 1
                    cases.append(
                        evaluate_case(
                            name=f"jacobi_n{n}_rho{rho_target:.2f}_deg{deg}_q{q}",
                            g=g,
                            rho_bound=rho,
                            q=q,
                        )
                    )

    args.output_md.parent.mkdir(parents=True, exist_ok=True)
    args.output_json.parent.mkdir(parents=True, exist_ok=True)

    args.output_md.write_text(build_markdown(cases, q_values), encoding="utf-8")
    args.output_json.write_text(
        json.dumps({"cases": [asdict(case) for case in cases]}, indent=2),
        encoding="utf-8",
    )

    print(f"Wrote {args.output_md}")
    print(f"Wrote {args.output_json}")


if __name__ == "__main__":
    main()
