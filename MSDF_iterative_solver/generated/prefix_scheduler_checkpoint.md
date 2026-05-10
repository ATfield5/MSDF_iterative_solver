# Prefix Digit Scheduler Checkpoint

This checkpoint implements the first control primitive for moving the runtime
solver from a manual digit-slice fixture toward an automatic full-digit replay
flow.

## Implemented

- Added `iter_digit_prefix_scheduler`.
- Generates an automatic `digit_idx = 0..DATA_WIDTH-1` replay sweep.
- Masks issued rows by active cluster.
- Supports safe intra-iteration prefix gating: a cluster can be disabled for
  the remaining digits only after it reports `valid && certified`.
- Adds local counters for:
  - `active_digit_cycles`
  - `gated_digit_cycles`
  - `cert_prefix_digit_sum`
  - `certified_block_count`

## Current Boundary

The scheduler is intentionally standalone in this checkpoint. The current
runtime solver still uses the manual digit-slice contract for numerical tests.
This avoids incorrectly treating the existing prefix row-update slice as a
complete full-word solver before row-output assembly is added.

The runtime top now exposes the same counter family in manual mode, so solver
tests can already report block-level certification depth:

- `active_digit_cycles`
- `gated_digit_cycles`
- `cert_prefix_digit_sum`
- `certified_block_count`

The next implementation step is to connect this scheduler to the runtime top
through an optional auto mode and add the missing row-state assembly, pipeline
drain, and final-valid gating.

## Validation

```text
PASS tb_iter_digit_prefix_scheduler
PASS 37/37 testbenches
```

The combined prefix/stencil checkpoint is recorded in
`generated/prefix_scheduler_stencil_halo_checkpoint.md`.
