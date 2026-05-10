# Solver-Native Fractional Gap

本文档记录 P3 solver-native digit-stream 路径接入 `pagerank32_global_prior_fractional` fixture 时暴露出的数值差距。结论是：当前 mode3 还不能作为 P2/P4 fractional 同口径主结果。

## Probe

手工 probe 命令：

```bash
iverilog -g2012 -I MSDF_iterative_solver/tb \
  -DPAGERANK32_GLOBAL \
  -DPAGERANK32_SOLVER_NATIVE_RUNTIME \
  -DPAGERANK32_PRIOR_FRACTIONAL \
  -DJACOBI32_BIT_WIDTH_VALUE=11 \
  -DJACOBI32_NUM_ITERS_VALUE=4 \
  -DJACOBI32_NUM_GOLD_ITERS_VALUE=4 \
  -o /tmp/tb_pagerank_solver_native_fractional_probe.vvp \
  MSDF_iterative_solver/tb/tb_iter_dense_runtime_jacobi32_blockdiag_multi.v \
  MSDF_iterative_solver/rtl/*.v
vvp /tmp/tb_pagerank_solver_native_fractional_probe.vvp
```

当前失败点：

```text
ERROR multi max_error iter=0 cluster=0 got=24 expected=156
```

这说明误差不是 `<=4 LSB` 级别的 online selection 差异，而是 row-update 数值合同不一致。

## Why It Fails

P4 fractional 和 Python golden 的合同是：

$$
x_i^{(k+1)} =
b_i +
\sum_t
\operatorname{round}
\left(
\frac{x_{src(i,t)}^{(k)} a_{i,t}}{2^{DATA\_WIDTH}}
\right)
$$

P2-proxy full-digit fractional 已经按这个合同修正为 per-term accumulator：

$$
p_{i,t} =
\operatorname{round}
\left(
\frac{x_{src(i,t)}^{(k)} a_{i,t}}{2^{DATA\_WIDTH}}
\right)
$$

$$
x_i^{(k+1)} = b_i + \sum_t p_{i,t}
$$

而当前 P3 mode3 的 `iter_solver_native_row_digit_engine` 不是这个合同。它的路径是：

$$
\text{state digit}
\rightarrow
\text{coefficient contribution vector}
\rightarrow
\text{streamed bias digit}
\rightarrow
\text{single residual/output update}
$$

也就是说，它把多项乘积的 digit contribution 直接合成一个 affine digit stream，然后由一个 output-update 选择输出 digit。这个 bring-up 结构可以验证 digit-stream commit/replay 边界，但没有实现 prior fractional product 的每项延迟、每项 rounding 和 product/bias alignment。

## What Must Change

下一版 P3 不能只调 `skip_digits`、`affine_guard_shift` 或 `sample_width`。这些参数只能改变输出采样窗口，不能把错误的数值合同变成：

$$
\sum_t \operatorname{round}\left(\frac{x_t a_t}{2^{DATA\_WIDTH}}\right)
$$

需要替换底层 row engine：

1. 每个 term 维护独立 fractional product residual，或者采用原论文 integrated recurrence 的等价 solver-native 形式。
2. Bias 不能再作为普通同拍 digit 简单注入，必须和 product digit delay 对齐。
3. Delta/certification 仍应从 committed digit stream 生成，但 committed digit stream 必须来自正确的 fractional row-update recurrence。
4. `full_digit_fractional` 保留为 reference，不能作为最终 P3 claim，因为它仍然等 full word。

## Next RTL Target

建议新增一个独立模块，而不是继续 patch 现有 mode3：

```text
iter_solver_native_fractional_row_engine
```

目标合同：

$$
\{x_{t,j}, a_t, b_j\}
\rightarrow
\text{term-local fractional residuals}
\rightarrow
\text{row-level online reduction}
\rightarrow
x_{i,j}^{(k+1)}
$$

验收顺序：

1. 单 row：assembled output 等于 `P2-proxy full-digit fractional`。
2. Cluster：local L1(delta) 等于 P4 fractional。
3. Runtime：多轮 `pagerank32_global_prior_fractional` 与 P4 fractional 同 golden。
4. 性能：再比较 cycles/resource；如果仍慢于 P4，则不能写成强性能 claim。

## Current P3 Candidate Checkpoint

已新增第一版 P3 candidate：

```text
iter_prior_online_mma8_digit_stream_cluster_delta_cert
```

该模块复用原始 `MSDF_MUL_ADD_8` 的 fractional recurrence，但移除 P2 的 full-word output assembler：

$$
\text{prior output digit}
\rightarrow
\text{digit-stream state bank}
\rightarrow
\text{digit-stream delta/L1 certification}
$$

当前同 fixture 结果：

| entry | total cycles | issue cycles | cert_wait cycles |
| --- | ---: | ---: | ---: |
| P3 prior digit-stream fractional | 215 | 56 | 112 |

它已经通过 `pagerank32_global_prior_fractional` 多轮 runtime test，但没有带来性能优势。该结果说明当前瓶颈主要不是 output full-word assembly，而是 prior operator 的 feed/capture/flush 延迟，以及 runtime 仍按 full-digit issue 调度。下一步如果继续推进 P3，需要把 prior operator 从 autonomous word-style feed 改成 solver-scheduled streaming feed，或者重写 term-local fractional recurrence，使 output digit 能稳定进入下一轮而不额外等待 capture/flush。
