# Digit-Stream State Boundary Checkpoint

This checkpoint starts the migration away from the `full digit bridge` path.
It does not remove the existing bridge.  It adds a separate state/replay
boundary where iteration outputs can be committed one digit per cycle.

## Implemented RTL

| file | role |
| --- | --- |
| `rtl/iter_digit_stream_state_ping_pong_bank.v` | ping-pong state bank with digit-wise writes into the inactive bank |
| `rtl/iter_digit_stream_state_replay_top.v` | integration shell: digit-wise commit plus fixed-degree replay from the committed read bank |
| `tb/tb_iter_digit_stream_state_ping_pong_bank.v` | checks host load, digit write, commit swap and second-round writeback |
| `tb/tb_iter_digit_stream_state_replay_top.v` | checks that a digit-written state can immediately feed fixed-degree replay |

## Contract

The new state boundary changes the write-side contract from full-word commit:

```text
row-update -> full state word -> ping-pong state bank
```

to digit-stream commit:

```text
row-update digit stream -> digit-wise ping-pong write -> next-iteration replay
```

The bank still stores each row as a `p/n` rail word because replay needs random
access to `digit_idx`.  The architectural change is that the iteration datapath
no longer needs to reconstruct a full word before writing state.

For MSB-first replay, write cycle `j` maps to:

```text
bit_sel = DATA_WIDTH - 1 - j
state_p[row][bit_sel] <= output_digit_p[row]
state_n[row][bit_sel] <= output_digit_n[row]
```

After `DATA_WIDTH` digit cycles, `commit_swap` promotes the written bank to the
active read bank.

## Validation

```text
PASS tb_iter_digit_stream_state_ping_pong_bank
PASS tb_iter_digit_stream_state_replay_top
```

The tests cover:

- host/debug full-word initialization into bank0;
- MSB-first digit writes into the inactive bank;
- `commit_swap` promotion;
- a second digit-written iteration into the opposite bank;
- fixed-degree replay from a digit-written committed state.

## What This Does Not Solve Yet

This checkpoint only removes the full-word requirement at the state commit and
replay boundary.  It does not yet replace the full-digit row-update bridge.

The remaining work is:

1. make the row-update datapath emit final `x_new` digits directly;
2. replace full-word delta/certification with a digit-stream safe certificate;
3. connect the digit-stream state bank into `iter_dense_small_runtime_top` under
   a new mode, while keeping the current full-digit bridge as regression.

Until those steps are complete, this checkpoint should be described as the
state-boundary migration, not as the final all-digit solver datapath.
