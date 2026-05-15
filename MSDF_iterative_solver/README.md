# MSDF Iterative Solver Workflow

本目录用于承接新的论文主线：只讨论高维线性归约与固定点迭代核，不再继续旧的非线性方向。

当前固定的问题族是：

$$
x^{(k+1)} = Gx^{(k)} + c
$$

论文主应用场景现在锁定为 PageRank-style fixed-point graph propagation；Jacobi 保留为 RTL 数值压力测试和 signed-coefficient affine fixture，不再作为 headline application。决策依据见 [`PAGERANK_APPLICATION_LOCK.md`](./PAGERANK_APPLICATION_LOCK.md)。

这类问题覆盖：

- `PageRank / power iteration`
- `Richardson iteration`
- `Jacobi-style fixed-point update` as a validation fixture
- 一部分图传播与稀疏线性系统迭代

本方向的核心判断是：MSDF / online arithmetic 适合高维、流式、归约主导、可融合 operator boundary 的线性核；不适合作为独立非线性函数核的论文主线。


## Current Parallel-In Operator Branch: P3-SP

P3-SP 是当前新增的底层算子优化分支：系数矩阵仍由外部 template 输入，但以 parallel fixed-point word 进入 online MAC；state 继续以 MSDF digit stream 输入。该分支的目标是把原始 serial-serial inner-product delay 从

$$
\delta_{\mathrm{SS}}=\left\lceil\log_2\frac{2n+1}{3}\right\rceil+3
$$

替换为 PageRank bound-aware parallel-in delay：

$$
\delta_{\mathrm{SP}}=\max\left(2,\left\lceil\log_2\frac{\max_i(A_i+B_i)}{3}\right\rceil+3\right)
$$

索引：

- [`PAPER_RESULTS_INDEX.md`](./PAPER_RESULTS_INDEX.md)
- [`PARALLEL_IN_OPERATOR_PAPER_MATH.md`](./PARALLEL_IN_OPERATOR_PAPER_MATH.md)
- [`PARALLEL_IN_ONLINE_DELAY_DERIVATION.md`](./PARALLEL_IN_ONLINE_DELAY_DERIVATION.md)
- [`BOUNDED_ESTIMATE_SELECTOR.md`](./BOUNDED_ESTIMATE_SELECTOR.md)
- [`run_parallel_in_bound_sweep.py`](./run_parallel_in_bound_sweep.py)
- [`run_parallel_in_paper_reports.py`](./run_parallel_in_paper_reports.py)
- [`make_pagerank_parallel_in_fractional_vectors.py`](./make_pagerank_parallel_in_fractional_vectors.py)
- [`prior_rtl/iter_parallel_in_online_mma8_frac_core.v`](./prior_rtl/iter_parallel_in_online_mma8_frac_core.v)
- [`prior_rtl/iter_parallel_in_conv_mma8_global_wavefront_top.v`](./prior_rtl/iter_parallel_in_conv_mma8_global_wavefront_top.v)
- [`run_parallel_in_fractional_eval.py`](./run_parallel_in_fractional_eval.py)
- [`run_parallel_in_route_sweep.py`](./run_parallel_in_route_sweep.py)
- [`generated/parallel_in_fractional_eval.md`](./generated/parallel_in_fractional_eval.md)
- [`generated/parallel_in_route_sweep.md`](./generated/parallel_in_route_sweep.md)
- [`generated/parallel_in_dense32_eval.md`](./generated/parallel_in_dense32_eval.md)
- [`generated/parallel_in_bound_sweep.md`](./generated/parallel_in_bound_sweep.md)
- [`generated/parallel_in_cycle_ablation.md`](./generated/parallel_in_cycle_ablation.md)
- [`generated/paper_baseline_fairness_table.md`](./generated/paper_baseline_fairness_table.md)

当前 checkpoint：`pagerank32_global_parallel_in_fractional` 得到 `max_i(A_i+B_i)=0.85468750`，推导与实现的 `online_delay=2`；P3-SP 外部已改为 `DATA_WIDTH=32` 个 MSB-first signed digits。重新推导后的位宽为：`BIT_WIDTH_min=29`，工程取 `BIT_WIDTH=30`；`BIAS_WIDTH=32`；内部 residual accumulator 最小安全位宽 `ACC_WIDTH_min=33`，工程也取 `ACC_WIDTH=33`。这是 workload-specific 安全宽度，不降低外部 32-bit 输出精度；原 36-bit guard 版本功能正确但 feedback loop 在 U55C 5 ns 下只剩极小负 slack。K=4 standalone P3-SP wavefront Icarus 仿真通过，`observed total=50`，`capture=32`。

P4-SP conventional baseline 已按当前口径改为一轮并行 row baseline：32 个 row lane 并行，每个 row lane 内有 8 个并行 `32 x 32` signed MAC slot，不做 K-stage 物理展开。公平功能测试中复用同一个 one-stage datapath 连续跑 4 轮，第一轮输入全 0，每轮输出回写作为下一轮输入；Icarus 结果为 `17` cycles。

U55C 5 ns OOC route 已补，报告见 [`generated/parallel_in_route_sweep.md`](./generated/parallel_in_route_sweep.md)。当前 fast50 standalone P3-SP 保留 direct stage-to-stage digit cascade，只加入 contribution register，并把 contribution 生成器改成显式 balanced tree；standalone route 通过 5 ns：`WNS=+0.104 ns / 85373 LUT / 10831 FF / 7568 CARRY8 / 0 DSP / 0 BRAM / dynamic 0.966 W`。4-cycle feedback loop 在 core36 下只差极小负 slack，切到数学证明的 core33 后 route-clean：`WNS=+0.040 ns / 116066 LUT / 27089 FF / 9676 CARRY8 / 0 DSP / 0 BRAM / dynamic 1.749 W`。I=3 fast2 分支功能上能把 feedback 从 `94` cycles 压到 `88` cycles；exact threshold selector、feedback term preselect、valid/data decoupling、split bounded-estimate selector、PageRank 非负系数和非负 bias 专用路径后，route 从 `WNS=-2.303 ns` 改善到 `WNS=-0.121 ns / 92002 LUT / 22564 FF / 8140 CARRY8 / 0 DSP / dynamic 1.589 W`，但仍未过 U55C 5 ns，因此暂不进入主线。该优化保持 `88` cycles 和 `first_gap01=3` 不变，收益来自 PageRank transition coefficient 与 teleport/bias 项均非负，去掉了每个 term 的 `coeff_p-coeff_n` 减法和 bias 负分支。最新 redundant-residual 实验确认：carry-save residual rail 不能直接截高位做 selector，必须配套 canonical estimate residual；bit-exact PageRank32 最小通过设置为 `EST_FRAC_BITS=4 / EST_GUARD_BITS=26`，但 U55C 5 ns route 仍约 `WNS=-2.78 ns`，关键路径转移到 `r_w_est_norm[32]`，因此该分支不进入主线。新的 P4-SP one-stage parallel-row baseline 为 `WNS=+1.284 ns / 62877 LUT / 24644 FF / 8896 CARRY8 / 1024 DSP / dynamic 3.046 W`。因此这些行不再是同形状 latency-first 对比：P3-SP feedback 是 4-stage x 32-row online wavefront + FIFO/termination，P4-SP 是 1-stage x 32-row conventional datapath。

验证入口：

```bash
conda run -n qas python MSDF_iterative_solver/run_parallel_in_fractional_eval.py
```

## Current Mainline: PageRank Digit-Wavefront Feedback

当前主线不再优先做 term-slot 裁剪。P3 默认固定为原始 `MSDF_MUL_ADD_8` strict prior operator，并在 solver 层做 digit-wavefront：

$$
x^{(k)} \rightarrow x^{(k+K)} \rightarrow \text{feedback FIFO} \rightarrow x^{(k+2K)}
$$

新增连续反馈 checkpoint：

- [`prior_rtl/iter_prior_online_mma8_global_feedback_top.v`](./prior_rtl/iter_prior_online_mma8_global_feedback_top.v)
- [`tb/tb_iter_prior_online_mma8_global_feedback_top.v`](./tb/tb_iter_prior_online_mma8_global_feedback_top.v)
- [`run_prior_fractional_feedback_eval.py`](./run_prior_fractional_feedback_eval.py)
- [`generated/prior_fractional_feedback_eval.md`](./generated/prior_fractional_feedback_eval.md)

该路径验证两件事：final-stage committed digit 通过 FIFO 回到 stage0，且每一级 stage 都能同步输出 PageRank L1 delta，用于发现最早收敛 stage。4-term PageRank fractional core 只保留为 experimental resource-cleanup，不进入默认 P3 主线，也不进入默认 sweep。

验证入口：

```bash
conda run -n qas python MSDF_iterative_solver/run_prior_fractional_feedback_eval.py
```

## Goal

论文主张固定为：

$$
\textbf{convergence-aware iteration-fused online arithmetic for affine fixed-point solvers}
$$

目标不是只做更好的 online inner product，而是把下面几段统一到一个在线迭代数据流里：

$$
Gx^{(k)} + c
$$

$$
d^{(k)} = x^{(k+1)} - x^{(k)}
$$

$$
\|d^{(k)}\| \le \varepsilon \; ?
$$

也就是同时消掉两类 boundary：

- `inner-product -> bias/add/update` 的算子边界
- `iteration result -> format conversion -> convergence check -> next iteration` 的迭代边界

## Why This Pivot

当前工程已经得到三个明确结论：

1. 旧非线性主线在单核算术和系统后端两个层面都已经证明不占优。
2. 继续在非线性核上优化，工程收益和论文收益都偏低。
3. online arithmetic 真正成立的地方是高维线性归约核，而不是独立非线性函数本身。

因此新主线不再问旧方向中的函数替代问题，而改成：

$$
\text{MSDF 如何重写高维迭代核的数据流与收敛过程?}
$$

## Relation to the Prior Integrated Inner-Product Paper

本主线直接继承了[基于高效集成在线算术的高维线性系统计算.pdf](/home/sy/FPGA/MSDF/%E5%9F%BA%E4%BA%8E%E9%AB%98%E6%95%88%E9%9B%86%E6%88%90%E5%9C%A8%E7%BA%BF%E7%AE%97%E6%9C%AF%E7%9A%84%E9%AB%98%E7%BB%B4%E7%BA%BF%E6%80%A7%E7%B3%BB%E7%BB%9F%E8%AE%A1%E7%AE%97.pdf)的 integrated online inner-product 思想，但两者不是同一层级的问题。

### What the Prior Paper Does

那篇文章做的是：

$$
\langle x, y \rangle + b
$$

的 integrated online inner product。它解决的是 **算子级** 问题：

- 把 `online multiplier -> online adder tree -> bias add` 的级联 boundary 折叠掉；
- 降低单次 row update 的初始时延；
- 在 `matrix-vector multiply / PageRank` 中证明 integrated row-update 相比 cascaded online 更好。

它的主收益来自：

$$
\theta_{\text{row,cas}} - \theta_{\text{row,int}}
$$

也就是 row-update 这一层的 operator-boundary reduction。

### What This Mainline Does

本主线做的不是“再优化一个 inner product”，而是把 solver 重写成：

$$
x^{(k)} \rightarrow x^{(k+1)} \rightarrow d^{(k)} \rightarrow \text{certification} \rightarrow x^{(k+1)}
$$

也就是说，我们解决的是 **迭代级** 问题，而不是只解决单个 row update。

数学上，本主线利用两件事：

1. `x^{(k+1)}` 和 `d^{(k)}` 都是 affine outputs：

$$
x^{(k+1)} = Gx^{(k)} + c
$$

$$
d^{(k)} = (G-I)x^{(k)} + c
$$

2. prefix digit 天然带有尾项界，因此可对：

$$
\|d^{(k)}\|
$$

做严格在线认证。

所以，本主线的贡献层级高于那篇文章：

- 那篇文章解决 `inner product` 的 online integration；
- 这条主线要解决 `solver iteration` 的 online fusion 与 convergence certification。

### Practical Difference in Dataflow

那篇文章的数据流本质上还是：

$$
\text{row update}
\rightarrow
\text{store / latch}
\rightarrow
\text{next-stage compare / next iteration}
$$

只是 row update 本身从 cascaded 改成了 integrated。

本主线要做的是把下面这些边界一起处理掉：

1. `row update -> x^{(k+1)} full-width materialization`
2. `x^{(k+1)} -> d^{(k)} subtraction`
3. `d^{(k)} -> norm check`
4. `norm check -> next-iteration restart / re-serialization`

因此，新的收益不再只来自 row-update 内部，而来自三项叠加：

$$
\underbrace{\theta_{\text{row,cas}}-\theta_{\text{row,int}}}_{\text{row-update integration}}
+
\underbrace{(q-j_k^\star)}_{\text{online certification}}
+
\underbrace{\Delta T_{\text{boundary}}}_{\text{iteration boundary removal}}
$$

## What Pain Point We Actually Target

本主线理论上要解决的真实痛点，不是“单个乘法器慢”或“单个 adder 慢”，而是高维迭代核里这几类反复出现的系统级开销：

1. **每轮都要把 `x^{(k+1)}` 落成 full-width 再进入下一步**
   这会引入额外存储、格式转换和 handoff 开销。

2. **`delta` 和 convergence check 是独立 kernel**
   即使 row update 已经 integrated，求解器级数据流仍然被切开。

3. **必须算满 `q` 位后才能决定是否停止**
   如果 prefix digit 已足以严格认证收敛，后续低位继续计算就是浪费。

4. **迭代之间有显式 restart / refill / re-serialization 开销**
   对 online arithmetic 来说，这部分边界成本很容易吃掉 row-level 优势。

因此，这条主线的核心意义不是 “更快的 inner product”，而是：

$$
\textbf{把 online arithmetic 的优势从 operator-level 提升到 iteration-level}
$$

## How Important This Is

这个方向有意义，但意义是**有条件成立的**，不是无条件大胜。

### Meaningful Part

当前软件模型已经表明：

- `Gate 1` 通过：在至少一类 workload 上，在线认证确实能比 full `q` 位更早停止；
- `Gate 2` 通过：iteration-fused 相对 cascaded online 有稳定周期优势。

这说明：

1. 这条主线不是空想；
2. 它相对那篇内积论文，确实多解决了 solver-level boundary 和 certification 问题；
3. 它有潜力形成一篇比“更好的 integrated inner product”更高层级的论文。

### Current Limitation

当前软件模型也明确表明：

- `Gate 3` 还没通过：相对 optimistic conventional FPGA proxy，还不能证明 raw cycle 领先。

这意味着，本主线目前的价值更像：

- 更少 iteration boundary
- 更少中间存储
- 更低 DSP 依赖
- 更好的 solver-level online 组织方式

而不是：

$$
\text{我们已经在所有维度上打赢 conventional FPGA}
$$

### Practical Reading of the Current Evidence

因此，本主线现在最稳的表述是：

1. 相比那篇文章，本工作从 row-update integration 升级到了 iteration-fused solver datapath。
2. 它理论上解决了 full-width handoff、独立 delta kernel、独立 norm kernel、逐轮 restart 这些实际痛点。
3. 从论文应用叙事看，`PageRank` 更适合当前定点核心：状态与系数天然有界，非负传播和 fixed-point rail datapath 更匹配。
4. 从 RTL 验证看，`Jacobi` 仍然有价值，因为它覆盖 signed coefficient、halo replay 和更困难的 affine 数值边界；但它不再作为第一应用场景。
5. 当前结果已经足够支撑继续做 PageRank-specific generator、baseline 和 certification，但还不够支撑“已经全面优于 conventional FPGA”的强 claim。

## Problem Definition

第一阶段只研究 affine fixed-point family：

$$
x^{(k+1)} = Gx^{(k)} + c
$$

其中：

- `G` 可以是 dense、sparse 或 block-sparse；
- `x^{(k)}`、`x^{(k+1)}`、`c` 默认为实数向量；
- 收敛判定默认使用 `L_inf` 范数，也保留 `L_1` 作为备选；
- 第一版只考虑数值范围已规约到 online arithmetic 易处理的区间，不在首稿解决完整浮点动态范围。

本方向不把 CG / GMRES 作为起点，因为它们会过早引入：

- dot-product 链间耦合
- `alpha / beta` 更新
- 除法与更复杂的全局同步

## Core Contributions

本方向的论文贡献只保留两条。

### 1. Iteration-Fused Online Datapath

不是把 `SpMV`、`AXPY`、`delta update` 分开做，而是统一成一个在线迭代核：

$$
x^{(k)} \rightarrow x^{(k+1)} \rightarrow d^{(k)} \rightarrow \text{certification}
$$

中间不要求每轮先完整转成 digit-parallel / normal format 再进入下一轮。

### 2. Convergence-Aware Online Certification

对每个分量维护部分和与尾项界。若第 `j` 拍的差值部分和为 `\tilde d_i^{(j)}`，则在线数天然满足尾项界：

$$
|d_i-\tilde d_i^{(j)}| \le 2^{-j+1}
$$

于是：

$$
|d_i| \le |\tilde d_i^{(j)}| + 2^{-j+1}
$$

$$
|d_i| \ge \max\left(0,\ |\tilde d_i^{(j)}| - 2^{-j+1}\right)
$$

对 `L_inf` 范数可得：

$$
\|d\|_\infty \le \max_i |\tilde d_i^{(j)}| + 2^{-j+1}
$$

如果该上界已经不超过 `\varepsilon`，就能严格判定收敛；如果下界已经超过 `\varepsilon`，就能严格判定未收敛。这不是启发式 early stop，而是带数学保证的 online certification。

## Target Workloads

### Phase A

- `PageRank`
- `power iteration`

这两类工作负载的优点是：

- 公式简单；
- 迭代结构清晰；
- 容易对接现有 integrated inner-product 思想；
- baseline 和 end-to-end 结果都比较容易解释。

### Phase B

- `Richardson iteration`
- `Jacobi-style solver`

这一步用来证明方法不是只适用于图问题，而是适用于更一般的 affine fixed-point solver。

## Baselines

baseline 分三层，避免再次出现“只在 MSDF 内部自比”的问题。

### FPGA-B1: Cascaded Online

传统 online primitive 级联：

$$
\text{online multiply} \rightarrow \text{online add tree} \rightarrow \text{iteration update}
$$

这个 baseline 用来证明 iteration-fused 的数学与微架构意义。

### FPGA-B2: Conventional FPGA Kernel

DSP MAC / adder tree / conventional convergence check 的实现。它是工程主 baseline，用来回答：

$$
\text{为什么还需要 online arithmetic?}
$$

### CPU-C0: Software Reference

CPU 只作为应用级参考，不和 FPGA 混资源表。它回答的是：

$$
\text{端到端迭代求解是否有意义?}
$$

## Evaluation Metrics

必须同时报告四类指标：

### Algorithm / Iteration

- `iterations to convergence`
- `effective digits until certification`
- `certified stop cycle`
- `false-stop count = 0`（必须严格为零）

### Hardware

- `cycles / iteration`
- `cycles to convergence`
- `LUT / FF / DSP / BRAM`
- `Fmax / WNS`
- `energy / solve` 或 power proxy

### Dataflow / Memory

- intermediate storage bytes
- required format conversion points
- matrix / vector streaming bandwidth

### Accuracy

- 相对软件 reference 的最终向量误差
- 收敛阈值判定一致性
- 不同矩阵谱半径和条件数下的稳定性

## Architecture Skeleton

第一版目标微架构固定为四块：

1. `matrix streaming engine`
2. `integrated online row-update engine`
3. `online delta / norm-bounds engine`
4. `online state buffer + iteration controller`

其中 `row-update engine` 负责统一生成：

$$
x_i^{(k+1)}
$$

和：

$$
d_i^{(k)} = x_i^{(k+1)} - x_i^{(k)}
$$

`norm-bounds engine` 负责在线给出收敛上界/下界，而不是等完整结果落地后再做一次独立比较。

## Deliverables

本目录后续固定维护以下内容：

- `README.md`：主问题定义、baseline、指标、当前状态
- `ITERATION_FUSED_MATH.md`：完整数学推导，覆盖 integrated row-update、delta 生成、solver 级误差界和在线收敛认证
- `WORKLOADS_AND_BASELINES.md`：固定 W1/W2 工作负载、baseline 层级、公平性规则和第一轮实验矩阵
- `PRIOR_ONLINE_COMPARISON.md`：固定与原始 integrated online inner-product 论文的 P0/P1/P2/P3/P4 同口径对比、RTL 映射和 claim 边界
- `PAGERANK_SAME_SCOPE_REPORT.md`：记录 PageRank global-source fixture、L1 convergence decision、testbench 入口和当前限制
- `PAGERANK_RUNTIME_OPERATION_SPEC.md`：说明当前 PageRank runtime 的实际运算、矩阵规模、数据类型、每阶段公式、P3/P4 执行差异和当前 routed 指标
- `SOLVER_NATIVE_FRACTIONAL_GAP.md`：记录 P3 solver-native 直接接 prior fractional fixture 的失败点、原因和下一版 row engine 合同
- `run_prior_online_original_smoke.py`：原始 `MSDF_MUL_ADD_8` 有限 smoke 入口，用于 P1 rerun 的最小可复现检查
- `make_pagerank_prior_fractional_vectors.py`：生成 prior-compatible fractional PageRank fixture，用于原始 `MSDF_MUL_ADD_8` 同壳 baseline 的严格数制入口
- `run_prior_online_p2_adapter_smoke.py`：P2 prior-online adapter smoke，验证当前 row digit interface 到原始 8-lane operator 的映射、explicit full-word assembly boundary、cluster-level delta/certification wrapper、relaxed PageRank runtime shell 接入，以及 prior-compatible fractional runtime
- `run_pagerank_fractional_same_scope_eval.py`：P2 prior-online fractional 与 P4 conventional fractional 的严格同 fixture 对比入口
- `CYCLE_RESOURCE_MODEL.md`：解析周期/资源模型，明确 B1/B2/fused 的周期项、存储项、DSP/LUT 主导项和 go/no-go 门槛
- `MICROARCHITECTURE_SPEC.md`：目标微架构说明，固定模块边界、`delta` 生成路径、认证引擎位置和 RTL bring-up 顺序
- `ITERATION_FUSED_PLAN.md`：按阶段拆开的工程/论文计划
- `run_iterative_solver_model.py`：软件 golden model 与周期估计入口，负责生成 PageRank/Jacobi 的停止轮数、认证深度 `j_k^*`、B1/B2/fused 周期对比报告
- `run_jacobi_cert_sweep.py`：面向 `Jacobi` 的参数 sweep，展开 `q / eta / rho / degree`，用于判断认证收益对 RTL 参数的敏感性
- 数学推导报告
- cycle/resource model 报告
- 软件 golden model
- RTL 与综合报告

## Current Status

当前已经完成：

1. 数学主文档：
   - [`ITERATION_FUSED_MATH.md`](./ITERATION_FUSED_MATH.md)
2. workload 与 baseline 固定：
   - [`WORKLOADS_AND_BASELINES.md`](./WORKLOADS_AND_BASELINES.md)
3. cycle / resource 解析模型：
   - [`CYCLE_RESOURCE_MODEL.md`](./CYCLE_RESOURCE_MODEL.md)
4. 第一版软件模型与 quick profile 报告：
   - [`run_iterative_solver_model.py`](./run_iterative_solver_model.py)
   - [`generated/iterative_solver_model_report.md`](./generated/iterative_solver_model_report.md)
5. 面向 `Jacobi` 的认证 sweep：
   - [`run_jacobi_cert_sweep.py`](./run_jacobi_cert_sweep.py)
   - [`generated/jacobi_cert_sweep.md`](./generated/jacobi_cert_sweep.md)
6. 目标微架构规格：
   - [`MICROARCHITECTURE_SPEC.md`](./MICROARCHITECTURE_SPEC.md)
7. 第一版 memory-backed RTL top 的 U55C OOC checkpoint：
   - [`generated/u55c_param_bank_ooc_checkpoint.md`](./generated/u55c_param_bank_ooc_checkpoint.md)
8. 第一版 runtime-loadable solver top：
   - [`rtl/iter_runtime_word_bank.v`](./rtl/iter_runtime_word_bank.v)
   - [`rtl/iter_runtime_sdp_field_ram.v`](./rtl/iter_runtime_sdp_field_ram.v)
   - [`rtl/iter_template_field_bank.v`](./rtl/iter_template_field_bank.v)
   - [`rtl/iter_cert_param_field_bank.v`](./rtl/iter_cert_param_field_bank.v)
   - [`rtl/iter_dense_small_runtime_top.v`](./rtl/iter_dense_small_runtime_top.v)
   - [`tb/tb_iter_dense_small_runtime_top.v`](./tb/tb_iter_dense_small_runtime_top.v)
   - [`summarize_runtime_top_reports.py`](./summarize_runtime_top_reports.py)
   - [`generated/u55c_runtime_top_ooc_checkpoint.md`](./generated/u55c_runtime_top_ooc_checkpoint.md)
   - [`generated/runtime_top_scale_sweep.md`](./generated/runtime_top_scale_sweep.md)
   - [`generated/runtime_top_auto_report.md`](./generated/runtime_top_auto_report.md)
9. 第一版 32 active-row runtime workload 功能检查：
   - [`make_jacobi32_blockdiag_runtime_vectors.py`](./make_jacobi32_blockdiag_runtime_vectors.py)
   - [`tb/tb_iter_dense_runtime_jacobi32_blockdiag.v`](./tb/tb_iter_dense_runtime_jacobi32_blockdiag.v)
   - [`generated/rtl_vectors/jacobi32_blockdiag/summary.json`](./generated/rtl_vectors/jacobi32_blockdiag/summary.json)
   - [`generated/runtime_jacobi32_blockdiag_function_report.md`](./generated/runtime_jacobi32_blockdiag_function_report.md)
10. 第一版 32 active-row multi-iteration solver checkpoint：
   - [`make_jacobi32_blockdiag_multi_runtime_vectors.py`](./make_jacobi32_blockdiag_multi_runtime_vectors.py)
   - [`tb/tb_iter_dense_runtime_jacobi32_blockdiag_multi.v`](./tb/tb_iter_dense_runtime_jacobi32_blockdiag_multi.v)
   - [`generated/rtl_vectors/jacobi32_blockdiag_multi/summary.json`](./generated/rtl_vectors/jacobi32_blockdiag_multi/summary.json)
   - [`generated/runtime_jacobi32_blockdiag_multi_solver_report.md`](./generated/runtime_jacobi32_blockdiag_multi_solver_report.md)
11. 第一版 raw banded `32x32` global-source solver checkpoint：
   - [`make_jacobi32_global_runtime_vectors.py`](./make_jacobi32_global_runtime_vectors.py)
   - [`tb/tb_iter_dense_runtime_jacobi32_global_multi.v`](./tb/tb_iter_dense_runtime_jacobi32_global_multi.v)
   - [`generated/rtl_vectors/jacobi32_global/summary.json`](./generated/rtl_vectors/jacobi32_global/summary.json)
   - [`generated/runtime_jacobi32_global_solver_report.md`](./generated/runtime_jacobi32_global_solver_report.md)
12. 第一版 raw banded `32x32` halo-window solver checkpoint：
   - [`make_jacobi32_halo_runtime_vectors.py`](./make_jacobi32_halo_runtime_vectors.py)
   - [`tb/tb_iter_dense_runtime_jacobi32_halo_multi.v`](./tb/tb_iter_dense_runtime_jacobi32_halo_multi.v)
   - [`tb/tb_iter_dense_runtime_jacobi32_halo_reg_multi.v`](./tb/tb_iter_dense_runtime_jacobi32_halo_reg_multi.v)
   - [`generated/rtl_vectors/jacobi32_halo/summary.json`](./generated/rtl_vectors/jacobi32_halo/summary.json)
   - [`generated/runtime_jacobi32_halo_solver_report.md`](./generated/runtime_jacobi32_halo_solver_report.md)
13. 第一版 conventional FPGA-B2 datapath lower-bound checkpoint：
   - [`rtl/conv_signed_row_update_delta_slice.v`](./rtl/conv_signed_row_update_delta_slice.v)
   - [`rtl/conv_signed_row_update_delta_slice_pipe.v`](./rtl/conv_signed_row_update_delta_slice_pipe.v)
   - [`rtl/iter_fixed_degree_state_word_replay.v`](./rtl/iter_fixed_degree_state_word_replay.v)
   - [`rtl/conv_row_cluster_delta_cert.v`](./rtl/conv_row_cluster_delta_cert.v)
   - [`rtl/conv_jacobi_datapath_array_top.v`](./rtl/conv_jacobi_datapath_array_top.v)
   - [`tb/tb_conv_jacobi_datapath_array_top.v`](./tb/tb_conv_jacobi_datapath_array_top.v)
   - [`make_jacobi32_halo_conv_runtime_vectors.py`](./make_jacobi32_halo_conv_runtime_vectors.py)
   - [`tb/tb_iter_dense_runtime_jacobi32_halo_reg_conv_multi.v`](./tb/tb_iter_dense_runtime_jacobi32_halo_reg_conv_multi.v)
   - [`synth_conv_jacobi_datapath_array_top.tcl`](./synth_conv_jacobi_datapath_array_top.tcl)
   - [`generated/conv_jacobi_datapath_baseline_report.md`](./generated/conv_jacobi_datapath_baseline_report.md)
   - [`generated/runtime_conventional_baseline_report.md`](./generated/runtime_conventional_baseline_report.md)
14. 第一版 binary-I/O wrapper checkpoint：
   - [`rtl/iter_signed_to_rail.v`](./rtl/iter_signed_to_rail.v)
   - [`rtl/iter_rail_to_signed.v`](./rtl/iter_rail_to_signed.v)
   - [`rtl/iter_dense_small_runtime_binary_io_top.v`](./rtl/iter_dense_small_runtime_binary_io_top.v)
   - [`tb/tb_iter_signed_rail_codec.v`](./tb/tb_iter_signed_rail_codec.v)
   - [`tb/tb_iter_dense_small_runtime_binary_io_top.v`](./tb/tb_iter_dense_small_runtime_binary_io_top.v)
   - [`synth_iter_dense_small_runtime_top.tcl`](./synth_iter_dense_small_runtime_top.tcl), with `MSDF_TOP=iter_dense_small_runtime_binary_io_top`

当前最重要的阶段性结论是：

- 论文应用场景锁定为 `PageRank`；现有 `jacobi32_*` 是 affine/wavefront RTL 结构验证 fixture，不是最终应用 benchmark；
- PageRank 适合当前定点核心，因为 rank/state 与转移系数天然在 `[0,1]` 附近，避免 Jacobi 可能大于 1 的整数位压力；
- solver-level 认证收益已经出现；
- iteration-fused 相对 cascaded online 已成立；
- conventional DSP-MAC datapath 下界和 runtime-equivalent baseline 都已经 routed；
- 在同样 loader、state bank、halo replay、certification 和 controller 下，当前 online solver 相对 pipelined conventional DSP-MAC baseline 已经同时降低 LUT、FF、DSP 和动态功耗，并有更好的 WNS；
- conventional runtime 已补 full-word golden 与 6 轮 solver-level cycle validation，当前 fast-done NC8 fixture 为旧 online digit-slice `151` cycles、conventional `157` cycles；该旧 online path 只作为 prior datapath checkpoint，不是当前 solver-native 主线；
- binary-I/O wrapper 已补：外部 state/coeff/bias 使用 signed two's-complement binary，内部仍自动转换到 `p/n` 差分对 datapath，输出 state 再转回 signed binary；
- 当前已补 `pagerank32_global` graph-to-template generator、PageRank digit-final `L1` certification 汇总、PageRank-equivalent conventional runtime baseline 入口、P1 原始 `MSDF_MUL_ADD_8` finite smoke、P2 prior-online row-kernel adapter smoke、P2 explicit full-word assembler smoke、P2 cluster delta/certification smoke，以及 `ROW_DATAPATH_MODE=5` relaxed same-shell runtime smoke；
- 已确认原始 `MSDF_MUL_ADD_8` 需要 per-operation reset，且其乘积路径是 fractional online contract，不是当前 integer PageRank fixture 的普通 MAC；
- 已新增 `pagerank32_global_prior_fractional` fixture，并通过 P2 prior-compatible runtime：`total=227 / issue=4 / cert_wait=124`，该结果使用 `BIT_WIDTH=11`、`DATA_WIDTH=14`、fraction-only capture 和 `<=4 LSB` online rounding tolerance；
- 已补 P2-proxy full-digit fractional reference：`total=183 / issue=56 / cert_wait=80`，使用 per-term rounded product shift，数值上和 P4 fractional 同 golden；
- 已补 P3 prior digit-stream fractional candidate：`total=215 / issue=56 / cert_wait=112`，复用原始 `MSDF_MUL_ADD_8` 输出 digit 直接 commit 到 state bank，但当前仍慢于 P2-proxy/P4；
- 已补 standalone strict prior-fractional K-stage wavefront：`K=2/3/4` 分别为 `36/46/56` cycles，最终 state 均与 `pagerank32_global_prior_fractional` golden 在 `<=4 LSB` 内一致；该入口证明原始 `MSDF_MUL_ADD_8` 可以做 stage-to-stage committed digit 级联，但尚未计入 runtime loader/certification；
- 已补 P3 strict prior-fractional K=4 runtime wavefront：`compute=70 / issue=14 / cert_wait=56 / observed_total=150`，最终 state 对齐第 4 轮 fractional golden，认证语义为 last-step delta `x^(k+4)-x^(k+3)`；该版本相对 P3 prior digit-stream `168` compute cycles 提升 `2.400x`，但仍慢于 P4 conventional fractional `36` compute cycles；
- 已补 P4 conventional fractional same-fixture baseline：`total=135 / issue=4 / cert_wait=32`，说明只接入原论文 online operator 还不能击败干净 DSP-MAC baseline；
- 已 probe P3 solver-native 直接接 fractional fixture，当前第 0 轮 `max_error=24` vs golden `156`，说明现有 mode3 是 integer/guarded bring-up，不是正确 prior fractional product recurrence；
- 已补 timing-clean P4 conventional fractional baseline：global replay register + product-rounding pipeline，功能为 `compute=44 / issue=4 / cert_wait=40 / observed_total=143`。为对齐原始 `MSDF_MUL_ADD_8` 的 8 路物理槽位，当前公平 routed 口径使用 reserved 8-slot P4：`WNS +0.052 ns / 59482 LUT / 23753 FF / 320 DSP / 10.5 BRAM / dynamic 2.390 W`；与 P3 routed 对比后，当前结论是 P3 省 DSP/动态功耗但不赢 compute cycle/LUT/FF。

## Current Document Index

当前主文档已经落在：

- [`ITERATION_FUSED_MATH.md`](./ITERATION_FUSED_MATH.md)
- [`WORKLOADS_AND_BASELINES.md`](./WORKLOADS_AND_BASELINES.md)
- [`PAGERANK_APPLICATION_LOCK.md`](./PAGERANK_APPLICATION_LOCK.md)
- [`PRIOR_ONLINE_COMPARISON.md`](./PRIOR_ONLINE_COMPARISON.md)
- [`PAGERANK_SAME_SCOPE_REPORT.md`](./PAGERANK_SAME_SCOPE_REPORT.md)
- [`CYCLE_RESOURCE_MODEL.md`](./CYCLE_RESOURCE_MODEL.md)
- [`MICROARCHITECTURE_SPEC.md`](./MICROARCHITECTURE_SPEC.md)
- [`ORIGINAL_PAPER_REANALYSIS.md`](./ORIGINAL_PAPER_REANALYSIS.md)
- [`SOLVER_NATIVE_DIGIT_STREAM_ARCHITECTURE.md`](./SOLVER_NATIVE_DIGIT_STREAM_ARCHITECTURE.md)
- [`OPERATOR_SOURCE_REVIEW.md`](./OPERATOR_SOURCE_REVIEW.md)
- [`OPERATOR_TO_SOLVER_BRIDGE.md`](./OPERATOR_TO_SOLVER_BRIDGE.md)
- [`RESEARCH_AND_INNOVATION_ROADMAP.md`](./RESEARCH_AND_INNOVATION_ROADMAP.md)
- [`PRE_RTL_TOP_DOWN_ARCHITECTURE.md`](./PRE_RTL_TOP_DOWN_ARCHITECTURE.md)
- [`COEFF_TEMPLATE_FORMAT.md`](./COEFF_TEMPLATE_FORMAT.md)
- [`PREFIX_SAFE_STENCIL_STREAMING.md`](./PREFIX_SAFE_STENCIL_STREAMING.md)
- [`WAVEFRONT_DIGIT_STREAMING.md`](./WAVEFRONT_DIGIT_STREAMING.md)
- [`PAGERANK_WAVEFRONT_STAGE_DEPTH.md`](./PAGERANK_WAVEFRONT_STAGE_DEPTH.md)

当前最关键的模型输出位于：

- [`generated/const_coeff_specialization_report.md`](./generated/const_coeff_specialization_report.md)
- [`generated/local_cert_sweep.md`](./generated/local_cert_sweep.md)
- [`generated/specialized_stack_eval.md`](./generated/specialized_stack_eval.md)
- [`generated/u55c_param_bank_ooc_checkpoint.md`](./generated/u55c_param_bank_ooc_checkpoint.md)
- [`generated/u55c_runtime_top_ooc_checkpoint.md`](./generated/u55c_runtime_top_ooc_checkpoint.md)
- [`generated/runtime_top_scale_sweep.md`](./generated/runtime_top_scale_sweep.md)
- [`generated/runtime_top_auto_report.md`](./generated/runtime_top_auto_report.md)
- [`generated/runtime_jacobi32_blockdiag_function_report.md`](./generated/runtime_jacobi32_blockdiag_function_report.md)
- [`generated/runtime_jacobi32_blockdiag_multi_solver_report.md`](./generated/runtime_jacobi32_blockdiag_multi_solver_report.md)
- [`generated/runtime_jacobi32_global_solver_report.md`](./generated/runtime_jacobi32_global_solver_report.md)
- [`generated/full_digit_bridge_checkpoint.md`](./generated/full_digit_bridge_checkpoint.md)
- [`generated/digit_stream_state_checkpoint.md`](./generated/digit_stream_state_checkpoint.md)
- [`generated/digit_stream_row_update_exploration.md`](./generated/digit_stream_row_update_exploration.md)
- [`generated/solver_native_digit_stream_checkpoint.md`](./generated/solver_native_digit_stream_checkpoint.md)
- [`generated/solver_native_mode3_runtime_probe.md`](./generated/solver_native_mode3_runtime_probe.md)
- [`generated/prefix_safe_stencil_gate_checkpoint.md`](./generated/prefix_safe_stencil_gate_checkpoint.md)
- [`generated/wavefront_digit_stream_checkpoint.md`](./generated/wavefront_digit_stream_checkpoint.md)
- [`generated/wavefront_digit_stream_sweep.md`](./generated/wavefront_digit_stream_sweep.md)
- [`generated/wavefront_commit_stream_sweep.md`](./generated/wavefront_commit_stream_sweep.md)
- [`generated/wavefront_stage_depth_model.md`](./generated/wavefront_stage_depth_model.md)
- [`generated/pagerank_wavefront_stage_sweep.md`](./generated/pagerank_wavefront_stage_sweep.md)
- [`generated/prior_fractional_wavefront_sweep.md`](./generated/prior_fractional_wavefront_sweep.md)
- [`generated/prior_fractional_feedback_eval.md`](./generated/prior_fractional_feedback_eval.md)
- [`generated/pagerank_fractional_routed_backend_report.md`](./generated/pagerank_fractional_routed_backend_report.md)
- [`PAGERANK_RUNTIME_OPERATION_SPEC.md`](./PAGERANK_RUNTIME_OPERATION_SPEC.md)

当前已经落地的第一版 RTL / 工具脚本位于：

- [`compile_coeff_templates.py`](./compile_coeff_templates.py)
- [`pack_fixed_degree_templates.py`](./pack_fixed_degree_templates.py)
- [`pack_cert_params.py`](./pack_cert_params.py)
- [`run_iter_rtl_vector_gen.py`](./run_iter_rtl_vector_gen.py)
- [`make_jacobi32_blockdiag_runtime_vectors.py`](./make_jacobi32_blockdiag_runtime_vectors.py)
- [`make_jacobi32_blockdiag_full_digit_runtime_vectors.py`](./make_jacobi32_blockdiag_full_digit_runtime_vectors.py)
- [`make_jacobi32_blockdiag_multi_runtime_vectors.py`](./make_jacobi32_blockdiag_multi_runtime_vectors.py)
- [`make_jacobi32_global_runtime_vectors.py`](./make_jacobi32_global_runtime_vectors.py)
- [`summarize_runtime_top_reports.py`](./summarize_runtime_top_reports.py)
- [`run_wavefront_digit_stream_sweep.py`](./run_wavefront_digit_stream_sweep.py)
- [`run_wavefront_commit_sweep.py`](./run_wavefront_commit_sweep.py)
- [`model_wavefront_stage_depth.py`](./model_wavefront_stage_depth.py)
- [`run_pagerank_wavefront_stage_sweep.py`](./run_pagerank_wavefront_stage_sweep.py)
- [`run_prior_fractional_wavefront_sweep.py`](./run_prior_fractional_wavefront_sweep.py)
- [`run_prior_fractional_feedback_eval.py`](./run_prior_fractional_feedback_eval.py)
- [`synth_iter_dense_small_param_bank_top.tcl`](./synth_iter_dense_small_param_bank_top.tcl)
- [`synth_iter_dense_small_runtime_top.tcl`](./synth_iter_dense_small_runtime_top.tcl)
- [`rtl/online_const_coeff_contrib.v`](./rtl/online_const_coeff_contrib.v)
- [`rtl/online_affine_row_update_core.v`](./rtl/online_affine_row_update_core.v)
- [`rtl/online_delta_linf_cert_core.v`](./rtl/online_delta_linf_cert_core.v)
- [`rtl/online_row_update_delta_slice.v`](./rtl/online_row_update_delta_slice.v)
- [`rtl/block_bound_max_pool.v`](./rtl/block_bound_max_pool.v)
- [`rtl/block_h_cert_engine.v`](./rtl/block_h_cert_engine.v)
- [`rtl/online_row_cluster_block_cert.v`](./rtl/online_row_cluster_block_cert.v)
- [`rtl/online_row_cluster_delta_cert.v`](./rtl/online_row_cluster_delta_cert.v)
- [`rtl/iter_cluster_cert_controller.v`](./rtl/iter_cluster_cert_controller.v)
- [`rtl/iter_dense_small_closed_loop_top.v`](./rtl/iter_dense_small_closed_loop_top.v)
- [`rtl/iter_row_state_handoff_buffer.v`](./rtl/iter_row_state_handoff_buffer.v)
- [`rtl/iter_dense_small_handoff_top.v`](./rtl/iter_dense_small_handoff_top.v)
- [`rtl/iter_fixed_degree_state_replay.v`](./rtl/iter_fixed_degree_state_replay.v)
- [`rtl/iter_dense_small_replay_top.v`](./rtl/iter_dense_small_replay_top.v)
- [`rtl/iter_state_ping_pong_bank.v`](./rtl/iter_state_ping_pong_bank.v)
- [`rtl/iter_dense_small_ping_pong_top.v`](./rtl/iter_dense_small_ping_pong_top.v)
- [`rtl/iter_fixed_degree_row_scheduler.v`](./rtl/iter_fixed_degree_row_scheduler.v)
- [`rtl/iter_dense_small_sched_top.v`](./rtl/iter_dense_small_sched_top.v)
- [`rtl/iter_fixed_degree_template_rom.v`](./rtl/iter_fixed_degree_template_rom.v)
- [`rtl/iter_fixed_degree_template_unpack.v`](./rtl/iter_fixed_degree_template_unpack.v)
- [`rtl/iter_dense_small_template_top.v`](./rtl/iter_dense_small_template_top.v)
- [`rtl/iter_fixed_degree_template_bank.v`](./rtl/iter_fixed_degree_template_bank.v)
- [`rtl/iter_runtime_word_bank.v`](./rtl/iter_runtime_word_bank.v)
- [`rtl/iter_runtime_sdp_field_ram.v`](./rtl/iter_runtime_sdp_field_ram.v)
- [`rtl/iter_template_field_bank.v`](./rtl/iter_template_field_bank.v)
- [`rtl/iter_cert_param_bank.v`](./rtl/iter_cert_param_bank.v)
- [`rtl/iter_cert_param_field_bank.v`](./rtl/iter_cert_param_field_bank.v)
- [`rtl/iter_cert_param_unpack.v`](./rtl/iter_cert_param_unpack.v)
- [`rtl/iter_dense_small_param_bank_top.v`](./rtl/iter_dense_small_param_bank_top.v)
- [`rtl/iter_dense_small_runtime_top.v`](./rtl/iter_dense_small_runtime_top.v)
- [`rtl/iter_digit_prefix_scheduler.v`](./rtl/iter_digit_prefix_scheduler.v)
- [`rtl/iter_prefix_safe_stencil_gate.v`](./rtl/iter_prefix_safe_stencil_gate.v)
- [`rtl/iter_prefix_safe_issue_controller.v`](./rtl/iter_prefix_safe_issue_controller.v)
- [`rtl/iter_prefix_safe_two_stage_probe.v`](./rtl/iter_prefix_safe_two_stage_probe.v)
- [`rtl/iter_prefix_safe_row_start_queue.v`](./rtl/iter_prefix_safe_row_start_queue.v)
- [`rtl/iter_prefix_safe_two_stage_scheduler.v`](./rtl/iter_prefix_safe_two_stage_scheduler.v)
- [`rtl/iter_prefix_safe_consumer_stub.v`](./rtl/iter_prefix_safe_consumer_stub.v)
- [`rtl/iter_prefix_safe_digit_replay_source.v`](./rtl/iter_prefix_safe_digit_replay_source.v)
- [`rtl/iter_prefix_safe_solver_native_row_lane.v`](./rtl/iter_prefix_safe_solver_native_row_lane.v)
- [`rtl/iter_fullword_row_start_scheduler.v`](./rtl/iter_fullword_row_start_scheduler.v)
- [`rtl/iter_prefix_safe_row_start_multi_lane_dispatcher.v`](./rtl/iter_prefix_safe_row_start_multi_lane_dispatcher.v)
- [`rtl/iter_prefix_safe_two_stage_multilane_scheduler.v`](./rtl/iter_prefix_safe_two_stage_multilane_scheduler.v)
- [`rtl/iter_fullword_row_start_multilane_scheduler.v`](./rtl/iter_fullword_row_start_multilane_scheduler.v)
- [`rtl/iter_wavefront_digit_delay_line.v`](./rtl/iter_wavefront_digit_delay_line.v)
- [`rtl/iter_wavefront_two_stage_row_pipeline.v`](./rtl/iter_wavefront_two_stage_row_pipeline.v)
- [`rtl/iter_wavefront_radius1_two_stage_cluster.v`](./rtl/iter_wavefront_radius1_two_stage_cluster.v)
- [`rtl/iter_wavefront_radius1_multistage_cluster.v`](./rtl/iter_wavefront_radius1_multistage_cluster.v)
- [`rtl/iter_wavefront_commit_stage_cluster.v`](./rtl/iter_wavefront_commit_stage_cluster.v)
- [`rtl/iter_wavefront_radius1_commit_multistage_cluster.v`](./rtl/iter_wavefront_radius1_commit_multistage_cluster.v)
- [`rtl/iter_wavefront_commit_last_delta_cert_top.v`](./rtl/iter_wavefront_commit_last_delta_cert_top.v)
- [`rtl/iter_wavefront_superstep_cluster_state_top.v`](./rtl/iter_wavefront_superstep_cluster_state_top.v)
- [`prior_rtl/iter_prior_online_mma8_stream_stage_cluster.v`](./prior_rtl/iter_prior_online_mma8_stream_stage_cluster.v)
- [`prior_rtl/iter_prior_online_mma8_global_wavefront_top.v`](./prior_rtl/iter_prior_online_mma8_global_wavefront_top.v)
- [`prior_rtl/iter_prior_online_mma8_global_feedback_top.v`](./prior_rtl/iter_prior_online_mma8_global_feedback_top.v)
- [`rtl/iter_digit_serial_full_row_update_delta_slice.v`](./rtl/iter_digit_serial_full_row_update_delta_slice.v)
- [`rtl/iter_digit_serial_full_row_cluster_delta_cert.v`](./rtl/iter_digit_serial_full_row_cluster_delta_cert.v)
- [`rtl/iter_digit_stream_state_ping_pong_bank.v`](./rtl/iter_digit_stream_state_ping_pong_bank.v)
- [`rtl/iter_digit_stream_state_replay_top.v`](./rtl/iter_digit_stream_state_replay_top.v)
- [`rtl/iter_online_output_update.v`](./rtl/iter_online_output_update.v)
- [`rtl/iter_online_affine_digit_core.v`](./rtl/iter_online_affine_digit_core.v)
- [`rtl/iter_online_affine_digit_row.v`](./rtl/iter_online_affine_digit_row.v)
- [`tb/tb_online_const_coeff_contrib.v`](./tb/tb_online_const_coeff_contrib.v)
- [`tb/tb_online_delta_linf_cert_core.v`](./tb/tb_online_delta_linf_cert_core.v)
- [`tb/tb_block_h_cert_engine.v`](./tb/tb_block_h_cert_engine.v)
- [`tb/tb_online_affine_row_update_core.v`](./tb/tb_online_affine_row_update_core.v)
- [`tb/tb_online_row_update_delta_slice.v`](./tb/tb_online_row_update_delta_slice.v)
- [`tb/tb_block_bound_max_pool.v`](./tb/tb_block_bound_max_pool.v)
- [`tb/tb_online_row_cluster_block_cert.v`](./tb/tb_online_row_cluster_block_cert.v)
- [`tb/tb_online_row_cluster_delta_cert.v`](./tb/tb_online_row_cluster_delta_cert.v)
- [`tb/tb_iter_cluster_cert_controller.v`](./tb/tb_iter_cluster_cert_controller.v)
- [`tb/tb_iter_dense_small_closed_loop_top.v`](./tb/tb_iter_dense_small_closed_loop_top.v)
- [`tb/tb_iter_dense_small_handoff_top.v`](./tb/tb_iter_dense_small_handoff_top.v)
- [`tb/tb_iter_fixed_degree_state_replay.v`](./tb/tb_iter_fixed_degree_state_replay.v)
- [`tb/tb_iter_dense_small_replay_top.v`](./tb/tb_iter_dense_small_replay_top.v)
- [`tb/tb_iter_state_ping_pong_bank.v`](./tb/tb_iter_state_ping_pong_bank.v)
- [`tb/tb_iter_dense_small_ping_pong_top.v`](./tb/tb_iter_dense_small_ping_pong_top.v)
- [`tb/tb_iter_fixed_degree_row_scheduler.v`](./tb/tb_iter_fixed_degree_row_scheduler.v)
- [`tb/tb_iter_dense_small_sched_top.v`](./tb/tb_iter_dense_small_sched_top.v)
- [`tb/tb_iter_dense_small_template_top.v`](./tb/tb_iter_dense_small_template_top.v)
- [`tb/tb_iter_param_banks.v`](./tb/tb_iter_param_banks.v)
- [`tb/tb_iter_dense_small_param_bank_top.v`](./tb/tb_iter_dense_small_param_bank_top.v)
- [`tb/tb_online_row_cluster_delta_cert_file.v`](./tb/tb_online_row_cluster_delta_cert_file.v)
- [`tb/tb_iter_dense_small_param_bank_top_file.v`](./tb/tb_iter_dense_small_param_bank_top_file.v)
- [`tb/tb_iter_dense_small_runtime_top.v`](./tb/tb_iter_dense_small_runtime_top.v)
- [`tb/tb_iter_dense_runtime_jacobi32_blockdiag.v`](./tb/tb_iter_dense_runtime_jacobi32_blockdiag.v)
- [`tb/tb_iter_dense_runtime_jacobi32_blockdiag_multi.v`](./tb/tb_iter_dense_runtime_jacobi32_blockdiag_multi.v)
- [`tb/tb_iter_dense_runtime_jacobi32_global_multi.v`](./tb/tb_iter_dense_runtime_jacobi32_global_multi.v)
- [`tb/tb_iter_dense_runtime_jacobi32_halo_multi.v`](./tb/tb_iter_dense_runtime_jacobi32_halo_multi.v)
- [`tb/tb_iter_dense_runtime_jacobi32_halo_reg_multi.v`](./tb/tb_iter_dense_runtime_jacobi32_halo_reg_multi.v)
- [`tb/tb_iter_digit_prefix_scheduler.v`](./tb/tb_iter_digit_prefix_scheduler.v)
- [`tb/tb_iter_prefix_safe_stencil_gate.v`](./tb/tb_iter_prefix_safe_stencil_gate.v)
- [`tb/tb_iter_prefix_safe_issue_controller.v`](./tb/tb_iter_prefix_safe_issue_controller.v)
- [`tb/tb_iter_prefix_safe_two_stage_probe.v`](./tb/tb_iter_prefix_safe_two_stage_probe.v)
- [`tb/tb_iter_prefix_safe_row_start_queue.v`](./tb/tb_iter_prefix_safe_row_start_queue.v)
- [`tb/tb_iter_prefix_safe_two_stage_scheduler.v`](./tb/tb_iter_prefix_safe_two_stage_scheduler.v)
- [`tb/tb_iter_prefix_safe_scheduler_consumer_stub.v`](./tb/tb_iter_prefix_safe_scheduler_consumer_stub.v)
- [`tb/tb_iter_prefix_safe_digit_replay_source.v`](./tb/tb_iter_prefix_safe_digit_replay_source.v)
- [`tb/tb_iter_prefix_safe_scheduler_solver_native_lane.v`](./tb/tb_iter_prefix_safe_scheduler_solver_native_lane.v)
- [`tb/tb_iter_prefix_safe_scheduler_solver_native_replay.v`](./tb/tb_iter_prefix_safe_scheduler_solver_native_replay.v)
- [`tb/tb_iter_prefix_safe_overlap_perf_probe.v`](./tb/tb_iter_prefix_safe_overlap_perf_probe.v)
- [`tb/tb_iter_prefix_safe_multilane_overlap_perf_probe.v`](./tb/tb_iter_prefix_safe_multilane_overlap_perf_probe.v)
- [`tb/tb_iter_wavefront_two_stage_row_pipeline.v`](./tb/tb_iter_wavefront_two_stage_row_pipeline.v)
- [`tb/tb_iter_wavefront_radius1_two_stage_cluster.v`](./tb/tb_iter_wavefront_radius1_two_stage_cluster.v)
- [`tb/tb_iter_wavefront_radius1_multistage_cluster.v`](./tb/tb_iter_wavefront_radius1_multistage_cluster.v)
- [`tb/tb_iter_wavefront_radius1_commit_multistage_cluster.v`](./tb/tb_iter_wavefront_radius1_commit_multistage_cluster.v)
- [`tb/tb_iter_wavefront_commit_last_delta_cert_top.v`](./tb/tb_iter_wavefront_commit_last_delta_cert_top.v)
- [`tb/tb_iter_wavefront_superstep_cluster_state_top.v`](./tb/tb_iter_wavefront_superstep_cluster_state_top.v)
- [`tb/tb_iter_prior_online_mma8_global_wavefront_top.v`](./tb/tb_iter_prior_online_mma8_global_wavefront_top.v)
- [`tb/tb_iter_prior_online_mma8_global_feedback_top.v`](./tb/tb_iter_prior_online_mma8_global_feedback_top.v)
- [`tb/tb_iter_dense_runtime_wavefront_superstep_smoke.v`](./tb/tb_iter_dense_runtime_wavefront_superstep_smoke.v)
- [`tb/tb_iter_dense_runtime_jacobi32_blockdiag_wavefront_superstep.v`](./tb/tb_iter_dense_runtime_jacobi32_blockdiag_wavefront_superstep.v)
- [`tb/tb_iter_dense_runtime_jacobi32_halo_reg_wavefront_superstep.v`](./tb/tb_iter_dense_runtime_jacobi32_halo_reg_wavefront_superstep.v)
- [`tb/tb_iter_dense_runtime_jacobi32_halo_reg_solver_native_four.v`](./tb/tb_iter_dense_runtime_jacobi32_halo_reg_solver_native_four.v)
- [`tb/tb_iter_digit_serial_full_row_update_delta_slice.v`](./tb/tb_iter_digit_serial_full_row_update_delta_slice.v)
- [`tb/tb_iter_digit_serial_full_row_cluster_delta_cert.v`](./tb/tb_iter_digit_serial_full_row_cluster_delta_cert.v)
- [`tb/tb_iter_digit_stream_state_ping_pong_bank.v`](./tb/tb_iter_digit_stream_state_ping_pong_bank.v)
- [`tb/tb_iter_digit_stream_state_replay_top.v`](./tb/tb_iter_digit_stream_state_replay_top.v)
- [`tb/tb_iter_online_output_update.v`](./tb/tb_iter_online_output_update.v)
- [`tb/tb_iter_dense_runtime_jacobi32_halo_reg_full_digit_multi.v`](./tb/tb_iter_dense_runtime_jacobi32_halo_reg_full_digit_multi.v)
- [`tb/tb_iter_dense_runtime_jacobi32_halo_reg_full_digit_prefix_multi.v`](./tb/tb_iter_dense_runtime_jacobi32_halo_reg_full_digit_prefix_multi.v)
- [`run_iterative_solver_rtl_smoke.tcl`](./run_iterative_solver_rtl_smoke.tcl)

当前最小 template 样例位于：

- [`testdata/blockdiag8_matrix.json`](./testdata/blockdiag8_matrix.json)
- [`testdata/blockdiag8_cert_params.json`](./testdata/blockdiag8_cert_params.json)
- [`generated/blockdiag8_coeff_templates.json`](./generated/blockdiag8_coeff_templates.json)
- [`generated/blockdiag8_fixed4_templates.memh`](./generated/blockdiag8_fixed4_templates.memh)
- [`generated/blockdiag8_cert_params.memh`](./generated/blockdiag8_cert_params.memh)
- [`generated/rtl_vectors/blockdiag8/summary.json`](./generated/rtl_vectors/blockdiag8/summary.json)
- [`generated/rtl_vectors/jacobi32_blockdiag/summary.json`](./generated/rtl_vectors/jacobi32_blockdiag/summary.json)
- [`generated/rtl_vectors/jacobi32_blockdiag_multi/summary.json`](./generated/rtl_vectors/jacobi32_blockdiag_multi/summary.json)
- [`generated/rtl_vectors/jacobi32_global/summary.json`](./generated/rtl_vectors/jacobi32_global/summary.json)
- [`generated/rtl_vectors/jacobi32_halo/summary.json`](./generated/rtl_vectors/jacobi32_halo/summary.json)

## Runtime-Loadable Top Boundary

`iter_dense_small_runtime_top.v` 是从 `$readmemh` 小样例走向真实系统接口的第一步。它新增三类 runtime 配置入口：

- `i_cfg_template_we / i_cfg_template_word`：写入每个 cluster 的 row-template packed payload
- `i_cfg_cert_we / i_cfg_cert_word`：写入每个 cluster 的 `block_H` certification payload
- `i_cfg_state_we / i_cfg_state_*`：写入当前活动 cluster slot 的 ping-pong state row word

当前 runtime bank 已从组合 window read 改为同步读 + window cache：host 先写入 cluster payload，再 pulse `i_load_window`，bank 用 `NUM_CLUSTERS` 个周期把从 `i_base_cluster_idx` 开始的 active window 装入 cache。`o_window_valid` 拉高后，scheduler/unpack/core 才应该启动。这个边界更接近 BRAM/URAM 实现，避免大规模 cluster memory 直接出现在组合路径上。

最新版本进一步把原先的超宽 packed payload bank 拆成窄 field banks，并通过标准同步 RAM wrapper 收敛成可推断 BRAM 的物理形态：

- [`rtl/iter_runtime_sdp_field_ram.v`](./rtl/iter_runtime_sdp_field_ram.v)：标准 1W1R 同步 RAM wrapper，避免 field bank 内部直接动态读宽数组。
- [`rtl/iter_template_field_bank.v`](./rtl/iter_template_field_bank.v)：按 `valid/src/coeff_p/coeff_n/bias_p/bias_n` 分库存储 template payload。
- [`rtl/iter_cert_param_field_bank.v`](./rtl/iter_cert_param_field_bank.v)：按 `block_H weights/eta` 分库存储 certification payload。

外部接口仍然写入 packed payload，内部只改变存储物理形态。这样做的直接效果是去掉 `NUM_TOTAL_CLUSTERS` 扩展时的 FF 线性爆炸，并让 template/cert storage 推断为 BRAM。当前 `NTC=2/8/16/32` 已完成 U55C 5 ns route，`NTC=64/128/256` 已完成 synth-only 存储探针；默认 `runtime_mem_style=1` 的 RAM-wrapper 版本保持 `LUTRAM=0`、`BRAM=8.5`，LUT/FF 基本不随深度增长。`runtime_mem_style=0` 可用于 tiny regression 的 distributed-RAM 模式。

当前 runtime top 也暴露了第一组 counters：

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

这组 counters 先服务于 RTL bring-up 和 loader/window/cache 事件定位，后续需要继续扩展 loader stall、active cluster mask、certified cluster count 等性能事件。

当前 scale sweep 见 [`generated/runtime_top_scale_sweep.md`](./generated/runtime_top_scale_sweep.md)，自动汇总入口见 [`generated/runtime_top_auto_report.md`](./generated/runtime_top_auto_report.md)。关键结论是：旧 packed-bank 版本 `FF=2912 -> 17075`，不具备扩展性；direct field-bank 版本解决 FF 扩展但仍是 LUTRAM；RAM-wrapper field-bank 版本在 `NTC=2/8/16/32` route 与 `NTC=64/128/256` synth-only 下保持约 `3.8k LUT / 2.2k FF / 8.5 BRAM / 0 LUTRAM`。物理 active-cluster sweep 已 routed 到 `NUM_CLUSTERS=8`，也就是 `32` active rows，WNS `+0.643 ns`。

当前 32 active-row 功能 checkpoint 见 [`generated/runtime_jacobi32_blockdiag_function_report.md`](./generated/runtime_jacobi32_blockdiag_function_report.md)。它使用 `8` 个 cluster x 每 cluster `4` 行的 block-diagonal Jacobi-family fixture，验证 runtime template/cert/state loader、window cache、row scheduler、iteration controller、`block_H` certification 和 counters。`iverilog` 全量回归为 `PASS all 24 testbenches`，Vivado 2023.2 `xvlog/xelab` 对该 testbench 通过。这个 checkpoint 仍然遵守当前 cluster-local source contract；通用 banded `32 x 32` Jacobi 矩阵需要后续 inter-cluster source router 或 halo-window 机制。

当前 multi-iteration solver checkpoint 见 [`generated/runtime_jacobi32_blockdiag_multi_solver_report.md`](./generated/runtime_jacobi32_blockdiag_multi_solver_report.md)。它在同一个 `8` clusters x `4` rows fixture 上连续运行 `6` 轮：每轮从 committed ping-pong state replay 一个 digit slice，完成 row-update / delta / `block_H` certification，然后 commit 到另一侧 state bank 并作为下一轮输入。`iverilog` 全量回归为 `PASS all 25 testbenches`，Vivado 2023.2 `xvlog/xelab` 对新 testbench 通过。由于本次只新增 generator/testbench/report，没有修改 RTL，现有 `NUM_CLUSTERS=8` U55C routed checkpoint 仍然有效。

当前 raw banded `32x32` global-source checkpoint 见 [`generated/runtime_jacobi32_global_solver_report.md`](./generated/runtime_jacobi32_global_solver_report.md)。它把 source field 从 local 2-bit index 扩展为 active-window global 5-bit index，并启用 `global_source_replay=1`，因此可以运行跨 cluster 依赖的原始 banded Jacobi fixture。`iverilog` 全量回归为 `PASS all 26 testbenches`，Vivado 2023.2 `xvlog/xelab` 通过，U55C 5 ns OOC route 也通过；但资源从 local NC8 的 `10267 LUT / WNS +0.643 ns` 变为 `35495 LUT / WNS +0.028 ns`。结论是：global-source replay 可作为功能 checkpoint，但论文版应继续收缩为 bounded halo-window，而不是保留全局 source mux。

当前 raw banded `32x32` registered halo-window checkpoint 见 [`generated/runtime_jacobi32_halo_solver_report.md`](./generated/runtime_jacobi32_halo_solver_report.md)。它保留原始 banded Jacobi fixture，但每个 cluster 只从“前一簇 + 本簇 + 后一簇”的 `12` 行 source window replay，source index width 为 `4` bit，并启用 `halo_source_replay=1` 与 `halo_replay_output_register=1`。该版本 `iverilog` 全量回归为 `PASS all 31 testbenches`，Vivado 2023.2 `xvlog/xelab` 通过，U55C 5 ns OOC route 通过；NC8 latency-default 资源为 `20040 LUT / 8237 FF / 64 DSP / 9 BRAM`，WNS `+1.125 ns`。相对 global-source，registered halo-window 降低 `43.54%` LUT 和 `51.87%` dynamic power，并把 WNS 提升 `1.097 ns`；相对未寄存 halo，WNS 额外提升 `0.857 ns` 且不增加 solver-level cycle。NC16 / 64 active rows 也已 route 通过，非 opipe WNS `+0.390 ns`；启用 `cert_operand_pipeline=1` 后 WNS 提升到 `+0.646 ns`，资源基本不变但每轮 certification 多 1 cycle。`cert_product_pipeline=1` 和 `cert_compare_pipeline=1` 都是负向 ablation，不设为默认。

当前 conventional DSP-MAC datapath lower-bound checkpoint 见 [`generated/conv_jacobi_datapath_baseline_report.md`](./generated/conv_jacobi_datapath_baseline_report.md)。它实现 signed fixed-point DSP-MAC row update，并复用同一个 `block_H` certification path；NC8 route 为 `9039 LUT / 2049 FF / 192 DSP / 0 BRAM / WNS +0.820 ns`，NC16 route 为 `18080 LUT / 4097 FF / 384 DSP / 0 BRAM / WNS +0.664 ns`。这个 baseline 没有 runtime loader、state bank、halo replay 和 solver controller，因此只能作为 conventional datapath 下界。当前 online halo solver 相对它的明确优势是 `3x` DSP 节省；明确劣势是 LUT、FF、BRAM 和动态功耗更高。下一步不能继续只做 MSDF 内部优化，必须实现 runtime-equivalent conventional baseline，才能判断创新点是否足够硬。

当前 runtime-equivalent conventional baseline 见 [`generated/runtime_conventional_baseline_report.md`](./generated/runtime_conventional_baseline_report.md)。它保留同一个 runtime loader、template/cert bank、ping-pong state bank、halo replay 和 iteration controller，只把 row-update datapath 替换成 full-word signed fixed-point DSP-MAC。未流水化版本 NC8 route 失败，WNS 为 `-3.411 ns`，失败路径从 full-word replay register 穿过 DSP multiply/accumulate 到 delta bound；加入 3-stage MAC pipeline，并在 conventional 模式下裁掉 online-only digit debug replay后，fast-done NC8 clean route 为 `24997 LUT / 10236 FF / 192 DSP / 9 BRAM / WNS +0.059 ns / dynamic 0.877 W`，NC16 加同样 operand pipeline 后 clean route 为 `55265 LUT / 25657 FF / 384 DSP / 9 BRAM / WNS +0.474 ns / dynamic 1.859 W`。conventional runtime 现在已有 full-word golden 和 6 轮 cycle test：旧 online digit-slice halo 为 `151` total cycles，pipelined conventional 为 `157` total cycles；这条旧 online path 只作为 prior datapath checkpoint，当前论文主线应看 solver-native mode3 报告。

当前 binary-I/O wrapper checkpoint 已加入 [`rtl/iter_dense_small_runtime_binary_io_top.v`](./rtl/iter_dense_small_runtime_binary_io_top.v)。它不改变核心 online datapath，只把外部 state、coefficient 和 bias 的 signed binary 接口转换为内部 `p/n` 差分对，并把内部 committed state 转回 signed binary 输出。`tb_iter_signed_rail_codec` 和 `tb_iter_dense_small_runtime_binary_io_top` 已通过。这个 wrapper 解决“最终输入输出是二进制、内部保持差分对”的接口问题；当前 full-digit runtime 仍在内部使用 rail-coded state bank，外部二进制接口和 full-digit runtime 的组合后续需要单独做 wrapper-level regression。

当前 prefix digit scheduler 与 stencil halo checkpoint 见 [`generated/prefix_scheduler_stencil_halo_checkpoint.md`](./generated/prefix_scheduler_stencil_halo_checkpoint.md)，单独的 scheduler 记录见 [`generated/prefix_scheduler_checkpoint.md`](./generated/prefix_scheduler_checkpoint.md)。[`rtl/iter_digit_prefix_scheduler.v`](./rtl/iter_digit_prefix_scheduler.v) 已实现自动 `digit_idx=0..DATA_WIDTH-1` sweep、cluster active mask、同一 iteration 内的 prefix gating 以及 `active_digit_cycles / gated_digit_cycles / cert_prefix_digit_sum / certified_block_count` 计数器；runtime top 已暴露这些 counter。`STENCIL_HALO_R1` 作为可选 replay ablation 已通过功能测试；U55C route 显示它在 NC8 改善 WNS 和 dynamic power，但 NC16 WNS 变差且 LUT 增加，因此不设为默认主线。

当前 full-digit runtime checkpoint 见 [`generated/full_digit_bridge_checkpoint.md`](./generated/full_digit_bridge_checkpoint.md)。[`rtl/iter_digit_serial_full_row_update_delta_slice.v`](./rtl/iter_digit_serial_full_row_update_delta_slice.v) 和 [`rtl/iter_digit_serial_full_row_cluster_delta_cert.v`](./rtl/iter_digit_serial_full_row_cluster_delta_cert.v) 用 `DATA_WIDTH` 个 MSB-first state digit 重构 conventional full-word row update，并输出同样的 `sum_p/sum_n` rail-coded full state 和 `block_H` certification 结果。`iter_dense_small_runtime_top` 已新增 `auto_full_digit=1`，由 scheduler 自动跑完 `digit_idx=0..DATA_WIDTH-1`；`tb_iter_dense_runtime_jacobi32_halo_reg_full_digit_multi` 已验证 `6` 轮 full-word Jacobi golden 对齐，计数为 `issue=66 = 6*11`，全量 Icarus 回归为 `SUMMARY PASS 41/41`。为通过 U55C 5 ns route，full-digit row slice 已改成 Horner recurrence、输入本地化寄存和 final-sum/abs-upper 两级切分；NC8 routed 主结果为 `28731 LUT / 15451 FF / 64 DSP / 9 BRAM / WNS +0.261 ns / dynamic 1.223 W`，runtime counter 为 `total=223 issue=66 cert_wait=114`。`AUTO_PREFIX_GATING=1` 已补成负向 ablation：功能上 `gated_digit=0`，route 为 `36845 LUT / 16294 FF / 224 DSP / WNS -1.185 ns / dynamic 1.550 W`，因此当前 prefix-bound 实现不作为主线优化。它内部暂用 signed binary accumulator，是 correctness bridge，不是最终低成本 online residual datapath。

当前 digit-stream state boundary checkpoint 见 [`generated/digit_stream_state_checkpoint.md`](./generated/digit_stream_state_checkpoint.md)。[`rtl/iter_digit_stream_state_ping_pong_bank.v`](./rtl/iter_digit_stream_state_ping_pong_bank.v) 已把 state commit 侧从 full-word 写入改成 MSB-first digit-wise 写入 inactive bank；[`rtl/iter_digit_stream_state_replay_top.v`](./rtl/iter_digit_stream_state_replay_top.v) 验证 digit-written state 可以在 `commit_swap` 后直接进入 fixed-degree replay。`tb_iter_digit_stream_state_ping_pong_bank` 和 `tb_iter_digit_stream_state_replay_top` 已通过。这个 checkpoint 只解决 state/replay 边界，不声称 row-update 和 certification 已完全 digit-stream 化；下一步要让 row-update 直接输出最终 `x_new` digits，并替换 full-word delta/certification。

当前 digit-stream row-output exploration 见 [`generated/digit_stream_row_update_exploration.md`](./generated/digit_stream_row_update_exploration.md)。[`rtl/iter_online_output_update.v`](./rtl/iter_online_output_update.v) 已把原始 operator 里的 `output_and_update` 提炼成 solver 可复用 primitive，`tb_iter_online_output_update` 已通过。基于它实现的 [`rtl/iter_online_affine_digit_core.v`](./rtl/iter_online_affine_digit_core.v) 和 [`rtl/iter_online_affine_digit_row.v`](./rtl/iter_online_affine_digit_row.v) 暂定为实验模块：首次对接表明当前 `online_affine_row_update_core` 仍是 digit-slice affine checkpoint，且 bias 仍按 full-word 每拍注入，不满足最终 all-digit-stream solver contract。因此这条路径现在的论文级结论不是“row-output 已闭环”，而是“已经抽出真正的 residual/output-update primitive，并定位出 streamed-bias / no-bias affine producer 是下一步必须重构的边界”。

当前 solver-native digit-stream checkpoint 见 [`generated/solver_native_digit_stream_checkpoint.md`](./generated/solver_native_digit_stream_checkpoint.md)，runtime probe 见 [`generated/solver_native_mode3_runtime_probe.md`](./generated/solver_native_mode3_runtime_probe.md)。[`rtl/iter_streamed_bias_source.v`](./rtl/iter_streamed_bias_source.v) 已把 bias 从 full-word 每拍注入改成 MSB-first digit source；[`rtl/iter_const_coeff_digit_contrib_rail.v`](./rtl/iter_const_coeff_digit_contrib_rail.v) 为 solver-native magnitude p/n rail 新增固定系数 digit contribution，负 digit 使用 p/n 交换；[`rtl/iter_online_affine_no_bias_core.v`](./rtl/iter_online_affine_no_bias_core.v) 提供固定系数、无 bias 的 4-term contribution producer；[`rtl/iter_digit_stream_delta_bound.v`](./rtl/iter_digit_stream_delta_bound.v) 实现 old/new digit 的 prefix delta bound，并在 mode3 exact runtime 中启用 `final_only=1` 关闭未使用的中间 prefix upper-bound 逻辑；[`rtl/iter_solver_native_row_digit_engine.v`](./rtl/iter_solver_native_row_digit_engine.v) 把上述路径和 residual/output-update loop 串成 row-level digit-output boundary；[`rtl/iter_solver_native_commit_adapter.v`](./rtl/iter_solver_native_commit_adapter.v) 负责跳过固定 online latency digits，并只提交后续 `DATA_WIDTH` 个 state digits；[`rtl/iter_solver_native_cluster_digit_stream_top.v`](./rtl/iter_solver_native_cluster_digit_stream_top.v) 已把 replay mux、row digit engine、commit adapter 和 digit-stream state bank 封装成 runtime 可接入的 cluster shell；[`rtl/iter_solver_native_cluster_delta_cert_top.v`](./rtl/iter_solver_native_cluster_delta_cert_top.v) 进一步把 commit digit stream 接入 inline delta、runtime `tail_bound` 和 `block_H` certification。runtime mode3 现在复用顶层 `w_drv_x*` source-select streams，因此 halo-window replay 可以直接喂 solver-native row digit engine。`iter_solver_native_row_digit_engine` 的 runtime 默认已调成 `affine_guard_shift=7, skip_digits=4`；该组合来自 strict blockdiag+halo sweep，不减少 `DATA_WIDTH` 输入 digit，只减少必须丢弃的 online warm-up/drain digit。`sample_width=4..9` sweep 没有让更激进的 `guard=8, skip=3` 通过 strict blockdiag，因此剩余 drain 不是 selector sample 窗口问题。fast-done controller/result bypass 去掉了每轮 1 cycle 的纯控制尾巴，并同时应用到 conventional baseline。当前 directed Icarus 已覆盖 row 等价、单 row state commit/replay、多 row shared state bank commit/replay、inline delta bound、replayed-state identity update、非恒等 two-iteration affine cluster、cluster shell 两轮 affine、cluster shell inline delta/certification、runtime `ROW_DATAPATH_MODE=3` 两轮 smoke，以及 `8 clusters x 4 rows x 6 iterations` 的 strict full-digit blockdiag 和 halo-window runtime。strict blockdiag 与 no-register halo runtime 均为 `total=229 issue=66 cert_wait=120`，带 halo replay 输出寄存器的 timing-protection ablation 为 `total=241 issue=66 cert_wait=132`。当前 mode3 已证明 local-source blockdiag 和 radius-1 halo full-digit runtime 闭环；任意 global-source mode3 尚未接入，也不是当前论文优先路线。U55C NC8 5 ns OOC route 已通过，当前 no-register fast-done halo checkpoint 为 `26779 LUT / 9083 FF / 64 DSP / 9 BRAM / WNS +0.128 ns / dynamic 0.711 W`。相对同样 fast-done 的 cleaned conventional runtime，mode3 仍然更慢（`229` vs `157` cycles），但保持 `3x` DSP 降低、FF 和动态功耗更低，LUT 仍在同一量级；最新 worst path 仍是 `delta_bound/o_abs_upper_reg -> cluster_cert/cert_engine` 的 `block_H` DSP certification 路径，下一步应优化 state-ready/certification overlap，而不是继续微调 row digit engine。

当前 wavefront super-step checkpoint 见 [`WAVEFRONT_DIGIT_STREAMING.md`](./WAVEFRONT_DIGIT_STREAMING.md)、[`PAGERANK_WAVEFRONT_STAGE_DEPTH.md`](./PAGERANK_WAVEFRONT_STAGE_DEPTH.md) 和 [`generated/wavefront_digit_stream_checkpoint.md`](./generated/wavefront_digit_stream_checkpoint.md)。[`rtl/iter_wavefront_superstep_cluster_state_top.v`](./rtl/iter_wavefront_superstep_cluster_state_top.v) 已把 `K` 个 solver stage 串成 committed digit wavefront，并用 `x^{(k+K)}-x^{(k+K-1)}` 做 last-delta certification；`ROW_DATAPATH_MODE=4` 已接入 `iter_dense_small_runtime_top`。当前已通过三个 runtime 检查：one-cluster smoke 为 `max_error=5 state=0a/05`；8-cluster blockdiag super-step 为 `total=135 issue=11 cert_wait=41 iter=1 conv_iter=1`；8-cluster registered halo-window super-step 为 `total=136 issue=11 cert_wait=42 iter=1 conv_iter=1`。两组多 cluster 测试都和第 4 轮 golden state/certification 对齐。为支持 blockdiag，committed wavefront 的内部 stage source 已从固定 radius-1 扩展为 template `src_row_idx` 选择；为支持 halo-window，mode4 已补跨 cluster inter-stage forwarding，把上一 stage 的 previous/current/next cluster committed digits 组成下一 stage 的 halo source window。最新 PageRank global-source stage sweep 见 [`generated/pagerank_wavefront_stage_sweep.md`](./generated/pagerank_wavefront_stage_sweep.md)：`K=2/3/4` 分别为 `121/128/135` cycles，`issue=11` 固定不随 `K` 增长，说明后级确实消费前级 committed digit stream，而不是等待 full word 重启。strict prior-fractional standalone sweep 见 [`generated/prior_fractional_wavefront_sweep.md`](./generated/prior_fractional_wavefront_sweep.md)：复用原始 `MSDF_MUL_ADD_8`，`K=2/3/4` 分别为 `36/46/56` cycles，`capture=14` 固定，最终 state 与 `pagerank32_global_prior_fractional` golden 在 `<=4 LSB` 内一致。strict prior-fractional runtime 现已作为 P3 fixed K=4 wavefront 接入，同 fixture 报告见 [`generated/pagerank_fractional_same_scope_eval.md`](./generated/pagerank_fractional_same_scope_eval.md)：P3 K=4 wavefront 为 `compute=70 issue=14 cert_wait=56 observed_total=150`，相对 prior digit-stream single-stage `168` compute cycles 有 `2.400x` speedup。U55C routed 对比见 [`generated/pagerank_fractional_routed_backend_report.md`](./generated/pagerank_fractional_routed_backend_report.md)：P3 在 5 ns 下 timing-clean，`compute=70 / observed_total=150 / WNS +0.114 ns / 121364 LUT / 64706 FF / 64 DSP / 10.5 BRAM / dynamic 1.247 W`；reserved 8-slot timing-clean P4 conventional fractional 为 `compute=44 / observed_total=143 / WNS +0.052 ns / 59482 LUT / 23753 FF / 320 DSP / 10.5 BRAM / dynamic 2.390 W`。同一 registered halo-window fixture 下，四轮普通 mode3 为 `total=187 issue=44 cert_wait=84`，一轮 `K=4` mode4 super-step 为 `total=136 issue=11 cert_wait=42`，runtime speedup 为 `1.375x`。U55C NC8 5 ns OOC route 也已完成：mode3 registered halo 为 `26107 LUT / 9381 FF / 64 DSP / 9 BRAM / WNS +0.321 ns / dynamic 0.825 W`；mode4 wavefront 为 `40759 LUT / 13174 FF / 64 DSP / 9 BRAM / WNS +0.368 ns / dynamic 1.115 W`；启用 `cert_operand_pipeline=1` 后 mode4 为 `40789 LUT / 13182 FF / 64 DSP / 9 BRAM / WNS +0.667 ns / dynamic 1.052 W`，runtime 变为 `total=137`。结论是 wavefront/fusion 已证明能降低 online solver boundary 成本，strict prior runtime 也已证明可 route；但当前 P3 相比 reserved 8-slot timing-clean P4 仍是 `70` vs `44` compute cycles，优势在 `5x` DSP 降低和更低 dynamic power，劣势在 LUT/FF/latency。 新增 standalone continuous feedback checkpoint 见 [`generated/prior_fractional_feedback_eval.md`](./generated/prior_fractional_feedback_eval.md)：K=4 连续两段 super-step 为 `total=101 / final_supersteps=2 / feedback_stall=0`，stage-wise L1 stop 测试得到 `converged_stage=1`；该结果尚未计入 same-shell runtime 主表。
