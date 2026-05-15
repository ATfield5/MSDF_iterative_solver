# Workloads and Baselines

This document fixes the current paper scope for the **Parallel-In Digit-Serial Online Affine Operator** line.

## Workload

The only headline workload is PageRank-style bounded affine iteration:

$$
r^{(k+1)} = \beta M r^{(k)} + (1-\beta)\frac{1}{n}e
$$

Equivalently:

$$
x^{(k+1)} = Gx^{(k)} + c
$$

PageRank is used because the state and coefficients are bounded, non-negative, and directly map to the parallel-in delay proof:

$$
A_i=\sum_s |a_{i,s}|,\qquad B_i=|b_i|
$$

The current fixture is bounded-degree PageRank with fixed physical term slots. Arbitrary CSR graph acceleration, HBM graph streaming, and general sparse-matrix support are outside the current claim.

## Baselines

The paper should keep these baselines separate:

| ID | Name | Role |
| --- | --- | --- |
| P0 | Original reported result | Prior-work reference only; do not mix directly with U55C tables. |
| P1 | Original serial-serial online operator reference | Shows what the prior integrated online operator does under local rerun/wrapper conditions. |
| P3-SP | Parallel-in digit-serial online affine operator | This work. Coefficients enter as parallel fixed-point words; state enters as digit stream. |
| P4-SP | Conventional fixed-point DSP-MAC | Hardware baseline using the same PageRank fixture. |
| CPU | NumPy/OpenBLAS PageRank | Software reference only; report separately from FPGA resource tables. |

## Fairness Rules

Do not compare rows unless the table states whether each row is:

- measured RTL simulation,
- synth-only,
- routed,
- modeled, or
- CPU measured.

Do not mix single-stage datapath latency with K-stage feedback-loop latency as if they were the same hardware shape. Do not compare FPGA LUT/DSP against CPU timing in one ranked table.

## Current Claim Boundary

The current claim is not that the online operator universally beats DSP-MAC latency. The current defensible claim is narrower:

$$
\text{serial-serial integrated online MAC}
\rightarrow
\text{parallel-in digit-serial affine MAC}
$$

with a provable online-delay reduction under bounded affine coefficients and a zero-DSP datapath option. PageRank is the validation workload for that claim.
