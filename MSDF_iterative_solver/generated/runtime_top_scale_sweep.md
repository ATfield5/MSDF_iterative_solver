# Runtime Top Scale Sweep

This report checks whether the runtime-loadable solver top scales as a realistic memory-backed design when `NUM_TOTAL_CLUSTERS` increases.

The important change in the latest checkpoint is the replacement of one ultra-wide packed payload bank with narrower template/cert field banks plus a standard synchronous RAM wrapper:

- `iter_runtime_sdp_field_ram.v`
- `iter_template_field_bank.v`
- `iter_cert_param_field_bank.v`

The external packed write protocol is unchanged. The internal storage is split by field, then reassembled into the existing active-window payload contract.

## Setup

| Item | Value |
| --- | --- |
| Top | `iter_dense_small_runtime_top` |
| Device | `xcu55c-fsvh2892-2L-e` |
| Vivado | 2023.2 |
| Clock target | 5.000 ns |
| `NUM_CLUSTERS` | 2 |
| `NUM_ROWS` | 4 |
| `DEGREE` | 4 |
| `BIT_WIDTH` | 8 |
| `BOUND_WIDTH` | 13 |
| `COEFF_WIDTH` | 8 |
| `ACC_WIDTH` | 24 |
| `BLOCK_SIZE` | 2 |
| `DATA_WIDTH` | 11 |

The sweep changes only `NUM_TOTAL_CLUSTERS`; the physical active window remains `NUM_CLUSTERS=2`.

## Old Packed-Bank Routed Results

This is the pre-field-bank checkpoint. It used `iter_runtime_word_bank.v` as one packed payload memory.

| `NUM_TOTAL_CLUSTERS` | WNS (ns) | LUT | FF | CARRY8 | DSP | BRAM | URAM | Dynamic W | Total W |
| ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 2 | +1.046 | 4474 | 2912 | 108 | 16 | 0 | 0 | 0.145 | 3.421 |
| 8 | +0.897 | 5511 | 5737 | 108 | 16 | 0 | 0 | 0.153 | 3.428 |
| 16 | +0.815 | 6472 | 9507 | 108 | 16 | 0 | 0 | 0.181 | 3.457 |
| 32 | +0.864 | 8723 | 17075 | 108 | 16 | 0 | 0 | 0.237 | 3.514 |

## Direct Field-Bank Routed Results

This intermediate checkpoint kept the same runtime top protocol and stored template/cert payloads as separate field arrays, but read the arrays directly inside the field-bank modules.

| `NUM_TOTAL_CLUSTERS` | WNS (ns) | LUT | LUTRAM | FF | CARRY8 | DSP | BRAM | URAM | Dynamic W | Total W |
| ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 2 | +0.446 | 4156 | 276 | 1949 | 108 | 16 | 0 | 0 | 0.159 | 3.435 |
| 8 | +1.047 | 4163 | 276 | 1953 | 108 | 16 | 0 | 0 | 0.166 | 3.442 |
| 16 | +1.034 | 4400 | 276 | 1955 | 108 | 16 | 0 | 0 | 0.167 | 3.443 |
| 32 | +1.037 | 4179 | 276 | 1963 | 108 | 16 | 0 | 0 | 0.170 | 3.446 |

## Direct Field-Bank Deep Synth Probe

These larger points were run as synthesis-only storage probes, not route results.

| `NUM_TOTAL_CLUSTERS` | Stage | WNS (ns) | LUT | LUTRAM | FF | CARRY8 | DSP | BRAM | URAM | Dynamic W | Total W |
| ---: | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 64 | synth | +1.437 | 4481 | 544 | 1965 | 108 | 16 | 0 | 0 | 0.172 | 3.448 |
| 128 | synth | +1.437 | 5583 | 1088 | 1967 | 108 | 16 | 0 | 0 | 0.185 | 3.462 |
| 256 | synth | +1.437 | 7188 | 2176 | 1975 | 108 | 16 | 0 | 0 | 0.209 | 3.486 |

## RAM-Wrapper Field-Bank Results

This is the current checkpoint. Each field bank now uses `iter_runtime_sdp_field_ram.v`, a standard synchronous 1W1R RAM wrapper. The active-window assembly happens outside the physical RAM.

| `NUM_TOTAL_CLUSTERS` | Stage | WNS (ns) | LUT | LUTRAM | FF | CARRY8 | DSP | BRAM | URAM | Dynamic W | Total W |
| ---: | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 2 | routed | +0.898 | 3760 | 0 | 2162 | 132 | 16 | 8.5 | 0 | 0.252 | 3.529 |
| 8 | routed | +0.858 | 3766 | 0 | 2170 | 132 | 16 | 8.5 | 0 | 0.256 | 3.534 |
| 16 | routed | +0.860 | 3765 | 0 | 2174 | 132 | 16 | 8.5 | 0 | 0.260 | 3.538 |
| 32 | routed | +0.966 | 3769 | 0 | 2177 | 132 | 16 | 8.5 | 0 | 0.258 | 3.536 |
| 64 | synth | +1.437 | 3780 | 0 | 2181 | 132 | 16 | 8.5 | 0 | 0.247 | 3.525 |
| 128 | synth | +1.437 | 3783 | 0 | 2186 | 132 | 16 | 8.5 | 0 | 0.250 | 3.528 |
| 256 | synth | +1.437 | 3781 | 0 | 2189 | 132 | 16 | 8.5 | 0 | 0.248 | 3.526 |

## Memory-Style Parameter Check

`runtime_mem_style` is now a top-level generic and Tcl environment variable:

- `0`: distributed RAM, useful for tiny regression runs.
- `1`: block RAM, default capacity-mode checkpoint.
- `2`: UltraRAM, reserved for later larger memory experiments.

The routed `NTC=2` check confirms the parameter changes physical storage:

| `runtime_mem_style` | WNS (ns) | LUT | LUTRAM | FF | CARRY8 | DSP | BRAM | URAM | Dynamic W | Total W |
| ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 0 | +1.054 | 4035 | 276 | 2633 | 132 | 16 | 0 | 0 | 0.215 | 3.492 |
| 1 | +0.898 | 3760 | 0 | 2162 | 132 | 16 | 8.5 | 0 | 0.252 | 3.529 |

## Interpretation

The field-bank refactor fixes the first scaling problem. FF no longer grows linearly with `NUM_TOTAL_CLUSTERS`; it stays near `2k` from `NTC=2` to `NTC=256`. That means the previous wide-word runtime bank was physically wrong for scale.

The direct field-bank version still did not create a BRAM-backed capacity model. Vivado emitted `Synth 8-6849` warnings and implemented the field arrays as LUTRAM. For `NTC<=32`, LUTRAM cost was nearly flat because one LUTRAM primitive can cover the shallow depth. For `NTC=64/128/256`, LUTRAM grew with depth while FF remained flat.

The RAM-wrapper version fixes the second storage problem for this checkpoint. Vivado now infers BRAM (`8.5` Block RAM tiles), LUTRAM drops to zero, and LUT/FF stay almost flat through `NTC=256`. This is now a credible BRAM-backed runtime-loader/window-cache boundary.

The cost is that BRAM mode reserves the same BRAM footprint for tiny instances. That is now handled by `runtime_mem_style`: use style `0` for small regression and style `1` for scalable capacity-mode evaluation.

## Timing Note

At the routed `NTC=2` RAM-wrapper checkpoint, the worst path is still inside the solver/certification datapath, from a row-update output register into the `cert_engine` DSP input stage. The runtime field banks, RAM wrapper, loader, and window cache are not the routed critical path.

## Verification

- All local `iverilog` testbenches pass.
- Xilinx 2023.2 `xvlog/xelab` passes for `tb_iter_dense_small_runtime_top`.
- U55C 5 ns OOC route passes for `NTC=2/8/16/32` RAM-wrapper field-bank checkpoints.
- U55C 5 ns OOC synthesis passes for `NTC=64/128/256` RAM-wrapper field-bank storage probes.
- Local runtime top counters now cover config writes, state writes, accepted window loads, window busy cycles, and window ready cycles.

## Logs

The route logs and Vivado run directories are intentionally gitignored:

```text
MSDF_iterative_solver/logs/iter_dense_small_runtime_top_fieldbank_ntc2_route.log
MSDF_iterative_solver/logs/iter_dense_small_runtime_top_fieldbank_ntc8_route.log
MSDF_iterative_solver/logs/iter_dense_small_runtime_top_fieldbank_ntc16_route.log
MSDF_iterative_solver/logs/iter_dense_small_runtime_top_fieldbank_ntc32_route.log
MSDF_iterative_solver/logs/iter_dense_small_runtime_top_fieldbank_ntc64_synth.log
MSDF_iterative_solver/logs/iter_dense_small_runtime_top_fieldbank_ntc128_synth.log
MSDF_iterative_solver/logs/iter_dense_small_runtime_top_fieldbank_ntc256_synth.log
MSDF_iterative_solver/logs/iter_dense_small_runtime_top_ramwrap_ntc2_route.log
MSDF_iterative_solver/logs/iter_dense_small_runtime_top_ramwrap_ntc8_route.log
MSDF_iterative_solver/logs/iter_dense_small_runtime_top_ramwrap_ntc16_route.log
MSDF_iterative_solver/logs/iter_dense_small_runtime_top_ramwrap_ntc32_route.log
MSDF_iterative_solver/logs/iter_dense_small_runtime_top_ramwrap_ntc64_synth.log
MSDF_iterative_solver/logs/iter_dense_small_runtime_top_ramwrap_ntc128_synth.log
MSDF_iterative_solver/logs/iter_dense_small_runtime_top_ramwrap_ntc256_synth.log
MSDF_iterative_solver/logs/iter_dense_small_runtime_top_mem0_ntc2_route.log
MSDF_iterative_solver/logs/iter_dense_small_runtime_top_mem1_ntc2_route.log
MSDF_iterative_solver/logs/iter_dense_small_runtime_top_mem1_ntc8_route.log
MSDF_iterative_solver/logs/iter_dense_small_runtime_top_mem1_ntc16_route.log
MSDF_iterative_solver/logs/iter_dense_small_runtime_top_mem1_ntc32_route.log
MSDF_iterative_solver/logs/iter_dense_small_runtime_top_mem1_ntc64_synth.log
MSDF_iterative_solver/logs/iter_dense_small_runtime_top_mem1_ntc128_synth.log
MSDF_iterative_solver/logs/iter_dense_small_runtime_top_mem1_ntc256_synth.log
MSDF_iterative_solver/generated/vivado_iter_dense_small_runtime_top_*route*/
```
