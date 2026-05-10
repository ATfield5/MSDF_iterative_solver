# Prior Online P2 Adapter Smoke Report

This report validates the first same-shell prior-online adapter boundaries.
`iter_prior_online_mma8_row_kernel` maps the current fixed-degree row
digit interface onto the original `MSDF_MUL_ADD_8` operator.
`iter_prior_online_mma8_word_assembler` adds the explicit full-word
assembly boundary needed by the P2 prior-online baseline.
`iter_prior_online_mma8_row_cluster_delta_cert` adds row-parallel
assembly, full-word delta, and cluster certification.
`ROW_DATAPATH_MODE=5` connects that wrapper into the same
PageRank runtime shell as a relaxed same-shell smoke.
`tb_iter_prior_online_mma8_semantics` records the native
operator scaling so the P2 baseline does not silently become
a different arithmetic operation.
`tb_iter_dense_runtime_pagerank32_global_prior_fractional_multi`
uses a prior-compatible fractional fixture and bounded LSB
tolerance for original online selection rounding.

## Row-Kernel Adapter Icarus Output

```text
COUNTERS prior_mma8_row_kernel out=83 unit=1 frac=77 z_p_trace=0000000000000040 z_n_trace=ffffffffffffff80
PASS tb_iter_prior_online_mma8_row_kernel
MSDF_iterative_solver/tb/tb_iter_prior_online_mma8_row_kernel.v:120: $finish called at 915000 (1ps)
```

## Word-Assembler Icarus Output

```text
COUNTERS prior_mma8_word_assembler cycles=23 captured=11 sum_p=010 sum_n=004
PASS tb_iter_prior_online_mma8_word_assembler
MSDF_iterative_solver/tb/tb_iter_prior_online_mma8_word_assembler.v:90: $finish called at 275000 (1ps)
```

## Cluster Wrapper Icarus Output

```text
COUNTERS prior_mma8_cluster cycles=26 max_error=8 certified=1 sum0p=001 sum0n=000
PASS tb_iter_prior_online_mma8_row_cluster_delta_cert
MSDF_iterative_solver/tb/tb_iter_prior_online_mma8_row_cluster_delta_cert.v:132: $finish called at 305000 (1ps)
```

## Operator Semantics Icarus Output

```text
SEM label=0 state=0 coeff=0 bias=1 out_p=1 out_n=0 out_signed=1 cycles=23 captured=11
SEM label=1 state=1 coeff=1 bias=0 out_p=0 out_n=0 out_signed=0 cycles=23 captured=11
SEM label=2 state=1 coeff=4 bias=0 out_p=0 out_n=0 out_signed=0 cycles=23 captured=11
SEM label=3 state=4 coeff=4 bias=0 out_p=0 out_n=0 out_signed=0 cycles=23 captured=11
SEM label=4 state=8 coeff=4 bias=1 out_p=1 out_n=0 out_signed=1 cycles=23 captured=11
SEM label=5 state=1024 coeff=1024 bias=0 out_p=512 out_n=256 out_signed=256 cycles=23 captured=11
SEM label=6 state=1024 coeff=512 bias=0 out_p=256 out_n=128 out_signed=128 cycles=23 captured=11
SEM label=7 state=512 coeff=512 bias=0 out_p=128 out_n=64 out_signed=64 cycles=23 captured=11
SEM label=8 state=2047 coeff=2047 bias=0 out_p=0 out_n=1024 out_signed=-1024 cycles=23 captured=11
PASS tb_iter_prior_online_mma8_semantics
MSDF_iterative_solver/tb/tb_iter_prior_online_mma8_semantics.v:161: $finish called at 2585000 (1ps)
```

## Runtime-Shell P2 Smoke Icarus Output

```text
ITER multi iter=0 cert_wait_delta=27 conv=1 cont=0 maxerr0=8 state0p=00200400801 state0n=00000000000
ITER multi iter=1 cert_wait_delta=27 conv=1 cont=0 maxerr0=20 state0p=00a01402805 state0n=00000000000
ITER multi iter=2 cert_wait_delta=27 conv=0 cont=1 maxerr0=68 state0p=02a0540a815 state0n=00000000000
ITER multi iter=3 cert_wait_delta=27 conv=0 cont=1 maxerr0=260 state0p=0aa1542a855 state0n=00000000000
COUNTERS pagerank32_global_prior_online_multi total=211 issue=4 cert_wait=108 iter=4 conv_iter=4 cfg_template=8 cfg_cert=8 cfg_state=32 window_load=1 window_busy=10 window_ready=184 active_digit=4 gated_digit=0 cert_blocks=32 cert_sum=352
PASS tb_iter_dense_runtime_pagerank32_global_prior_online_multi
./MSDF_iterative_solver/tb/tb_iter_dense_runtime_jacobi32_blockdiag_multi.v:1017: $finish called at 2131000 (1ps)
```

## Prior-Compatible Fractional Runtime Icarus Output

```text
ITER multi iter=0 cert_wait_delta=31 conv=0 cont=1 maxerr0=156 state0p=00980260098026 state0n=00000000000000
ITER multi iter=1 cert_wait_delta=31 conv=0 cont=1 maxerr0=68 state0p=00d803600d8036 state0n=00000000000000
ITER multi iter=2 cert_wait_delta=31 conv=0 cont=1 maxerr0=36 state0p=00f803e00f803e state0n=00000000000000
ITER multi iter=3 cert_wait_delta=31 conv=0 cont=1 maxerr0=20 state0p=01080420108042 state0n=00000000000000
COUNTERS pagerank32_global_prior_fractional_multi total=227 issue=4 cert_wait=124 iter=4 conv_iter=0 cfg_template=8 cfg_cert=8 cfg_state=32 window_load=1 window_busy=10 window_ready=200 active_digit=4 gated_digit=0 cert_blocks=16 cert_sum=224
PASS tb_iter_dense_runtime_pagerank32_global_prior_fractional_multi
./MSDF_iterative_solver/tb/tb_iter_dense_runtime_jacobi32_blockdiag_multi.v:1017: $finish called at 2291000 (1ps)
```

## Status

- Adapter compile/smoke: PASS.
- Word assembler compile/smoke: PASS.
- Cluster delta/certification wrapper smoke: PASS.
- Operator semantics sweep: PASS.
- Runtime shell integration smoke: PASS.
- Prior-compatible fractional runtime: PASS.
- Runtime-shell smoke uses relaxed numerical checks; it proves
  scheduling/state/certification integration, not final PageRank
  numerical equivalence.
- Fractional runtime uses `BIT_WIDTH=11`, `DATA_WIDTH=14`,
  fraction-only capture, and `<=4 LSB` tolerance for the
  prior operator's online selection/rounding behavior.
- The original operator is not a plain integer MAC. The observed
  product path follows the operator's fractional online scaling
  and delay, so strict P2 requires a prior-compatible fixed-point
  fixture or an explicit bias/product alignment bridge.
