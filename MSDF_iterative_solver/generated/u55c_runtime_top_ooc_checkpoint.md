# U55C OOC Checkpoint: Runtime-Loadable Solver Top

This checkpoint validates the current runtime-loadable solver top. Compared with `iter_dense_small_param_bank_top`, this top replaces pure `$readmemh` parameter banks with host-loadable payload banks, adds a window-cache load phase, exposes ping-pong state loading, and adds basic solver counters.

The latest checkpoint uses field-split runtime storage with a standard synchronous RAM wrapper:

- `iter_runtime_sdp_field_ram.v`
- `iter_template_field_bank.v`
- `iter_cert_param_field_bank.v`

The external configuration protocol still writes packed template/cert payloads. Internally, the payloads are stored by field and reassembled into the active window before scheduler/unpack/core execution.

## Configuration

| Item | Value |
| --- | --- |
| Top | `iter_dense_small_runtime_top` |
| Device | `xcu55c-fsvh2892-2L-e` |
| Vivado | 2023.2 |
| Clock target | 5.000 ns |
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
| `runtime_mem_style` | 1, block RAM |

## Routed Result

| Metric | Routed value |
| --- | ---: |
| WNS | +0.898 ns |
| TNS | 0.000 ns |
| failing endpoints | 0 |
| CLB LUTs | 3760 |
| LUT as Memory | 0 |
| CLB registers | 2162 |
| CARRY8 | 132 |
| DSP48E2 | 16 |
| BRAM / URAM | 8.5 / 0 |
| Total on-chip power | 3.529 W |
| Dynamic power | 0.252 W |
| Device static power | 3.277 W |

The worst routed path remains in the solver/certification datapath, from a row-update output register into the `cert_engine` DSP input stage. The runtime field banks, RAM wrapper, loader, window cache, and counters do not become the critical path at this small checkpoint.

## Interface Changes

The runtime storage uses a synchronous-read window cache:

1. Host writes packed payloads through `i_cfg_*`.
2. Host pulses `i_load_window`.
3. The bank loads `NUM_CLUSTERS` payloads from `i_base_cluster_idx` into active-window registers.
4. `o_window_valid` marks the cached active window as ready for scheduler/unpack/core execution.

`iter_dense_small_runtime_top` also exposes:

- `i_cfg_state_we/i_cfg_state_*` for ping-pong state-bank initialization.
- `o_total_cycles`
- `o_issue_cycles`
- `o_cert_wait_cycles`
- `o_iter_count`
- `o_converged_iter`
- `o_cfg_template_write_count`
- `o_cfg_cert_write_count`
- `o_cfg_state_write_count`
- `o_window_load_count`
- `o_window_busy_cycles`
- `o_window_ready_cycles`

## Interpretation

The RAM-wrapper field-bank version uses less LUT/FF than the earlier packed runtime bank at `NUM_TOTAL_CLUSTERS=2`, and the scale sweep shows that FF no longer grows linearly with total cluster count. This validates the storage-interface direction.

BRAM is now physically present. Vivado infers `8.5` Block RAM tiles for the template/cert field storage, with LUTRAM reduced to zero. The design is now a valid BRAM-backed runtime-loader/window-cache checkpoint for the small specialized solver stack. Tiny regression instances can set `runtime_mem_style=0` to force distributed RAM; scalable capacity-mode runs should keep the default `runtime_mem_style=1`.

## Verification

- All local `iverilog` testbenches pass.
- Xilinx 2023.2 `xvlog/xelab` passes for `tb_iter_dense_small_runtime_top`.
- U55C 5 ns OOC route passes.
- The larger `NUM_TOTAL_CLUSTERS` sweep is recorded in [`runtime_top_scale_sweep.md`](./runtime_top_scale_sweep.md).

The final route log and generated Vivado directory are intentionally gitignored:

```text
MSDF_iterative_solver/logs/iter_dense_small_runtime_top_mem1_ntc2_route.log
MSDF_iterative_solver/generated/vivado_iter_dense_small_runtime_top_partxcu55c-fsvh2892-2L-e_ntc2_nc2_nr4_deg4_bw8_bound13_cw8_acc24_blk2_data11_mem1_ooc1_clk5.000_route1/
```

## Next Step

Do not return to one packed runtime word. The next implementation step should move toward larger Jacobi cluster sweeps using the RAM-wrapper field-bank boundary and the new loader/window counters.
