# U55C OOC Checkpoint: Param-Bank Iterative Solver Top

This checkpoint validates the first file-driven, memory-backed iterative-solver top after adding a pipelined `block_H` certification path.

## Configuration

| Item | Value |
| --- | --- |
| Top | `iter_dense_small_param_bank_top` |
| Device | `xcu55c-fsvh2892-2L-e` |
| Vivado | 2023.2 |
| Clock target | 5.000 ns |
| Matrix fixture | `blockdiag8` |
| `NUM_TOTAL_CLUSTERS` | 2 |
| `NUM_CLUSTERS` | 2 |
| `NUM_ROWS` | 4 |
| `DEGREE` | 4 |
| `BIT_WIDTH` | 8 |
| `BOUND_WIDTH` | 13 |
| `COEFF_WIDTH` | 8 |
| `ACC_WIDTH` | 24 |
| `BLOCK_SIZE` | 2 |
| `DATA_WIDTH` | 11 |

## Routed Result

| Metric | Routed value |
| --- | ---: |
| WNS | +0.964 ns |
| TNS | 0.000 ns |
| failing endpoints | 0 |
| CLB LUTs | 858 |
| CLB registers | 508 |
| CARRY8 | 80 |
| DSP48E2 | 16 |
| BRAM / URAM | 0 / 0 |
| Total on-chip power | 3.337 W |
| Dynamic power | 0.063 W |
| Device static power | 3.274 W |

The worst routed path is now from the ping-pong state-bank read select through row-local delta/bound logic into the first registered H-cert row-sum stage. The previous single-cycle path from state replay through row update, block-H weighted sum, max/compare, and iteration controller has been removed.

## RTL Change Behind This Checkpoint

`online_row_cluster_block_cert` now registers block bounds before H-certification. `block_h_cert_engine` is now internally pipelined:

1. Stage 1 computes and registers per-row weighted block sums.
2. Stage 2 computes the max row error and compares it with `eta`.
3. The wrapper registers the final cluster certification output before it reaches the iteration controller.

This adds fixed certification latency but keeps throughput compatible with one issued cluster result stream. It is the correct production direction because convergence certification should not be on the same cycle as state-bank read, row update, and controller commit.

## Verification

All 22 local `iverilog` testbenches under `MSDF_iterative_solver/tb/` pass after the pipeline change.

The final Vivado route log is intentionally not tracked:

```text
MSDF_iterative_solver/logs/iter_dense_small_param_bank_top_ooc_route_final.log
```

The generated Vivado implementation directory is also gitignored:

```text
MSDF_iterative_solver/generated/vivado_iter_dense_small_param_bank_top_partxcu55c-fsvh2892-2L-e_ntc2_nc2_nr4_deg4_bw8_bound13_cw8_acc24_blk2_data11_ooc1_clk5.000_route1/
```

## Remaining Caveats

The OOC route reports expected port-routing warnings because no `HD.PARTPIN_LOCS` are assigned. These warnings limit exported partial-routing accuracy for top-level ports, but they do not indicate a failing internal datapath. A full shell-integrated run must eventually add realistic interface constraints.
