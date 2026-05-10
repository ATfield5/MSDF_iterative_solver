# Wavefront Digit Streaming

This document records the new mainline after the prefix-safe row-start
experiment.

## Core Idea

The previous prefix-safe path still did:

$$
x^{(k+1)}_{0:D-1}
\rightarrow
\text{row-start decision}
\rightarrow
\text{replay } x^{(k+1)}_{0:D-1}
\rightarrow
x^{(k+2)}
$$

That is only row-start overlap.  It can reduce the first-row wait, but it still
replays a full digit stream after a row is issued.

The wavefront path is different:

$$
x^{(k+1)}_j
\rightarrow
\text{digit FIFO / alignment}
\rightarrow
\text{row engine for } x^{(k+2)}_j
$$

Each emitted digit is final in the MSDF signed-digit stream, so it may feed the
next online operator directly.  The downstream operator's own online delay and
digit alignment determine when the next output digit appears.

## Correctness Contract

The wavefront contract does not rely on dynamic early-stop or heuristic prefix
certification.  It relies on standard online arithmetic:

$$
y_j = F(x_0,\ldots,x_{j+\delta})
$$

where \(\delta\) is the online delay of the row engine.  The source digit is not
revised later; the downstream residual loop handles the unknown lower digits by
its own recurrence and selection logic.

For Jacobi-style fixed-point iteration:

$$
x^{(k+1)} = Gx^{(k)} + c
$$

the next iteration is legal as soon as the required digits of \(x^{(k+1)}\) are
available:

$$
x^{(k+2)} = Gx^{(k+1)} + c
$$

The remaining hardware problem is alignment:

- every consumer row needs all required neighbor digits for the same digit index;
- halo/stencil terms need per-source digit FIFOs;
- the stage start pulse must align with consumer digit index `0`;
- the final state commit still writes the full digit stream, but it no longer
  gates the next iteration's computation.

## Performance Model

Without wavefronting, a two-stage row pipeline behaves approximately as:

$$
T_{\mathrm{fullwait}}
\approx
T_0 + T_1
$$

With digit wavefronting:

$$
T_{\mathrm{wavefront}}
\approx
T_0 + \delta_1
$$

For \(K\) streamed iterations:

$$
T_{\mathrm{fullwait}}
\approx
K(D+L)
$$

$$
T_{\mathrm{wavefront}}
\approx
D + (K-1)\Delta + L
$$

where \(D\) is digit width, \(L\) is row-engine drain latency, and \(\Delta\) is
the effective stage-to-stage online delay after FIFO alignment.

This is the stronger architecture-level claim: not "some rows start early", but
"successive solver iterations are pipelined at digit granularity".

## Current RTL Checkpoint

The first RTL checkpoint is:

```text
rtl/iter_wavefront_two_stage_row_pipeline.v
```

It connects:

```text
stage0 iter_solver_native_row_digit_engine
-> stage1 iter_solver_native_row_digit_engine
```

directly at the digit-stream boundary.  Only term0 is connected in this first
row-level proof.

The directed test is:

```text
tb/tb_iter_wavefront_two_stage_row_pipeline.v
```

It verifies:

- stage1 starts before stage0 has completed the full digit word;
- wavefront stage1 output matches a full-wait reference stage1 fed by the
  recorded stage0 output stream;
- the wavefront schedule finishes earlier than the full-wait model.

Result:

```text
PASS tb_iter_wavefront_two_stage_row_pipeline
INFO stage0_done_cycle=9 wavefront_done_cycle=11 fullwait_model_cycle=17 saved_cycles=6
```

Local speedup:

$$
\frac{17}{11}=1.545\times
$$

The second RTL checkpoint is:

```text
rtl/iter_wavefront_radius1_two_stage_cluster.v
```

It connects multiple rows with radius-1 stencil wiring:

```text
stage1 term0 <- stage0 left-row digit
stage1 term1 <- stage0 self-row digit
stage1 term2 <- stage0 right-row digit
stage1 term3 <- zero
```

The directed test is:

```text
tb/tb_iter_wavefront_radius1_two_stage_cluster.v
```

Result:

```text
PASS tb_iter_wavefront_radius1_two_stage_cluster
INFO stage0_done_cycle=9 wavefront_done_cycle=11 fullwait_model_cycle=17 saved_cycles=6
```

This validates multi-row neighbor alignment, not only a single term0 chain.

The third RTL checkpoint is:

```text
rtl/iter_wavefront_radius1_multistage_cluster.v
```

It generalizes the radius-1 cluster to \(K\) streamed solver stages.  Stage 0
consumes the external source stream; every later stage consumes the previous
stage's output digits through the same left/self/right stencil wiring.  The
directed test is:

```text
tb/tb_iter_wavefront_radius1_multistage_cluster.v
```

The test compares the wavefront pipeline against a full-wait reference that
runs one complete stage at a time and restarts the same row engines for each
stage.  Result for \(K=4\), `NUM_ROWS=3`, `DATA_WIDTH=8`:

```text
PASS tb_iter_wavefront_radius1_multistage_cluster
INFO stages=4 wavefront_done_cycle=15 fullwait_model_cycle=32 saved_cycles=17
```

Local speedup:

$$
\frac{32}{15}=2.133\times
$$

This is the first checkpoint where the benefit compounds across more than two
solver iterations.

Important boundary correction: this checkpoint forwards the raw row-engine
output stream.  It proves online stream scheduling, but it is not yet the exact
runtime mode3 state-bank contract, because mode3 writes state only after:

$$
\text{row raw digit}
\rightarrow
\text{commit adapter / skip}
\rightarrow
\text{fixed-width state digit}
$$

The runtime-adjacent committed-state checkpoint is:

```text
rtl/iter_wavefront_commit_stage_cluster.v
rtl/iter_wavefront_radius1_commit_multistage_cluster.v
tb/tb_iter_wavefront_radius1_commit_multistage_cluster.v
```

It forwards only committed state digits between stages.  Result for \(K=4\),
`DATA_WIDTH=8`, `SKIP_DIGITS=4`:

```text
PASS tb_iter_wavefront_radius1_commit_multistage_cluster
INFO commit stages=4 skip=4 delay=0 wavefront_done_cycle=35 fullwait_model_cycle=60 saved_cycles=25
```

Local committed-state speedup:

$$
\frac{60}{35}=1.714\times
$$

This is the result that should be used when discussing runtime mode3
integration.

## Super-Step Certification Semantics

A fused \(K\)-stage wavefront must not certify:

$$
x^{(k+K)} - x^{(k)}
$$

That quantity is the whole super-step displacement, not the normal Jacobi
convergence delta.  The compatible rule is to certify the last internal
iteration:

$$
\Delta_{\mathrm{last}} =
x^{(k+K)} - x^{(k+K-1)}
$$

The RTL checkpoint is:

```text
rtl/iter_wavefront_commit_last_delta_cert_top.v
tb/tb_iter_wavefront_commit_last_delta_cert_top.v
```

It caches the committed digits from stage \(K-1\), compares them with the
committed digits from stage \(K\), and feeds the result into the existing
`iter_digit_stream_delta_bound -> online_row_cluster_block_cert` path.

Directed result:

```text
PASS tb_iter_wavefront_commit_last_delta_cert_top final=5 prev=10 max_error=5
```

This proves the certification boundary is semantically compatible with the
existing per-iteration solver rule.  It still does not mean runtime mode3 has
been converted to super-step execution; that is the next integration step.

## Runtime-Adjacent State Shell

The next checkpoint wraps the committed wavefront and last-delta certification
with the same digit-stream state-bank boundary used by mode3:

```text
rtl/iter_wavefront_superstep_cluster_state_top.v
tb/tb_iter_wavefront_superstep_cluster_state_top.v
```

Dataflow:

$$
\text{state replay or external source}
\rightarrow
\text{K-stage committed wavefront}
\rightarrow
\text{last-delta certification}
\rightarrow
\text{inactive state-bank digit writes}
$$

Directed result:

```text
PASS tb_iter_wavefront_superstep_cluster_state_top max_error=5 state=0a/05
```

This validates that final committed digits can be written into the inactive
state bank and read back after `commit_swap`.  It is the immediate building
block for a future `ROW_DATAPATH_MODE=4` super-step runtime mode.

## Runtime Mode4 Smoke

`ROW_DATAPATH_MODE=4` now instantiates the runtime-adjacent super-step shell
inside `iter_dense_small_runtime_top` through `iter_dense_small_ping_pong_top`.
The mode keeps the existing runtime loader, template/cert banks, source replay
selection, iteration controller, and state-bank commit interface, but replaces
the single-iteration row datapath with:

$$
\text{external/replayed digit stream}
\rightarrow
\text{K-stage committed wavefront}
\rightarrow
\text{last-delta certification}
\rightarrow
\text{digit-stream state write}
$$

The directed smoke test is:

```text
tb/tb_iter_dense_runtime_wavefront_superstep_smoke.v
```

Result:

```text
PASS tb_iter_dense_runtime_wavefront_superstep_smoke max_error=5 state=0a/05
```

This proves the super-step wavefront is no longer only a standalone cluster
prototype: it can pass through the runtime shell and commit the final state into
the inactive runtime state bank.  It is still a one-cluster smoke test, not yet
an NC8/NC16 solver workload or routed U55C result.

## Runtime Blockdiag Super-Step

The committed wavefront inter-stage source path now has two modes:

- radius-1 stencil wiring, used by the original directed proof;
- fixed-degree template wiring, where every internal stage selects the previous
  stage's committed digit by `src_row_idx`.

This is required for block-diagonal Jacobi, whose local rows are not a pure
left/self/right stencil.  `ROW_DATAPATH_MODE=4` uses the fixed-degree template
mode.

The directed multi-cluster blockdiag test is:

```text
tb/tb_iter_dense_runtime_jacobi32_blockdiag_wavefront_superstep.v
```

It runs one runtime super-step with `K=4`, then compares against the golden
state and last-delta certification after iteration 4.  Result:

```text
ITER multi iter=0 cert_wait_delta=41 conv=1 cont=0 maxerr0=255 state0p=05400000024 state0n=00006c0c000
COUNTERS jacobi32_blockdiag_wavefront_superstep total=135 issue=11 cert_wait=41 iter=1 conv_iter=1 cfg_template=8 cfg_cert=8 cfg_state=32 window_load=1 window_busy=10 window_ready=108 active_digit=11 gated_digit=0 cert_blocks=8 cert_sum=88
PASS tb_iter_dense_runtime_jacobi32_blockdiag_wavefront_superstep
```

This is the first `8`-cluster runtime checkpoint for mode4.  It validates the
runtime loader, template/cert banks, automatic digit issue, K-stage wavefront,
last-delta certification, and digit-stream state commit as one path.  It is the
local-dependency checkpoint before the halo-window test below.

## Runtime Halo Super-Step

Cross-cluster inter-stage halo forwarding has now been added.  For internal
stage \(s>0\), each cluster builds a source window from stage \(s-1\)'s committed
digits:

$$
[\text{previous cluster},\ \text{current cluster},\ \text{next cluster}]
$$

and then uses the same packed `src_row_idx` contract as the normal halo replay:

$$
0\ldots R-1,\quad R\ldots 2R-1,\quad 2R\ldots 3R-1
$$

The directed halo-window runtime test is:

```text
tb/tb_iter_dense_runtime_jacobi32_halo_reg_wavefront_superstep.v
```

It runs one `K=4` super-step on the registered halo-window Jacobi fixture and
compares the final committed state and last-delta certification against the
fourth golden iteration.  Result:

```text
ITER multi iter=0 cert_wait_delta=42 conv=1 cont=0 maxerr0=39 state0p=00200401002 state0n=00000000000
COUNTERS jacobi32_halo_reg_wavefront_superstep total=136 issue=11 cert_wait=42 iter=1 conv_iter=1 cfg_template=8 cfg_cert=8 cfg_state=32 window_load=1 window_busy=10 window_ready=109 active_digit=11 gated_digit=0 cert_blocks=8 cert_sum=88
PASS tb_iter_dense_runtime_jacobi32_halo_reg_wavefront_superstep
```

This is the first functional checkpoint where mode4 covers the intended
halo-window workload.  Routed U55C results are recorded below in the same
document.

## Runtime Fair Cycle Comparison

The fair runtime comparison is now available on the same registered halo-window
fixture.  The reference path is mode3 solver-native execution running four
ordinary Jacobi iterations.  The wavefront path is mode4 running one `K=4`
super-step and comparing against the same fourth-iteration golden state.

```text
COUNTERS jacobi32_halo_reg_solver_native_four total=187 issue=44 cert_wait=84 iter=4 conv_iter=4 cfg_template=8 cfg_cert=8 cfg_state=32 window_load=1 window_busy=10 window_ready=160 active_digit=44 gated_digit=0 cert_blocks=32 cert_sum=352
PASS tb_iter_dense_runtime_jacobi32_halo_reg_solver_native_four
```

| path | semantic work | total cycles | issue cycles | cert wait cycles | result |
| --- | --- | ---: | ---: | ---: | --- |
| mode3 solver-native | four ordinary iterations | 187 | 44 | 84 | matches iteration-4 golden |
| mode4 wavefront | one `K=4` super-step | 136 | 11 | 42 | matches iteration-4 golden |

The runtime-level speedup is:

$$
\frac{187}{136}=1.375\times
$$

The issue path shows the intended effect directly: mode3 pays `11` digit-issue
cycles per iteration, so four iterations cost `44`; mode4 streams all four
logical stages through one digit issue window and keeps `issue=11`.  The total
speedup is smaller than `4x` because configuration, window load, certification,
and final commit still exist at runtime level.

## U55C Routed Checkpoint

Both paths have now been routed out-of-context on U55C at `5 ns` with the same
registered halo-window configuration (`NUM_CLUSTERS=8`, `NUM_ROWS=4`,
`DEGREE=4`, `DATA_WIDTH=11`, `SRC_IDX_WIDTH=4`, `HALO_SOURCE_REPLAY=1`,
`HALO_REPLAY_OUTPUT_REGISTER=1`).

| path | total cycles | LUT | FF | DSP | BRAM tile | WNS | dynamic |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| mode3 solver-native, four iterations | 187 | 26107 | 9381 | 64 | 9 | +0.321 ns | 0.825 W |
| mode4 wavefront, one `K=4` super-step | 136 | 40759 | 13174 | 64 | 9 | +0.368 ns | 1.115 W |
| mode4 wavefront + cert operand pipeline | 137 | 40789 | 13182 | 64 | 9 | +0.667 ns | 1.052 W |

The routed result is positive for cycle latency but not yet a free win in
area.  The unpipelined mode4 path reduces runtime cycles by `27.27%` and keeps
DSP/BRAM unchanged, but increases LUT by `56.12%`, FF by `40.43%`, and dynamic
power by `35.15%`.  The effective optimization is `cert_operand_pipeline=1`:
it costs one runtime cycle and only `+30 LUT / +8 FF`, improves WNS from
`+0.368 ns` to `+0.667 ns`, and lowers dynamic power from `1.115 W` to
`1.052 W`.

The optimized dynamic energy proxy against four ordinary mode3 iterations is:

$$
\frac{1.052 \times 137}{0.825 \times 187}=0.934
$$

After this pipeline is enabled, the worst routed path moves away from the
last-delta certification multiply.  The remaining worst paths are mostly
template/window and digit-index routing, so the certification pipeline should
be the recommended mode4 timing configuration.

```text
template_bank / digit-index routing
```

So the next useful optimization is not another row-engine tweak; it is reducing
or restructuring last-delta `block_H` certification cost for the super-step.

The parameter sweep script is:

```text
run_wavefront_digit_stream_sweep.py
```

Current directed sweep result:

| stages K | data width D | inter-stage delay | wavefront cycles | full-wait cycles | speedup |
| ---: | ---: | ---: | ---: | ---: | ---: |
| 2 | 8 | 0 | 11 | 16 | 1.455x |
| 4 | 8 | 0 | 15 | 32 | 2.133x |
| 8 | 8 | 0 | 23 | 64 | 2.783x |
| 4 | 11 | 0 | 18 | 44 | 2.444x |
| 8 | 11 | 0 | 26 | 88 | 3.385x |
| 4 | 8 | 1 | 18 | 32 | 1.778x |
| 8 | 11 | 1 | 33 | 88 | 2.667x |

Full report:

```text
generated/wavefront_digit_stream_sweep.md
```

Committed-state sweep:

| stages K | data width D | skip digits | delay | wavefront cycles | full-wait cycles | speedup |
| ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 2 | 8 | 4 | 0 | 21 | 30 | 1.429x |
| 4 | 8 | 4 | 0 | 35 | 60 | 1.714x |
| 8 | 8 | 4 | 0 | 63 | 120 | 1.905x |
| 4 | 11 | 4 | 0 | 38 | 72 | 1.895x |
| 8 | 11 | 4 | 0 | 66 | 144 | 2.182x |
| 4 | 8 | 4 | 1 | 38 | 60 | 1.579x |

Full committed-state report:

```text
generated/wavefront_commit_stream_sweep.md
```

## Difference From Prefix-Safe Row-Start

Prefix-safe row-start asks:

$$
\text{when can a row be issued?}
$$

Wavefront digit streaming asks:

$$
\text{can every produced digit immediately become another operator's input?}
$$

The second question is more aligned with MSDF.  Prefix-safe row-start remains a
useful negative/ablation branch, but the mainline should now move to wavefront
FIFOs and multi-row stencil alignment.

## Next Steps

1. Add mode4 solver-level counters so reports distinguish input digit issue,
   internal K-stage wavefront drain, last-delta certification, and state-bank
   commit.
2. Reduce mode4 area overhead.  The current latency result is defensible, but
   LUT remains about `56%` above mode3; the next target is sharing or pruning
   replicated K-stage control/state selection logic.
3. Run NC16 route for mode4 only after the NC8 certification path is improved.
4. Replace the current fixed delay line with ready/valid halo FIFOs only if
   runtime mode3 introduces real backpressure.
