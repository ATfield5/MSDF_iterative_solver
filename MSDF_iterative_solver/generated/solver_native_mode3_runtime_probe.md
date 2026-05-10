# Solver-Native Mode3 Runtime Probe

This report records the current `ROW_DATAPATH_MODE=3` runtime status.  Mode3 is the solver-native digit-stream path:

$$
\text{state replay}
\rightarrow
\text{solver-native row digit engine}
\rightarrow
\text{digit-stream state commit}
\rightarrow
\text{inline delta/certification}
\rightarrow
\text{next iteration}
$$

It does not reconstruct a full-word row-update result before committing state.  The committed state is stored as a signed-digit rail trace.

## What Changed

The first Jacobi32 diagnostic used the existing `jacobi32_blockdiag_multi` golden.  That was wrong for mode3 because the old fixture is a one-digit-slice demo.  It computes a row update from only one selected replay digit, while mode3 consumes all `DATA_WIDTH` digits.

A new generator was added:

```text
MSDF_iterative_solver/make_jacobi32_blockdiag_full_digit_runtime_vectors.py
```

It generates a full-digit blockdiag contract:

$$
x_i^{(k+1)} = b_i + \sum_t a_{i,t}x_{src(i,t)}^{(k)}
$$

The current strict local-source vector set is:

```text
MSDF_iterative_solver/generated/rtl_vectors/jacobi32_blockdiag_full_digit_f4
```

It uses `frac_bits=4` so the integer recurrence remains inside the 11-digit signed-digit state range for 6 iterations.  The `frac_bits=6` stress vector is also generated, but it drives the conventional magnitude-rail golden into saturation and is not used as mode3 acceptance.

## RTL Fixes

`iter_solver_native_cluster_delta_cert_top` now receives `i_tail_bound` and adds it to every row delta bound before `block_H` certification.  Before this fix, mode3 state matched the full-digit golden, but `max_error` was consistently lower because the certification tail contribution was missing.

The mode3 testbench now uses `tb/iter_tb_signed_digit_reconstruct.vh`:

```text
signed-digit value = value(p digits) - value(n digits)
```

This is required because mode3 signed-digit rails are numerically comparable to magnitude-rail golden, but not bit-identical.

## Passing Checkpoints

Directed cluster tests:

```text
PASS tb_iter_solver_native_cluster_digit_stream_top iter1=(170,-92) scaled_iter2=(64,694)
PASS tb_iter_solver_native_cluster_delta_cert_top max_error=5 final=(7,-3)
PASS tb_iter_dense_runtime_solver_native_mode3_smoke final_state=(9,2) max_error=5
```

Strict multi-iteration runtime:

```text
ITER multi iter=0 cert_wait_delta=27 conv=1 cont=0 maxerr0=12 state0p=00000400001 state0n=00200000800
ITER multi iter=1 cert_wait_delta=27 conv=1 cont=0 maxerr0=30 state0p=00000800800 state0n=00a00000003
ITER multi iter=2 cert_wait_delta=27 conv=1 cont=0 maxerr0=84 state0p=00000005800 state0n=00203800004
ITER multi iter=3 cert_wait_delta=27 conv=1 cont=0 maxerr0=255 state0p=05400000024 state0n=00006c0c000
ITER multi iter=4 cert_wait_delta=27 conv=1 cont=0 maxerr0=921 state0p=0002a400016 state0n=00e00042800
ITER multi iter=5 cert_wait_delta=27 conv=1 cont=0 maxerr0=2856 state0p=00044ca1000 state0n=3dc000001b9
COUNTERS jacobi32_blockdiag_solver_native_multi total=235 issue=66 cert_wait=126 iter=6 conv_iter=6 cfg_template=8 cfg_cert=8 cfg_state=32 window_load=1 window_busy=10 window_ready=208 active_digit=66 gated_digit=0 cert_blocks=48 cert_sum=528
PASS tb_iter_dense_runtime_jacobi32_blockdiag_solver_native_multi
```

## Halo Replay Probe

Mode3 now reuses the top-level `w_drv_x*` source-select streams instead of using the cluster shell's internal local replay during runtime.  This lets the same registered halo-window replay path used by other datapaths feed the solver-native row digit engine:

$$
\text{cluster signed-digit state banks}
\rightarrow
\text{top-level halo replay}
\rightarrow
\text{solver-native row digit engine}
$$

The strict halo vector set is:

```text
MSDF_iterative_solver/generated/rtl_vectors/jacobi32_halo_conv_f2
```

It uses `frac_bits=2` to avoid saturation in the 11-digit state range for the 6-iteration structural halo checkpoint.

Passing result with the timing-protection halo replay register enabled:

```text
COUNTERS jacobi32_halo_reg_solver_native_multi total=241 issue=66 cert_wait=132 iter=6 conv_iter=6 cfg_template=8 cfg_cert=8 cfg_state=32 window_load=1 window_busy=10 window_ready=214 active_digit=66 gated_digit=0 cert_blocks=48 cert_sum=528
PASS tb_iter_dense_runtime_jacobi32_halo_reg_solver_native_multi
```

The same strict halo workload also passes with `HALO_REPLAY_OUTPUT_REGISTER=0`:

```text
COUNTERS jacobi32_halo_reg_solver_native_multi total=235 issue=66 cert_wait=126 iter=6 conv_iter=6 cfg_template=8 cfg_cert=8 cfg_state=32 window_load=1 window_busy=10 window_ready=208 active_digit=66 gated_digit=0 cert_blocks=48 cert_sum=528
PASS tb_iter_dense_runtime_jacobi32_halo_reg_solver_native_multi
```

The printed label is inherited from the shared halo testbench path; this run is compiled without `JACOBI32_HALO_REG`.  It removes one replay-register cycle per iteration.  It is now the default simulation/synthesis setting because the U55C route remains timing-clean.

The controller now also supports fast-done result bypass.  The last cluster's certification result, `seen_mask` and `cert_mask` are exposed in the same cycle as the final `cluster_valid`, instead of waiting one extra controller register cycle.  With this fair shell optimization enabled, both strict blockdiag and strict halo mode3 checkpoints become:

```text
COUNTERS jacobi32_halo_reg_solver_native_multi total=229 issue=66 cert_wait=120 iter=6 conv_iter=6 cfg_template=8 cfg_cert=8 cfg_state=32 window_load=1 window_busy=10 window_ready=202 active_digit=66 gated_digit=0 cert_blocks=48 cert_sum=528
PASS tb_iter_dense_runtime_jacobi32_halo_reg_solver_native_multi
```

## U55C Routed Checkpoint

The no-register halo-window mode3 runtime was routed out-of-context on U55C at 5 ns:

```text
part        = xcu55c-fsvh2892-2L-e
clock       = 5.000 ns
top         = iter_dense_small_runtime_top
run tag     = solver_native_mode3_halo_nc8_g7s4_noreg_fastdone
checkpoint  = generated/vivado_iter_dense_small_runtime_top_solver_native_mode3_halo_nc8_g7s4_noreg_fastdone
```

Routed result:

| Metric | Value |
| --- | ---: |
| LUT | `26779` |
| FF | `9083` |
| CARRY8 | `472` |
| DSP | `64` |
| BRAM | `9` |
| URAM | `0` |
| WNS | `+0.128 ns` |
| Dynamic power | `0.711 W` |
| Total on-chip power | `3.999 W` |

The run is timing-clean.  The first large improvement was `iter_digit_stream_delta_bound.final_only=1`: the exact runtime only consumes the final full-width delta, so intermediate prefix upper-bound and variable-tail-shift logic is disabled for this path.  That moved the old pre-optimization route from `31897 LUT / 10095 FF / 600 CARRY8 / WNS +0.222 ns / dynamic 0.993 W` to `27102 LUT / 10054 FF / 472 CARRY8 / WNS +0.750 ns / dynamic 0.828 W`, with unchanged cycles.  The certification wrapper input/output bypass reduced halo runtime cycles from `277` to `265`.  The `affine_guard_shift=7, skip_digits=4` sweep reduced registered-halo runtime to `241` cycles, disabling the halo replay output register reduced it to `235`, and fast-done result bypass reduces the current default to `229` cycles while still passing U55C 5 ns route.

The guard/skip sweep is workload-checked against both strict blockdiag and strict halo vectors.  The robust passing pairs are `guard=1/skip=10`, `2/9`, `3/8`, `4/7`, `5/6`, `6/5`, and `7/4`.  More aggressive pairs such as `8/3` and `9/2` pass halo but fail blockdiag, so they are not safe defaults.  The selected default is `guard=7/skip=4`: it is exact on both acceptance workloads and gives the shortest validated runtime so far.

The `sample_width` sweep does not unlock a shorter `skip_digits` setting.  For `sample_width=4..9`, `guard=8/skip=3` still fails the strict blockdiag workload, while `guard=7/skip=4` remains the best robust pair.  This confirms that the remaining drain cycles are not caused by too narrow a residual observation window; they are part of the current solver-native output alignment.

The current NC8 comparison is:

| Runtime path | Total cycles | Issue cycles | Cert wait cycles | LUT | FF | DSP | BRAM | WNS | Dynamic |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| Registered halo online digit-slice path | `157` | `6` | `48` | `20040` | `8237` | `64` | `9` | `+1.125 ns` | `0.916 W` |
| Pipelined conventional DSP-MAC runtime | `157` | `6` | `48` | `24997` | `10236` | `192` | `9` | `+0.059 ns` | `0.877 W` |
| Full-digit bridge reference | `223` | `66` | `114` | `28731` | `15451` | `64` | `9` | `+0.261 ns` | `1.223 W` |
| Solver-native mode3 digit-stream runtime, registered halo | `241` | `66` | `132` | `26009` | `9384` | `64` | `9` | `+0.436 ns` | `0.825 W` |
| Solver-native mode3 digit-stream runtime, no-register halo + fast-done | `229` | `66` | `120` | `26779` | `9083` | `64` | `9` | `+0.128 ns` | `0.711 W` |

This is still not a latency/throughput win against the cleaned conventional runtime: `229` cycles versus `157`.  It does, however, keep the `3x` DSP reduction, reduces FF and dynamic power, and has LUT in the same range as the conventional runtime (`26779` versus `24997`).  Against the full-digit bridge it reduces LUT, FF and dynamic power, but the solver-native digit issue plus drain/certification schedule is still longer.  The valid claim is functional/architectural plus resource/power: the solver iteration boundary can remain digit-stream through state replay, row update, state commit and inline certification.  A raw throughput claim still needs state-ready/certification overlap, not more row-engine micro-tuning.

The routed hierarchy shows the main physical costs:

| Hierarchy item | Representative routed cost |
| --- | ---: |
| Top-level runtime | `26779 LUT / 9083 FF / 64 DSP / 9 BRAM` |
| Template field bank | `1710 LUT / 3361 FF / 8 BRAM` |
| Certification parameter bank | `570 LUT / 739 FF / 1 BRAM` |
| Runtime core | `23757 LUT / 4831 FF / 64 DSP` |
| Halo replay scheduler per cluster | about `1047..2079 LUT` |
| Solver-native cluster datapath per cluster | about `1536..1539 LUT / 539 FF / 8 DSP` |
| Cluster stream per cluster | about `990..993 LUT / 335 FF` |
| Row digit engine per row | about `109..111 LUT / 25 FF` |
| Commit adapter per row | about `45..292 LUT / 12 FF` |
| Digit-stream delta bound per row | about `60..79 LUT / 38 FF` |
| Block-H certification per cluster | `111 LUT / 52 FF / 8 DSP` |

The worst routed timing path is not inside the row digit engine:

```text
source      = delta_bound/o_abs_upper_reg[5]
destination = cluster_cert/cert_engine/r_row_sums0/DSP_OUTPUT_INST/ALU_OUT[0]
delay       = about 4.79 ns
logic level = 12, including 3 CARRY8 and DSP internals
slack       = +0.128 ns
```

So the next optimization target has moved from the row digit engine and commit adapter to the delta/certification boundary.  The row digit engine is small and off the critical path; the timing limiter is now the final `abs(delta)` value entering the `block_H` DSP certification engine.

## Current Claim Boundary

Mode3 now supports both local-source blockdiag and registered radius-1 halo-window full-digit runtime checkpoints.  It proves that the solver iteration boundary can remain digit-stream across 6 committed iterations while consuming neighbor cluster state through the existing halo replay boundary.

It does not yet prove arbitrary global-source solver-native runtime.  That path would require a wider global source mux over signed-digit state and is not the preferred paper route.
