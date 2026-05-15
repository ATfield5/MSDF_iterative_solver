# P3-SP Feedback Termination Test

This report checks whether the continuous PageRank feedback pipeline can stop
with the original paper's termination predicate:

$$
\|r^{(k+1)}-r^{(k)}\|_\infty \le 2^{-q}
$$

For the current `DATA_WIDTH=32` fixed-point contract, the RTL threshold is one
raw LSB:

$$
\max_i |r_i^{(k+1)}-r_i^{(k)}| \le 1
$$

## Golden Setup

The fixture was regenerated with `128` PageRank iterations:

```text
conda run -n qas python MSDF_iterative_solver/make_pagerank_parallel_in_fractional_vectors.py --num-iters 128 --force-delay 2 --data-width 32 --bit-width 30 --acc-width 64
```

Python golden first satisfies the strict `L∞ <= 1` condition at zero-based
iteration index `97`, i.e. after the `98`th PageRank update:

```text
iter_index=97
iteration_count=98
global_linf_delta=1
```

With `K=4`, this maps to wavefront stage:

$$
97 \bmod 4 = 1
$$

## RTL Result

The strict-stop RTL test passed:

```text
PASS tb_iter_parallel_in_online_mma8_global_feedback_top
COUNTERS parallel_in_feedback K=4 target_supersteps=32 linf_eta=1 total=1007 final_supersteps=24 capture=798 stage_counts=0000031e000003200000032000000320 linf_counts=00000018000000190000001900000019 feedback_stall=0 cert_late=99 converged=1 converged_stage=1 hist=00000000000000000000000100000000 kill=29 overlap=111
```

## Interpretation

- `converged=1`: the RTL observed the strict `L∞ <= 1` condition.
- `converged_stage=1`: matches the golden stage because `97 mod 4 = 1`.
- `kill=29`: after convergence, the controller stopped accepting feedback and
  discarded speculative in-flight digits.
- `feedback_stall=0`: the feedback FIFO did not throttle the loop.
- `overlap=111`: downstream stages consumed upstream high-order digits before
  the previous stages fully completed.

This is a functional termination test, not a routed timing result.
