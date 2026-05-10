# Prior Online Paper Comparison Contract

本文档固定后续 PageRank 论文实验的同口径 baseline。当前主线不再把工作表述为“新的 MSDF 内积核”，而是表述为：

$$
\textbf{operator-level integrated online inner product}
\rightarrow
\textbf{solver-level digit-stream PageRank execution}
$$

## Prior Work Scope

本地论文《基于高效集成在线算术的高维线性系统计算》解决的是算子级 online inner-product 边界。它把传统级联：

$$
\text{online multiplier}
\rightarrow
\text{online adder tree}
\rightarrow
\text{bias add}
$$

折叠为一个 integrated online inner-product recurrence：

$$
v[j]=2w[j]+2^{-\delta}\left(\sigma_n(x,y)+b_{j+1+\delta}\right)
$$

$$
z_{j+1}=\mathrm{sel}(\hat v[j])
$$

$$
w[j+1]=v[j]-z_{j+1}
$$

它的核心收益来自降低 row-update 内部初始延迟，而不是消除求解器迭代边界。

原论文报告的 PageRank case study 口径如下，只作为 prior-work reference，不和 U55C 结果硬混：

| 项目 | 原论文报告口径 |
| --- | --- |
| 应用 | PageRank |
| 规模 | 32 dimension |
| 精度 | 32-bit precision |
| 迭代 | 13 iterations |
| FPGA | ZU15EG |
| 工具 | Vivado 2023.2 |
| 时钟 | 175 MHz |
| CPU baseline | Intel i9-12900K + NumPy/OpenBLAS |
| 报告性能 | FPGA speedup 13.4x |

## Source RTL Mapping

原始 RTL 位于 [`../MSDF_operator_srcs/`](../MSDF_operator_srcs/)。核心模块对应关系：

| 原始模块 | 作用 | 对新工程的定位 |
| --- | --- | --- |
| `MSDF_MUL_ADD_8.v` | 8 路 integrated online multiply-add / inner-product demo | P1 prior RTL rerun 的核心候选 |
| `MSDF_MUL_ADD.v` | 单路 integrated multiply-add shell | 可作为小规模 operator-level reference |
| `MSDF_MUL.v` | online multiply primitive | 低层参考，不直接作为 solver top |
| `parallel_online_adder*.v` | rail-coded local online reduction | 可借鉴低层 carry-free reduction |
| `output_and_update*.v` | residual selection and update | 可借鉴 residual recurrence |
| `vector_append.v` / `append_and_select.v` / `selector.v` | signed-digit source window and sign-controlled selection | 可借鉴 digit/select 逻辑 |

关键限制：原始 RTL 的 top-level contract 是 operator-centric。它没有 runtime state bank、iteration controller、PageRank L1 certification、global source template，也没有把下一轮迭代直接接在上一轮 committed digit 后面。

## Baseline Layers

后续实验必须分四层报告，避免审稿人质疑 baseline 是人为构造。

| ID | 名称 | 用途 | 是否和 U55C 结果同表硬比 |
| --- | --- | --- | --- |
| P0 | Original paper reported PageRank | 复述 prior work 公开指标 | 否 |
| P1 | Original RTL same-device rerun | 尽量 route 原始 `MSDF_MUL_ADD_8` / PageRank row kernel | 只作为 prior RTL reference |
| P2 | Same-shell prior-online baseline | 原论文 operator 包进本 runtime shell，但保留 full-word/vector iteration boundary | 是 |
| P3 | Ours solver-level digit-stream PageRank | global source template + digit-stream state commit + L1 decision | 是 |
| P4 | Conventional fixed-point FPGA baseline | 同 graph / same shell / fixed-point DSP-MAC row update | 是 |

P2 是最关键的公平 baseline。它回答：如果只把原论文 integrated online operator 放进 solver shell，而不做 solver-level digit-stream iteration fusion，性能到哪里为止。

## What We Can Claim

可以声称：

- 原论文是 operator-level integrated online inner-product；
- 本工作把在线算术推进到 solver-level PageRank datapath；
- 本工作针对 PageRank 迭代边界消除：

$$
\text{Digit2Vector}
\rightarrow
\text{compare}
\rightarrow
\text{Vector2Digit}
\rightarrow
\text{restart}
$$

- 本工作新增 global-source PageRank template 和 L1 convergence decision。

不能声称：

- 我们重新发明 integrated online inner product；
- 只比较 CPU speedup 就证明 FPGA 架构优于所有硬件 baseline；
- PageRank v1 已支持 arbitrary-degree Web graph / CSR / HBM graph accelerator；
- 当前 RTL integer rail bridge 已经完全等价原论文 32-bit fractional PageRank 数值语义。

## Current Implementation Checkpoint

本轮新增 `pagerank32_global_full_digit` fixture 和 PageRank testbench wrappers，作为 P2/P3/P4 的同 shell 入口。当前 v1 采用 bounded-degree circulant graph，所有 row 有固定 `DEGREE=4` 个全局 source：

$$
r_i^{(k+1)} = c_i + \sum_{t=0}^{3} a_{i,t} r_{src(i,t)}^{(k)}
$$

认证先采用 digit-final L1 decision。每个 cluster 的 certification engine 输出 local L1(delta)，runtime top 再汇总：

$$
L_1^{(k)}=\sum_c L_{1,c}^{(k)}
$$

$$
\text{converged} = \left[L_1^{(k)} \le \eta\right]
$$

这里的 `eta` 是硬件 memh 中第 0 个 cluster 的 `eta` 字段，所有 cluster 写入同一个值。

另外，本轮补了两个 prior-online 可复现入口：

| 入口 | 文件 | 当前状态 |
| --- | --- | --- |
| P1 original RTL smoke | [`run_prior_online_original_smoke.py`](./run_prior_online_original_smoke.py) | 编译原始 `MSDF_MUL_ADD_8` 及依赖，有限 TB 通过 |
| P2 adapter smoke | [`run_prior_online_p2_adapter_smoke.py`](./run_prior_online_p2_adapter_smoke.py) | [`prior_rtl/iter_prior_online_mma8_row_kernel.v`](./prior_rtl/iter_prior_online_mma8_row_kernel.v) 已能把当前 4-term row digit 接口映射到原始 8-lane operator |
| P2 word-assembler smoke | [`run_prior_online_p2_adapter_smoke.py`](./run_prior_online_p2_adapter_smoke.py) | [`prior_rtl/iter_prior_online_mma8_word_assembler.v`](./prior_rtl/iter_prior_online_mma8_word_assembler.v) 已补 explicit full-word assembly boundary |
| P2 cluster wrapper smoke | [`run_prior_online_p2_adapter_smoke.py`](./run_prior_online_p2_adapter_smoke.py) | [`prior_rtl/iter_prior_online_mma8_row_cluster_delta_cert.v`](./prior_rtl/iter_prior_online_mma8_row_cluster_delta_cert.v) 已补 row-parallel assembly、delta 和 cluster certification |
| P2 runtime-shell smoke | [`run_prior_online_p2_adapter_smoke.py`](./run_prior_online_p2_adapter_smoke.py) | `ROW_DATAPATH_MODE=5` 已把 prior cluster wrapper 接入 PageRank runtime shell，当前 relaxed check 通过 |
| P2 prior-compatible fractional | [`run_prior_online_p2_adapter_smoke.py`](./run_prior_online_p2_adapter_smoke.py) | `pagerank32_global_prior_fractional` fixture 已通过，使用 fraction-only capture 和 `<=4 LSB` online rounding tolerance |
| P2/P4 fractional same-fixture | [`run_pagerank_fractional_same_scope_eval.py`](./run_pagerank_fractional_same_scope_eval.py) | P2 prior-online fractional 与 P4 conventional fractional 共用同一 graph/fixture/controller |

P2 adapter 的硬件边界是：

$$
\{x_{src,t,j}, a_{t,j}, b_j\}
\rightarrow
\text{MSDF\_MUL\_ADD\_8}
\rightarrow
z_j
$$

`iter_prior_online_mma8_word_assembler` 已补第一版受控采样窗口，显式处理原始 operator 的 `i_ena` flush 行为和 flag-hold 问题。`iter_prior_online_mma8_row_cluster_delta_cert` 已补 cluster 级 full-word delta/certification。`ROW_DATAPATH_MODE=5` 已经把它接入 runtime state commit 和 global L1 decision：

$$
\text{cluster result}
\rightarrow
\text{runtime state commit}
\rightarrow
\text{global L1 decision}
$$

当前 P2 runtime smoke 只证明调度、state commit 和 certification shell 能闭合；数值检查仍放宽，因为原始 `MSDF_MUL_ADD_8` 的输出 scaling / signed-digit contract 还没有和 PageRank fixed-point golden 完全对齐。这一点必须和 P3 的 solver-native digit-stream state commit 区分开。

## Prior Operator Numerical Contract

本轮新增 `tb_iter_prior_online_mma8_semantics`，用于避免把原始 operator 误当成普通 integer MAC。关键观测如下：

| case | state | coeff | bias | observed output |
| ---: | ---: | ---: | ---: | ---: |
| 0 | 0 | 0 | 1 | 1 |
| 1 | 1 | 1 | 0 | 0 |
| 5 | 1024 | 1024 | 0 | 256 |
| 6 | 1024 | 512 | 0 | 128 |
| 7 | 512 | 512 | 0 | 64 |

因此原始 `MSDF_MUL_ADD_8` 的乘积路径带有 online fractional scaling / delay，不等价于当前 bring-up fixture 的：

$$
\text{sum} = b + \sum_t x_t a_t
$$

更接近：

$$
\text{sum}_{\text{prior}} = b_{\text{aligned}} + \sum_t \operatorname{MSDFFracMul}(x_t, a_t)
$$

其中乘积 digit 与 bias digit 的相对位置必须按原始 online delay 对齐。另一个工程事实是：原始 `vector_append` 内部 full/idx 状态不会自动清空，所以每个 word-level operation 都必须对 `MSDF_MUL_ADD_8` 做本地 reset；`iter_prior_online_mma8_word_assembler` 已加入 per-operation reset。

这意味着当前 `pagerank32_global_full_digit` integer fixture 不能直接作为严格 P2 golden。当前已实现第一条路线：

1. 生成 prior-compatible fractional PageRank fixture，并让 P3/P4 也使用同一 fixed-point scaling；
2. 在 P2 wrapper 内加入明确的 bias/product alignment bridge，但这会改变 prior operator 的原生合同，必须在论文里单独标注。

当前 `pagerank32_global_prior_fractional` 的设置是：

| 参数 | 值 |
| --- | --- |
| `BIT_WIDTH` | 11 |
| `DATA_WIDTH` | 14 |
| coefficient/bias quantization | fraction stream scale |
| product model | round-to-nearest after `DATA_WIDTH` shift |
| output capture | fraction-only, skip unit marker |
| check tolerance | `<=4 LSB` for online selection/rounding |

该 fixture 的 P2 runtime 结果为 `total=227 / issue=4 / cert_wait=124`，已通过同 shell testbench。

本轮已经把 P4 conventional DSP-MAC baseline 也切到同一 fractional fixture。P4 的 row slice 新增 `product_shift=DATA_WIDTH`，即：

$$
\text{sum}_{\text{conv-frac}} = b + \sum_t
\operatorname{round}\left(\frac{x_t a_t}{2^{DATA\_WIDTH}}\right)
$$

同 fixture 结果如下。性能主表使用 `compute cycles = issue + cert_wait`，配置、state preload、window load 和 testbench/controller overhead 单独剥离。

| entry | compute cycles | issue cycles | cert_wait cycles | observed total |
| --- | ---: | ---: | ---: | ---: |
| P2 prior-online fractional | 128 | 4 | 124 | 227 |
| P2-proxy full-digit fractional | 136 | 56 | 80 | 183 |
| P3 prior digit-stream fractional | 168 | 56 | 112 | 215 |
| P3 prior K=4 wavefront fractional | 70 | 14 | 56 | 150 |
| P4 conventional fractional | 36 | 4 | 32 | 135 |

其中 P2-proxy full-digit fractional 已修正为 per-term product rounding，因此数值上和 P4 fractional 使用同一个 golden；但它仍然 materialize full row word，只能作为数值参考层。P3 prior digit-stream fractional 已移除 P2 的 full-word output assembler，把原始 prior output digit 直接写入 digit-stream state bank；它已经接入同 fixture，但当前 cycles 仍高于 P2-proxy 和 P4。

最新 P3 prior K=4 wavefront fractional 已接入 runtime shell：四级原始 prior operator 级联，后一级在前一级 committed digit 出现后立即消费，不等待 full word；最终认证比较的是 $x^{(k+4)}-x^{(k+3)}$，不是 $x^{(k+4)}-x^{(k)}$。该版本 `compute=70 / issue=14 / cert_wait=56 / observed_total=150`，相对 P3 prior digit-stream single-stage 的 `168` compute cycles 有 `2.400x` speedup，但仍比 P4 conventional fractional 的 `36` compute cycles 慢 `1.944x`。结论是：solver-level digit wavefront 已经证明能显著压低原始 online operator 的 iteration boundary 成本，但还没有击败干净 DSP-MAC baseline。

U55C 5 ns OOC route 已补充，见 `generated/pagerank_fractional_routed_backend_report.md`。P3 timing-clean：`compute=70 / observed_total=150 / WNS +0.114 ns / 121364 LUT / 64706 FF / 64 DSP / 10.5 BRAM / dynamic 1.247 W`。原始 P4 conventional fractional route 不过时序：`WNS -2.852 ns / 57828 LUT / 15069 FF / 192 DSP / 10.5 BRAM / dynamic 1.853 W`，因此 `compute=36` 只能作为功能级 lower-bound。已补 timing-clean P4：global replay register + product-rounding pipeline，`compute=44 / observed_total=143 / WNS +0.204 ns / 55084 LUT / 19657 FF / 192 DSP / 10.5 BRAM / dynamic 2.019 W`。

为解决“P3 底层是 8 路 `MSDF_MUL_ADD_8`，P4 却是干净 4 路 DSP-MAC”的公平性问题，当前又加入了 reserved 8-slot P4：PageRank 数学仍为每行 4 个有效项，但 conventional 额外保留 4 个物理 MAC 槽位。该版本 routed 结果为 `compute=44 / observed_total=143 / WNS +0.052 ns / 59482 LUT / 23753 FF / 320 DSP / 10.5 BRAM / dynamic 2.390 W`。当前最终 routed 口径是 P3 `70` compute cycles vs reserved 8-slot P4 `44` compute cycles：P3 省 `5x` DSP、dynamic 低约 `47.82%`，但 LUT 高 `2.04x`、FF 高 `2.72x`，core cycle 也慢 `1.591x`。

## Next Required Work

下一步必须补齐两件事，才能从工程 checkpoint 升级为论文主结果：

- P1：对原始 `MSDF_operator_srcs` 做 same-device rerun，至少 route `MSDF_MUL_ADD_8` 并记录 ZU15EG/U55C 差异；
- P2/P3/P4：继续使用 `run_pagerank_fractional_same_scope_eval.py` 维护同 fixture 对比；下一步重点不是再证明 boundary fusion 存在，而是压低 P3 wavefront 的 runtime overhead 或给出资源/功耗/吞吐上的硬优势。
