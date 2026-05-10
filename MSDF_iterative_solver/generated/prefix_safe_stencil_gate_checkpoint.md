# Prefix-Safe Stencil Gate Checkpoint

This checkpoint starts the cross-iteration prefix-safe streaming branch.  It is
separate from the existing `iter_digit_prefix_scheduler`, which only controls
digit issue inside one iteration.

## Implemented RTL

| file | role |
| --- | --- |
| `rtl/iter_prefix_safe_stencil_gate.v` | Computes the conservative uncertainty of the unknown source tail and decides whether a prefix is safe for next-iteration issue. |
| `rtl/iter_prefix_safe_issue_controller.v` | Replicates the safety gate per row, emits one issue pulse when a row first becomes prefix-safe, and tracks the issued mask for one scheduler epoch. |
| `rtl/iter_prefix_safe_two_stage_probe.v` | Prototypes the scheduler boundary from one iteration prefix stream into the next-iteration row issue mask, and records lead cycles before full-word commit. |
| `rtl/iter_prefix_safe_row_start_queue.v` | Converts the prefix-safe row issue mask into a ready/valid row-start command stream for a physical next-iteration row engine. |
| `rtl/iter_prefix_safe_two_stage_scheduler.v` | Wraps the issue controller and row-start queue into the ready/valid scheduler boundary used by the next row-engine stage. |
| `rtl/iter_prefix_safe_consumer_stub.v` | Models a one-lane next-iteration row engine with fixed service latency and ready/valid backpressure. |
| `rtl/iter_prefix_safe_digit_replay_source.v` | Returns packed per-row/per-digit source term digits for the solver-native row lane. |
| `rtl/iter_prefix_safe_solver_native_row_lane.v` | Adapts a prefix-safe row-start command into a full MSB-first run of the real `iter_solver_native_row_digit_engine`. |
| `rtl/iter_fullword_row_start_scheduler.v` | Baseline no-overlap scheduler that waits for full-word commit before issuing all rows through the same row-start queue. |
| `rtl/iter_prefix_safe_row_start_multi_lane_dispatcher.v` | Multi-lane row-start dispatcher that can issue multiple pending rows to ready row lanes in one cycle. |
| `rtl/iter_prefix_safe_two_stage_multilane_scheduler.v` | Multi-lane prefix-safe scheduler using the same safety controller and multi-lane dispatcher. |
| `rtl/iter_fullword_row_start_multilane_scheduler.v` | Multi-lane full-word baseline scheduler using the same multi-lane dispatcher. |
| `tb/tb_iter_prefix_safe_stencil_gate.v` | Checks tail-bound, weighted uncertainty and strict margin comparison. |
| `tb/tb_iter_prefix_safe_issue_controller.v` | Checks row issue pulses for staggered safety depths across four stencil rows. |
| `tb/tb_iter_prefix_safe_two_stage_probe.v` | Checks that prefix-safe rows can be issued before the final digit and records the expected lead-cycle profile. |
| `tb/tb_iter_prefix_safe_row_start_queue.v` | Checks multi-row enqueue, one-row-per-cycle dispatch, backpressure and duplicate issue detection. |
| `tb/tb_iter_prefix_safe_two_stage_scheduler.v` | Checks the integrated prefix-stream to row-start ready/valid path and verifies delayed digit-index metadata alignment. |
| `tb/tb_iter_prefix_safe_scheduler_consumer_stub.v` | Connects the integrated scheduler to the consumer stub and checks command acceptance, completion, backpressure and lead-cycle metadata. |
| `tb/tb_iter_prefix_safe_digit_replay_source.v` | Checks row/digit/term addressing for the packed combinational replay source. |
| `tb/tb_iter_prefix_safe_scheduler_solver_native_lane.v` | Connects the integrated scheduler to the real solver-native digit row engine through the row-lane adapter. |
| `tb/tb_iter_prefix_safe_scheduler_solver_native_replay.v` | Connects scheduler, replay source and real solver-native row lane with non-zero source digits and a reference row-engine checker. |
| `tb/tb_iter_prefix_safe_overlap_perf_probe.v` | Compares prefix-safe overlap against a full-word wait baseline using the same row lane, replay source and row-start queue. |
| `tb/tb_iter_prefix_safe_multilane_overlap_perf_probe.v` | Repeats the local performance probe with parameterized row-lane count. |

## Safety Rule

For aligned radix-2 signed-digit source streams:

$$
\tau_p = 2^{D-1-p}-1
$$

For a stencil row:

$$
E_i(p)=\tau_p\sum_t |a_{i,t}|
$$

The next-iteration prefix issue is allowed only when:

$$
E_i(p) < M_i(p)
$$

where `M_i(p)` is the downstream selector margin.  The comparison is strict:
equal uncertainty and margin is treated as unsafe.

## Test Result

The directed test uses a radius-1 coefficient pattern:

$$
|a_{-1}|, |a_0|, |a_{+1}| = 1,2,1
$$

so:

$$
\sum_t |a_t| = 4
$$

The checked cases are:

| digit index | tail bound | weighted tail | margin | expected |
| ---: | ---: | ---: | ---: | --- |
| `0` | `127` | `508` | `32` | unsafe |
| `4` | `7` | `28` | `32` | safe |
| `4` | `7` | `28` | `28` | unsafe |
| `7` | `0` | `0` | `1` | safe |

The test also instantiates an 8-bit margin variant and drives the coefficient
sum high enough to overflow the output bound.  The RTL must saturate
`weighted_tail_bound` to all ones instead of wrapping, because wraparound could
turn an unsafe prefix into a false safe decision.

Command:

```text
iverilog -g2012 -o /tmp/tb_iter_prefix_safe_stencil_gate.vvp \
  MSDF_iterative_solver/rtl/iter_prefix_safe_stencil_gate.v \
  MSDF_iterative_solver/tb/tb_iter_prefix_safe_stencil_gate.v
vvp /tmp/tb_iter_prefix_safe_stencil_gate.vvp
```

Result:

```text
PASS tb_iter_prefix_safe_stencil_gate
```

## Scheduler-Level Test

The issue-controller test uses four rows with coefficient sums:

$$
2,\;4,\;8,\;16
$$

and margins selected so they become safe at different prefix depths:

| row | coefficient sum | margin | first safe digit |
| ---: | ---: | ---: | ---: |
| `0` | `2` | `65` | `2` |
| `1` | `4` | `33` | `4` |
| `2` | `8` | `9` | `6` |
| `3` | `16` | `1` | `7` |

Command:

```text
iverilog -g2012 -o /tmp/tb_iter_prefix_safe_issue_controller.vvp \
  MSDF_iterative_solver/rtl/iter_prefix_safe_stencil_gate.v \
  MSDF_iterative_solver/rtl/iter_prefix_safe_issue_controller.v \
  MSDF_iterative_solver/tb/tb_iter_prefix_safe_issue_controller.v
vvp /tmp/tb_iter_prefix_safe_issue_controller.vvp
```

Result:

```text
PASS tb_iter_prefix_safe_issue_controller
```

## Two-Stage Probe

The two-stage probe connects the row issue mask to a consumer-side scheduling
boundary.  It still does not execute the next row update, but it quantifies the
cycle lead that prefix-safe streaming can expose before full-word commit.

The directed test uses the same four rows and expects issue at digits:

$$
2,\;4,\;6,\;7
$$

for an 8-digit word.  Therefore the next-iteration consumer could start with
lead cycles:

$$
5,\;3,\;1,\;0
$$

relative to waiting for digit `7`.

Command:

```text
iverilog -g2012 -o /tmp/tb_iter_prefix_safe_two_stage_probe.vvp \
  MSDF_iterative_solver/rtl/iter_prefix_safe_stencil_gate.v \
  MSDF_iterative_solver/rtl/iter_prefix_safe_issue_controller.v \
  MSDF_iterative_solver/rtl/iter_prefix_safe_two_stage_probe.v \
  MSDF_iterative_solver/tb/tb_iter_prefix_safe_two_stage_probe.v
vvp /tmp/tb_iter_prefix_safe_two_stage_probe.vvp
```

Result:

```text
PASS tb_iter_prefix_safe_two_stage_probe
```

The summary counters checked by the test are:

| metric | value |
| --- | ---: |
| `max_lead_cycles` | `5` |
| `early_issue_count` | `3` |
| `all_issued` | `1` |

## Row-Start Queue Test

The row-start queue is the first physical interface toward a next-iteration row
engine.  The prefix-safe controller may assert multiple row issue bits in one
cycle, while a row engine lane usually consumes one start command per cycle.  The
queue stores one pending command per row and drains them with a ready/valid
handshake.

The directed test checks:

- rows `0` and `1` issued in the same digit cycle and drained over two cycles;
- rows `2` and `3` issued in the same digit cycle while consumer ready is high;
- row metadata propagation: `row_id`, `issue_digit_idx`, `lead_cycles`;
- duplicate issue detection for a still-pending row.

Command:

```text
iverilog -g2012 -o /tmp/tb_iter_prefix_safe_row_start_queue.vvp \
  MSDF_iterative_solver/rtl/iter_prefix_safe_row_start_queue.v \
  MSDF_iterative_solver/tb/tb_iter_prefix_safe_row_start_queue.v
vvp /tmp/tb_iter_prefix_safe_row_start_queue.vvp
```

Result:

```text
PASS tb_iter_prefix_safe_row_start_queue
```

## Integrated Scheduler Test

The integrated scheduler is the module intended for the next runtime-top
connection.  It hides the one-cycle alignment between the registered issue pulse
and the digit index that caused that pulse, then exposes a row-engine command:

```text
consumer_valid
consumer_ready
consumer_row_id
consumer_digit_idx
consumer_lead_cycles
```

The directed test holds the consumer not-ready while all four rows become
prefix-safe, then drains the queued starts.  The expected command sequence is:

| dispatch order | row | issue digit | lead cycles |
| ---: | ---: | ---: | ---: |
| `0` | `0` | `2` | `5` |
| `1` | `1` | `4` | `3` |
| `2` | `2` | `6` | `1` |
| `3` | `3` | `7` | `0` |

Command:

```text
iverilog -g2012 -o /tmp/tb_iter_prefix_safe_two_stage_scheduler.vvp \
  MSDF_iterative_solver/rtl/iter_prefix_safe_stencil_gate.v \
  MSDF_iterative_solver/rtl/iter_prefix_safe_issue_controller.v \
  MSDF_iterative_solver/rtl/iter_prefix_safe_row_start_queue.v \
  MSDF_iterative_solver/rtl/iter_prefix_safe_two_stage_scheduler.v \
  MSDF_iterative_solver/tb/tb_iter_prefix_safe_two_stage_scheduler.v
vvp /tmp/tb_iter_prefix_safe_two_stage_scheduler.vvp
```

Result:

```text
PASS tb_iter_prefix_safe_two_stage_scheduler
```

## Consumer Stub End-to-End Test

The consumer stub is a protocol stand-in for the real next-iteration row engine.
It accepts one command when:

```text
consumer_valid && consumer_ready
```

then stays busy for a fixed service latency.  This is intentionally simple: the
purpose is to verify that prefix-safe starts can tolerate row-engine
backpressure before the real digit row engine is connected.

Command:

```text
iverilog -g2012 -o /tmp/tb_iter_prefix_safe_scheduler_consumer_stub.vvp \
  MSDF_iterative_solver/rtl/iter_prefix_safe_stencil_gate.v \
  MSDF_iterative_solver/rtl/iter_prefix_safe_issue_controller.v \
  MSDF_iterative_solver/rtl/iter_prefix_safe_row_start_queue.v \
  MSDF_iterative_solver/rtl/iter_prefix_safe_two_stage_scheduler.v \
  MSDF_iterative_solver/rtl/iter_prefix_safe_consumer_stub.v \
  MSDF_iterative_solver/tb/tb_iter_prefix_safe_scheduler_consumer_stub.v
vvp /tmp/tb_iter_prefix_safe_scheduler_consumer_stub.vvp
```

Result:

```text
PASS tb_iter_prefix_safe_scheduler_consumer_stub
INFO accept=4 done=4 busy=4 backpressure=1 maxlead=5
```

This result means all four prefix-safe row starts reached the consumer, one
cycle of real backpressure was observed, and the earliest row still carried a
five-cycle lead over full-word commit.

## Solver-Native Row-Lane Test

The solver-native row lane is the first connection to the real row digit engine.
When a row-start command is accepted, the lane requests source digits:

$$
0,\;1,\;\ldots,\;D-1
$$

and feeds them into `iter_solver_native_row_digit_engine`.  The test uses zero
source digits, zero coefficients and zero bias so that the expected solver output
stream is all zero.  The purpose is not numerical coverage; it is lifecycle
coverage for:

```text
prefix-safe command
-> source digit request sequence
-> real solver-native row digit engine
-> DATA_WIDTH output digits
-> row done metadata
```

Command:

```text
iverilog -g2012 -o /tmp/tb_iter_prefix_safe_scheduler_solver_native_lane.vvp \
  MSDF_iterative_solver/rtl/iter_prefix_safe_stencil_gate.v \
  MSDF_iterative_solver/rtl/iter_prefix_safe_issue_controller.v \
  MSDF_iterative_solver/rtl/iter_prefix_safe_row_start_queue.v \
  MSDF_iterative_solver/rtl/iter_prefix_safe_two_stage_scheduler.v \
  MSDF_iterative_solver/rtl/iter_prefix_safe_solver_native_row_lane.v \
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
  MSDF_iterative_solver/tb/tb_iter_prefix_safe_scheduler_solver_native_lane.v
vvp /tmp/tb_iter_prefix_safe_scheduler_solver_native_lane.vvp
```

Result:

```text
PASS tb_iter_prefix_safe_scheduler_solver_native_lane
INFO accept=4 done=4 output_digits=32 maxlead=5
```

## Non-Zero Replay Source Test

The replay-source test replaces the zero source stream with a packed
row/digit/term table.  The source is combinational in this checkpoint because
the current row lane consumes source digits in the same cycle as its request.
The table layout is:

```text
table[((row * DATA_WIDTH + digit_idx) * DEGREE) + term]
```

Two checks are used:

- `tb_iter_prefix_safe_digit_replay_source` verifies direct row/digit addressing.
- `tb_iter_prefix_safe_scheduler_solver_native_replay` connects the scheduler,
  replay source and real row lane.  A separate reference
  `iter_solver_native_row_digit_engine` consumes the same replayed source terms
  and checks row-lane output `valid/p/n` every cycle.

Command:

```text
iverilog -g2012 -o /tmp/tb_iter_prefix_safe_digit_replay_source.vvp \
  MSDF_iterative_solver/rtl/iter_prefix_safe_digit_replay_source.v \
  MSDF_iterative_solver/tb/tb_iter_prefix_safe_digit_replay_source.v
vvp /tmp/tb_iter_prefix_safe_digit_replay_source.vvp
```

Result:

```text
PASS tb_iter_prefix_safe_digit_replay_source
```

End-to-end command:

```text
iverilog -g2012 -o /tmp/tb_iter_prefix_safe_scheduler_solver_native_replay.vvp \
  MSDF_iterative_solver/rtl/iter_prefix_safe_stencil_gate.v \
  MSDF_iterative_solver/rtl/iter_prefix_safe_issue_controller.v \
  MSDF_iterative_solver/rtl/iter_prefix_safe_row_start_queue.v \
  MSDF_iterative_solver/rtl/iter_prefix_safe_two_stage_scheduler.v \
  MSDF_iterative_solver/rtl/iter_prefix_safe_digit_replay_source.v \
  MSDF_iterative_solver/rtl/iter_prefix_safe_solver_native_row_lane.v \
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
  MSDF_iterative_solver/tb/tb_iter_prefix_safe_scheduler_solver_native_replay.v
vvp /tmp/tb_iter_prefix_safe_scheduler_solver_native_replay.vvp
```

Result:

```text
PASS tb_iter_prefix_safe_scheduler_solver_native_replay
INFO accept=4 done=4 source_req=32 nonzero_source=24 output_digits=32 maxlead=5
```

## Local Performance Probe

The first performance probe compares two scheduling policies under the same
microarchitecture:

| path | row-start policy | row lane | replay source | row-start queue |
| --- | --- | --- | --- | --- |
| prefix-safe overlap | issue each row when its prefix is safe | same solver-native lane | same packed replay table | same queue |
| full-word wait | issue all rows after digit `DATA_WIDTH-1` | same solver-native lane | same packed replay table | same queue |

This isolates scheduling policy only.  It does not yet prove full runtime Jacobi
speedup.

Command:

```text
iverilog -g2012 -o /tmp/tb_iter_prefix_safe_overlap_perf_probe.vvp \
  MSDF_iterative_solver/rtl/iter_prefix_safe_stencil_gate.v \
  MSDF_iterative_solver/rtl/iter_prefix_safe_issue_controller.v \
  MSDF_iterative_solver/rtl/iter_prefix_safe_row_start_queue.v \
  MSDF_iterative_solver/rtl/iter_prefix_safe_two_stage_scheduler.v \
  MSDF_iterative_solver/rtl/iter_fullword_row_start_scheduler.v \
  MSDF_iterative_solver/rtl/iter_prefix_safe_digit_replay_source.v \
  MSDF_iterative_solver/rtl/iter_prefix_safe_solver_native_row_lane.v \
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
  MSDF_iterative_solver/tb/tb_iter_prefix_safe_overlap_perf_probe.v
vvp /tmp/tb_iter_prefix_safe_overlap_perf_probe.vvp
```

Result:

```text
PASS tb_iter_prefix_safe_overlap_perf_probe
INFO prefix_done_cycle=49 fullword_done_cycle=53 saved_cycles=4 maxlead=5
```

Current interpretation:

$$
\text{local speedup}=\frac{53}{49}=1.0816\times
$$

This proves the cross-iteration prefix-safe mechanism can reduce local schedule
completion time when the next row lane is ready to consume early commands.  It
does not yet prove runtime-level speedup because the runtime top still needs
memory-backed replay, multi-iteration control and real Jacobi counters.

## Multi-Lane Performance Probe

The multi-lane probe repeats the same local comparison with `NUM_LANES=1/2/4`.
Both prefix-safe and full-word paths use the same multi-lane dispatcher and the
same number of solver-native row lanes.

Commands use the same source list as the single-lane probe, with:

```text
-P tb_iter_prefix_safe_multilane_overlap_perf_probe.NUM_LANES=<1|2|4>
```

Results:

| lanes | prefix done | full-word done | saved cycles | local speedup |
| ---: | ---: | ---: | ---: | ---: |
| `1` | `49` | `53` | `4` | `1.0816x` |
| `2` | `29` | `31` | `2` | `1.0690x` |
| `4` | `21` | `20` | `-1` | `0.9524x` |

Interpretation:

- Single-lane benefits because early issue reduces the first row's start wait.
- Two lanes still benefit, but less, because row service overlap already hides
  part of the wait.
- Four lanes loses in this directed case because the full-word baseline can
  launch all rows together immediately after digit `DATA_WIDTH-1`, while the
  prefix-safe path launches rows at staggered safe digits `2/4/6/7`.

This is a useful negative result.  Prefix-safe overlap is not automatically
better with more lanes.  It only helps when the early-safe distribution offsets
the full-word baseline's ability to batch-launch many lanes at the final digit.

## Current Boundary

These modules now reach the real row digit engine and can replay non-zero source
digits from a packed prefix table.  The current verified shell is:


```text
source prefix FIFO
-> iter_prefix_safe_stencil_gate
-> next-iteration row issue mask
-> next-iteration row engine start queue
-> ready/valid row-engine command
-> fixed-latency consumer stub
-> solver-native row-lane adapter
-> combinational prefix replay source
```

The next checkpoint should replace the combinational replay table with a
memory-backed prefix FIFO/state-bank read path and add the necessary one-cycle
response alignment, then compare runtime `mode3 no-overlap` against
`mode3 prefix-overlap`.  The safety rule must remain external and explicit: a
consumer may start early only for rows whose weighted source-tail bound is
strictly below the selector margin.
