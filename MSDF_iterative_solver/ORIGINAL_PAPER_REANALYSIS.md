# Original Paper Reanalysis

This document keeps the original-paper interpretation needed by the current mainline.

## Original Problem

The original work addresses the delay of cascaded online arithmetic inside high-dimensional inner product:

$$
\text{online multiply}
\rightarrow
\text{online add/reduce}
\rightarrow
\text{bias/output update}
$$

Its contribution is an integrated online multiply-add operator that folds these boundaries into one residual recurrence.

## Original Recurrence

The operator computes a biased inner product with online signed-digit operands:

$$
v[j]=2w[j]+2^{-\delta}\left(\sigma_n(x,y)+b_{j+1+\delta}\right)
$$

$$
z_{j+1}=\mathrm{sel}(\hat v[j])
$$

$$
w[j+1]=v[j]-z_{j+1}
$$

The original serial-serial delay is:

$$
\delta_{\mathrm{SS}}
=
\left\lceil\log_2\frac{2n+1}{3}\right\rceil+3
$$

The key limitation for the current project is that this delay grows with the inner-product term count.

## Current Upgrade

The current repository keeps the online residual/update idea but changes the operand contract. Coefficients and bias are parallel fixed-point words, while the state remains an MSB-first digit stream:

$$
a_{i,s},b_i:\ \text{parallel fixed-point words}
$$

$$
x_s:\ \text{digit stream}
$$

The delay is then bounded by the affine row magnitude:

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

For the PageRank fixture used in this repository, the bound is below one, so `delta=2`.

## Difference From Prior Work

The prior paper contributes a serial-serial integrated online inner-product operator.

This project contributes a parallel-in digit-serial online affine operator for bounded fixed-point iteration. The main claimed improvement is not a new selector rule or a new signed-digit number system; it is the replacement of term-count delay with affine-bound delay.

## Paper Claim Boundary

The current evidence supports:

- a strict mathematical delay derivation for the parallel-in contract;
- reproducible PageRank fixtures;
- P3-SP online RTL and P4-SP conventional DSP-MAC baseline;
- U55C out-of-context route checkpoints.

The current evidence does not support:

- claiming universal latency superiority over DSP-MAC;
- claiming a complete graph accelerator;
- treating CPU comparisons as FPGA hardware baselines.
