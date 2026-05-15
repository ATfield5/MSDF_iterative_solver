# PageRank Application Lock

PageRank is the only headline workload for the current repository.

The paper title-level object is still the operator:

$$
\textbf{Parallel-In Digit-Serial Online Affine Operator}
$$

PageRank is used because it is a bounded affine iteration:

$$
r^{(k+1)} = \beta M r^{(k)} + (1-\beta)\frac{1}{n}e
$$

Equivalently:

$$
x^{(k+1)} = Gx^{(k)} + c
$$

## Why PageRank

PageRank matches the operator contract:

- coefficients are known parallel fixed-point words;
- rank values are bounded and non-negative;
- the row bound satisfies `max_i(A_i+B_i)<1` in the current fixture;
- convergence can be checked with a standard residual norm;
- it has direct continuity with the original online inner-product paper.

## What Is Not Claimed

This repository does not claim:

- arbitrary-degree CSR graph acceleration;
- HBM-backed Web-scale graph streaming;
- a general sparse-matrix solver;
- superiority over every DSP-MAC implementation.

The current fixture is a controlled PageRank workload for evaluating the affine operator and its hardware tradeoffs.
