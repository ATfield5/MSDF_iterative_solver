# Conventional Jacobi Datapath Baseline Report

This report records the first routed `FPGA-B2` conventional FPGA datapath
checkpoint for the iterative-solver mainline.

## Scope

This is a **datapath lower-bound baseline**, not a final end-to-end runtime
solver baseline.

| item | value |
| --- | --- |
| Top module | `conv_jacobi_datapath_array_top` |
| Row-update style | signed fixed-point DSP-MAC + adder tree |
| Certification | same `online_row_cluster_block_cert` / `block_H` certification path |
| Primary shape | `8` clusters x `4` rows/cluster = `32` active rows |
| Scaling shape | `16` clusters x `4` rows/cluster = `64` active rows |
| Degree | `4` |
| State input | reconstructed signed binary value from rail-coded `{state_p,state_n}` |
| Coefficient input | reconstructed signed binary value from rail-coded `{coeff_p,coeff_n}` |
| Bias input | signed binary fixed-point |
| Device | U55C, `xcu55c-fsvh2892-2L-e` |
| Tool | Vivado 2023.2 |
| Clock target | `5.000 ns` |

The implemented conventional row update is:

$$
y_i=\sum_{k=0}^{d-1} a_{ik}x_{s(i,k)}+b_i
$$

followed by the same block certification fabric already used by the online
solver path. This intentionally isolates the cost of a conventional DSP-MAC
row datapath and avoids mixing it with runtime loader, state-bank, and
halo-window routing costs.

## RTL Added

| file | role |
| --- | --- |
| `rtl/conv_signed_row_update_delta_slice.v` | one conventional signed row-update and delta-bound slice |
| `rtl/conv_row_cluster_delta_cert.v` | row cluster wrapper plus shared block certification |
| `rtl/conv_jacobi_datapath_array_top.v` | replicated conventional datapath array |
| `tb/tb_conv_jacobi_datapath_array_top.v` | smoke test for request/valid/certification handshake |
| `synth_conv_jacobi_datapath_array_top.tcl` | U55C OOC synth/route script |

## Functional Check

Targeted smoke test:

```text
PASS tb_conv_jacobi_datapath_array_top
```

Full local regression after adding the conventional datapath:

```text
PASS all 32 testbenches
```

This test verifies datapath handshake and certification response shape. It is
not yet a numerical equivalence test against the runtime Jacobi golden vectors.

## U55C Routed Results

Command shape:

```bash
MSDF_NUM_CLUSTERS=8 \
MSDF_NUM_ROWS=4 \
MSDF_DEGREE=4 \
MSDF_BIT_WIDTH=8 \
MSDF_DATA_WIDTH=11 \
MSDF_BIAS_WIDTH=10 \
MSDF_BOUND_WIDTH=13 \
MSDF_COEFF_WIDTH=8 \
MSDF_ACC_WIDTH=24 \
MSDF_MAC_ACC_WIDTH=32 \
MSDF_BLOCK_SIZE=2 \
MSDF_CLK_PERIOD_NS=5.000 \
MSDF_OOC=1 \
MSDF_RUN_ROUTE=1 \
vivado -mode batch -source MSDF_iterative_solver/synth_conv_jacobi_datapath_array_top.tcl
```

| datapath | active rows | WNS | LUT | FF | CARRY8 | DSP | BRAM | Dynamic W | Total W |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| conventional DSP-MAC NC8 | `32` | `+0.820 ns` | `9039` | `2049` | `800` | `192` | `0` | `0.367` | `3.648` |
| conventional DSP-MAC NC16 | `64` | `+0.664 ns` | `18080` | `4097` | `1600` | `384` | `0` | `0.741` | `4.030` |

The conventional datapath scales almost exactly linearly from NC8 to NC16:
`2.00x` LUT, `2.00x` FF, `2.00x` CARRY8, `2.00x` DSP and `2.02x` dynamic
power. This is expected because the module is a replicated full-word row
datapath without shared runtime storage.

## Timing

The critical path is not the row DSP-MAC itself. For both NC8 and NC16, the
routed worst path is inside the shared `block_H` certification path:

```text
cluster_cert/cert_engine/r_row_sums0/DSP_OUTPUT_INST
-> cluster_cert/cert_engine/o_certified_reg
```

| datapath | WNS | data path delay | logic | route | logic levels |
| --- | ---: | ---: | ---: | ---: | ---: |
| conventional DSP-MAC NC8 | `+0.820 ns` | `4.130 ns` | `1.298 ns` | `2.832 ns` | `11` |
| conventional DSP-MAC NC16 | `+0.664 ns` | `4.286 ns` | `1.372 ns` | `2.914 ns` | `11` |

The same certification path also became the scaling bottleneck in the current
online halo solver. This means the next fair comparison must separate row-update
datapath cost from certification cost.

## Relation To Current Online Solver

Current best online halo-window runtime checkpoints:

| path | active rows | WNS | LUT | FF | CARRY8 | DSP | BRAM | Dynamic W | Total W |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| online halo NC8 | `32` | `+1.125 ns` | `20040` | `8237` | `396` | `64` | `9.0` | `0.916` | `4.208` |
| online halo NC16 + operand pipeline | `64` | `+0.646 ns` | `41935` | `16158` | `748` | `128` | `9.0` | `1.713` | `5.021` |

This table is not a fair final apples-to-apples comparison, because the online
halo top includes runtime loader, state banks, template banks, window cache,
halo replay, scheduler and counters, while the conventional datapath baseline
excludes all those runtime-system costs.

Still, it gives a useful lower-bound signal:

| metric | NC8 online halo vs conventional datapath | NC16 online halo vs conventional datapath |
| --- | ---: | ---: |
| DSP reduction | `3.00x` fewer DSP | `3.00x` fewer DSP |
| LUT overhead | `2.22x` more LUT | `2.32x` more LUT |
| FF overhead | `4.02x` more FF | `3.94x` more FF |
| Dynamic power | `2.50x` higher | `2.31x` higher |
| BRAM | online uses `9` BRAM, conventional datapath uses `0` |

The current online architecture therefore has a solid DSP-saving story, but it
does **not** yet have a routed conventional-FPGA dominance story. The missing
piece is a runtime-equivalent conventional baseline with the same loader,
state banks, source replay and solver control.

## Current Progress Assessment

What is already strong:

- Solver-level closed-loop Jacobi runtime works for multi-iteration tests.
- Raw banded `32x32` Jacobi with cross-cluster dependencies works through
  halo-window replay.
- Halo-window replay is a real architectural win over full global-source
  replay: it cuts the expensive source mux and preserves the workload contract.
- U55C route is healthy at 32 and 64 active rows.
- Compared with cascaded online arithmetic, the iteration-fused formulation is
  already justified by the cycle/resource model.

What this datapath-only report does not prove:

- The current conventional baseline is a datapath lower bound, so it is too
  favorable to conventional hardware for final claims, but it is also not
  functionally equivalent to the runtime solver yet.
- The online top pays control/storage/routing overhead for runtime flexibility;
  a fair comparison must include that same overhead in the conventional path.

## Follow-Up Runtime Baseline

The runtime-equivalent baseline has now been added in
`runtime_conventional_baseline_report.md`. It keeps:

```text
same runtime loader
same state banks
same halo-window source replay
same block_H certification
same iteration controller
different row-update datapath only:
  online fused row update vs conventional signed DSP-MAC row update
```

That follow-up changes the current position to:

```text
GO for solver-level architecture development;
PARTIAL_GO for routed conventional comparison;
NO_GO for final paper claim until conventional numerical golden/cycle validation is done.
```
