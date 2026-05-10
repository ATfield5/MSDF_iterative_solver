# Prefix Scheduler and Stencil Halo Checkpoint

This checkpoint implements the first two items from the next-stage iterative
solver plan that can be validated without changing the numerical contract:

1. full-digit / prefix scheduler control primitive;
2. radius-1 stencil halo replay ablation.

The runtime solver still keeps the existing manual digit-slice numerical path.
This is intentional: the current row-update core needs row-state assembly and
pipeline-drain control before automatic full-digit replay can safely become the
main runtime mode.

## RTL Changes

| file | role |
| --- | --- |
| `rtl/iter_digit_prefix_scheduler.v` | automatic `digit_idx=0..DATA_WIDTH-1` sweep, active-cluster mask, intra-iteration prefix gating counters |
| `rtl/iter_fixed_degree_state_replay_halo_r1.v` | radius-1 halo digit replay, specialized for prev/current/next cluster windows |
| `rtl/iter_fixed_degree_state_word_replay_halo_r1.v` | radius-1 halo full-word replay for the conventional datapath |
| `rtl/iter_dense_small_ping_pong_top.v` | adds `halo_replay_mode`; `0=generic`, `1=stencil_halo_r1` |
| `rtl/iter_dense_small_runtime_top.v` | propagates `halo_replay_mode`; adds prefix/certification counters |
| `tb/tb_iter_dense_runtime_jacobi32_halo_reg_stencil_r1_multi.v` | functional regression for stencil halo mode |

## Prefix Counters

The runtime top now exposes:

| counter | meaning in current manual mode |
| --- | --- |
| `active_digit_cycles` | cycles with at least one issued row digit |
| `gated_digit_cycles` | currently `0`; reserved for automatic prefix gating |
| `certified_block_count` | cluster-iteration count with `cert_mask=1` |
| `cert_prefix_digit_sum` | sum of certified prefix depths; in manual mode this is `(replay_digit_idx+1)` per certified cluster |

For `jacobi32_halo_reg_multi`, the observed counter line is:

```text
COUNTERS jacobi32_halo_reg_multi total=157 issue=6 cert_wait=48 iter=6 conv_iter=6 cfg_template=8 cfg_cert=8 cfg_state=32 window_load=1 window_busy=10 window_ready=130 active_digit=6 gated_digit=0 cert_blocks=48 cert_sum=528
```

For the cleaned conventional runtime, block-level certification is not the same
as whole-iteration convergence. The golden check was therefore changed to count
`gold_certified_mem[iter,cluster]` directly instead of deriving certified blocks
from `converged_iter * NUM_CLUSTERS`.

## Stencil Halo Replay

The existing generic halo replay accepts a packed source index over a flat
`12`-row source window. The stencil mode keeps the same packed template and
golden vectors, but selects state through a fixed hierarchy:

```text
source index
-> previous/current/next cluster slot
-> local row inside the selected cluster
-> digit or full-word replay
```

This is functionally identical for `HALO_CLUSTER_RADIUS=1`. It is not enabled by
default because routed results are mixed.

## Functional Validation

```text
PASS tb_iter_digit_prefix_scheduler
PASS tb_iter_dense_runtime_jacobi32_halo_reg_stencil_r1_multi
PASS 37/37 testbenches
```

## U55C Routed Results

Common setup:

- Vivado 2023.2
- part `xcu55c-fsvh2892-2L-e`
- OOC route
- target clock `5.000 ns`
- `NUM_ROWS=4`, `DEGREE=4`, `BIT_WIDTH=8`, `DATA_WIDTH=11`
- `halo_source_replay=1`
- `halo_cluster_radius=1`
- `halo_replay_output_register=1`
- `cert_operand_pipeline=1`

| case | replay mode | LUT | FF | DSP | BRAM | WNS ns | dynamic W |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: |
| NC8 | generic halo | 20034 | 8319 | 64 | 9 | +0.474 | 0.896 |
| NC8 | stencil halo r1 | 20056 | 8320 | 64 | 9 | +0.742 | 0.883 |
| NC16 | generic halo | 43015 | 16233 | 128 | 9 | +0.754 | 1.809 |
| NC16 | stencil halo r1 | 43216 | 16234 | 128 | 9 | +0.491 | 1.787 |

Logs:

- `logs/vivado_nc8_generic_halo_route.log`
- `logs/vivado_nc8_stencil_halo_route.log`
- `logs/vivado_nc16_generic_halo_route.log`
- `logs/vivado_nc16_stencil_halo_route.log`

## Decision

`STENCIL_HALO_R1` is an ablation, not the default mainline.

The NC8 result suggests a timing and dynamic-power benefit, but NC16 loses
timing slack and adds LUT. The likely reason is that the hierarchical
prev/current/next structure helps small fanout placement but gives Vivado less
freedom to optimize the larger replicated NC16 source network.

The mainline should therefore keep `halo_replay_mode=0` until a stronger
specialized stencil design removes source-index storage/control entirely rather
than only restructuring the replay mux.

## Follow-Up Checkpoint

The full-digit numerical bridge is now recorded in
`generated/full_digit_bridge_checkpoint.md`.

## Next Engineering Step

The next required item is a safe automatic full-digit runtime mode. It needs:

1. an issue scheduler that accounts for row-update/certification pipeline drain;
2. per-digit or final-digit valid gating, not the current one-digit `iter_done`;
3. row-state assembly that proves the final committed rail word is equivalent
   to the conventional full-word contract;
4. prefix gating enabled only after the above full-digit contract passes.
