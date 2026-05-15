# Parallel-In Digit-Serial Online Affine Operator: Paper Math

This document is the paper-facing mathematical contract for the current
operator line.  The title-level object is the operator, not PageRank:

$$
\textbf{Parallel-In Digit-Serial Online Affine Operator}
$$

PageRank is used only as a representative affine iterative workload.

## Operator Definition

For one output row, the affine update is:

$$
y_i = \sum_{s=0}^{n-1} a_{i,s}x_s + b_i
$$

The proposed operand contract is asymmetric:

$$
a_{i,s}, b_i:\ \text{parallel fixed-point words}
$$

$$
x_s:\ \text{MSB-first signed digit stream}
$$

The output is also an MSB-first signed digit stream:

$$
y_i = \sum_{j=1}^{q} z_{i,j}2^{-j},\quad z_{i,j}\in\{-1,0,1\}
$$

The design therefore targets iterative solvers where the next iteration can
consume the most significant output digits before the whole word is rebuilt.

## Original Serial-Serial Online Delay

The prior integrated online inner-product operator treats both multiplicand
streams as digit-serial operands.  For an inner product with bias, the driver
bound scales with the number of terms:

$$
\delta_{\mathrm{SS}}
=
\left\lceil\log_2\frac{2n+1}{3}\right\rceil+3
$$

For dense `n=32`, this gives:

$$
\delta_{\mathrm{SS}}=
\left\lceil\log_2\frac{65}{3}\right\rceil+3=8
$$

This is the source of the prior operator's larger startup delay at high
dimension.

## Parallel-In Delay Bound

For the parallel-in affine operator, the coefficient words are available in
parallel and only the state operands arrive as signed digit streams.  Define:

$$
A_i = \sum_s |a_{i,s}|,\quad B_i = |b_i|
$$

Then the driver magnitude is controlled by the row affine bound rather than by
the raw number of terms.  The global safe online delay is:

$$
\delta_{\mathrm{PI}}
=
\max\left(
2,\left\lceil\log_2\frac{\max_i(A_i+B_i)}{3}\right\rceil+3
\right)
$$

The `max(2, ...)` term is the implementation floor used by the radix-2 signed
digit selector and the registered residual path.  It does not reduce output
precision; it fixes the number of leading input digits consumed before the
first output digit is emitted.

For PageRank-style affine propagation:

$$
x^{(k+1)} = \beta Mx^{(k)} + (1-\beta)n^{-1}e
$$

with row-stochastic transition rows:

$$
A_i+B_i \le \beta + \frac{1-\beta}{n} < 1
$$

therefore:

$$
\delta_{\mathrm{PI}}=2
$$

This is the main mathematical improvement over the original serial-serial
operator: the delay no longer grows as a direct function of dense input
dimension when the affine row bound remains below one.

## Recurrence

Let `q` be the output digit count and let the fixed-point scale be:

$$
S=2^{q-1}
$$

At online step `j`, the contribution digit is:

$$
c_i[j]=
\sum_s a_{i,s}x_s[j+\delta_{\mathrm{PI}}]
+ b_i[j+\delta_{\mathrm{PI}}]
$$

The residual recurrence is:

$$
v_i[j]=2w_i[j]+2^{-\delta_{\mathrm{PI}}}c_i[j]
$$

$$
z_{i,j+1}=\mathrm{sel}(\hat v_i[j])
$$

$$
w_i[j+1]=v_i[j]-z_{i,j+1}
$$

The selector uses the same radix-2 signed digit threshold as the prior work:

$$
z=1\ \text{if}\ \hat v\ge\frac12
$$

$$
z=0\ \text{if}\ -\frac12\le\hat v<\frac12
$$

$$
z=-1\ \text{if}\ \hat v<-\frac12
$$

The current RTL default runs all `DATA_WIDTH` output digits.  It is not an
early-stop or reduced-precision approximation.

## Width Contract

For the current 32-bit PageRank fixture:

$$
q=32,\quad S=2^{31}
$$

The generated dense32 fixture reports:

$$
\max_i(A_i+B_i)=0.85468749
$$

and the derived implementation parameters are:

| field | value |
| --- | ---: |
| external state/output width | `DATA_WIDTH=32` |
| coefficient magnitude width | `BIT_WIDTH=30` |
| bias width | `BIAS_WIDTH=32` |
| online delay | `2` |
| minimum residual accumulator width | `33` |

The residual accumulator width is an internal safety bound.  It does not change
the external 32-digit signed-digit output contract.

## Scope And Limitations

This operator is appropriate when the affine row bound is known or can be
compiled:

$$
\max_i(A_i+B_i)
$$

It is strongest for contraction/probability-style iterations such as PageRank,
bounded power iteration, and fixed-point graph propagation.  It is not a
drop-in replacement for arbitrary dynamic-range matrix-vector multiplication
unless dynamic fixed-point scaling or per-block normalization is added.

All paper result tables must distinguish:

| scope | meaning |
| --- | --- |
| operator-level | only the affine datapath / online operator |
| wavefront-level | cascaded or feedback digit-stream stages |
| runtime-level | state memory, loader, certification, and controller |
| CPU-level | software benchmark only; no LUT/DSP comparison |
