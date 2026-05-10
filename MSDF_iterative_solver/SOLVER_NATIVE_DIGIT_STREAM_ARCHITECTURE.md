# Solver-Native Digit-Stream Architecture

本文档固定新的论文级主线：不再把 `K schedule`、少跑几轮或启发式 early-stop 作为核心创新，而是把原论文的 operator-level integrated online recurrence 推进到 solver-level iteration boundary。

## Main Claim Boundary

原论文解决的是：

$$
\text{online multiplier / online adder boundary inside an inner product}
$$

本主线要解决的是：

$$
\text{row update / state commit / delta / certification boundary inside an iterative solver}
$$

因此 v1 默认跑满全部 `DATA_WIDTH` digit。它不是近似计算，也不是动态精度方案。

## Target Dataflow

目标数据流是：

$$
x^{(k)}\_\mathrm{digit}
\rightarrow
\text{state replay}
\rightarrow
\text{solver-native row digit engine}
\rightarrow
x^{(k+1)}\_\mathrm{digit}
\rightarrow
\text{digit state commit}
\rightarrow
\text{digit delta/certification}
$$

其中 `x_new_digit` 不需要先重构成 full word 才能写回 state bank。full-word bridge 只作为 reference 和 regression。

## Solver-Native Row Recurrence

原论文的带 bias integrated inner-product recurrence 是：

$$
v[j]=2w[j]+2^{-\delta}\left(\sigma_n(x,y)+b_{j+1+\delta}\right)
$$

$$
z_{j+1}=\mathrm{sel}(\hat v[j])
$$

$$
w[j+1]=v[j]-z_{j+1}
$$

solver-native 版本把 generic variable-by-variable inner product 改成固定矩阵 affine row update：

$$
v_i^{(k)}[j]
=
2w_i^{(k)}[j]
+
\mathcal{C}_i
\left(
\{x_t^{(k)}[j]\}_{t\in N(i)},
\{g_{it}\}_{t\in N(i)}
\right)
+
c_{i,j}
$$

$$
x_{i,j+1}^{(k+1)}
=
\mathrm{sel}\left(\hat v_i^{(k)}[j]\right)
$$

$$
w_i^{(k)}[j+1]
=
v_i^{(k)}[j]-x_{i,j+1}^{(k+1)}
$$

这里 `g_it` 是固定系数，不能继续按两个 variable operands 的 generic product 处理。v1 先建立 no-bias fixed-coefficient contribution producer、streamed bias source、residual/output-update loop 三段边界。

## Digit-Stream Delta Bound

在每个新 digit 输出时，同步消费旧 state digit：

$$
d_{i,j}^{(k)}
=
x_{i,j}^{(k+1)}-x_{i,j}^{(k)}
$$

MSB-first prefix accumulator 为：

$$
D_i[j+1]=2D_i[j]+d_{i,j}
$$

若还剩 `r` 个低位 digit，signed-digit 差分每位最大幅度为 2，因此安全上界是：

$$
|\Delta_i^{(k)}|
\le
\left|D_i[j+1]2^r\right|
+
2(2^r-1)
$$

v1 只使用这个 bound 作为 inline certification 数据路径，不做提前停止。后续如果要做 certified work reduction，必须证明 false-stop 不可能发生。

## Current Implementation Checkpoint

本 checkpoint 新增五类模块：

- `iter_const_coeff_digit_contrib_rail`: 对 magnitude p/n 固定系数 rail 执行 signed digit contribution，负 digit 使用 p/n 交换。
- `iter_streamed_bias_source`: 把 bias full rail word 对齐成 MSB-first digit stream。
- `iter_online_affine_no_bias_core`: 固定系数、无 bias 的 4-term affine contribution producer。
- `iter_digit_stream_delta_bound`: 对新旧 digit stream 做 prefix delta 和 tail bound。
- `iter_solver_native_row_digit_engine`: 连接 no-bias contribution、streamed bias 和 residual/output-update loop。

`iter_solver_native_row_digit_engine` 使用：

$$
t=3
$$

对应的 `affine_guard_shift = 3` 和 `sample_offset = 3`。贡献向量进入 residual datapath 时保留 3 位 guard/fractional estimate，而 selector 采样窗口同步下移 3 位，避免把阈值也随 datapath 扩宽一起抬高。

当前 directed row-level equivalence 已覆盖非零正向和 mixed-sign case。注意新路径输出的是 signed-digit rail trace，full bridge 输出的是 magnitude rail word；两者数值等价，但 p/n bit pattern 不应直接比较。

## Baseline Positioning

最终论文表必须保留三类 baseline：

- `B0`: 原论文式 integrated online inner-product shell，用来证明我们不是只复现 operator-level boundary folding。
- `B1`: clean conventional DSP-MAC Jacobi runtime，用来证明 FPGA baseline 公平。
- `B2`: full-digit bridge runtime，用来证明 solver-native digit stream 没有改变数值语义。

本主线的有效收益应来自 iteration boundary removal、digit-stream state/delta/certification，而不是来自降低精度。
