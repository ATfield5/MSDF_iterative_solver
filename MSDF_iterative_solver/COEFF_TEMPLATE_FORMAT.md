# Coefficient Template Format

This document records the compact PageRank template format used by the current mainline fixtures.

Each row implements:

$$
y_i=b_i+\sum_{s=0}^{D-1}a_{i,s}x_{\mathrm{src}(i,s)}
$$

The current hardware reserves `PHYSICAL_DEGREE=8` term slots. Workloads with fewer valid terms set unused slots to zero.

## Template Fields

| Field | Meaning |
| --- | --- |
| `src_id` | source row index for the term |
| `coeff_p/coeff_n` | rail-coded signed coefficient word |
| `bias_p/bias_n` | rail-coded signed bias word |
| `degree` | valid sparse terms per row |
| `physical_degree` | physical term slots reserved in hardware |

The current PageRank fixture keeps coefficients non-negative, so `coeff_n=0` and `bias_n=0` in the main path.

## Generated Fixtures

Current generated fixtures are under:

- `generated/rtl_vectors/pagerank32_global_parallel_in_fractional/`
- `generated/rtl_vectors/pagerank32_global_parallel_in_fractional_deg8/`
- `generated/rtl_vectors/pagerank32_global_parallel_in_fractional_deg32/`
- `generated/rtl_vectors/pagerank32_global_prior_fractional/`

These are small, tracked fixtures used for reproducible RTL simulation and paper report generation.
