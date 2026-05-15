# Bounded-Estimate Selector for P3-SP Fast2

## Goal

The route-clean P3-SP feedback core uses a 4-cycle adjacent stage interval.  The experimental fast2 core reduces the functional interval to 3 cycles, but the original exact selector does this in one cycle:

$$
\text{source digit}
\rightarrow
\text{contribution tree}
\rightarrow
v_j=2w_j+u_j
\rightarrow
z_{j+1}
$$

That path was not routable at U55C 5 ns.  The bounded-estimate selector shortens the `z` path without changing the external 32-bit digit-stream contract.

## Recurrence

The exact fast2 recurrence remains:

$$
v_j = 2w_j + u_j
$$

$$
z_{j+1}=\mathrm{sel}(v_j)
$$

$$
w_{j+1}=v_j-z_{j+1}
$$

where `z` is a radix-2 signed digit:

$$
z_{j+1}\in\{-1,0,1\}
$$

The exact selector uses:

$$
z=1 \quad \text{if } v_j\ge \frac{1}{2}
$$

$$
z=-1 \quad \text{if } v_j\le -\frac{1}{2}
$$

$$
z=0 \quad \text{otherwise}
$$

## Estimate Selector

Instead of selecting from the full binary `v_j`, the fast2 estimate path forms:

$$
\hat v_j =
\widehat{2w_j} + \hat u_j
$$

Only the sign, integer bit, and a small number of fractional guard bits are kept.  In the current routed experiment:

$$
\text{EST\_FRAC\_BITS}=4,
\qquad
\text{EST\_GUARD\_BITS}=2
$$

The selector then uses the same threshold rule on the scaled estimate:

$$
z=1 \quad \text{if } \hat v_j\ge \frac{1}{2}
$$

$$
z=-1 \quad \text{if } \hat v_j\le -\frac{1}{2}
$$

$$
z=0 \quad \text{otherwise}
$$

This is not a lower-precision output mode.  The full residual update path still updates the 33-bit internal residual:

$$
w_{j+1}=2w_j+u_j-z_{j+1}
$$

and the emitted state is still `DATA_WIDTH=32` MSB-first signed digits.

## Split Estimate Contribution

The first estimate implementation still sliced `\hat u_j` from the full-width contribution tree.  That reduced the comparator width but did not fully remove the full carry-propagate contribution path from the selector.

The split version adds an independent high-bit contribution tree:

$$
\hat u_j =
\mathrm{high}\left(
2^{-\delta}
\left(
\sum_s a_s x_{s,j+\delta+1} + b_{j+\delta+1}
\right)
\right)
$$

The exact contribution tree remains for residual update, but `z` no longer waits for the full contribution carry chain.

## Current Routed Results

All rows below use `K=4`, `DATA_WIDTH=32`, `CORE_ACC_WIDTH=33`, U55C 5 ns OOC route.

| checkpoint | functional cycles | WNS | note |
| --- | ---: | ---: | --- |
| exact fast2 selector | 88 | -2.303 ns | baseline synchronous fast2 |
| exact threshold decoder | 88 | -1.866 ns | removes full signed comparator |
| feedback preselect + valid/data decoupling | 88 | -1.746 ns | removes control from digit rail |
| bounded estimate selector, exact contribution source | 88 | -0.905 ns | selector uses truncated estimate |
| split bounded estimate selector | 88 | -0.594 ns | best generic signed-coefficient I=3 checkpoint |
| split estimate + PageRank nonnegative coefficient path | 88 | -0.272 ns | removes unnecessary `coeff_p-coeff_n` subtract for nonnegative PageRank matrix |
| split estimate + PageRank nonnegative coeff/bias path | 88 | -0.121 ns | also removes the unused negative teleport/bias branch |

The best path is no longer the selector path.  It is the full binary residual update:

$$
\text{stage output digit}
\rightarrow
\text{source selection / contribution}
\rightarrow
2w+u-z
\rightarrow
\text{residual register}
$$

## Conclusion

Bounded-estimate selection is effective: it improves fast2 WNS from `-2.303 ns` to `-0.594 ns` without changing functional cycles or PageRank golden output.  The PageRank-specific nonnegative coefficient and bias path then improves the best routed result to `WNS=-0.121 ns` and reduces LUT from the previous generic `112990` checkpoint to `92002`, because PageRank transition coefficients and teleport/bias terms are nonnegative.

It is not sufficient by itself.  The next required microarchitecture is a redundant residual datapath:

$$
w_j = S_j + C_j
$$

$$
(S_{j+1},C_{j+1})=
\mathrm{CSA}(2S_j,2C_j,u_j-z_{j+1})
$$

That would remove the remaining full binary carry-propagate residual update from the fast2 cycle.

## Redundant Residual Checkpoint

The first carry-save experiment exposed an important correctness constraint:
the carry-save rails cannot be used directly as signed estimates.  If

$$
w_j = S_j + C_j
$$

then `S_j` and `C_j` are arbitrary two's-complement carry-save words.  Their
individual sign bits are not the sign of the represented residual.  Therefore
this selector is invalid:

$$
\hat v_j =
\mathrm{high}(2S_j)+\mathrm{high}(2C_j)+\hat u_j
$$

because sign-extending the two rails independently can select the wrong digit
even when `S_j+C_j` is numerically correct.

The corrected structure keeps two residual states:

$$
(S_{j+1},C_{j+1})=
\mathrm{CSA}(2S_j,2C_j,u_j-z_{j+1})
$$

for the full residual feedback, and a small canonical estimate residual:

$$
\hat w_{j+1}=2\hat w_j+\hat u_j-\hat z_{j+1}
$$

for selection.  The selector uses only the canonical estimate:

$$
\hat v_j = 2\hat w_j+\hat u_j
$$

This keeps the full residual feedback carry-save while preserving a valid
signed estimate for `z`.

For exact PageRank32 agreement with the current binary fast2 checkpoint, the
normalized estimate needs nearly full guard precision.  The observed minimum
passing setting is:

$$
\text{EST\_FRAC\_BITS}=4,\qquad \text{EST\_GUARD\_BITS}=26
$$

`EST_GUARD_BITS=25` still has a 1-LSB mismatch in the multi-stage feedback
test.  This means the carry-save residual path is mathematically valid, but its
practical timing value depends on whether removing the full residual CPA is
worth the added canonical-estimate recurrence.

The U55C 5 ns route probe was negative.  With
`EST_FRAC_BITS=4 / EST_GUARD_BITS=26 / split_estimate=0 /
redundant_residual=1`, the design routed but post-route timing stayed near
`WNS=-2.78 ns`.  Vivado repeatedly reported the critical net around
`r_w_est_norm[32]`, i.e. the canonical estimate residual feedback.  Therefore
the exact redundant-residual version is not a useful I=3 optimization in the
current architecture: it removes the full residual CPA, but replaces it with a
nearly full-width estimate recurrence that is worse than the PageRank
nonnegative-coeff/bias checkpoint (`WNS=-0.121 ns`).

## Negative Routing Ablations

Two follow-up route probes were rejected:

- Source one-hot predecode moved dynamic source selection into one-hot AND/OR logic, but increased routing congestion and did not improve timing.
- Stage-local coefficient registers looked promising after placement, but post-route timing degraded to roughly `WNS=-0.37 ns`.  The added local registers reduced top-level coefficient distance but increased stage-local routing density and high-fanout control, so this is not kept in the main RTL path.
- Forcing duplicated stage-output group registers with `equivalent_register_removal=no` also hurt timing (`WNS=-0.166 ns`) and increased FF count.  Vivado's automatic replication is currently better than preserving all manual group copies.
