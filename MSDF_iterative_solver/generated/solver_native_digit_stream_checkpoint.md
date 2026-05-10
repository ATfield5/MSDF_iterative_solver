# Solver-Native Digit-Stream Checkpoint

This checkpoint starts the new mainline:

$$
\text{state replay}
\rightarrow
\text{solver-native row digit engine}
\rightarrow
\text{digit state commit}
\rightarrow
\text{digit delta/certification}
$$

It is not a low-precision or early-stop checkpoint.  All tests assume the full `DATA_WIDTH` digit stream is issued.

## New RTL Blocks

| Module | Role |
| --- | --- |
| `rtl/iter_const_coeff_digit_contrib_rail.v` | Multiplies a magnitude p/n coefficient vector by one signed source digit using p/n rail swap for negative digits. |
| `rtl/iter_streamed_bias_source.v` | Converts a full bias rail word into an MSB-first digit stream aligned to the state word. |
| `rtl/iter_online_affine_no_bias_core.v` | Produces a fixed-coefficient, no-bias 4-term affine contribution vector. |
| `rtl/iter_digit_stream_delta_bound.v` | Tracks digit-stream delta prefix and conservative tail bound. |
| `rtl/iter_solver_native_row_digit_engine.v` | Connects no-bias contribution, streamed bias and residual/output-update into a row-level digit-output engine. |

## Current Scope

The new row engine is a boundary checkpoint.  It validates that:

- bias is no longer injected as a full word every cycle;
- row output can be exposed as a digit stream;
- inline delta/certification can consume old/new digits without waiting for full-word reconstruction.

The row engine now includes explicit `affine_guard_shift = 3` and `sample_offset = 3`.  This matches the paper's bias-term estimate width `t = 3`: contribution vectors are shifted into the residual datapath, while the selector samples the corresponding lowered window instead of moving the threshold upward with the wider guard path.

The fixed-coefficient contribution path also uses magnitude-rail sign semantics.  A negative source digit swaps coefficient p/n rails; it does not bitwise-complement them.  This is intentionally separated from the original operator selector, whose bitwise-complement convention is tied to its own digit-window representation.

## Directed Tests

| Testbench | Status | Coverage |
| --- | --- | --- |
| `tb_iter_streamed_bias_source` | PASS | MSB-first bias alignment and zero-padding when `stream_width > bias_width`. |
| `tb_iter_digit_stream_delta_bound` | PASS | Prefix delta accumulation and final exact delta magnitude for `new=5`, `old=2`. |
| `tb_iter_solver_native_row_digit_engine` | PASS | Zero-row full `DATA_WIDTH` stream emits exactly `DATA_WIDTH` zero output digits. |
| `tb_iter_solver_native_row_digit_characterization` | PASS | Non-zero row-level equivalence against the full-digit bridge for positive and mixed-sign rows. |
| `tb_iter_solver_native_state_commit_replay` | PASS | Writes solver-native signed-digit trace into digit-stream state bank, commits, replays and reconstructs the full bridge value. |
| `tb_iter_solver_native_multirow_state_commit_replay` | PASS | Two solver-native row engines commit fixed-width signed-digit states to one state bank and replay row0/row1 values. |
| `tb_iter_solver_native_state_delta_bound` | PASS | Replayed solver-native state digits feed inline delta bound and match `full_bridge_sum - old_state`. |
| `tb_iter_solver_native_replayed_state_identity_update` | PASS | Replayed signed-digit states feed the next solver-native row update and preserve row values through an identity update. |
| `tb_iter_solver_native_two_iter_affine_cluster` | PASS | Replayed signed-digit states feed a second non-identity affine iteration and match the full-digit bridge reference. |
| `tb_iter_solver_native_cluster_digit_stream_top` | PASS | The reusable cluster shell runs the same two-iteration affine checkpoint through one physical RTL boundary. |
| `tb_iter_solver_native_cluster_delta_cert_top` | PASS | The cluster shell commit digit stream feeds inline delta and `block_H` certification without full-word reconstruction. |
| `tb_iter_dense_runtime_solver_native_mode3_smoke` | PASS | Runtime loader/template/cert/state interfaces drive `ROW_DATAPATH_MODE=3` for two committed iterations. |

## Commands Run

```text
iverilog -g2012 -o /tmp/tb_iter_streamed_bias_source.vvp ...
vvp /tmp/tb_iter_streamed_bias_source.vvp

iverilog -g2012 -o /tmp/tb_iter_digit_stream_delta_bound.vvp ...
vvp /tmp/tb_iter_digit_stream_delta_bound.vvp

iverilog -g2012 -o /tmp/tb_iter_solver_native_row_digit_engine.vvp ...
vvp /tmp/tb_iter_solver_native_row_digit_engine.vvp

iverilog -g2012 -o /tmp/tb_iter_solver_native_row_digit_characterization.vvp ...
vvp /tmp/tb_iter_solver_native_row_digit_characterization.vvp

iverilog -g2012 -o /tmp/tb_iter_solver_native_state_commit_replay.vvp ...
vvp /tmp/tb_iter_solver_native_state_commit_replay.vvp

iverilog -g2012 -o /tmp/tb_iter_solver_native_multirow_state_commit_replay.vvp ...
vvp /tmp/tb_iter_solver_native_multirow_state_commit_replay.vvp

iverilog -g2012 -o /tmp/tb_iter_solver_native_state_delta_bound.vvp ...
vvp /tmp/tb_iter_solver_native_state_delta_bound.vvp

iverilog -g2012 -o /tmp/tb_iter_solver_native_replayed_state_identity_update.vvp ...
vvp /tmp/tb_iter_solver_native_replayed_state_identity_update.vvp

iverilog -g2012 -o /tmp/tb_iter_solver_native_two_iter_affine_cluster.vvp ...
vvp /tmp/tb_iter_solver_native_two_iter_affine_cluster.vvp

iverilog -g2012 -o /tmp/tb_iter_solver_native_cluster_digit_stream_top.vvp ...
vvp /tmp/tb_iter_solver_native_cluster_digit_stream_top.vvp

iverilog -g2012 -o /tmp/tb_iter_solver_native_cluster_delta_cert_top.vvp ...
vvp /tmp/tb_iter_solver_native_cluster_delta_cert_top.vvp

iverilog -g2012 -o /tmp/tb_iter_dense_runtime_solver_native_mode3_smoke.vvp ...
vvp /tmp/tb_iter_dense_runtime_solver_native_mode3_smoke.vvp
```

## Row-Level Equivalence Result

The non-zero equivalence test assembles the solver-native signed-digit output trace after the online drain interval and compares it with the full-digit bridge full-word sum.

```text
CHECK solver_native_row case=0 full_sum=170 native_trace_sum=170 full_p=0aa full_n=000 native_p=00154 native_n=000aa
CHECK solver_native_row case=1 full_sum=67 native_trace_sum=67 full_p=043 full_n=000 native_p=00084 native_n=00041
PASS tb_iter_solver_native_row_digit_characterization
```

The p/n trace is redundant signed-digit rail form, so it is not bit-identical to the full bridge's magnitude rail output.  The numerical value `p - n` is exact for these directed rows.

## State Commit / Replay Result

The state checkpoint confirms that the solver-native signed-digit trace can be stored directly in the digit-stream state bank and replayed without magnitude-rail reconstruction:

```text
PASS tb_iter_solver_native_state_commit_replay value=170 p=00154 n=000aa
```

The replayed numerical value matches the full bridge reference:

$$
170 = 0x154 - 0x0aa
$$

## Multi-Row State Commit Result

Two solver-native row engines now commit through fixed-width adapters into one shared state bank:

```text
PASS tb_iter_solver_native_multirow_state_commit_replay row0=170 row1=-92 p=024154 n=0520aa
```

The commit adapters skip the fixed online latency digits and write the next `DATA_WIDTH` signed digits, so the state width does not grow across iterations.

## Inline Delta Result

The replayed solver-native state can feed `iter_digit_stream_delta_bound` directly:

```text
PASS tb_iter_solver_native_state_delta_bound delta=165 abs=165
```

This corresponds to:

$$
\Delta = 170 - 5 = 165
$$

No full-word reconstruction is required in the datapath for the delta stream.

## Replayed-State Row-Update Result

The replayed signed-digit state now feeds a solver-native row engine directly.  The identity update test preserves both row values:

```text
PASS tb_iter_solver_native_replayed_state_identity_update row0=170 row1=-92
```

This is the first closed-loop datapath evidence that the signed-digit state contract can cross an iteration boundary:

$$
\text{iteration } k \text{ replay}
\rightarrow
\text{parallel solver-native row updates}
\rightarrow
\text{digit-stream state bank}
$$

## Two-Iteration Affine Cluster Result

The next directed checkpoint replaces identity replay with a real two-iteration affine cluster:

$$
x^{(k)}
\rightarrow
Gx^{(k)}+c
\rightarrow
Gx^{(k+1)}+c
$$

The test first computes and commits:

$$
x^{(1)} = (170,\,-92)
$$

It then replays those committed signed-digit states and computes:

$$
x_0^{(2)} = x_0^{(1)} + x_1^{(1)} = 78
$$

$$
x_1^{(2)} = x_0^{(1)} - x_1^{(1)} = 262
$$

The RTL result is:

```text
PASS tb_iter_solver_native_two_iter_affine_cluster iter1=(170,-92) iter2=(78,262)
PASS tb_iter_solver_native_cluster_digit_stream_top iter1=(170,-92) scaled_iter2=(64,694)
```

Both iterations in `tb_iter_solver_native_two_iter_affine_cluster` are checked against `iter_digit_serial_full_row_update_delta_slice`, so the result validates a true replayed-state affine update, not only state-bank readback.  The reusable cluster-shell test now uses a stronger second iteration:

$$
x_0^{(2)} = 2x_0^{(1)} + 3x_1^{(1)} = 64
$$

$$
x_1^{(2)} = 3x_0^{(1)} - 2x_1^{(1)} = 694
$$

This second line is produced through `iter_solver_native_cluster_digit_stream_top`, which packages the replay mux, row digit engines, commit adapters and digit-stream state bank into one runtime-ready RTL shell.

## Cluster Inline Delta / Certification Result

`iter_solver_native_cluster_delta_cert_top` connects the fixed-width commit digit stream to `iter_digit_stream_delta_bound` and then to `online_row_cluster_block_cert`.  A directed test preloads old state:

$$
x^{(k)} = (5, 2)
$$

and writes new state:

$$
x^{(k+1)} = (7, -3)
$$

The exact row deltas are:

$$
|\Delta_0| = |7 - 5| = 2
$$

$$
|\Delta_1| = |-3 - 2| = 5
$$

With one block and unit block weights, the certified max error is therefore `5`:

```text
PASS tb_iter_solver_native_cluster_delta_cert_top max_error=5 final=(7,-3)
```

This proves the certification boundary can be driven by the same digit stream that writes the next state.  It does not require a full-word row-update bridge.

`iter_solver_native_cluster_delta_cert_top` now also receives the runtime `tail_bound` and saturating-adds it to the digit-stream delta bound before `block_H` certification.  This fixed a real interface gap: without `tail_bound`, mode3 state matched the full-digit golden, but `max_error` was lower by the certification tail contribution.

## Runtime Mode3 Smoke Result

`ROW_DATAPATH_MODE=3` is now wired into `iter_dense_small_ping_pong_top`.  In this mode, the solver-native cluster shell owns the state bank, so the runtime no longer writes row-update results through `iter_state_ping_pong_bank`.

The runtime smoke uses the normal loader path:

$$
\text{template/cert/state load}
\rightarrow
\text{auto digit scheduler}
\rightarrow
\text{solver-native cluster}
\rightarrow
\text{iteration controller}
$$

The directed two-iteration update is:

$$
x^{(k)} = (5, 2)
$$

$$
x_0^{(k+1)} = x_0^{(k)} + 2 = 7
$$

$$
x_1^{(k+1)} = -x_1^{(k)} - 1 = -3
$$

The second iteration replays the committed signed-digit state and applies the same update:

$$
x^{(k+2)} = (9, 2)
$$

The runtime result is:

```text
PASS tb_iter_dense_runtime_solver_native_mode3_smoke final_state=(9,2) max_error=5
```

One important implementation detail is now explicit: the global auto digit scheduler still issues only `DATA_WIDTH` input digits.  The solver-native cluster shell adds an internal fixed drain interval of `skip_digits` zero-input cycles so the online row engine can emit enough output digits for fixed-width state commit.  This keeps runtime control simple and localizes online latency handling inside the solver-native cluster.

The smoke now uses `tb/iter_tb_signed_digit_reconstruct.vh` as the reusable numerical checker for signed-digit rail state.  This checker is also used by the larger mode3 runtime regression, because raw p/n bit patterns are not comparable to magnitude-rail golden files.

## Runtime Mode3 Full-Digit Blockdiag Result

The old `jacobi32_blockdiag_multi` fixture is a one-digit-slice demo and is not a valid golden for mode3.  A new full-digit fixture is generated by:

```text
conda run -n qas python MSDF_iterative_solver/make_jacobi32_blockdiag_full_digit_runtime_vectors.py --out-dir MSDF_iterative_solver/generated/rtl_vectors/jacobi32_blockdiag_full_digit_f4 --frac-bits 4
```

The `frac_bits=4` variant keeps the integer recurrence inside the signed-digit state range for 6 iterations.  The `frac_bits=6` variant intentionally remains in the tree as a stress case, but it saturates the conventional magnitude-rail golden after several iterations and is not used as the strict mode3 acceptance vector.

The strict runtime result is:

```text
COUNTERS jacobi32_blockdiag_solver_native_multi total=235 issue=66 cert_wait=126 iter=6 conv_iter=6 cfg_template=8 cfg_cert=8 cfg_state=32 window_load=1 window_busy=10 window_ready=208 active_digit=66 gated_digit=0 cert_blocks=48 cert_sum=528
PASS tb_iter_dense_runtime_jacobi32_blockdiag_solver_native_multi
```

This proves the local-source solver-native runtime can close 6 full iterations with:

$$
\text{template/cert/state load}
\rightarrow
\text{auto full-digit scheduler}
\rightarrow
\text{solver-native digit-stream row engine}
\rightarrow
\text{digit-stream state commit}
\rightarrow
\text{inline delta/certification}
\rightarrow
\text{next iteration}
$$

Mode3 now also reuses the top-level `w_drv_x*` replay-selected digit streams, so halo-window source replay can feed the solver-native row digit engine without reconstructing full words.  The strict halo checkpoint uses:

```text
MSDF_iterative_solver/generated/rtl_vectors/jacobi32_halo_conv_f2
```

and passes with the timing-protection halo replay register enabled:

```text
COUNTERS jacobi32_halo_reg_solver_native_multi total=241 issue=66 cert_wait=132 iter=6 conv_iter=6 cfg_template=8 cfg_cert=8 cfg_state=32 window_load=1 window_busy=10 window_ready=214 active_digit=66 gated_digit=0 cert_blocks=48 cert_sum=528
PASS tb_iter_dense_runtime_jacobi32_halo_reg_solver_native_multi
```

The same strict halo workload also passes with `HALO_REPLAY_OUTPUT_REGISTER=0`, which removes one replay-register cycle per iteration:

```text
COUNTERS jacobi32_halo_reg_solver_native_multi total=235 issue=66 cert_wait=126 iter=6 conv_iter=6 cfg_template=8 cfg_cert=8 cfg_state=32 window_load=1 window_busy=10 window_ready=208 active_digit=66 gated_digit=0 cert_blocks=48 cert_sum=528
PASS tb_iter_dense_runtime_jacobi32_halo_reg_solver_native_multi
```

The printed label is inherited from the shared halo testbench path; this run is compiled without `JACOBI32_HALO_REG`.

The controller now also bypasses the final certification result and masks in the same cycle as the last `cluster_valid`.  This fast-done optimization removes one pure controller tail cycle per iteration and gives:

```text
COUNTERS jacobi32_halo_reg_solver_native_multi total=229 issue=66 cert_wait=120 iter=6 conv_iter=6 cfg_template=8 cfg_cert=8 cfg_state=32 window_load=1 window_busy=10 window_ready=202 active_digit=66 gated_digit=0 cert_blocks=48 cert_sum=528
PASS tb_iter_dense_runtime_jacobi32_halo_reg_solver_native_multi
```

The remaining source-scope limitation is arbitrary global-source replay.  Radius-1 halo-window mode3 is now a functional runtime checkpoint.

The same NC8 halo mode3 checkpoint has also been routed on U55C at 5 ns.  The first routed optimization enabled `iter_digit_stream_delta_bound.final_only=1` in mode3, improving the checkpoint from `31897 LUT / WNS +0.222 ns / dynamic 0.993 W` to `27102 LUT / 10054 FF / 64 DSP / 9 BRAM / WNS +0.750 ns / dynamic 0.828 W` without changing cycles.  Certification wrapper input/output bypass reduced the 6-iteration halo runtime from `277` to `265` cycles.  The current default is `affine_guard_shift=7, skip_digits=4, HALO_REPLAY_OUTPUT_REGISTER=0` plus fast-done result bypass, selected by strict blockdiag+halo sweep and U55C route; it gives `26779 LUT / 9083 FF / 64 DSP / 9 BRAM / WNS +0.128 ns / dynamic 0.711 W` and reduces the halo runtime to `229` cycles.  The registered-halo variant remains available as a timing-protection ablation with `26009 LUT / 9384 FF / WNS +0.436 ns / total=241`.

The validated guard/skip pairs form a clear alignment trade-off: `guard=1/skip=10`, `2/9`, `3/8`, `4/7`, `5/6`, `6/5`, and `7/4` all pass both strict workloads.  More aggressive pairs such as `8/3` and `9/2` pass halo but fail blockdiag, so they are not safe defaults.  This is a real microarchitecture improvement, not an approximation: the selected pair still runs the full `DATA_WIDTH` digit stream and matches the same full-digit golden.

The `sample_width=4..9` sweep did not unlock a shorter `skip_digits` setting: `guard=8/skip=3` still fails the strict blockdiag workload for every tested sample width.  The residual observation window is therefore not the remaining runtime limiter.

This route proves implementation feasibility and removes a large amount of unused intermediate prefix-bound logic, but it is still not a latency/throughput leadership result.  Compared with the cleaned conventional runtime under the same fast-done shell, mode3 keeps the `3x` DSP reduction plus lower FF and dynamic power, but remains slower in cycles (`229` versus `157`).  Its LUT count is now in the same range as conventional (`26779` versus `24997`).  The routed worst path remains `delta_bound/o_abs_upper_reg -> cluster_cert/cert_engine` through the `block_H` DSP certification path, so the next solver-native optimization target is state-ready/certification overlap, not the row digit engine.
