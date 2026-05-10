# Research and Innovation Roadmap

本文档记录围绕当前 `MSDF_iterative_solver/` 主线的论文调研、可落地创新点和工程优先级。目标是回答一个具体问题：

$$
\text{当前 online / MSDF solver 主线怎样才能比“复现那篇内积论文”更硬?}
$$

当前结论是：**不要把创新停在 generic online inner-product operator。最有价值的升级是利用固定矩阵迭代核的结构，把 generic variable-by-variable operator 改造成 constant-matrix-specialized online affine solver engine，并叠加局部收敛认证与 solver 级加速。主线后续只围绕迭代核，不再回到旧的非线性方向。**

## Current Baseline Reality

现有软件模型已经给出清晰边界：

- `Gate 1` 通过：online certification 在至少一类 workload 上确实能提前于 full `q` 位判定。
- `Gate 2` 通过：iteration-fused 相对 cascaded online 有稳定周期优势。
- `Gate 3` 未通过：相对 optimistic conventional FPGA proxy，当前还不能主张 raw cycle 领先。

因此后续论文不能只写：

$$
\text{integrated online inner product is faster than cascaded online}
$$

这已经接近 prior paper 的贡献范围。后续必须把贡献推到：

1. 固定矩阵专用化；
2. solver-level delta / certification 融合；
3. 局部或块级更紧收敛界；
4. 减少迭代次数的 weighted Jacobi / Chebyshev semi-iteration；
5. 稀疏矩阵静态调度。

## Related Work Readings

| Work | What It Shows | Relevance to This Project | Gap We Can Target |
| --- | --- | --- | --- |
| Prior integrated inner-product paper, local PDF `基于高效集成在线算术的高维线性系统计算.pdf` | 把 online multiplier -> online adder tree 的 operator boundary 折叠成 integrated inner product / MAC | 证明 operator-level online integration 是可行的，原始 RTL 已放在 `../MSDF_operator_srcs/` | 它没有做 solver-level delta、norm certification、iteration handoff，也没有利用固定矩阵系数 |
| Sparse Matrix-Vector Multiplication Based on Online Arithmetic, IEEE Access 2024, DOI `10.1109/ACCESS.2024.3416395` | online arithmetic 被用于 SpMV 这种流式高维线性核，并报告 `1.69x` speedup 与最高 `60.4%` 能耗降低 | 证明 SpMV / sparse linear algebra 是 online arithmetic 的合理战场 | 它主打 SpMV operator，不是 iteration-fused solver，也没有把 certification 作为核心贡献 |
| Efficient FPGA Implementation of Digit Parallel Online Arithmetic Operators, FPT 2014 | naive online arithmetic 在 FPGA 上 area overhead 很大，针对 Xilinx LUT/carry 的实现可显著降低开销 | 提醒我们不能直接搬原始 operator RTL，需要 FPGA-aware primitive 优化 | 我们应把复用范围限制在 local adder fabric，并为 U55C 重写可综合 row engine |
| ECHO: Energy-Efficient Computation Harnessing Online Arithmetic, Electronics 2024 | MSDF 的强项是 early decision / pruning，而不是单个 MAC 必然快 | 支持当前的 online convergence certification 叙事：MSDF 价值来自 prefix digit 的早判定 | ECHO 面向 DNN ReLU 负值早停；我们面向 solver 收敛认证，数学判据不同 |
| A Mathematical Framework for Online Constant Coefficient Multiplication, IJETI 2017 | online constant coefficient multipliers / multiple constant multipliers 可减少资源、online delay 并提升频率 | 直接支持本项目最重要的升级：固定矩阵 `G` 的 constant-coefficient specialization | 该工作不处理 solver-level delta/certification，也不处理稀疏迭代调度 |
| Reduced-Area Constant-Coefficient and Multiple-Constant Multipliers for Xilinx FPGAs, Electronics 2017 | FPGA 上常数乘可以用 LUT/CSD/partial-product 方法节省 DSP | 说明 conventional constant-multiplier baseline 很强，必须公平对比 | 我们不能只声称“常数化省资源”，必须强调 online prefix + certification + solver fusion |
| Jacobi FPGA sparse solver work, e.g. large sparse matrix thesis and reconfigurable Jacobi solvers | Jacobi 天然适合 FPGA 并行，因为缺少强数据依赖 | 说明 Jacobi 是合理 workload，但 conventional FPGA baseline 会很强 | 我们必须避开“只是另一个 Jacobi FPGA accelerator”的弱叙事 |
| Chebyshev semi-iteration / Chebyshev acceleration | 用少量额外状态降低迭代次数，和 Jacobi 并行结构兼容 | 给出算法层增强方向：把每轮省周期转成总 solve 周期收益 | 需要先做数值模型，不能直接改 RTL |
| PageRank Beyond the Web, SIAM Review 2015 | PageRank 是通用图/网络计算 workload，不局限网页排名 | 说明 PageRank 有应用意义，适合作为论文 headline application | 第一版必须限制为 bounded-degree / partitioned PageRank，并补 PageRank-specific `L1` certification，不能直接声称支持任意 Web graph |

## Related-Work Positioning

当前相关工作可以分成四类，必须明确区分，不然论文贡献会被冲散。

### A. Online arithmetic operator papers

这类工作解决的是：

$$
\text{adder / multiplier / inner-product operator}
$$

的组织问题。典型代表就是本地那篇 integrated inner-product 论文和 FPT 2014。它们的强项是：

- 证明 online primitive 可以在 FPGA 上做得不那么昂贵；
- 证明 operator boundary 可以被折叠；
- 证明 inner-product / SpMV 这类线性归约核适合 online arithmetic。

它们的共同边界也很清楚：

- 不处理 iteration handoff；
- 不处理 solver-level `delta`；
- 不处理在线收敛认证；
- 不利用固定矩阵这个结构信息。

### B. Conventional FPGA sparse linear algebra papers

这类工作解决的是：

$$
\text{SpMV / sparse solver throughput on FPGA}
$$

典型关注点是：

- memory bandwidth；
- sparse format；
- row/edge parallelism；
- DSP / floating-point MAC efficiency。

代表工作包括 Fowers 2014、Dorrance 2014、Jain 2020，以及 2024 的 SpMM survey。它们说明一件事：**如果只比 raw row-update throughput，conventional sparse accelerator baseline 很强。**

因此本项目不能把论文主张写成：

$$
\text{online arithmetic universally beats DSP sparse kernels}
$$

这在现阶段没有证据支持。

### C. Iterative-method acceleration papers

这类工作不是优化单轮算术，而是优化：

$$
\text{total iterations to convergence}
$$

典型代表是 weighted Jacobi、SRJ、Chebyshev semi-iteration。它们提供的启发很明确：如果每轮架构不可能全面打赢 conventional baseline，就必须把主指标从

$$
\text{cycles / iteration}
$$

转成

$$
\text{cycles to certified convergence}
$$

这是当前主线必须吸收的评价逻辑。

### D. Constant-coefficient / multiple-constant multiplication papers

这类工作给出的不是 solver 级故事，而是一个很硬的工程事实：**固定系数乘法不该继续按 variable-by-variable 最坏情况实现。**

对当前主线，这一类工作的重要性不是“拿来当论文 baseline”，而是作为设计武器，支持：

$$
\text{constant-matrix specialization}
$$

这是现在最适合做成主创新的一层。

## Innovation Screening Criteria

后续创新点不应凭直觉扩展，而应通过下面四个筛选条件。

### C1. 是否利用了 solver 的额外结构

如果一个优化只是在 generic online operator 上继续打磨，但没有利用：

- `G` 固定；
- `x^{(k+1)}-x^{(k)}` 必须同时产生；
- 收敛判定依赖 prefix digit；
- iteration 之间存在 handoff；

那它很难成为新的论文级贡献。

### C2. 是否能改善当前最弱 gate

现状是：

- `Gate 1` 过；
- `Gate 2` 过；
- `Gate 3` 未过。

因此高优先级创新必须至少满足下列之一：

1. 降低 `cycles to certified convergence`；
2. 降低 conventional baseline 难以同步优化的 solver-level extra pass；
3. 降低对 DSP / coefficient bandwidth / state bandwidth 的依赖。

### C3. 是否能形成清晰 baseline

如果一个优化没有明确的主比较对象，它就不适合当主贡献。当前每条创新都必须能映射到下面某个对比：

- vs `cascaded online`
- vs `prior integrated row-update`
- vs `conventional DSP / KCM baseline`

### C4. 是否能先在模型里闭环

如果一个创新必须先写大量 RTL 才知道有没有用，这个优先级应该降低。当前最优创新应能先在软件模型上验证：

- `avg j*`
- `certified_frac`
- `cycles to certified convergence`
- coefficient bandwidth / state bytes proxy

## What Actually Hurts Today

从当前模型和原始 RTL 审阅结果看，真正的痛点不是“online arithmetic 不够 clever”，而是下面四个更具体的问题。

### P1. Generic variable-by-variable operator 浪费了固定矩阵结构

当前 operator 把

$$
g_{is} \times x_s^{(k)}
$$

按两个都在线变化的最坏情况去实现，这会引入过重的 partial-product 生成和选择逻辑。对 solver 来说，这部分理论上应该专用化。

### P2. 全局粗认证界使 `j_k^\star` 偏大

即使在线认证在数学上成立，如果

$$
j_k^\star \approx q
$$

那 prefix 特性就没有转化成周期收益。PageRank 当前就是这个问题。

### P3. 仅优化每轮周期，不优化总迭代数，不足以打 conventional baseline

如果 plain Jacobi 的 iteration count 很高，那么 conventional dense/sparse FPGA kernel 仍可能依靠更高单轮吞吐赢回去。

### P4. 稀疏矩阵的数据流组织尚未和 online arithmetic 协同设计

如果后续仍按 dense lane 或粗糙 CSR 方式驱动 operator，很多 online 架构的潜在收益会被存储和调度吃掉。

## Key Technical Reading

### Online arithmetic is useful when prefix digits drive downstream work

ECHO 明确利用 MSDF 的前缀输出做早期负值检测，避免继续执行无用 MAC。这个事实对本项目很重要：MSDF 不是靠单个 operator raw latency 取胜，而是靠 prefix digit 让后续决策提前发生。

本项目对应关系是：

$$
\text{DNN negative output detection}
\rightarrow
\text{solver convergence certification}
$$

如果我们只做完整 `x^{(k+1)}` 输出，再用普通逻辑检查收敛，就失去了 online arithmetic 的主要价值。

### Constant-matrix structure is currently underused

当前原始 operator RTL 假设两个输入都是在线变量：

$$
x_s^{(k)} \times g_{is}
$$

都按 variable-by-variable online multiplication 处理。  
但在固定点迭代里：

$$
x^{(k+1)} = Gx^{(k)} + c
$$

矩阵 `G` 在整个求解过程中不变。  
这意味着当前 datapath 为“变量乘变量”的最坏情况付了代价，却没有利用：

- 常数系数可以离线 CSD / signed-digit 编码；
- 稀疏非零 pattern 可以离线调度；
- 同一 row 的系数局部归约树可以提前定制；
- 系数存储可以从 full rail stream 降成 compact coefficient template。

这是当前工程最明显的结构漏项。

### PageRank is now the headline application

从论文应用定位和当前定点核心约束看，PageRank 比 Jacobi 更适合作为 headline application。PageRank 的 rank/state 和转移系数天然有界，主要工作是重复的非负 affine propagation：

$$
r^{(k+1)}=\beta Mr^{(k)}+(1-\beta)v
$$

这与当前 digit-stream wavefront 的优势更一致。Jacobi 仍然保留为 RTL stress fixture，因为它覆盖 signed coefficient、halo replay 和更困难的动态范围，但不再作为第一应用叙事。

PageRank 的自然 norm 是 `L1`，并且 damping factor 通常接近 1，导致收敛阈值更紧：

$$
\varepsilon_d^{PR} = \eta \frac{1-\beta}{\beta}
$$

因此最终 PageRank 认证不应继续沿用 Jacobi 的 `block_H` 路径，而应做 PageRank-specific `L1` delta accumulation。当前 `jacobi32_*` 结果只证明 affine/wavefront datapath，不是最终 PageRank benchmark。

后续优先级变为：PageRank graph-to-template generator、PageRank-equivalent conventional runtime baseline、PageRank `L1` certification。

## Candidate Innovation Tracks

### I1. Constant-Matrix-Specialized Online Affine Engine

这是第一优先级。

当前 generic operator 的核心代价来自：

$$
\text{variable} \times \text{variable}
$$

而 solver 实际需要的是：

$$
\text{constant } g_{is} \times \text{online state } x_s^{(k)}
$$

应把 `G` 离线编译成 coefficient templates：

$$
g_{is} \approx \sum_{m} \gamma_{is,m} 2^{-b_{is,m}},
\quad
\gamma_{is,m}\in\{-1,+1\}
$$

然后在线计算：

$$
g_{is}x_s^{(k)} \approx \sum_m \gamma_{is,m}\left(x_s^{(k)} \gg b_{is,m}\right)
$$

这会把 `vector_append + selector` 的通用乘法逻辑替换成固定 shift/add contribution generator。

**理论收益：**

- 降低 partial-product 选择逻辑；
- 减少系数侧 rail stream；
- 降低 coefficient bandwidth；
- 更容易为每行生成静态归约树；
- DSP 继续保持低依赖。

**工程落地：**

1. 新增 coefficient compiler，把 dense/sparse `G` 转成 CSD/signed-digit template。
2. 新增 `online_const_coeff_contrib.v`，输入 `x_s` digit，输出若干 shifted signed contribution。
3. 用现有 `parallel_online_adder*` 做 local reduction。
4. 和 generic `MSDF_MUL_ADD_8` 做同等 row-update 对比。

**当前模型证据：**

新增代理报告
[generated/const_coeff_specialization_report.md](./generated/const_coeff_specialization_report.md)
表明，这条方向在“前端控制深度”上是有希望的：当前 Jacobi case 中，`theta_row_const_proxy` 相对 `theta_row_generic_proxy` 的代理改善约为：

$$
1.23\times \sim 1.36\times
$$

但同一份报告也给出一个重要负结果：若只看静态系数存储，signed-digit template 在当前 `q=16/20/24` 设置下并**没有**比直接存定点系数更省，`coeff_storage_ratio < 1` 是主流现象。

这意味着：

- 这条创新应主打 **selector/front-end 深度下降** 和 **专用 row-update 结构**；
- 不应主打“静态 coefficient bits 一定更小”。

**论文表达：**

这不是普通 constant multiplier；主张应写成：

$$
\textbf{constant-matrix-specialized online affine update for iterative solvers}
$$

关键差异是它服务于 solver-level fusion 和 online certification。

### I2. Local / Block-Wise Convergence Certification

当前认证使用全局粗界：

$$
\|G\| \le \rho < 1
$$

这会让 `j_k^*` 偏大，尤其对 PageRank 和 `rho` 接近 1 的 Jacobi case 不友好。

Jacobi 可改成 row-wise 或 block-wise 界。对第 `i` 行定义：

$$
\rho_i = \sum_j |g_{ij}|
$$

则可对不同 row/block 使用不同停止阈值，而不是全局最坏 `rho`。块级形式：

$$
\rho_B = \max_{i\in B}\sum_j |g_{ij}|
$$

认证可写成：

$$
U_{\infty,B}^{(k,j)} \le \eta_B
$$

**理论收益：**

- 降低 `j_k^*`；
- 提升 `certified_frac`；
- 对局部收敛快的 block 提前完成；
- 使 solver-level certification 成为真正的数值指标，而不只是形式正确。

**工程落地：**

1. 在软件模型里新增 row/block `rho` 模式。
2. 先比较 global vs block certification 的 `avg j*`。
3. RTL 第一版只做 block-level threshold table，不做复杂动态调度。

**风险：**

控制复杂度会上升。第一版必须把 block 数限制在可控范围，例如 `BLOCK_ROWS=8/16`。

**当前模型证据：**

新增报告
[generated/local_cert_sweep.md](./generated/local_cert_sweep.md)
已经把这条方向从“设想”推进到“有数据支撑”。

结论很明确：

1. `global_rho` 认证过于保守，很多 case 下 `avg j* = q`，几乎没有 prefix 收益；
2. 基于

   $$
   H = G(I-G)^{-1}
   $$

   的严格 `block_H` 认证在 `block_size = 1/4` 时通常明显更强；
3. 在较友好的 Jacobi case 上，`avg j*` 可从 `24` 降到 `20~23`，`speedup vs B1` 提升到大约：

   $$
   1.33\times \sim 1.40\times
   $$

4. block 过大时收益会消失，因此后续 RTL 不应直接做很粗的 block。

这说明局部认证不是锦上添花，而是当前最值得推进的数值侧增强。

### I3. Weighted Jacobi / Chebyshev Semi-Iteration

当前 plain Jacobi 的问题是迭代次数仍然多。只优化每轮周期，很容易被 conventional DSP pipeline 靠吞吐压住。

Weighted Jacobi：

$$
x^{(k+1)} = (1-\omega)x^{(k)} + \omega(Gx^{(k)} + c)
$$

Chebyshev semi-iteration 通常需要少量历史状态和预设系数，可把固定点迭代加速为：

$$
x^{(k+1)} = x^{(k)} + \alpha_k r^{(k)} + \beta_k(x^{(k)}-x^{(k-1)})
$$

其中 `alpha_k/beta_k` 可离线生成或周期性查表。

**理论收益：**

- 降低 total iterations；
- 让 `cycles to convergence` 变硬；
- 保留仿射/线性主结构，不引入 CG/GMRES 那种 dot/divider 路径。

**工程落地：**

1. 先在 Python 模型加入 weighted Jacobi。
2. 再加入 Chebyshev coefficient schedule。
3. 只在软件模型显示明显减少 iteration count 后再做 RTL。

**论文表达：**

不要写成“我们发明 Chebyshev”。应写成：

$$
\textbf{online-certified Chebyshev/Jacobi solver datapath}
$$

也就是算法加速与 online certification 的硬件协同。

### I4. Sparse-Aware Static Schedule

如果 `G` 是稀疏矩阵，row-update 不应走固定 dense 8-lane operator。应离线生成静态调度：

- 每行 nonzero 分组；
- 每组 coefficient template；
- 每组 local reduction tree；
- state read order；
- output/delta/certification handoff。

**理论收益：**

- 避免零项进入 operator；
- 降低 state memory bandwidth；
- 让 local adder tree 和矩阵结构匹配；
- 更符合 SpMV / Jacobi 的实际 workload。

**工程落地：**

1. 软件模型先加入 sparse schedule cost。
2. RTL 第一版支持 fixed degree，例如 `DEG=4/8`。
3. 后续再扩展 CSR-like metadata。

**风险：**

如果一开始做完整 CSR controller，会拖慢工程。第一版应采用 fixed-degree sparse rows 或 banded sparse matrix。

### I5. FPGA-Aware Online Primitive Refactoring

FPT 2014 工作明确指出 naive online operator 在 FPGA 上会有很大 area overhead。原始 RTL 直接搬到 U55C 不一定合适。

这条优化不是论文主贡献，但必须做：

- 合并小 full-adder cell；
- 控制 Vivado 对 carry resources 的映射；
- 给 local reduction tree 加明确 pipeline；
- 避免 rail-to-binary conversion 出现在关键路径；
- 为 `LANES=4/8/16` 做 OOC route sweep。

**论文定位：**

这是 implementation optimization，不是主贡献。主贡献应保留给 solver-level fusion / constant-matrix specialization / certification。

## Recommended Paper Claim

最稳的论文主张应改成：

$$
\textbf{A constant-matrix-specialized online affine solver engine with provable convergence certification}
$$

贡献点建议固定为三条：

1. **Constant-matrix-specialized online affine row engine**  
   利用固定矩阵 `G`，把 generic online inner product 降成 coefficient-template-driven affine update。

2. **Iteration-fused delta and certification datapath**  
   在同一 digit stream 中生成 `x^{(k+1)}`、`d^{(k)}` 和 convergence bound，减少 materialization / delta / norm pass。

3. **Local / block-wise online convergence certification**  
   用更紧的 row/block contraction bound 降低 `j_k^*`，提升 certified convergence 的周期收益。

可选第四贡献：

4. **Chebyshev/weighted-Jacobi schedule support**  
   如果软件模型证明 iteration count 明显下降，再作为算法-硬件协同贡献加入。

## Selected Innovation Stack

当前最适合论文落地的创新组合应固定为“三主一辅”。

### Main-1. Constant-matrix-specialized online affine row engine

这是最强主贡献。它直接利用 `G` 固定这一 solver 结构，避免继续沿用 variable-by-variable operator 的最坏情况逻辑。

### Main-2. Iteration-fused row-update / delta / certification datapath

这是当前主线的体系结构骨架，负责把 prior operator paper 的算子级 integration 提升到 iteration 级。

### Main-3. Local or block-wise provable certification

这是把 prefix digit 价值真正转成硬指标的关键层。如果没有这一层，在线认证在很多 workload 上只会“数学成立”，却没有足够的周期收益。

### Optional-4. Weighted Jacobi / Chebyshev overlay

这条不应先做 RTL，而应先看软件模型是否能显著降低：

$$
\text{iterations to certified convergence}
$$

如果收益明显，再进入正式工程。

## Explicit No-Go Directions

后续不应再把时间投入到下面这些方向上。

1. 继续打磨 generic `MSDF_MUL_ADD_8` 顶层外壳。  
   它最多是 prior operator 的更整洁实现，不会自动变成 solver 级贡献。

2. 继续追求 dense raw row-update cycle 胜利。  
   conventional DSP/KCM baseline 在这个指标上天然很强，当前更合理的主指标应是：

   $$
   \text{cycles to certified convergence}
   $$

3. 直接承诺任意图 PageRank 全系统。  
   第一版应限制在 bounded-degree / partitioned graph propagation，先证明 digit-stream iteration fusion，而不是做完整 CSR/HBM graph accelerator。

4. 在没有模型证据前直接上 weighted/Chebyshev RTL。  
   这会把工程复杂度先推高，而不一定带来真实收益。

## Immediate Work Sequence

后续顺序应固定，不再来回切。

### Step A. Constant-coefficient model

先补：

- coefficient template compiler
- generic online row-update proxy
- constant-coeff online row-update proxy
- conventional constant-multiplier proxy

目标是先判断：

$$
\text{constant specialization 是否有机会改善 Gate 3}
$$

### Step B. Local certification sweep

新增三种界：

- global `rho`
- row-wise `rho_i`
- block-wise `rho_B`

主看：

- `avg j*`
- `certified_frac`
- `cycles to certified convergence`

### Step C. Minimum specialized RTL

如果 Step A/B 给出正结果，再做：

- `online_const_coeff_contrib.v`
- `online_affine_row_update_core.v`
- `online_delta_linf_cert_core.v`

先不做复杂 sparse controller。

### Step D. Weighted / Chebyshev model

如果 Step C 后 raw cycle 仍不够硬，再引入 iteration-count reduction，并把论文主指标正式切到：

$$ 
\text{cycles to certified convergence}
$$

## Current Evidence After the New Model Extensions

在补完 `constant specialization` 代理和 `block_H` 认证 sweep 之后，当前证据可以重新归纳为：

1. `Gate 1` 不只是成立，而且其主要增益来自 **更紧的局部认证**，不是原始 `global_rho` 规则；
2. `Gate 2` 继续成立，而且在 `block_size = 1/4` 的 Jacobi case 上变得更硬；
3. `Gate 3` 仍未被 raw-cycle 证明扭转，因此论文主指标仍应优先使用：

   $$
   \text{cycles to certified convergence}
   $$

4. `constant specialization` 当前最像计算/控制深度优化，而不是系数存储压缩优化。
5. 统一 stack 评估
   [generated/specialized_stack_eval.md](./generated/specialized_stack_eval.md)
   已经表明：
   - `Ours-B` 在 `18/18` 个 case 中优于 `Ours-A`；
   - `Ours-C` 在 `15/18` 个 case 中优于 `Ours-B`。

因此，当前主线不应再讨论“是否进入 specialized RTL”，而应直接讨论 specialized RTL 的具体接口与划分。

## Scope Discipline

从这份文档开始，主线只讨论：

$$
x^{(k+1)} = Gx^{(k)} + c
$$

及其 solver-level architecture、认证和系数专用化。历史非主线只保留在归档目录中，不再进入当前创新讨论。

## What Not to Claim

不应主张：

- online arithmetic 全面优于 DSP MAC；
- generic `MSDF_MUL_ADD_8` 已足够形成新论文；
- 当前 `jacobi32_*` 测试已经等价于 PageRank；
- raw cycle 已经打赢 conventional FPGA；
- Chebyshev / CSD / KCM 本身是我们的新算法。

当前必须保持的表述是：

$$
\text{online/MSDF is useful when prefix digits remove solver-level work}
$$

而不是：

$$
\text{online/MSDF primitive is always faster}
$$

## Engineering Priority

下一阶段建议按下面顺序推进。

### Step 1: Add constant-matrix specialization to the model

新增：

- coefficient CSD compiler；
- generic online row-update cost；
- constant-coeff online row-update cost；
- conventional constant-multiplier baseline cost。

目标是先回答：

$$
\text{constant specialization 能否改善 Gate 3?}
$$

### Step 2: Add local/block certification sweep

新增：

- global `rho`；
- row-wise `rho_i`；
- block-wise `rho_B`；
- 对比 `avg j*`、`certified_frac`、cycles to certified convergence。

目标是把 `j_k^*` 从当前的“只比 q 小一点”压得更明显。

### Step 3: Implement minimum RTL only after model improves

最小 RTL 不应从旧 `MSDF_MUL_ADD_8` 开始缝补，而应新建：

- `online_const_coeff_contrib.v`
- `online_affine_row_update_core.v`
- `online_delta_linf_cert_core.v`

并复用或重写：

- `parallel_online_adder`
- `parallel_online_adder_4`
- `output_and_update` 的 digit selection 思想。

### Step 4: Add weighted Jacobi / Chebyshev model

只有当 Step 1/2 后仍无法支撑 Gate 3，再加入 solver acceleration。  
如果 weighted/Chebyshev 能显著降低 iteration count，就把主指标从：

$$
\text{cycles / iteration}
$$

转成：

$$
\text{cycles to certified convergence}
$$

## Evaluation Matrix

| Variant | Purpose |
| --- | --- |
| `B1`: cascaded online | 证明 prior online cascade 不是最佳 |
| `B1-int`: prior integrated online row update | 复现那篇文章层级 |
| `Ours-A`: iteration-fused generic online | 当前主线基础版本 |
| `Ours-B`: constant-matrix-specialized online | 第一优先创新 |
| `Ours-C`: Ours-B + block certification | 数值指标增强 |
| `Ours-D`: Ours-C + weighted/Chebyshev Jacobi | 总 solve 周期增强 |
| `B2`: conventional DSP / KCM FPGA baseline | 工程主 baseline |
| `CPU`: software reference | 应用参考，不作为硬件主比较 |

核心指标：

- `cycles / iteration`
- `cycles to certified convergence`
- `avg j*`
- `certified_frac`
- `state bytes / iteration`
- `delta/norm extra pass bytes`
- `DSP/LUT/FF/BRAM`
- `Fmax`
- `energy proxy` or post-route power

## Bottom Line

当前最适合你工程的论文级创新点不是继续优化 generic MSDF operator，而是：

$$
\textbf{固定矩阵专用 online affine solver + 局部在线认证}
$$

它比 prior paper 更高一层，因为 prior paper 解决 operator boundary，而这里解决：

$$
\text{operator boundary}
+
\text{iteration boundary}
+
\text{certification boundary}
$$

它也比旧的非线性主线更稳，因为它把 MSDF 放回了真正适合的场景：高维、有界、流式、可归约、可提前认证的线性迭代核。

## Source Links

- Sparse Matrix-Vector Multiplication Based on Online Arithmetic, IEEE Access 2024: https://www.european-processor-initiative.eu/dissemination-material/sparse-matrix-vector-multiplication-based-on-online-arithmetic/
- ECHO: Energy-Efficient Computation Harnessing Online Arithmetic, Electronics 2024: https://www.mdpi.com/2079-9292/13/10/1893
- Efficient FPGA Implementation of Digit Parallel Online Arithmetic Operators, FPT 2014: https://research.monash.edu/en/publications/efficient-fpga-implementation-of-digit-parallel-online-arithmetic/
- A Mathematical Framework for Online Constant Coefficient Multiplication, IJETI 2017: https://ojs.imeti.org/index.php/IJETI/article/view/412
- Reduced-Area Constant-Coefficient and Multiple-Constant Multipliers for Xilinx FPGAs, Electronics 2017: https://www.mdpi.com/2079-9292/6/4/101
- A Scalable Architecture For Hardware Acceleration of Large Sparse Matrix Calculations, 2007 thesis: https://repository.lib.ncsu.edu/items/111bd32c-4d7e-493d-b28f-54e6caf46aaf
- Chebyshev Semi-Iterative Approach for Accelerating Projective and Position-Based Dynamics, ACM TOG 2015: https://wanghmin.github.io/publication/wang-2015-csi/
- PageRank Beyond the Web, SIAM Review 2015: https://epubs.siam.org/doi/abs/10.1137/140976649
