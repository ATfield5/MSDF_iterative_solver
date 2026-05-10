# Wavefront Digit-Stream Checkpoint

This checkpoint starts the true cross-iteration digit-stream branch.

## Implemented RTL

| file | role |
| --- | --- |
| `rtl/iter_wavefront_two_stage_row_pipeline.v` | Connects stage0 solver-native row output digits directly into stage1 solver-native row input term0. |
| `rtl/iter_wavefront_radius1_two_stage_cluster.v` | Extends the wavefront proof to multiple rows with left/self/right radius-1 stencil wiring. |
| `rtl/iter_wavefront_radius1_multistage_cluster.v` | Extends the radius-1 proof to a parameterized K-stage solver wavefront pipeline. |
| `tb/tb_iter_wavefront_two_stage_row_pipeline.v` | Compares the wavefront path against a full-wait reference fed by the recorded stage0 output stream. |
| `tb/tb_iter_wavefront_radius1_two_stage_cluster.v` | Compares the multi-row radius-1 wavefront path against a full-wait reference cluster. |
| `tb/tb_iter_wavefront_radius1_multistage_cluster.v` | Compares a K-stage wavefront cluster against a sequential full-wait stage reference. |

## Test Result

Command:

```text
iverilog -g2012 -o /tmp/tb_iter_wavefront_two_stage_row_pipeline.vvp \
  MSDF_iterative_solver/rtl/iter_wavefront_two_stage_row_pipeline.v \
  MSDF_iterative_solver/rtl/iter_solver_native_row_digit_engine.v \
  MSDF_iterative_solver/rtl/iter_streamed_bias_source.v \
  MSDF_iterative_solver/rtl/iter_online_affine_no_bias_core.v \
  MSDF_iterative_solver/rtl/iter_const_coeff_digit_contrib_rail.v \
  MSDF_iterative_solver/rtl/iter_parallel_online_adder_4_with_obuf.v \
  MSDF_iterative_solver/rtl/iter_parallel_online_adder_4.v \
  MSDF_iterative_solver/rtl/iter_parallel_online_adder.v \
  MSDF_iterative_solver/rtl/iter_parallel_online_adder_block.v \
  MSDF_iterative_solver/rtl/iter_full_adder.v \
  MSDF_iterative_solver/rtl/iter_dff.v \
  MSDF_iterative_solver/rtl/iter_online_affine_digit_core.v \
  MSDF_iterative_solver/rtl/iter_online_output_update.v \
  MSDF_iterative_solver/tb/tb_iter_wavefront_two_stage_row_pipeline.v
vvp /tmp/tb_iter_wavefront_two_stage_row_pipeline.vvp
```

Result:

```text
PASS tb_iter_wavefront_two_stage_row_pipeline
INFO stage0_done_cycle=9 wavefront_done_cycle=11 fullwait_model_cycle=17 saved_cycles=6
```

The local row-level speedup is:

$$
\frac{17}{11}=1.545\times
$$

## Radius-1 Cluster Result

Command:

```text
iverilog -g2012 -o /tmp/tb_iter_wavefront_radius1_two_stage_cluster.vvp \
  MSDF_iterative_solver/rtl/iter_wavefront_radius1_two_stage_cluster.v \
  MSDF_iterative_solver/rtl/iter_solver_native_row_digit_engine.v \
  MSDF_iterative_solver/rtl/iter_streamed_bias_source.v \
  MSDF_iterative_solver/rtl/iter_online_affine_no_bias_core.v \
  MSDF_iterative_solver/rtl/iter_const_coeff_digit_contrib_rail.v \
  MSDF_iterative_solver/rtl/iter_parallel_online_adder_4_with_obuf.v \
  MSDF_iterative_solver/rtl/iter_parallel_online_adder_4.v \
  MSDF_iterative_solver/rtl/iter_parallel_online_adder.v \
  MSDF_iterative_solver/rtl/iter_parallel_online_adder_block.v \
  MSDF_iterative_solver/rtl/iter_full_adder.v \
  MSDF_iterative_solver/rtl/iter_dff.v \
  MSDF_iterative_solver/rtl/iter_online_affine_digit_core.v \
  MSDF_iterative_solver/rtl/iter_online_output_update.v \
  MSDF_iterative_solver/tb/tb_iter_wavefront_radius1_two_stage_cluster.v
vvp /tmp/tb_iter_wavefront_radius1_two_stage_cluster.vvp
```

Result:

```text
PASS tb_iter_wavefront_radius1_two_stage_cluster
INFO stage0_done_cycle=9 wavefront_done_cycle=11 fullwait_model_cycle=17 saved_cycles=6
```

The radius-1 cluster connects:

```text
stage1 term0 <- stage0 left row
stage1 term1 <- stage0 self row
stage1 term2 <- stage0 right row
stage1 term3 <- zero
```

The full-wait reference records the complete stage0 output streams first, then
feeds the same left/self/right digit streams into independent reference row
engines.  The wavefront stage1 output matches the full-wait reference output.

## Multi-Stage Radius-1 Result

Command:

```text
iverilog -g2012 -o /tmp/tb_iter_wavefront_radius1_multistage_cluster.vvp \
  MSDF_iterative_solver/rtl/iter_wavefront_radius1_multistage_cluster.v \
  MSDF_iterative_solver/rtl/iter_wavefront_digit_delay_line.v \
  MSDF_iterative_solver/rtl/iter_solver_native_row_digit_engine.v \
  MSDF_iterative_solver/rtl/iter_streamed_bias_source.v \
  MSDF_iterative_solver/rtl/iter_online_affine_no_bias_core.v \
  MSDF_iterative_solver/rtl/iter_const_coeff_digit_contrib_rail.v \
  MSDF_iterative_solver/rtl/iter_parallel_online_adder_4_with_obuf.v \
  MSDF_iterative_solver/rtl/iter_parallel_online_adder_4.v \
  MSDF_iterative_solver/rtl/iter_parallel_online_adder.v \
  MSDF_iterative_solver/rtl/iter_parallel_online_adder_block.v \
  MSDF_iterative_solver/rtl/iter_full_adder.v \
  MSDF_iterative_solver/rtl/iter_dff.v \
  MSDF_iterative_solver/rtl/iter_online_affine_digit_core.v \
  MSDF_iterative_solver/rtl/iter_online_output_update.v \
  MSDF_iterative_solver/tb/tb_iter_wavefront_radius1_multistage_cluster.v
vvp /tmp/tb_iter_wavefront_radius1_multistage_cluster.vvp
```

Result:

```text
PASS tb_iter_wavefront_radius1_multistage_cluster
INFO stages=4 wavefront_done_cycle=15 fullwait_model_cycle=32 saved_cycles=17
```

For this directed `NUM_ROWS=3`, `DATA_WIDTH=8` case, the local speedup is:

$$
\frac{32}{15}=2.133\times
$$

The reference model is intentionally conservative: it resets/reuses the same
row engines for one complete stage at a time, records the full output stream,
then feeds that stream into the next stage.  The wavefront DUT keeps all four
stages live and forwards emitted p/n digits directly to the next stage.  The
final stage output matches the full-wait reference, so the saved cycles come
from cross-iteration digit streaming, not from reduced precision.

This raw-stream checkpoint is not the final runtime mode3 contract.  The mode3
state bank receives only committed digits after `iter_solver_native_commit_adapter`
skips the online warm-up digits.  The committed-state checkpoint below is the
one to use for runtime integration claims.

## Committed-State Multi-Stage Result

Implemented RTL:

| file | role |
| --- | --- |
| `rtl/iter_wavefront_commit_stage_cluster.v` | One solver-native row cluster stage with drain and commit adapters. |
| `rtl/iter_wavefront_radius1_commit_multistage_cluster.v` | K-stage radius-1 wavefront that forwards committed state digits only. |
| `tb/tb_iter_wavefront_radius1_commit_multistage_cluster.v` | Compares committed-state wavefront against sequential full-wait committed reference. |

Result for `K=4`, `DATA_WIDTH=8`, `SKIP_DIGITS=4`:

```text
PASS tb_iter_wavefront_radius1_commit_multistage_cluster
INFO commit stages=4 skip=4 delay=0 wavefront_done_cycle=35 fullwait_model_cycle=60 saved_cycles=25
```

Committed-state local speedup:

$$
\frac{60}{35}=1.714\times
$$

## Parameter Sweep

`run_wavefront_digit_stream_sweep.py` runs the same multistage directed
testbench with parameter overrides:

| stages K | data width D | inter-stage delay | wavefront cycles | full-wait cycles | saved cycles | speedup |
| ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 2 | 8 | 0 | 11 | 16 | 5 | 1.455x |
| 4 | 8 | 0 | 15 | 32 | 17 | 2.133x |
| 8 | 8 | 0 | 23 | 64 | 41 | 2.783x |
| 4 | 11 | 0 | 18 | 44 | 26 | 2.444x |
| 8 | 11 | 0 | 26 | 88 | 62 | 3.385x |
| 4 | 8 | 1 | 18 | 32 | 14 | 1.778x |
| 8 | 11 | 1 | 33 | 88 | 55 | 2.667x |

The generated report is:

```text
generated/wavefront_digit_stream_sweep.md
```

Committed-state sweep generated by `run_wavefront_commit_sweep.py`:

| stages K | data width D | skip digits | inter-stage delay | wavefront cycles | full-wait cycles | saved cycles | speedup |
| ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 2 | 8 | 4 | 0 | 21 | 30 | 9 | 1.429x |
| 4 | 8 | 4 | 0 | 35 | 60 | 25 | 1.714x |
| 8 | 8 | 4 | 0 | 63 | 120 | 57 | 1.905x |
| 4 | 11 | 4 | 0 | 38 | 72 | 34 | 1.895x |
| 8 | 11 | 4 | 0 | 66 | 144 | 78 | 2.182x |
| 4 | 8 | 4 | 1 | 38 | 60 | 22 | 1.579x |

The generated committed-state report is:

```text
generated/wavefront_commit_stream_sweep.md
```

## Last-Delta Certification Checkpoint

The committed-state super-step must preserve the solver's convergence meaning.
The correct delta is:

$$
x^{(k+K)} - x^{(k+K-1)}
$$

not:

$$
x^{(k+K)} - x^{(k)}
$$

Implemented RTL:

| file | role |
| --- | --- |
| `rtl/iter_wavefront_commit_last_delta_cert_top.v` | Wraps the committed K-stage wavefront and certifies the last internal iteration delta. |
| `tb/tb_iter_wavefront_commit_last_delta_cert_top.v` | Checks that hardware `max_error` equals the signed-digit value difference between final and penultimate committed stages. |

Result:

```text
PASS tb_iter_wavefront_commit_last_delta_cert_top final=5 prev=10 max_error=5
```

This checkpoint validates the certification semantics needed before runtime
mode3 integration.

## Runtime-Adjacent State Shell

Implemented RTL:

| file | role |
| --- | --- |
| `rtl/iter_wavefront_superstep_cluster_state_top.v` | Adds state replay/write-bank boundary around the committed K-stage wavefront and last-delta certification. |
| `tb/tb_iter_wavefront_superstep_cluster_state_top.v` | Checks that final committed digits are written to the inactive state bank and read back after `commit_swap`. |
| `tb/tb_iter_dense_runtime_wavefront_superstep_smoke.v` | Checks the `ROW_DATAPATH_MODE=4` runtime integration path against a standalone super-step reference. |
| `tb/tb_iter_dense_runtime_jacobi32_blockdiag_wavefront_superstep.v` | Checks one 8-cluster block-diagonal runtime super-step against the iteration-4 golden state and last-delta certification. |
| `tb/tb_iter_dense_runtime_jacobi32_halo_reg_wavefront_superstep.v` | Checks one 8-cluster registered halo-window runtime super-step against the iteration-4 golden state and last-delta certification. |
| `tb/tb_iter_dense_runtime_jacobi32_halo_reg_solver_native_four.v` | Checks four ordinary mode3 iterations on the same registered halo-window fixture for the runtime fair cycle comparison. |

Result:

```text
PASS tb_iter_wavefront_superstep_cluster_state_top max_error=5 state=0a/05
```

This is still cluster-level, but it now has the same committed digit state-bank
handoff required by runtime mode integration.

## Runtime Mode4 Smoke

`ROW_DATAPATH_MODE=4` has been wired into `iter_dense_small_runtime_top` through
`iter_dense_small_ping_pong_top`.  The smoke test keeps the runtime loader,
template/cert banks, source replay boundary, iteration controller, and state
commit interface active, then compares the committed state against the
standalone super-step cluster reference.

Result:

```text
PASS tb_iter_dense_runtime_wavefront_superstep_smoke max_error=5 state=0a/05
```

This is a runtime-shell integration checkpoint, not yet a full NC8 halo-window
solver benchmark or U55C route result.

## Runtime Blockdiag Super-Step Result

The committed wavefront now supports fixed-degree inter-stage source selection.
In this mode every internal stage selects the previous stage's committed digit
according to the template `src_row_idx`, rather than assuming pure radius-1
left/self/right wiring.

Result:

```text
ITER multi iter=0 cert_wait_delta=41 conv=1 cont=0 maxerr0=255 state0p=05400000024 state0n=00006c0c000
COUNTERS jacobi32_blockdiag_wavefront_superstep total=135 issue=11 cert_wait=41 iter=1 conv_iter=1 cfg_template=8 cfg_cert=8 cfg_state=32 window_load=1 window_busy=10 window_ready=108 active_digit=11 gated_digit=0 cert_blocks=8 cert_sum=88
PASS tb_iter_dense_runtime_jacobi32_blockdiag_wavefront_superstep
```

The check compares one `K=4` runtime super-step against the fourth golden
Jacobi iteration.  This validates mode4 on the existing 8-cluster blockdiag
fixture.

## Runtime Halo Super-Step Result

Cross-cluster inter-stage halo forwarding has been added for mode4.  Internal
stage \(s>0\) now builds each cluster's source window from stage \(s-1\)'s
committed digits in the previous/current/next clusters, then reuses the normal
packed halo `src_row_idx` contract.

Result:

```text
ITER multi iter=0 cert_wait_delta=42 conv=1 cont=0 maxerr0=39 state0p=00200401002 state0n=00000000000
COUNTERS jacobi32_halo_reg_wavefront_superstep total=136 issue=11 cert_wait=42 iter=1 conv_iter=1 cfg_template=8 cfg_cert=8 cfg_state=32 window_load=1 window_busy=10 window_ready=109 active_digit=11 gated_digit=0 cert_blocks=8 cert_sum=88
PASS tb_iter_dense_runtime_jacobi32_halo_reg_wavefront_superstep
```

This validates mode4 on the registered halo-window Jacobi fixture.  Routed
U55C results are recorded below with the mode3 comparison.

## Runtime Fair Cycle Comparison

The same registered halo-window fixture now has a direct comparison between
four ordinary mode3 solver-native iterations and one mode4 `K=4` super-step.
Both paths are checked against the same fourth-iteration golden state.

Mode3 reference:

```text
ITER multi iter=0 cert_wait_delta=21 conv=1 cont=0 maxerr0=16 state0p=00000000000 state0n=00200400000
ITER multi iter=1 cert_wait_delta=21 conv=1 cont=0 maxerr0=22 state0p=00000000800 state0n=00000800001
ITER multi iter=2 cert_wait_delta=21 conv=1 cont=0 maxerr0=33 state0p=00400001800 state0n=00000400001
ITER multi iter=3 cert_wait_delta=21 conv=1 cont=0 maxerr0=39 state0p=00200401002 state0n=00000000000
COUNTERS jacobi32_halo_reg_solver_native_four total=187 issue=44 cert_wait=84 iter=4 conv_iter=4 cfg_template=8 cfg_cert=8 cfg_state=32 window_load=1 window_busy=10 window_ready=160 active_digit=44 gated_digit=0 cert_blocks=32 cert_sum=352
PASS tb_iter_dense_runtime_jacobi32_halo_reg_solver_native_four
```

| path | semantic work | total cycles | issue cycles | cert wait cycles | result |
| --- | --- | ---: | ---: | ---: | --- |
| mode3 solver-native | four ordinary iterations | 187 | 44 | 84 | matches iteration-4 golden |
| mode4 wavefront | one `K=4` super-step | 136 | 11 | 42 | matches iteration-4 golden |

Runtime speedup:

$$
\frac{187}{136}=1.375\times
$$

## U55C Routed Checkpoint

Both paths have been routed out-of-context on U55C at `5 ns` with the same
registered halo-window configuration.

| path | total cycles | LUT | FF | DSP | BRAM tile | WNS | dynamic |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| mode3 solver-native, four iterations | 187 | 26107 | 9381 | 64 | 9 | +0.321 ns | 0.825 W |
| mode4 wavefront, one `K=4` super-step | 136 | 40759 | 13174 | 64 | 9 | +0.368 ns | 1.115 W |
| mode4 wavefront + cert operand pipeline | 137 | 40789 | 13182 | 64 | 9 | +0.667 ns | 1.052 W |

Mode4 reduces cycles by `27.27%` and keeps DSP/BRAM unchanged.  The
`cert_operand_pipeline=1` variant is the recommended timing configuration: it
adds one runtime cycle and only `+30 LUT / +8 FF` over unpipelined mode4, but
improves WNS from `+0.368 ns` to `+0.667 ns` and lowers dynamic power from
`1.115 W` to `1.052 W`.

The optimized dynamic energy proxy against four ordinary mode3 iterations is:

$$
\frac{1.052 \times 137}{0.825 \times 187}=0.934
$$

The optimized routed worst path is no longer the certification multiply.  The
remaining top paths are mostly template/window and digit-index routing:

```text
template_bank / digit-index routing
```

## Interpretation

This is stronger than the prefix-safe row-start probe.  The stage1 row engine is
not waiting for a full-word stage0 commit, nor is it replaying a completed word.
It consumes stage0 output digits as they are emitted.

The test also instantiates a full-wait reference stage1 after recording the
stage0 output stream.  Wavefront stage1 output p/n digits match the full-wait
reference stream, so this checkpoint validates scheduling, not a numerical
shortcut.

## Current Boundary

The checkpoint is still a small cluster-level proof:

- it covers radius-1 neighbor wiring but not halo crossing between clusters;
- the K-stage version currently uses direct same-cycle inter-stage wires, not
  explicit halo/source FIFOs;
- `ROW_DATAPATH_MODE=4` has passed one-cluster smoke, 8-cluster blockdiag, and
  registered halo-window functional tests;
- U55C NC8 route passes at `5 ns`; the certification pipeline is effective, but
  mode4 still needs LUT/control sharing before it becomes an area-clean win.

The next hardware step is reducing replicated K-stage control/state selection
logic and then rerunning the same mode3/mode4 routed comparison.  A fixed
inter-stage delay line has already been added to model cluster-boundary
alignment; a ready/valid FIFO is only needed if the runtime fixture introduces
real backpressure.
