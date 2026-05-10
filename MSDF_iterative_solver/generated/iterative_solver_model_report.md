# Iteration-Fused Solver Software Model Report

This report instantiates the mathematical and cycle models for the new iterative-solver mainline.

## Configuration

- profile: `quick`
- q: `24` fractional digits
- eta: `1e-06`
- max iterations: `256`
- row engines R: `1`
- conventional row engines R_conv: `1`
- conventional P_MAC max proxy: `8`

## Gate Summary

- `gate1_certification_matters`: `True`
- `gate2_fused_beats_b1`: `True`
- `gate3_fused_beats_b2`: `False`

## Case Table

| case | family | n | rho | norm | exact stop iter | fused stop iter | avg j* | certified frac | false stop | cycles B1 | cycles fused | speedup vs B1 | cycles B2 | speedup vs B2 |
| --- | --- | ---: | ---: | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| `pr_dense_n8_beta0.85` | `pagerank_dense` | 8 | 0.850 | `l1` | 86 | NA | 24.00 | 0.00 | 0 | 30272 | NA | NA | 7568 | NA |
| `pr_dense_n8_beta0.95` | `pagerank_dense` | 8 | 0.950 | `l1` | 256 | NA | 24.00 | 0.00 | 0 | 90112 | NA | NA | 22528 | NA |
| `pr_dense_n32_beta0.85` | `pagerank_dense` | 32 | 0.850 | `l1` | 86 | NA | 24.00 | 0.00 | 0 | 137600 | NA | NA | 35776 | NA |
| `pr_dense_n32_beta0.95` | `pagerank_dense` | 32 | 0.950 | `l1` | 256 | NA | 24.00 | 0.00 | 0 | 409600 | NA | NA | 106496 | NA |
| `pr_dense_n64_beta0.85` | `pagerank_dense` | 64 | 0.850 | `l1` | 86 | NA | 24.00 | 0.00 | 0 | 291712 | NA | NA | 82560 | NA |
| `pr_dense_n64_beta0.95` | `pagerank_dense` | 64 | 0.950 | `l1` | 256 | NA | 24.00 | 0.00 | 0 | 868352 | NA | NA | 245760 | NA |
| `pr_sparse_n64_deg4` | `pagerank_sparse` | 64 | 0.900 | `l1` | 132 | NA | 24.00 | 0.00 | 0 | 371712 | NA | NA | 101376 | NA |
| `pr_sparse_n64_deg8` | `pagerank_sparse` | 64 | 0.900 | `l1` | 132 | NA | 24.00 | 0.00 | 0 | 397056 | NA | NA | 101376 | NA |
| `pr_sparse_n128_deg4` | `pagerank_sparse` | 128 | 0.900 | `l1` | 132 | NA | 24.00 | 0.00 | 0 | 743424 | NA | NA | 202752 | NA |
| `pr_sparse_n128_deg8` | `pagerank_sparse` | 128 | 0.900 | `l1` | 132 | NA | 24.00 | 0.00 | 0 | 794112 | NA | NA | 202752 | NA |
| `jacobi_dense_n8_rho0.50` | `jacobi_dense` | 8 | 0.493 | `linf` | 15 | 15 | 20.00 | 0.07 | 0 | 4920 | 3808 | 1.292 | 1320 | 0.347 |
| `jacobi_dense_n8_rho0.90` | `jacobi_dense` | 8 | 0.877 | `linf` | 21 | 21 | 23.00 | 0.05 | 0 | 7392 | 5536 | 1.335 | 1848 | 0.334 |
| `jacobi_dense_n32_rho0.50` | `jacobi_dense` | 32 | 0.500 | `linf` | 7 | 7 | 20.00 | 0.14 | 0 | 11200 | 7936 | 1.411 | 2912 | 0.367 |
| `jacobi_dense_n32_rho0.90` | `jacobi_dense` | 32 | 0.895 | `linf` | 11 | 11 | 24.00 | 0.09 | 0 | 17600 | 12672 | 1.389 | 4576 | 0.361 |
| `jacobi_dense_n64_rho0.50` | `jacobi_dense` | 64 | 0.500 | `linf` | 6 | 6 | 20.00 | 0.17 | 0 | 20352 | 13952 | 1.459 | 5760 | 0.413 |
| `jacobi_dense_n64_rho0.90` | `jacobi_dense` | 64 | 0.892 | `linf` | 8 | 8 | 23.00 | 0.12 | 0 | 27136 | 18880 | 1.437 | 7680 | 0.407 |
| `jacobi_sparse_n64_deg4` | `jacobi_sparse` | 64 | 0.798 | `linf` | 20 | 20 | 22.00 | 0.05 | 0 | 56320 | 42112 | 1.337 | 14080 | 0.334 |
| `jacobi_sparse_n64_deg8` | `jacobi_sparse` | 64 | 0.799 | `linf` | 13 | 13 | 22.00 | 0.08 | 0 | 39104 | 28160 | 1.389 | 9984 | 0.355 |
| `jacobi_sparse_n128_deg4` | `jacobi_sparse` | 128 | 0.800 | `linf` | 21 | 21 | 22.00 | 0.05 | 0 | 118272 | 88448 | 1.337 | 29568 | 0.334 |
| `jacobi_sparse_n128_deg8` | `jacobi_sparse` | 128 | 0.798 | `linf` | 13 | 13 | 22.00 | 0.08 | 0 | 78208 | 56320 | 1.389 | 19968 | 0.355 |

## Reading Guide

- `exact stop iter` uses the full-width delta criterion with the same solver-level threshold.
- `fused stop iter` is the first iteration whose online upper bound certifies convergence within `q` digits.
- `avg j*` is the average earliest certified digit among certified iterations. Lower is better.
- `false stop` must remain `0`; otherwise the certification rule is invalid.
- `B2` is still only a cycle proxy, not a routed hardware result.

## First Interpretation

- Gate 1 passes in this profile: at least one workload certifies materially before full `q` digits.
- Gate 2 passes in this profile: iteration-fused beats cascaded online in total cycles for at least one case.
- Gate 3 does not pass yet in this profile: relative value versus conventional FPGA still needs to come from storage/DSP/system arguments or later hardware results.

## Next Step

- If Gate 1 and Gate 2 both pass, the next action is to keep this script as the software golden model backbone and add more systematic sweeps.
- If Gate 3 does not pass, the next document should focus on microarchitecture and storage arguments before RTL, not on claiming raw cycle wins versus conventional FPGA.
