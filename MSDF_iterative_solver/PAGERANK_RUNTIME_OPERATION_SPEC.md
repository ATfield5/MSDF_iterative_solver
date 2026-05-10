# PageRank Runtime Operation Spec

本文档只维护当前论文口径下的四个 PageRank 对比对象：

| ID | name | role |
| --- | --- | --- |
| `P1` | original paper / original RTL reference | 原始论文和原始 `MSDF_MUL_ADD_8` operator 参考 |
| `P2` | same-shell prior-online baseline | 原始 online operator 放入我们的 PageRank runtime shell |
| `P3` | ours prior K=4 digit wavefront | 本文主线方案 |
| `P4` | conventional reserved 8-slot DSP-MAC baseline | 传统定点 DSP-MAC 公平 baseline |

后续文档和实验表格不再把历史 bring-up 路径作为主结果维护。

三类方案和四个编号的关系是：

| scheme | maintained entries |
| --- | --- |
| 原始论文方案 | `P1` 记录论文/原始 RTL 口径，`P2` 记录原始 operator 接入本文 runtime shell 后的同壳 baseline |
| 我的方案 | `P3`，也就是当前 K=4 solver-level digit wavefront |
| 传统方案 | `P4`，也就是 timing-clean reserved 8-slot conventional DSP-MAC |

## Workload Contract

当前主测试 fixture 是：

`MSDF_iterative_solver/generated/rtl_vectors/pagerank32_global_prior_fractional`

核心参数如下：

| item | value |
| --- | ---: |
| PageRank vector length | `N = 32` |
| physical clusters | `NUM_CLUSTERS = 8` |
| rows per cluster | `NUM_ROWS = 4` |
| rows per runtime window | `32` |
| valid sparse terms per row | `DEGREE = 4` |
| physical prior operator width | `8` input slots |
| PageRank iterations in golden | `4` |
| damping factor | `beta = 0.85` |
| coefficient integer | `1741` |
| teleport integer | `38` |

当前矩阵是 bounded-degree circulant PageRank matrix。对第 `i` 行：

$$
\mathrm{src}(i)=\{i,\ i-1,\ i-5,\ i-13\}\bmod 32
$$

因此它是一个 `32 x 32` 稀疏矩阵，每行只有 4 个有效非零项，不是 dense 32 项内积。

理想 PageRank 形式为：

$$
r_i^{(k+1)}
=
(1-\beta)v_i
+
\sum_{j\in \mathrm{In}(i)}
\beta\frac{1}{\mathrm{outdeg}(j)}r_j^{(k)}
$$

当前 fixed-point 同口径合同为：

$$
x_i^{(k+1)}
=
b_i
+
\sum_{t=0}^{3}
\operatorname{round}
\left(
\frac{x_{\mathrm{src}(i,t)}^{(k)} a_{i,t}}{2^{14}}
\right)
$$

这里 `2^14` 是为了匹配原始 `MSDF_MUL_ADD_8` 的 fractional 输出合同。`P2/P3/P4` 都使用同一个 graph、同一个量化系数、同一个 `product_shift = DATA_WIDTH = 14`。

## Number Format

当前不是 IEEE 浮点。runtime 内部使用 `p/n` rail-coded 差分表示：

$$
\mathrm{value}(u)=u_p-u_n
$$

主要位宽如下：

| signal class | format | width | meaning |
| --- | --- | ---: | --- |
| state `x_p/x_n` | rail-coded fractional word | `DATA_WIDTH = 14` | PageRank state |
| coefficient `a_p/a_n` | rail-coded coefficient | `BIT_WIDTH = 11` | sparse term coefficient |
| bias `b_p/b_n` | rail-coded bias | `BIAS_WIDTH = 13` | teleport term |
| source index | unsigned | `SRC_IDX_WIDTH = 5` | selects one of 32 rows |
| row delta bound | unsigned | `BOUND_WIDTH = 16` | certification bound |
| cluster/global L1 | unsigned | `ACC_WIDTH = 24` | convergence error |

## P1: Original Paper / Original RTL Reference

### Paper Problem

原始论文的出发点是 online arithmetic 内部的算子级瓶颈：传统在线乘法和在线加法级联时，中间结果需要跨 operator 边界传递，导致额外延迟和格式处理。论文提出 integrated online inner-product，把乘法 partial product、加法累加和 residual/output update 融合在一个 online operator 里。

它解决的是：

$$
\text{multiplier/addition boundary inside inner product}
$$

不是完整 solver 的 iteration boundary。

### Paper PageRank Formula

原论文 PageRank case study 可以写成 affine matrix-vector iteration：

$$
x^{(k+1)} = A x^{(k)} + b
$$

单行形式为：

$$
x_i^{(k+1)}=b_i+\sum_t a_{i,t}x_{\mathrm{src}(i,t)}^{(k)}
$$

### Engineering Implementation

原始 RTL 的核心 operator 是：

`../MSDF_operator_srcs/.../MSDF_MUL_ADD_8.v`

它是 8 路 integrated online multiply-add。输入是 digit stream，输出也是 online digit stream。原论文 PageRank 顶层仍然需要在 solver iteration 之间做类似：

$$
\text{Digit2Vector}
\rightarrow
\text{compare}
\rightarrow
\text{Vector2Digit}
\rightarrow
\text{next iteration}
$$

因此 P1 是 prior-work reference，不是本项目的 same-shell runtime 主结果。

### Available Reported Reference

原论文公开 PageRank 口径：

| item | value |
| --- | --- |
| application | PageRank |
| dimension | `32` |
| precision | `32-bit` |
| iterations | `13` |
| FPGA | `ZU15EG` |
| tool | `Vivado 2023.2` |
| frequency | `175 MHz` |
| reported comparison | Intel i9-12900K + NumPy/OpenBLAS |
| reported speedup | `13.4x` |

P1 不和 U55C P2/P3/P4 route 结果直接混表比较；它的作用是说明本文主线建立在已有 operator-level online arithmetic 之上。

## P2: Same-Shell Prior-Online Baseline

### Mathematical Processing

P2 使用和本文 fixture 相同的 PageRank 数学合同：

$$
x_i^{(k+1)}
=
b_i
+
\sum_{t=0}^{3}
\operatorname{round}
\left(
\frac{x_{\mathrm{src}(i,t)}^{(k)}a_{i,t}}{2^{14}}
\right)
$$

它的意义是：把原始 operator 接到我们的 PageRank runtime shell 里，但不改变原始 operator-level 边界。

### Engineering Implementation

P2 的 RTL 路径是：

| function | RTL |
| --- | --- |
| row operator wrapper | `prior_rtl/iter_prior_online_mma8_row_kernel.v` |
| word assembly / capture | `prior_rtl/iter_prior_online_mma8_word_assembler.v` |
| cluster + certification | `prior_rtl/iter_prior_online_mma8_row_cluster_delta_cert.v` |
| runtime shell | `rtl/iter_dense_small_runtime_top.v` |

数据流是：

$$
x^{(k)}_{\mathrm{digit}}
\rightarrow
\text{MSDF\_MUL\_ADD\_8}
\rightarrow
\text{full-word capture}
\rightarrow
\text{state commit}
\rightarrow
x^{(k+1)}
$$

也就是说，P2 仍然在每轮 PageRank 后 materialize full word；它是“原论文 online operator 接入 solver”，不是本文的 solver-level digit-stream 主线。

### Cycle Contribution

当前 P2 functional simulation counter：

| counter | value | meaning |
| --- | ---: | --- |
| `compute_cycles` | `128` | 性能主表采用的周期，等于 `issue + cert_wait` |
| `issue` | `4` | runtime 外部每轮只发一个 start/issue pulse |
| `cert_wait` | `124` | start 后等待 operator feed/capture、state commit 和 L1 certification 完成 |
| `observed_total` | `227` | 包含配置、state preload、window load 和 testbench/controller overhead 的总观测周期 |
| `non_compute_overhead` | `99` | `observed_total - compute_cycles`，不进入性能主表 |

P2 的 `issue=4` 不代表 operator 只算 4 拍；内部 digit feed、capture 和 certification 等待主要体现在 `cert_wait=124`。P2 的主要周期来源是：

| step | contribution |
| --- | --- |
| runtime configuration | `cfg_template=8`、`cfg_cert=8`、`cfg_state=32`，单独作为 setup activity，不进入性能主表 |
| window load | `window_load=1`、`window_busy=10`，单独作为 runtime overhead，不进入性能主表 |
| external solver launch | `issue=4`，4 轮各启动一次 |
| prior operator + full-word boundary | 包含在 `cert_wait=124`，主要是原始 operator feed/capture、full-word assembly、state commit |
| L1 certification/controller wait | 也包含在 `cert_wait=124` |

## P3: Ours Prior K=4 Digit Wavefront

### Core Idea

P3 是本文主线，对应：

`ROW_DATAPATH_MODE=7`

它继承原始 `MSDF_MUL_ADD_8` 的 digit-level operator，但把 4 个 PageRank iteration stage 级联为一个 solver-level wavefront。

P2 的 iteration 边界是：

$$
x^{(k)}_{\mathrm{digit}}
\rightarrow
\text{operator}
\rightarrow
\text{full word}
\rightarrow
x^{(k+1)}_{\mathrm{digit}}
$$

P3 改成：

$$
x^{(k)}_{\mathrm{digit}}
\rightarrow
x^{(k+1)}_{\mathrm{digit}}
\rightarrow
x^{(k+2)}_{\mathrm{digit}}
\rightarrow
x^{(k+3)}_{\mathrm{digit}}
\rightarrow
x^{(k+4)}_{\mathrm{digit}}
$$

后一级在前一级 committed digit 出现后立刻消费，不等待 full-word assembly。

### Mathematical Processing

每一级 stage 仍然执行同一个 PageRank row update：

$$
x_i^{(s+1)}
=
b_i
+
\sum_{t=0}^{3}
\operatorname{round}
\left(
\frac{x_{\mathrm{src}(i,t)}^{(s)}a_{i,t}}{2^{14}}
\right)
$$

其中：

$$
s=k,k+1,k+2,k+3
$$

K=4 wavefront 的最终输出是：

$$
x^{(k+4)}
$$

为了保持 convergence 语义正确，P3 的 delta/certification 不是比较：

$$
x^{(k+4)}-x^{(k)}
$$

而是比较最后一步：

$$
x^{(k+4)}-x^{(k+3)}
$$

因此 RTL 缓存 penultimate stage committed digits，用于 final-stage L1 delta。

### Engineering Implementation

P3 的主要 RTL 路径是：

| function | RTL |
| --- | --- |
| global K-stage wavefront | `prior_rtl/iter_prior_online_mma8_global_wavefront_top.v` |
| one wavefront stage | `prior_rtl/iter_prior_online_mma8_stream_stage_cluster.v` |
| prior row kernel | `prior_rtl/iter_prior_online_mma8_row_kernel.v` |
| cluster/runtime integration | `rtl/iter_dense_small_ping_pong_top.v` |
| runtime shell | `rtl/iter_dense_small_runtime_top.v` |

物理规模：

$$
K=4,\quad N=32,\quad \text{stage rows}=32
$$

每一级 stage 内部仍使用 8 路 `MSDF_MUL_ADD_8` 物理输入槽位。当前 PageRank 每行只有 4 个有效项，因此另 4 个槽位不承载有效 PageRank edge。

### Cycle Contribution

当前 P3 functional simulation counter：

| counter | value | meaning |
| --- | ---: | --- |
| `compute_cycles` | `70` | 性能主表采用的周期，等于 `issue + cert_wait` |
| `issue` | `14` | 外部只送一次 14-digit input stream |
| `cert_wait` | `56` | 等待 4-stage wavefront flush、last-step delta 和 L1 certification |
| `observed_total` | `150` | 包含配置、state preload、window load 和 testbench/controller overhead 的总观测周期 |
| `non_compute_overhead` | `80` | `observed_total - compute_cycles`，不进入性能主表 |

P3 的关键收益来自：

$$
4\times 14 = 56
\quad\rightarrow\quad
14
$$

也就是 4 轮 PageRank 不再重复从 full word 重新启动 4 次 digit stream。

P3 的主要周期来源是：

| step | contribution |
| --- | --- |
| runtime configuration | 同 P2/P4，`cfg_template=8`、`cfg_cert=8`、`cfg_state=32`，单独作为 setup activity |
| window load | 同 P2/P4，`window_load=1`、`window_busy=10`，单独作为 runtime overhead |
| external digit issue | `issue=14`，只输入一次 14-digit stream |
| K=4 wavefront drain | 包含在 `cert_wait=56`，等待 4 级 stage 级联输出 final committed digits |
| last-step delta | 包含在 `cert_wait=56`，比较 `x^(k+4)-x^(k+3)` |
| L1 certification/controller wait | 包含在 `cert_wait=56` |

## P4: Conventional Reserved 8-Slot DSP-MAC Baseline

### Mathematical Processing

P4 使用完全相同的 PageRank fixed-point 合同：

$$
x_i^{(k+1)}
=
b_i
+
\sum_{t=0}^{3}
\operatorname{round}
\left(
\frac{x_{\mathrm{src}(i,t)}^{(k)}a_{i,t}}{2^{14}}
\right)
$$

区别是 P4 不使用 online digit recurrence，而是 full-word replay 后用传统 DSP-MAC 计算。

### Engineering Implementation

P4 的主 RTL 路径是：

| function | RTL |
| --- | --- |
| conventional row update | `rtl/conv_signed_row_update_delta_slice_pipe.v` |
| cluster + certification | `rtl/conv_row_cluster_delta_cert.v` |
| reserved MAC slots | `rtl/conv_reserved_mac_slots.v` |
| runtime integration | `rtl/iter_dense_small_ping_pong_top.v` |
| runtime shell | `rtl/iter_dense_small_runtime_top.v` |

为了公平比较，P4 当前采用：

$$
\text{valid terms per row}=4
$$

但保留：

$$
\text{physical MAC slots per row}=8
$$

也就是后 4 路 conventional MAC 不改变数学输出，只作为 reserved physical slots 进入综合和 route。这样 P4 不会因为只实例化 4 路 DSP-MAC 而比原始 8 路 `MSDF_MUL_ADD_8` 占便宜。

P4 timing-clean 版本包含：

$$
\text{global replay register}
$$

和：

$$
\text{product-rounding pipeline}
$$

### Cycle Contribution

当前 P4 reserved 8-slot timing-clean functional simulation counter：

| counter | value | meaning |
| --- | ---: | --- |
| `compute_cycles` | `44` | 性能主表采用的周期，等于 `issue + cert_wait` |
| `issue` | `4` | 每轮一个 full-word DSP-MAC launch |
| `cert_wait` | `40` | 等待 replay register、DSP product/rounding pipeline、state commit 和 L1 certification |
| `observed_total` | `143` | 包含配置、state preload、window load 和 testbench/controller overhead 的总观测周期 |
| `non_compute_overhead` | `99` | `observed_total - compute_cycles`，不进入性能主表 |

P4 的 `issue=4` 是因为它一次消费 full-word state，不需要 14 个 digit issue 周期。

P4 的主要周期来源是：

| step | contribution |
| --- | --- |
| runtime configuration | `cfg_template=8`、`cfg_cert=8`、`cfg_state=32`，单独作为 setup activity |
| window load | `window_load=1`、`window_busy=10`，单独作为 runtime overhead |
| full-word solver launch | `issue=4`，4 轮各启动一次 |
| DSP-MAC pipeline | 包含在 `cert_wait=40`，包括 global replay register 和 product-rounding pipeline |
| state commit + L1 certification | 包含在 `cert_wait=40` |

## Certification Contract

PageRank 使用 L1 convergence check。每行 delta bound 为：

$$
\Delta_i^{(k)}
=
|x_i^{(k+1)}-x_i^{(k)}|
+
\mathrm{tail\_bound}
$$

当前：

$$
\mathrm{tail\_bound}=1
$$

当前 block size 为 1，所以每个 block 对应一行：

$$
B_i=\Delta_i
$$

cluster local L1 error：

$$
E_c=\sum_{i\in c}B_i
$$

global L1 error：

$$
E=\sum_{c=0}^{7}E_c
$$

收敛判定：

$$
E\le\eta
$$

当前：

$$
\eta=64
$$

golden 前 4 轮 global L1 为：

| iteration | global L1 |
| ---: | ---: |
| 0 | 1248 |
| 1 | 544 |
| 2 | 288 |
| 3 | 160 |

因此当前 4 轮测试没有收敛，`continue=1` 是预期结果。

## Current Results

### Functional Compute-Cycle Counters

性能主表只使用：

$$
\mathrm{compute\_cycles}
=
\mathrm{issue}
+
\mathrm{cert\_wait}
$$

它覆盖输入、主计算循环、输出/commit/certification wait。配置、state preload、window load 和 testbench/controller idle 不进入性能主表。

| ID | entry | compute_cycles | issue | cert_wait | observed_total | non_compute_overhead |
| --- | --- | ---: | ---: | ---: | ---: | ---: |
| `P1` | original paper / original RTL reference | N/A | N/A | N/A | N/A | 原论文 reported reference，不接同一 runtime counter |
| `P2` | same-shell prior-online | 128 | 4 | 124 | 227 | 99 |
| `P3` | prior K=4 digit wavefront | 70 | 14 | 56 | 150 | 80 |
| `P4` | timing-clean reserved 8-slot DSP-MAC | 44 | 4 | 40 | 143 | 99 |

这些 counters 不是严格互斥的流水级面积分解，而是仿真观测口径。`cert_wait` 从 `i_start_iter` 后持续到 `o_iter_done`，因此它覆盖了后端计算、pipeline drain、state commit 和 certification/controller wait。`non_compute_overhead` 只是一个辅助 residual：

$$
\mathrm{non\_compute\_overhead}
=
\mathrm{observed\_total}
-
\mathrm{compute\_cycles}
$$

它包括 template/cert/state 配置、window load、commit、controller idle 和 testbench 间隔。当前共同配置写入为：

$$
\mathrm{cfg\_template}=8,\quad
\mathrm{cfg\_cert}=8,\quad
\mathrm{cfg\_state}=32
$$

### Routed U55C 5 ns Results

`cycles` 列同样使用 compute-cycle 口径；包含配置/state preload 的 observed total 不放在 route 性能主表中。

| ID | entry | compute cycles | observed total | WNS | LUT | FF | DSP | BRAM | dynamic |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| `P1` | original paper / original RTL reference | N/A | N/A | N/A | N/A | N/A | N/A | N/A | N/A |
| `P2` | same-shell prior-online | not routed as main table | not routed as main table | not routed as main table | not routed as main table | not routed as main table | not routed as main table | not routed as main table | not routed as main table |
| `P3` | prior K=4 digit wavefront | 70 | 150 | +0.114 ns | 121364 | 64706 | 64 | 10.5 | 1.247 W |
| `P4` | timing-clean reserved 8-slot DSP-MAC | 44 | 143 | +0.052 ns | 59482 | 23753 | 320 | 10.5 | 2.390 W |

Current interpretation:

$$
\text{P3 compute cycles}=70 > \text{P4 compute cycles}=44
$$

所以剥离配置/state preload 后，当前 P3 更明确地不是 latency win。之前 observed total 接近，是因为配置和 window/control overhead 掩盖了核心计算差距。

但 P3 的硬件优势是：

$$
\text{DSP reduction}=5.00\times
$$

和：

$$
\text{dynamic power reduction}\approx47.82\%
$$

当前硬件劣势是：

$$
\text{LUT ratio}=2.04\times
$$

和：

$$
\text{FF ratio}=2.72\times
$$

因此 P3 下一步优化重点不是继续增加 `K`，而是降低 stage replication、committed-digit fanout 和 original prior operator wrapper 的 LUT/FF 成本。

## Maintained RTL Entry Points

| ID | function | file |
| --- | --- | --- |
| `P1` | original operator | `../MSDF_operator_srcs/.../MSDF_MUL_ADD_8.v` |
| `P2` | prior-online same-shell row/cluster | `prior_rtl/iter_prior_online_mma8_row_cluster_delta_cert.v` |
| `P3` | global prior wavefront | `prior_rtl/iter_prior_online_mma8_global_wavefront_top.v` |
| `P4` | conventional row update | `rtl/conv_signed_row_update_delta_slice_pipe.v` |
| `P4` | reserved conventional MAC slots | `rtl/conv_reserved_mac_slots.v` |
| all | runtime shell | `rtl/iter_dense_small_runtime_top.v` |
| all | cluster/state/replay top | `rtl/iter_dense_small_ping_pong_top.v` |
