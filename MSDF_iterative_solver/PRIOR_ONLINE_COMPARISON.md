# Prior Online Operator Comparison Contract

This document fixes how the current work relates to the original integrated online multiply-add paper and RTL.

The current contribution is not a reimplementation of the prior inner-product operator. The contribution is:

$$
\textbf{serial-serial integrated online MAC}
\rightarrow
\textbf{parallel-in digit-serial online affine operator}
$$

## Prior Work Scope

The original paper targets an operator-level problem: online multipliers, online adders, and bias addition introduce extra delay when connected as separate blocks. Its key structure is an integrated online inner product:

$$
v[j]=2w[j]+2^{-\delta}\left(\sigma_n(x,y)+b_{j+1+\delta}\right)
$$

$$
z_{j+1}=\mathrm{sel}(\hat v[j])
$$

$$
w[j+1]=v[j]-z_{j+1}
$$

The prior delay for a serial-serial inner product with `n` terms is:

$$
\delta_{\mathrm{SS}}
=
\left\lceil\log_2\frac{2n+1}{3}\right\rceil+3
$$

For dense `n=32`, this gives `delta=8`.

## Original RTL Mapping

The prior RTL is kept under [`../MSDF_operator_srcs/`](../MSDF_operator_srcs/) as a reference implementation.

| Prior RTL | Role in this repository |
| --- | --- |
| `MSDF_MUL_ADD_8.v` | 8-lane serial-serial integrated online multiply-add reference. |
| `MSDF_MUL.v` | online multiply primitive reference. |
| `parallel_online_adder*.v` | rail-coded online reduction reference. |
| `output_and_update*.v` | residual update and digit selection reference. |
| `vector_append.v` / `selector.v` | source digit window and digit selector reference. |

This repository does not modify the original RTL. New RTL is placed under `MSDF_iterative_solver/prior_rtl/`.

## Current Baseline Naming

| ID | Meaning | Use |
| --- | --- | --- |
| P0 | Original paper reported PageRank result | Background only; do not mix directly with U55C routed tables. |
| P1 | Original serial-serial online operator reference | Prior RTL / prior-style scalability baseline. |
| P3-SP | Parallel-in digit-serial online affine operator | This work. |
| P4-SP | Conventional fixed-point DSP-MAC affine baseline | Same fixture hardware baseline. |
| CPU | NumPy/OpenBLAS PageRank | Software reference only. |

Older same-shell solver experiments are no longer part of the tracked mainline.

## Parallel-In Difference

The current operator changes the operand contract:

$$
a_{i,s}, b_i:\ \text{parallel fixed-point words}
$$

$$
x_s:\ \text{MSB-first signed digit stream}
$$

The delay is bounded by the row affine magnitude:

$$
A_i=\sum_s |a_{i,s}|,\qquad B_i=|b_i|
$$

$$
\delta_{\mathrm{PI}}
=
\max\left(
2,
\left\lceil\log_2\frac{\max_i(A_i+B_i)}{3}\right\rceil+3
\right)
$$

For the current PageRank fixture, `max_i(A_i+B_i)<1`, so the implementation uses `delta=2`.

## Current Evidence

Current reports are maintained through:

- [`generated/parallel_in_fractional_eval.md`](./generated/parallel_in_fractional_eval.md)
- [`generated/parallel_in_bound_sweep.md`](./generated/parallel_in_bound_sweep.md)
- [`generated/parallel_in_cycle_ablation.md`](./generated/parallel_in_cycle_ablation.md)
- [`generated/parallel_in_routed_main_results.md`](./generated/parallel_in_routed_main_results.md)
- [`generated/paper_baseline_fairness_table.md`](./generated/paper_baseline_fairness_table.md)

The current evidence supports a bounded-delay, zero-DSP online affine datapath. It does not yet support a blanket latency-win claim over the conventional DSP-MAC baseline.

## Claim Boundary

Valid claims:

- The prior operator is serial-serial; this work uses a parallel-in affine contract.
- The online delay changes from a term-count bound to an affine-row bound.
- PageRank is a representative bounded affine workload where the bound gives `delta=2`.
- P3-SP can be implemented without DSPs.

Invalid claims:

- This work invented integrated online inner product.
- P3-SP already universally beats DSP-MAC latency.
- CPU speedup alone proves superiority over FPGA hardware baselines.
- The current fixture is a complete arbitrary-Web-graph accelerator.
