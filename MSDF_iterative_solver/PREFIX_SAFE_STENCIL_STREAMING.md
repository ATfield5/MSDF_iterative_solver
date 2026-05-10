# Prefix-Safe Stencil Streaming

This note defines the next solver-native direction: using MSB-first online
digits from iteration `k+1` before the full state word is complete, while still
keeping an exact final computation.

The key point is not that later low bits modify earlier high bits.  In a valid
online digit stream, emitted high digits are final.  Later digits only reduce the
unknown tail.

## Problem

For structured Jacobi or stencil solvers,

$$
x_i^{(k+1)} = b_i + \sum_{t=0}^{d-1} a_{i,t}x_{s(i,t)}^{(k)}
$$

the current full-digit runtime still behaves as:

$$
x^{(k)}
\rightarrow
\text{full digit stream for }x^{(k+1)}
\rightarrow
\text{commit}
\rightarrow
x^{(k+2)}
$$

This makes the `DATA_WIDTH` digit stream a per-iteration latency wall.  For the
current NC8 checkpoint, `DATA_WIDTH=11`, so the solver-native path spends 11
issue cycles every iteration before the next iteration can consume the result.

The proposed mechanism is:

$$
x^{(k)}
\rightarrow
\text{prefix of }x^{(k+1)}
\rightarrow
\text{safe prefix of }x^{(k+2)}
$$

The next iteration may start only when the unknown tail is provably unable to
change the next online digit decision.

## Prefix And Tail Bound

After `p+1` MSB-first signed digits of a source value have been emitted:

$$
x_j = \hat{x}_{j,p} + \epsilon_{j,p}
$$

where:

$$
|\epsilon_{j,p}| \le \tau_p
$$

For radix-2 signed digits with unit digit magnitude and integer-scaled storage:

$$
\tau_p = 2^{D-1-p}-1
$$

where `D` is `DATA_WIDTH` and `p` is the zero-based emitted digit index.  The
tail bound decreases monotonically:

$$
\tau_0 > \tau_1 > \cdots > \tau_{D-1}=0
$$

## Stencil Row Uncertainty

For a degree-`d` stencil row, the uncertainty injected into the next row update
is bounded by:

$$
E_i(p) =
\sum_{t=0}^{d-1} |a_{i,t}| \tau_{s(i,t),p}
$$

For aligned stencil streaming, all sources have the same prefix depth, so:

$$
E_i(p) =
\tau_p \sum_{t=0}^{d-1}|a_{i,t}|
$$

If the next online selector has margin:

$$
M_i(p)
$$

from its nearest decision boundary, the next digit can be emitted safely when:

$$
E_i(p) < M_i(p)
$$

This is a strict safety test.  If it fails, the hardware stalls that next
iteration row until more source prefix digits arrive and `E_i(p)` shrinks.

## Why This Is Different From Early Stop

Early stop reduces precision by not computing low-order digits.  Prefix-safe
streaming does not do that.  The solver still eventually emits all `DATA_WIDTH`
digits.  The optimization is overlap:

$$
\text{consume high prefix now}
\quad
\text{and consume low tail later}
$$

The final state remains full-width.  The only speculative part is the scheduling
of the next iteration, and the schedule is guarded by a conservative inequality.

## Hardware Contract

The first RTL checkpoint is `iter_prefix_safe_stencil_gate`:

```text
digit_idx
coeff_abs_terms
selection_margin
-> source_tail_bound
-> weighted_tail_bound
-> prefix_safe
```

It does not yet drive the runtime top.  Its purpose is to create a precise
hardware boundary for the next scheduler:

```text
state digit producer
-> prefix-safe stencil gate
-> next-iteration row issue/stall
```

## Expected Benefit

For single-RHS Jacobi, the current interval is approximately:

$$
T_{\mathrm{mode3}}
\approx
D + d_{\mathrm{drain}} + d_{\mathrm{cert}}
$$

Prefix-safe streaming targets the issue boundary:

$$
T_{\mathrm{effective}}
\approx
\max(D_{\mathrm{prefix-safe}}, d_{\mathrm{pipeline}})
$$

where `D_prefix-safe` is the first digit index at which the uncertainty bound is
smaller than the selector margin.  The best case is not zero latency; the best
case is that later iteration work overlaps with the remaining low-digit stream.

The mechanism is most promising for:

- radius-1 or low-degree stencil;
- strongly diagonally dominant Jacobi;
- block Jacobi with local halo FIFO;
- fixed-iteration solvers where convergence certification is not a global
  barrier every iteration.

It is weak for:

- high-degree irregular sparse graphs;
- PageRank-like global fan-in;
- matrices with spectral radius close to one;
- any workload that requires global certification before every next iteration
  launch.

## Next RTL Step

After this gate is validated, the next module should be a two-stage local
pipeline:

```text
iteration k+1 source prefix FIFO
-> prefix-safe gate
-> iteration k+2 row-engine issue mask
```

The first target should be a small radius-1 stencil with two in-flight
iterations, not the full runtime shell.
