# Runtime-Equivalent Conventional Baseline Report

This report records the first runtime-equivalent conventional FPGA baseline for
the iterative-solver mainline.

## Scope

This checkpoint keeps the same runtime boundary as the online halo solver:

```text
runtime template loader
-> template window
-> cert parameter loader
-> ping-pong state banks
-> halo-window source replay
-> row-update datapath
-> block_H certification
-> iteration controller
```

The only intended datapath change is:

```text
online digit-serial row update
-> conventional full-word signed fixed-point DSP-MAC row update
```

This is therefore much closer to a fair `FPGA-B2` comparison than the earlier
datapath-only baseline in `conv_jacobi_datapath_baseline_report.md`.

## RTL Changes

| file | role |
| --- | --- |
| `rtl/iter_fixed_degree_state_word_replay.v` | full-word source replay for conventional DSP-MAC rows |
| `rtl/conv_signed_row_update_delta_slice_pipe.v` | 3-stage pipelined signed DSP-MAC row-update + delta slice |
| `rtl/iter_dense_small_ping_pong_top.v` | added `row_datapath_mode=1` conventional branch |
| `rtl/iter_dense_small_runtime_top.v` | passes conventional datapath and MAC pipeline parameters |
| `synth_iter_dense_small_runtime_top.tcl` | adds `MSDF_ROW_DATAPATH_MODE`, `MSDF_MAC_ACC_WIDTH`, `MSDF_CONV_MAC_PIPELINE` |
| `make_jacobi32_halo_conv_runtime_vectors.py` | full-word conventional runtime golden generator |
| `tb/tb_iter_dense_runtime_jacobi32_halo_reg_conv_multi.v` | 6-iteration halo-window conventional runtime testbench |

Default `row_datapath_mode=0` preserves the online solver path. The new
conventional runtime path is enabled with:

```bash
MSDF_ROW_DATAPATH_MODE=1
MSDF_CONV_MAC_PIPELINE=1
```

## Why The Pipeline Is Required

The first unpipelined runtime-equivalent conventional attempt failed timing:

| case | WNS | LUT | FF | DSP | BRAM | Dynamic W |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| conventional runtime NC8, no MAC pipeline | `-3.411 ns` | `39456` | `10872` | `192` | `9` | `1.393` |

The critical path was:

```text
full-word replay register
-> signed value reconstruction
-> DSP multiply / accumulation
-> delta absolute-bound logic
-> o_abs_upper register
```

This is the important correction to the earlier datapath-only result: a
standalone conventional row array can look route-clean because it does not carry
the real registered runtime replay boundary. Once it is connected to the same
state/halo/runtime shell, a practical conventional baseline needs explicit MAC
pipeline stages.

The pipelined baseline uses:

```text
stage 1: rail reconstruction + DEGREE products
stage 2: product sum + bias
stage 3: delta, absolute bound, and rail-coded state writeback
```

## Functional And Cycle Validation

The conventional runtime path now has a dedicated full-word golden flow:

```text
same halo template/cert memh
-> same runtime loader
-> same ping-pong state banks
-> same registered halo-window source replay
-> conventional full-word row update
-> same block_H certification
-> same iteration controller
```

Targeted Icarus result:

```text
PASS tb_iter_dense_runtime_jacobi32_halo_reg_conv_multi
COUNTERS jacobi32_halo_reg_conv_multi total=157 issue=6 cert_wait=48 iter=6 conv_iter=1 cfg_template=8 cfg_cert=8 cfg_state=32 window_load=1 window_busy=10 window_ready=130
```

The old online digit-slice halo checkpoint now reports:

```text
COUNTERS jacobi32_halo_multi total=151 issue=6 cert_wait=42 iter=6 conv_iter=6 cfg_template=8 cfg_cert=8 cfg_state=32 window_load=1 window_busy=10 window_ready=124
```

Both paths use the same fast-done controller/result bypass, so the cycle comparison does not rely on an extra controller register in either direction.

Cycle interpretation for this fixed 6-iteration fixture:

| path | total cycles | issue cycles | cert_wait cycles | converged-count counter |
| --- | ---: | ---: | ---: | ---: |
| old online digit-slice halo NC8 | `151` | `6` | `42` | `6` |
| conventional runtime NC8, pipelined MAC | `157` | `6` | `48` | `1` |

The `+6` cycle total difference is exactly the extra `+1` certification-wait
cycle per iteration from the 3-stage conventional MAC path after removing the
shared controller tail. `conv_iter` is a
counter of iterations whose certification flag was true, not a termination
cycle. The conventional full-word fixed-point observable semantics diverge from
the online one after the first update, so `conv_iter=1` is expected for this
golden; it is not a simulation failure.

Full local Icarus regression after adding the conventional runtime test and
cleaning the conventional debug replay fanout:

```text
PASS 35/35 testbenches
```

## U55C Routed Results

All routed results use U55C `xcu55c-fsvh2892-2L-e`, Vivado 2023.2, OOC route,
and 5 ns target.

The conventional rows below are the cleaned paper-baseline runs. In
`row_datapath_mode=1`, the online digit debug outputs are tied off so Vivado can
remove the online-only `iter_fixed_degree_state_replay` tree. The conventional
path now retains only the full-word state replay, DSP-MAC row update, shared
state banks, shared block-H certification, and shared runtime controller.

| path | active rows | WNS | LUT | FF | CARRY8 | DSP | BRAM | Dynamic W | Total W |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| online halo NC8 | `32` | `+1.125 ns` | `20040` | `8237` | `396` | `64` | `9` | `0.916` | `4.208` |
| conventional runtime NC8, clean pipelined MAC + fast-done | `32` | `+0.059 ns` | `24997` | `10236` | `984` | `192` | `9` | `0.877` | `4.168` |
| online halo NC16 + operand pipeline | `64` | `+0.646 ns` | `41935` | `16158` | `748` | `128` | `9` | `1.713` | `5.021` |
| conventional runtime NC16, clean pipelined MAC + operand pipeline | `64` | `+0.474 ns` | `55265` | `25657` | `1900` | `384` | `9` | `1.859` | `5.171` |

Relative to the runtime-equivalent conventional baseline:

| metric | NC8 online / conventional | NC16 online / conventional |
| --- | ---: | ---: |
| LUT | `0.771x` | `0.759x` |
| FF | `0.635x` | `0.630x` |
| DSP | `0.333x` | `0.333x` |
| Dynamic power | `0.938x` | `0.921x` |
| Total power | `0.985x` | `0.971x` |
| WNS advantage | `+0.440 ns` | `+0.172 ns` |

The previous conventional routed checkpoints reported `36974` LUT for NC8 and
`77491` LUT for NC16. Those runs were functionally valid but not resource-clean:
their top-level online digit debug ports kept the online digit replay tree
observable in conventional mode. After cleanup, the hierarchical reports show:

| path | halo digit replay | halo word replay | row MAC slices |
| --- | ---: | ---: | ---: |
| clean conventional NC8 | `0 LUT` | `7744 LUT` | `8041 LUT / 128 DSP` |
| clean conventional NC16 | `0 LUT` | `16192 LUT` | `15270 LUT / 256 DSP` |

## Fairness Audit

The routed resource comparison is fair for a **runtime-shell hardware
checkpoint**, not yet for a final numerical-algorithm claim.

Fair parts:

- Same FPGA part: U55C `xcu55c-fsvh2892-2L-e`.
- Same Vivado version and OOC route flow: Vivado 2023.2, 5 ns target,
  `MSDF_RUN_ROUTE=1`.
- Same physical shape for each row of the table: `NC8 = 32` active rows,
  `NC16 = 64` active rows, `4` rows/cluster, degree `4`.
- Same runtime boundary: loader, template/cert banks, ping-pong state banks,
  registered halo-window replay, block-H certification and iteration
  controller.
- Same NC16 timing-closure option after the latest correction:
  both NC16 rows use `cert_operand_pipeline=1`.

Remaining caveats:

- The online checkpoint validates the digit-slice RTL-observable contract,
  while the conventional checkpoint validates a full-word signed fixed-point
  contract. They share the same runtime shell, but they are not yet a
  bit-equivalent solver for final numerical convergence claims.
- Power is vectorless Vivado power, so it is useful as a routed proxy but not a
  board-level energy number.
- The current workload is fixed-degree banded Jacobi. The result should not be
  generalized to arbitrary sparse matrices until more source schedules and
  matrix sizes are covered.
- NC8 has measured solver-level cycle counters for both paths. NC16 currently
  has routed resource/timing data; a parameterized NC16 cycle test should be
  added before using NC16 throughput as a measured result.

### Unit-Count / Parallelism Audit

The current NC8 comparison has equal row-level and cluster-level parallelism:

| item | online halo NC8 | conventional runtime NC8 | fairness status |
| --- | ---: | ---: | --- |
| physical clusters | `8` | `8` | same |
| rows per cluster | `4` | `4` | same |
| active row lanes | `32` | `32` | same |
| matrix degree per row | `4` | `4` | same |
| row issue width | `32 rows/cycle` | `32 rows/cycle` | same |
| halo source window | `12 rows/cluster` | `12 rows/cluster` | same |
| source index width | `4` bits | `4` bits | same |
| block-H products | `8/cluster = 64 total` | `8/cluster = 64 total` | same |
| row-update multiply units | `0 DSP` | `4/row = 128 DSP total` | intentionally different architecture |
| total DSP | `64` | `192` | certification DSPs are equal; extra DSPs are conventional row MAC |

For NC16 the same relation holds:

| item | online halo NC16 | conventional runtime NC16 | fairness status |
| --- | ---: | ---: | --- |
| active row lanes | `64` | `64` | same |
| block-H products | `128` | `128` | same |
| conventional row MAC DSPs | `0` | `256` | intentionally different architecture |
| total DSP | `128` | `384` | certification DSPs are equal; extra DSPs are conventional row MAC |

This is the intended fair comparison level. We do **not** equalize DSP count by
adding unused DSPs to the online design or by removing conventional row
multipliers. The designs are compared at the same solver shell, same row
parallelism and same matrix degree. The difference is the row-update
microarchitecture:

```text
online:
  digit {-1,0,+1}
  -> constant-coefficient contribution {+coeff, 0, -coeff}
  -> online parallel-adder reduction
  -> prefix delta/certification

conventional:
  full rail-coded state word
  -> signed reconstruction
  -> full-word coefficient * state DSP products
  -> product sum + bias
  -> full-word delta/certification
```

Therefore, the DSP reduction is not a weakened baseline; it is the direct
consequence of changing the operator boundary from full-word MAC to
digit-driven constant-coefficient contribution. What remains not equivalent is
the numerical contract: current online tests validate a digit-slice observable
solver contract, while conventional tests validate a full-word observable
contract.

### Pipeline Audit

| path | row-update pipeline | certification pipeline | measured NC8 wait / iteration |
| --- | --- | --- | ---: |
| online halo NC8 | contribution combinational + registered POA4 + registered bias output, effectively `2` row-update cycles | block-bound stage + cert engine | `8` cycles |
| conventional runtime NC8 | product register + sum/bias register + delta/writeback register, `3` row-update cycles | same block-bound stage + cert engine | `9` cycles |

The conventional MAC pipeline is not an artificial handicap: without it, the
runtime-equivalent conventional NC8 route fails timing at `-3.411 ns`. The
pipeline is the minimum practical correction that lets the conventional path
meet the same 5 ns target. It costs exactly one extra measured
certification-wait cycle per solver iteration in the NC8 fixture.

### What Would Be Fully Algorithm-Equivalent

A fully algorithm-equivalent comparison would require one of these stricter
baselines:

| stricter baseline | purpose | current status |
| --- | --- | --- |
| full-digit online solver | run all required digits and assemble the same full-word state contract as conventional | not implemented |
| prefix-aware conventional solver | let conventional stop/check on the same prefix-certification semantics as online | not implemented |
| common external mathematical oracle | compare both against the same quantized Jacobi fixed-point model, not only RTL-observable memh | partially available through separate Python models, not integrated into this route report |

Until one of these exists, the claim should be phrased as:

```text
At equal runtime shell, row-lane parallelism and matrix degree, the
digit-driven online row-update architecture reduces DSP/LUT/FF/power and
slightly improves measured NC8 iteration throughput versus a practical
pipelined full-word DSP-MAC row-update baseline.
```

It should **not** be phrased as:

```text
For an identical full-precision Jacobi numerical contract, online arithmetic is
already proven faster than conventional fixed-point MAC.
```

## Throughput

The runtime counter `o_total_cycles` includes configuration, template/cert
loads, state loads and window readiness time. It is useful for an end-to-end
testbench, but it is not the best steady-state throughput metric. For
steady-state solver throughput, the relevant measured counter is the per-round
`cert_wait_delta`.

Measured NC8, 5 ns target:

| path | active rows | measured cycles / iteration | latency / iteration | steady row-update throughput |
| --- | ---: | ---: | ---: | ---: |
| old online digit-slice halo NC8 | `32` | `7` | `35 ns` | `4.571 rows/cycle = 914 M rows/s` |
| conventional runtime NC8, pipelined MAC | `32` | `8` | `40 ns` | `4.000 rows/cycle = 800 M rows/s` |

Measured steady-state throughput speedup:

```text
(32 / 7) / (32 / 8) = 1.143x
```

Including the entire 6-iteration testbench overhead:

| path | row-updates | total cycles | effective throughput at 200 MHz |
| --- | ---: | ---: | ---: |
| old online digit-slice halo NC8 | `192` | `151` | `254.3 M rows/s` |
| conventional runtime NC8, pipelined MAC | `192` | `157` | `244.6 M rows/s` |

End-to-end testbench throughput speedup:

```text
(192 / 151) / (192 / 157) = 1.040x
```

This means the current throughput advantage exists but is modest. The resource
and power advantage is much stronger than the measured NC8 throughput advantage.
For a final paper table, throughput should be reported in two rows:
steady-state `rows/s` from per-iteration counters, and full-test `rows/s`
including runtime setup overhead.

## Where The Architecture Actually Improves

The improvement is architectural, but it is specific:

1. **Narrow source-replay boundary.**
   The online path replays one signed digit per source term. The conventional
   path must replay full `DATA_WIDTH` rail-coded source words per term. This
   reduces row-update operand width and cuts the expensive path from replay
   registers into row arithmetic.

2. **Constant-coefficient digit contribution instead of row MAC.**
   Because the input digit is only `-1/0/+1`, multiplying by a fixed
   coefficient becomes `+coeff`, `0`, or `-coeff` selection. This removes the
   row-update DSP array while keeping the same number of row lanes.

3. **Integrated row-update and delta/certification boundary.**
   The online path keeps the row-update output in the same rail/prefix domain
   used by delta bounds. The conventional path reconstructs signed full words,
   computes a full MAC result, then converts back to rail-coded writeback and
   absolute bounds.

4. **Certification is shared, not a hidden advantage.**
   Both paths use the same block-H certification engine and therefore the same
   certification DSP count. The advantage comes before certification, in the
   row-update/replay boundary.

5. **Timing closure pressure moves.**
   In the conventional path, timing pressure is full-word replay -> signed
   reconstruction -> MAC/delta. In the online path, that full-word MAC boundary
   does not exist; the remaining bottlenecks are template/window routing and
   certification operand placement.

## Current Interpretation

This is the first point where the mainline has a defensible hardware result
against a conventional FPGA baseline under the same runtime shell.

What the result supports:

- The online solver is not only a DSP-saving design. Under the same halo/runtime
  shell, it also uses less LUT, less FF, less dynamic power, and has better WNS.
- The earlier concern that the online design only wins against a weak baseline
  is partially addressed. The baseline now has the same state banks, halo replay,
  template/cert loader and iteration controller.
- The main architectural advantage is no longer just "online arithmetic avoids
  DSP". It is that digit-level row update keeps the runtime replay boundary
  narrow, while the conventional full-word path has to move and pipeline much
  wider source terms.

What still needs caution:

- The conventional path now has a dedicated full-word golden and solver-level
  cycle test, but the golden is the RTL-observable rail-coded fixed-point
  contract, not a floating-point Jacobi reference.
- The conventional path uses a 3-stage MAC pipeline, so final cycle accounting
  includes the extra row-update latency. On the current 6-iteration NC8 fixture
  this adds `6` total cycles versus the online registered halo path.
- The current workload remains fixed-degree banded Jacobi. The claim should not
  generalize to arbitrary sparse matrices until the source schedule and memory
  model are extended.

## Progress Status

Current status changes from:

```text
GO for solver development;
NO_GO for conventional FPGA superiority claim.
```

to:

```text
GO for writing a serious solver-level architecture claim;
GO for the current routed conventional comparison checkpoint;
NO_GO for final paper claim until workload scaling and report automation are broader.
```

The strongest claim currently supported is:

```text
For the same U55C halo-window runtime shell and fixed-degree Jacobi workload,
the online iteration-fused datapath routes at 5 ns with lower LUT, FF, DSP and
dynamic power than a pipelined conventional DSP-MAC row-update baseline.
```
