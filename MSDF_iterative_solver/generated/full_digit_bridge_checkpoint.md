# Full-Digit Runtime Checkpoint

This checkpoint adds a conservative full-digit numerical bridge and connects it
to the runtime solver through the automatic digit replay scheduler.

## Why This Exists

The older runtime solver path was a manual digit-slice checkpoint: each
iteration replayed one selected state digit and committed the corresponding
digit-slice row-update output. That contract was useful for bring-up, but it was
not equivalent to a conventional full-word Jacobi row update.

The new `AUTO_FULL_DIGIT=1` path uses `iter_digit_prefix_scheduler` to issue
`digit_idx=0..DATA_WIDTH-1` automatically, feeds those digits into the full-digit
cluster bridge, and commits only after the bridge/certification pipeline has
drained.

## Implemented RTL

| file | role |
| --- | --- |
| `rtl/iter_digit_serial_full_row_update_delta_slice.v` | consumes all source state digits MSB-first, uses a pipelined Horner-style signed accumulator, emits rail-coded `sum_p/sum_n` and row delta bound |
| `rtl/iter_digit_serial_full_row_cluster_delta_cert.v` | instantiates `NUM_ROWS` full-digit row slices and reuses the existing `block_H` certification engine |
| `rtl/iter_digit_prefix_scheduler.v` | issues automatic full-word digit replay; prefix gating remains disabled in the current runtime checkpoint |
| `rtl/iter_dense_small_runtime_top.v` | selects automatic scheduler control when `auto_full_digit=1` |
| `rtl/iter_dense_small_ping_pong_top.v` | adds `row_datapath_mode=2` to route replayed digit streams into the full-digit cluster bridge |
| `tb/tb_iter_digit_serial_full_row_update_delta_slice.v` | checks row-level equivalence against the conventional full-word formula |
| `tb/tb_iter_digit_serial_full_row_cluster_delta_cert.v` | checks cluster-level row outputs, block bounds, max error and certification |
| `tb/tb_iter_dense_runtime_jacobi32_halo_reg_full_digit_multi.v` | checks 6-iteration runtime replay/commit against the full-word conventional golden |

## Numerical Contract

For each row, the bridge consumes one digit per source term per cycle:

```text
state digit stream -> signed shift-add accumulator -> full-word rail output
```

The datapath uses an MSB-first Horner recurrence instead of a
`digit_idx`-controlled dynamic left shift:

```text
acc[j+1] = (acc[j] << 1) + Σ_t coeff_t * digit_t[j]
sum      = acc[DATA_WIDTH] + bias
```

The accumulated value is:

```text
sum = bias + Σ_t coeff_t * state_t
```

where each source state is reconstructed from its rail-coded digit stream:

```text
state_t = state_p_t - state_n_t
```

The output rail format matches the conventional runtime baseline:

```text
sum >= 0: sum_p = saturate(abs(sum)), sum_n = 0
sum <  0: sum_p = 0,                  sum_n = saturate(abs(sum))
```

The delta bound is computed against the old committed state:

```text
abs_upper = abs(sum - old_state) + tail_bound
```

## Important Limitation

The full-digit bridge intentionally uses a signed binary accumulator internally.
It is a correctness bridge, not the final paper datapath.

The final online datapath should replace this binary accumulator with a
lower-cost online residual / signed-digit accumulation path. The value of this
checkpoint is that it gives the automatic digit scheduler a safe numerical
target before prefix gating is enabled.

## Timing-Oriented Fixes

The first routed attempt exposed two non-paper datapath problems:

```text
dynamic digit_idx shift -> large LUT/CARRY path
template bank -> row slice arithmetic -> abs_upper register
```

The final checkpoint fixes those issues with four concrete microarchitecture
changes:

1. replace per-cycle dynamic shift by the Horner recurrence above;
2. register template/state/control inputs inside each full-digit row slice;
3. split final sum generation from `rail/abs_upper` generation;
4. guard prefix-bound hardware with `enable_prefix_cert` so the timing-clean
   main path does not retain the expensive residual-bound sideband.

This adds fixed pipeline latency to the bridge, but preserves one accepted digit
per cycle and makes the NC8 U55C route meet 5 ns.

## Runtime Contract

When `AUTO_FULL_DIGIT=1`, the testbench no longer manually pulses one selected
digit per iteration. The runtime top owns replay scheduling:

```text
start iteration
-> issue DATA_WIDTH digit cycles
-> wait for full-digit row-update/certification drain
-> commit assembled state
-> replay committed state in the next iteration
```

For the current `DATA_WIDTH=11`, `NUM_ITERS=6` halo-regression fixture, the
expected issue count is:

```text
6 iterations * 11 digits = 66 issue cycles
```

## Validation

```text
PASS tb_iter_digit_serial_full_row_update_delta_slice
PASS tb_iter_digit_serial_full_row_cluster_delta_cert
PASS tb_iter_dense_runtime_jacobi32_halo_reg_full_digit_multi
PASS tb_iter_dense_runtime_jacobi32_halo_reg_full_digit_prefix_multi
SUMMARY PASS 41/41
```

Representative runtime counter line:

```text
COUNTERS jacobi32_halo_reg_full_digit_multi total=223 issue=66 cert_wait=114 iter=6 conv_iter=1 cfg_template=8 cfg_cert=8 cfg_state=32 window_load=1 window_busy=10 window_ready=196 active_digit=66 gated_digit=0 cert_blocks=13 cert_sum=143
```

## U55C Routed Checkpoint

Command shape:

```bash
MSDF_RUN_TAG=auto_fd_nc8_halo \
MSDF_NUM_TOTAL_CLUSTERS=8 \
MSDF_NUM_CLUSTERS=8 \
MSDF_SRC_IDX_WIDTH=4 \
MSDF_GLOBAL_SOURCE_REPLAY=0 \
MSDF_HALO_SOURCE_REPLAY=1 \
MSDF_HALO_CLUSTER_RADIUS=1 \
MSDF_HALO_REPLAY_OUTPUT_REGISTER=1 \
MSDF_RUNTIME_MEM_STYLE=1 \
MSDF_ROW_DATAPATH_MODE=2 \
MSDF_AUTO_FULL_DIGIT=1 \
MSDF_AUTO_PREFIX_GATING=0 \
MSDF_CLK_PERIOD_NS=5.000 \
MSDF_OOC=1 \
MSDF_RUN_ROUTE=1 \
vivado -mode batch -source MSDF_iterative_solver/synth_iter_dense_small_runtime_top.tcl
```

Routed output:

| item | value |
| --- | ---: |
| Device | U55C `xcu55c-fsvh2892-2L-e` |
| Clock target | `5.000 ns` |
| WNS | `+0.261 ns` |
| TNS | `0.000 ns` |
| LUT | `28731` |
| FF | `15451` |
| CARRY8 | `1176` |
| DSP | `64` |
| BRAM | `9` |
| Dynamic power | `1.223 W` |
| Total on-chip power | `4.521 W` |
| Log | `logs/iter_dense_small_runtime_top_auto_full_digit_nc8_route.log` |
| Report dir | `generated/vivado_iter_dense_small_runtime_top_auto_fd_nc8_halo/` |

Worst routed path after the fixes is local to the full-digit row slice:

```text
r_bias_p_stage -> o_abs_upper_reg/CE
Data path delay = 4.636 ns
```

This is now a routed, timing-clean correctness checkpoint for automatic
full-digit replay. It is not yet the final claim path because the signed binary
accumulator still costs more latency than the intended low-cost online residual
datapath.

## Prefix-Gating Ablation

The prefix sideband was implemented and tested, but it is not a mainline
optimization yet.

Functional result with `AUTO_PREFIX_GATING=1`:

```text
COUNTERS jacobi32_halo_reg_full_digit_prefix_multi total=223 issue=66 cert_wait=114 iter=6 conv_iter=1 cfg_template=8 cfg_cert=8 cfg_state=32 window_load=1 window_busy=10 window_ready=196 active_digit=66 gated_digit=0 cert_blocks=13 cert_sum=143
PASS tb_iter_dense_runtime_jacobi32_halo_reg_full_digit_prefix_multi
```

This fixture shows no cycle benefit: `gated_digit=0`.

Routed result with prefix-bound hardware enabled:

| item | value |
| --- | ---: |
| WNS | `-1.185 ns` |
| LUT | `36845` |
| FF | `16294` |
| CARRY8 | `1592` |
| DSP | `224` |
| BRAM | `9` |
| Dynamic power | `1.550 W` |

The failed critical path starts at `r_digit_idx_stage` and goes through the
conservative residual-bound calculation into `o_abs_upper/o_prefix_abs_upper`.
Vivado maps the residual-bound multiply into DSPs, which explains the DSP jump
from `64` to `224`.

Conclusion: this safe prefix-bound implementation is a negative ablation for
the current workload. Prefix gating must not be written as a performance claim
until a cheaper bound or a workload with real `gated_digit_cycles` is found.

## Next Step

Use this routed full-digit mode as the safe baseline for the next optimization.
Do not enable the current prefix-bound implementation by default. The next
useful direction is either a cheaper bound that avoids the residual multiplier,
or a workload/model where prefix certification actually gates digits.
