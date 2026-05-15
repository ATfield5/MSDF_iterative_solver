# Parallel-In Fractional P3-SP vs P4-SP Checkpoint

This report is the standalone checkpoint for the 32-bit P3-SP parallel-in PageRank wavefront and the P4-SP one-stage conventional baseline.
P3-SP keeps the K-stage online wavefront. P4-SP follows the conventional baseline policy requested here: 32 rows run in parallel, each row has 8 full-word MAC slots, and K stages are not physically expanded.

## Delay Bound

- Formula: `max(2, ceil(log2(max_i(A_i+B_i)/3))+3)`
- max_i(A_i+B_i): `0.85468750`
- derived delay: `2`
- implemented global delay: `2`
- min/max row bound: `0.85468750` / `0.85468750`
- external DATA_WIDTH: `32`
- external coefficient BIT_WIDTH: `30`
- packed bias width: `32`
- P3-SP internal accumulator width: `33`
- P4-SP product width: `66`
- P4-SP accumulator width: `40`
- minimum coefficient width: `29`
- minimum bias magnitude width: `24`
- minimum residual accumulator width: `33`

## Functional / Cycle Checkpoint

| entry | pass | physical shape | observed cycles | output form | fixture |
| --- | ---: | --- | ---: | --- | --- |
| P3-SP parallel-in online wavefront | yes | 4 K-stages x 32 rows x 8 coeff-select slots | 50 | 32 streamed digits | pagerank32_global_parallel_in_fractional_deg4 |
| P3-SP feedback loop pipeline | yes | 4 reusable K-stages x 32 rows x 8 coeff-select slots, feedback FIFO, Linf stop check | 94 | 2 supersteps / 64 final-stage digits | pagerank32_global_parallel_in_fractional_deg4 |
| P3-SP feedback forced-stop smoke | yes | same feedback RTL, relaxed Linf eta to verify stop/kill control | 47 | converged=1, killed_digits=28 | pagerank32_global_parallel_in_fractional_deg4 |
| P4-SP conventional 32-row parallel DSP-MAC | yes | 4 feedback iterations on 1 stage x 32 row lanes x 8 parallel 32x32 MAC slots/row | 17 | 32-bit full-word p/n rails | pagerank32_global_parallel_in_fractional_deg4 |
| P4-SP conventional degree8 32-row parallel DSP-MAC | yes | 4 feedback iterations on 1 stage x 32 row lanes x 8 parallel 32x32 MAC slots/row | 17 | 32-bit full-word p/n rails | pagerank32_global_parallel_in_fractional_deg8 |

## Software P3/P4 Model Drift

| metric | value |
| --- | ---: |
| max absolute raw-state drift | 31334310 |
| sum absolute raw-state drift | 1002697920 |
| P4 product shift | 32 |

This drift is computed from the Python P3/P4 K=4 models in the shared fixture.
The parallel-row P4-SP RTL test itself checks four consecutive conventional feedback iterations over all 32 rows against `conv_gold_state_*`.

## Numeric Contract Note

The P3-SP external state/output contract is now a 32-digit MSB-first signed-digit stream.
The 33-bit internal accumulator is derived from the instantaneous coefficient-digit and bias-digit bound; it is not the output precision.
P4-SP uses 32 parallel row lanes.  Each row lane has eight parallel 32-bit x 32-bit signed MAC slots, 66-bit product guards, and a 40-bit accumulator; each product is rounded by `2^32` before row summation.

The P3-SP standalone total starts after reset release and includes the one 32-digit input launch plus wavefront drain.
The P4-SP total is four feedback iterations over all 32 rows using the same one-stage datapath repeatedly; it is not a K-stage physical wavefront.
Runtime configuration/state preload overhead is intentionally outside this checkpoint.

## Feedback Loop / Termination

The feedback loop uses the same convergence predicate as the original PageRank algorithm in the paper:

$$
\max_i |r_i^{(k+1)}-r_i^{(k)}| \le 2^{-q}
$$

For this `32`-digit fixed-point fixture, the hardware threshold is `1` raw LSB.
The default test drives two K-stage supersteps and reports `converged=0`; it does not force early stop unless the Linf predicate is actually true.
A separate forced-stop smoke sets a relaxed threshold and confirms the stop path with `converged=1` and `killed_digits=28`.

## Icarus Output

```text
PASS tb_iter_parallel_in_online_mma8_global_wavefront_top
COUNTERS parallel_in_wavefront K=4 delay=2 fast2=0 total=50 capture=32 stage_counts=00000020000000200000002000000020 overlap=111
MSDF_iterative_solver/tb/tb_iter_parallel_in_online_mma8_global_wavefront_top.v:257: $finish called at 536000 (1ps)
```

## Icarus Output: P3-SP Feedback

```text
PASS tb_iter_parallel_in_online_mma8_global_feedback_top
COUNTERS parallel_in_feedback K=4 target_supersteps=2 linf_eta=1 fast2=0 total=94 final_supersteps=2 capture=64 first_valid0=5 first_valid1=9 first_gap01=4 stage_counts=00000040000000410000004500000049 linf_counts=00000002000000020000000200000002 feedback_stall=0 cert_late=34 converged=0 converged_stage=0 hist=00000000000000000000000000000000 kill=0 overlap=111
MSDF_iterative_solver/tb/tb_iter_parallel_in_online_mma8_global_feedback_top.v:474: $finish called at 976000 (1ps)
```

## Icarus Output: P3-SP Feedback Forced Stop

```text
PASS tb_iter_parallel_in_online_mma8_global_feedback_top
COUNTERS parallel_in_feedback K=4 target_supersteps=2 linf_eta=2147483647 fast2=0 total=47 final_supersteps=0 capture=30 first_valid0=5 first_valid1=9 first_gap01=4 stage_counts=0000001e000000200000002000000022 linf_counts=00000000000000000000000100000001 feedback_stall=0 cert_late=10 converged=1 converged_stage=0 hist=00000000000000000000000000000001 kill=28 overlap=111
MSDF_iterative_solver/tb/tb_iter_parallel_in_online_mma8_global_feedback_top.v:474: $finish called at 506000 (1ps)
```

## Icarus Output: P4-SP

```text
PASS tb_iter_parallel_in_conv_mma8_parallel_rows_top
COUNTERS parallel_in_conv_parallel_rows rows=32 iterations=4 product_shift=32 total_compute=17 row_lanes=32 macs_per_row=8
MSDF_iterative_solver/tb/tb_iter_parallel_in_conv_mma8_parallel_rows_top.v:257: $finish called at 206000 (1ps)
```

## Icarus Output: P4-SP Degree8

```text
PASS tb_iter_parallel_in_conv_mma8_parallel_rows_top
COUNTERS parallel_in_conv_parallel_rows rows=32 iterations=4 product_shift=32 total_compute=17 row_lanes=32 macs_per_row=8
MSDF_iterative_solver/tb/tb_iter_parallel_in_conv_mma8_parallel_rows_top.v:257: $finish called at 206000 (1ps)
```
