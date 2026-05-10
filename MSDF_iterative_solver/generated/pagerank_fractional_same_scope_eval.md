# PageRank Fractional Same-Scope Evaluation

This report compares strict fractional PageRank runtime entries.
All entries use `pagerank32_global_prior_fractional`: same graph,
same coefficient/bias quantization, same product scaling target,
same runtime loader/state/controller, and same global L1 decision.

Cycle policy: the performance table uses `compute cycles = issue + cert_wait`.
Configuration, state preload, window load, and idle/control overhead are reported separately.

| entry | pass | compute cycles | input/issue | main+output wait | observed total | notes |
| --- | ---: | ---: | ---: | ---: | ---: | --- |
| P2 prior-online fractional | yes | 128 | 4 | 124 | 227 | original `MSDF_MUL_ADD_8`, fraction-only capture, <=4 LSB tolerance |
| P2-proxy full-digit fractional | yes | 136 | 56 | 80 | 183 | digit-serial bridge, per-term rounded product shift |
| P3 prior digit-stream fractional | yes | 168 | 56 | 112 | 215 | prior operator output digits committed directly to state bank |
| P3 prior K=4 wavefront fractional | yes | 70 | 14 | 56 | 150 | four prior-operator stages cascaded; final delta is x^(k+4)-x^(k+3) |
| P4 conventional fractional | yes | 36 | 4 | 32 | 135 | DSP-MAC with round((state*coeff)/2^DATA_WIDTH) |
| P4 timing-clean conventional fractional | yes | 44 | 4 | 40 | 143 | global replay register + product-rounding pipeline |

Non-compute overhead and setup/window activity counters:

The setup/window fields are raw activity counters, not a mutually exclusive cycle partition.

| entry | non-compute overhead | cfg_template | cfg_cert | cfg_state | window_load | window_busy |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| P2 prior-online fractional | 99 | 8 | 8 | 32 | 1 | 10 |
| P2-proxy full-digit fractional | 47 | 8 | 8 | 32 | 1 | 10 |
| P3 prior digit-stream fractional | 47 | 8 | 8 | 32 | 1 | 10 |
| P3 prior K=4 wavefront fractional | 80 | 8 | 8 | 32 | 1 | 10 |
| P4 conventional fractional | 99 | 8 | 8 | 32 | 1 | 10 |
| P4 timing-clean conventional fractional | 99 | 8 | 8 | 32 | 1 | 10 |

Derived compute-cycle ratios:

- P2/P4 compute-cycle ratio: `3.556x`.
- P2-proxy/P4 compute-cycle ratio: `3.778x`.
- P3-prior-stream/P4 compute-cycle ratio: `4.667x`.
- P3-prior-wavefront/P4 compute-cycle ratio: `1.944x`.
- P3-prior-wavefront/P4 timing-clean compute-cycle ratio: `1.591x`.
- P3-prior-stream/P3-prior-wavefront compute speedup: `2.400x`.
- P2/P4 cert-wait ratio: `3.875x`.
- P3-prior-wavefront/P4 timing-clean observed-total ratio, including overhead, is `1.049x`.
- Common setup writes: `48` cycles (`cfg_template + cfg_cert + cfg_state`).
- P4 conventional uses four one-cycle iteration launches: `issue=4`, `cert_wait=32`.
- P4 timing-clean conventional uses the same launches but adds pipeline wait: `issue=4`, `cert_wait=40`.
- P3 prior K=4 wavefront uses one 14-digit launch: `issue=14`, `cert_wait=56`.

Interpretation: this is a strict same-fixture baseline check, not a
final architecture claim.  It shows the original prior-online operator
boundary is slower than the clean conventional DSP-MAC runtime under
this PageRank fractional contract.  The new solver-level digit-stream
architecture must therefore beat P4, not only P2.
The K=4 prior wavefront is the first same-shell result where
the original prior operator benefits from solver-level digit
streaming; it fuses four PageRank iterations into one runtime
super-step while preserving last-step certification semantics.
The remaining gap to P4 is mainly backend latency: the fused
prior path reduces iteration-boundary restart cost but still pays
a longer prior-operator feed/capture/flush and last-delta wait.

## P2 Icarus Output

```text
ITER multi iter=0 cert_wait_delta=31 conv=0 cont=1 maxerr0=156 state0p=00980260098026 state0n=00000000000000
ITER multi iter=1 cert_wait_delta=31 conv=0 cont=1 maxerr0=68 state0p=00d803600d8036 state0n=00000000000000
ITER multi iter=2 cert_wait_delta=31 conv=0 cont=1 maxerr0=36 state0p=00f803e00f803e state0n=00000000000000
ITER multi iter=3 cert_wait_delta=31 conv=0 cont=1 maxerr0=20 state0p=01080420108042 state0n=00000000000000
COUNTERS pagerank32_global_prior_fractional_multi total=227 issue=4 cert_wait=124 iter=4 conv_iter=0 cfg_template=8 cfg_cert=8 cfg_state=32 window_load=1 window_busy=10 window_ready=200 active_digit=4 gated_digit=0 cert_blocks=16 cert_sum=224
PASS tb_iter_dense_runtime_pagerank32_global_prior_fractional_multi
./MSDF_iterative_solver/tb/tb_iter_dense_runtime_jacobi32_blockdiag_multi.v:1084: $finish called at 2291000 (1ps)
```

## P2-Proxy Full-Digit Icarus Output

```text
ITER multi iter=0 cert_wait_delta=20 conv=0 cont=1 maxerr0=156 state0p=00980260098026 state0n=00000000000000
ITER multi iter=1 cert_wait_delta=20 conv=0 cont=1 maxerr0=68 state0p=00d803600d8036 state0n=00000000000000
ITER multi iter=2 cert_wait_delta=20 conv=0 cont=1 maxerr0=36 state0p=00f803e00f803e state0n=00000000000000
ITER multi iter=3 cert_wait_delta=20 conv=0 cont=1 maxerr0=20 state0p=01080420108042 state0n=00000000000000
COUNTERS pagerank32_global_full_digit_fractional_multi total=183 issue=56 cert_wait=80 iter=4 conv_iter=0 cfg_template=8 cfg_cert=8 cfg_state=32 window_load=1 window_busy=10 window_ready=156 active_digit=56 gated_digit=0 cert_blocks=16 cert_sum=224
PASS tb_iter_dense_runtime_pagerank32_global_full_digit_fractional_multi
./MSDF_iterative_solver/tb/tb_iter_dense_runtime_jacobi32_blockdiag_multi.v:1084: $finish called at 1851000 (1ps)
```

## P3 Prior Digit-Stream Icarus Output

```text
ITER multi iter=0 cert_wait_delta=28 conv=0 cont=1 maxerr0=156 state0p=00980260098026 state0n=00000000000000
ITER multi iter=1 cert_wait_delta=28 conv=0 cont=1 maxerr0=68 state0p=00d803600d8036 state0n=00000000000000
ITER multi iter=2 cert_wait_delta=28 conv=0 cont=1 maxerr0=36 state0p=00f803e00f803e state0n=00000000000000
ITER multi iter=3 cert_wait_delta=28 conv=0 cont=1 maxerr0=20 state0p=01080420108042 state0n=00000000000000
COUNTERS pagerank32_global_prior_digit_stream_fractional_multi total=215 issue=56 cert_wait=112 iter=4 conv_iter=0 cfg_template=8 cfg_cert=8 cfg_state=32 window_load=1 window_busy=10 window_ready=188 active_digit=56 gated_digit=0 cert_blocks=16 cert_sum=224
PASS tb_iter_dense_runtime_pagerank32_global_prior_digit_stream_fractional_multi
./MSDF_iterative_solver/tb/tb_iter_dense_runtime_jacobi32_blockdiag_multi.v:1084: $finish called at 2171000 (1ps)
```

## P3 Prior K=4 Wavefront Icarus Output

```text
ITER multi iter=0 cert_wait_delta=56 conv=0 cont=1 maxerr0=20 state0p=01080420108042 state0n=00000000000000
COUNTERS pagerank32_global_prior_wavefront_fractional total=150 issue=14 cert_wait=56 iter=1 conv_iter=0 cfg_template=8 cfg_cert=8 cfg_state=32 window_load=1 window_busy=10 window_ready=123 active_digit=14 gated_digit=0 cert_blocks=8 cert_sum=112
PASS tb_iter_dense_runtime_pagerank32_global_prior_wavefront_fractional
./MSDF_iterative_solver/tb/tb_iter_dense_runtime_jacobi32_blockdiag_multi.v:1084: $finish called at 1521000 (1ps)
```

## P4 Icarus Output

```text
ITER multi iter=0 cert_wait_delta=8 conv=0 cont=1 maxerr0=156 state0p=00980260098026 state0n=00000000000000
ITER multi iter=1 cert_wait_delta=8 conv=0 cont=1 maxerr0=68 state0p=00d803600d8036 state0n=00000000000000
ITER multi iter=2 cert_wait_delta=8 conv=0 cont=1 maxerr0=36 state0p=00f803e00f803e state0n=00000000000000
ITER multi iter=3 cert_wait_delta=8 conv=0 cont=1 maxerr0=20 state0p=01080420108042 state0n=00000000000000
COUNTERS pagerank32_global_conv_fractional_multi total=135 issue=4 cert_wait=32 iter=4 conv_iter=0 cfg_template=8 cfg_cert=8 cfg_state=32 window_load=1 window_busy=10 window_ready=108 active_digit=4 gated_digit=0 cert_blocks=16 cert_sum=224
PASS tb_iter_dense_runtime_pagerank32_global_conv_fractional_multi
./MSDF_iterative_solver/tb/tb_iter_dense_runtime_jacobi32_blockdiag_multi.v:1084: $finish called at 1371000 (1ps)
```

## P4 Timing-Clean Icarus Output

```text
ITER multi iter=0 cert_wait_delta=10 conv=0 cont=1 maxerr0=156 state0p=00980260098026 state0n=00000000000000
ITER multi iter=1 cert_wait_delta=10 conv=0 cont=1 maxerr0=68 state0p=00d803600d8036 state0n=00000000000000
ITER multi iter=2 cert_wait_delta=10 conv=0 cont=1 maxerr0=36 state0p=00f803e00f803e state0n=00000000000000
ITER multi iter=3 cert_wait_delta=10 conv=0 cont=1 maxerr0=20 state0p=01080420108042 state0n=00000000000000
COUNTERS pagerank32_global_conv_fractional_multi total=143 issue=4 cert_wait=40 iter=4 conv_iter=0 cfg_template=8 cfg_cert=8 cfg_state=32 window_load=1 window_busy=10 window_ready=116 active_digit=4 gated_digit=0 cert_blocks=16 cert_sum=224
PASS tb_iter_dense_runtime_pagerank32_global_conv_fractional_multi
./MSDF_iterative_solver/tb/tb_iter_dense_runtime_jacobi32_blockdiag_multi.v:1084: $finish called at 1451000 (1ps)
```
