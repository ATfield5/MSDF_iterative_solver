# Pre-RTL Top-Down Architecture

本文档在正式进入 RTL 之前，从：

- 算法层
- 数学公式层
- 微架构层

三个层级重新固定当前 `MSDF_iterative_solver/` 主线。目标不是再泛泛讨论 online arithmetic，而是回答：

$$
\text{当前 solver 主线在进入 RTL 之前，到底该如何定型?}
$$

全文只讨论：

$$
x^{(k+1)} = Gx^{(k)} + c
$$

这一类 affine fixed-point solver datapath。

## 1. Design Goal and Boundary

当前主线的目标不是“做最快的单个 row-update operator”，而是：

$$
\textbf{minimize cycles to certified convergence}
$$

并同时减少：

- iteration handoff；
- full-width materialization；
- 独立 `delta` pass；
- 独立 norm/certification pass；
- 对 DSP general MAC 的依赖。

因此，当前设计不能再围绕下面这些旧目标展开：

1. dense raw row-update cycle 冠军；
2. generic online multiplier/add tree 的继续打磨；
3. 非线性函数核替代；
4. 任意图 PageRank 的完整 CSR/HBM 系统；
5. 一上来就做 CG/GMRES 这类带额外 dot/divider 路径的 solver。

## 2. Algorithm-Level Decision

### 2.1 First Solver Family

第一阶段应用场景固定在：

$$
\text{PageRank-style affine fixed-point graph propagation}
$$

而不是更复杂的 Krylov family 或 generic sparse solver。原因有三点：

1. 它天然符合

   $$
   x^{(k+1)} = Gx^{(k)} + c
   $$

   的 affine 形式；

2. 没有全局 dot product/divider 作为主路径瓶颈；

3. rank/state 和传播系数天然有界，和当前定点 MSDF / digit-stream datapath 更匹配。

Jacobi-style fixture 继续保留，但定位变为 RTL stress/validation：它覆盖 signed coefficient、halo replay 和更困难的动态范围，不再作为论文第一应用。

### 2.2 Second-Stage Algorithm Upgrade

若 PageRank 主线需要进一步增强，不应直接跳 CG 或完整图系统，而应优先考虑：

#### Topic-Specific / Personalized PageRank Batch

$$
r_s^{(k+1)}=\beta Mr_s^{(k)}+(1-\beta)v_s
$$

多个 personalization vector 可以共享同一图 template，把当前 digit-stream engine 扩展成 batched graph propagation。

#### Bounded-Degree / Tiled PageRank

第一版优先 bounded-degree padded template；高入度 vertex 后续通过 edge tiling 或多 template row 累加扩展。

### 2.3 What Not to Choose Yet

以下路径当前都不适合作为第一版 RTL 主线：

- CG / GMRES / BiCGStab  
  原因：过早引入 dot/divider/reduction feedback。

- 完整 CSR + 高度不规则稀疏控制器  
  原因：会把第一版工程重心拖到访存和调度，而不是 solver datapath。

- 任意 Web graph 全功能 PageRank  
  原因：dangling node、variable degree 和随机访存会把第一版工程拖进完整 graph accelerator，而不是验证 digit-stream iteration fusion。

## 3. Mathematical Structure That Must Be Preserved

### 3.1 Core Affine Outputs

第一输出：

$$
x^{(k+1)} = Gx^{(k)} + c
$$

第二输出：

$$
d^{(k)} = x^{(k+1)} - x^{(k)} = (G-I)x^{(k)} + c
$$

因此 `delta` 不是后处理，而是第二个 affine output。

### 3.2 Error Certification

由

$$
d^{(k)} = (G-I)e^{(k)}
$$

得

$$
e^{(k+1)} = -G(I-G)^{-1}d^{(k)}
$$

定义：

$$
H \triangleq G(I-G)^{-1}
$$

则

$$
|e^{(k+1)}| \le |H|\,|d^{(k)}|
$$

这比统一 `\rho` 粗界更有价值，因为它允许把认证做成：

- one-block sensitivity certification
- block-wise certification
- row-wise certification

而不是一律使用：

$$
\|d^{(k)}\|_\infty \le \eta \frac{1-\rho}{\rho}
$$

### 3.3 Block-Wise Certification Form

对 block 划分 `B_t`，定义：

$$
\Delta_t^{(k,j)}
\triangleq
\max_{s\in B_t}
\left(
|\tilde d_s^{(k,j)}| + 2^{-j}
\right)
$$

以及预计算 block weights：

$$
c_{i,t}
\triangleq
\sum_{s\in B_t}|H_{is}|
$$

则一个严格充分的在线认证条件是：

$$
\max_i \sum_t c_{i,t}\Delta_t^{(k,j)} \le \eta
$$

这条式子是当前最值得硬件化的认证公式。

### 3.4 Constant-Matrix Specialization Form

当前 row-update 不应继续按 generic variable-by-variable 形式组织，而应利用固定矩阵系数：

$$
g_{is} \approx \sum_m \gamma_{is,m} 2^{-b_{is,m}},
\qquad
\gamma_{is,m}\in\{-1,+1\}
$$

从而把每个乘项改写成：

$$
g_{is} x_s^{(k)}
\approx
\sum_m \gamma_{is,m}\left(x_s^{(k)} \gg b_{is,m}\right)
$$

这里真正重要的不是“数学上仍然是乘法”，而是工程上变成了：

- 固定 shift
- 固定 sign
- 局部小加法树

而不再是通用 variable-selector front-end。

## 4. What the New Model Already Proved

### 4.1 Local Certification Is Worth It

[generated/local_cert_sweep.md](./generated/local_cert_sweep.md)
已经给出清晰结论：

- `block_size = 1` 的 row-wise 形式在 `18` 个 Jacobi case 中有 `17` 个优于原始 `global_rho`；
- 平均 `avg j*` 额外下降约 `2.278` 位；
- `speedup vs B1` 落在：

  $$
  1.22\times \sim 1.403\times
  $$

因此，认证主线不应再停留在 `global_rho`。

### 4.2 Constant Specialization Has Control-Depth Value, Not Storage Value

[generated/const_coeff_specialization_report.md](./generated/const_coeff_specialization_report.md)
给出的结论是：

- `theta_row_const_proxy` 相对 `theta_row_generic_proxy` 的改善大约为：

  $$
  1.231\times \sim 1.364\times
  $$

- 但 signed-digit template 的静态系数存储并不占优：

  $$
  \text{storage ratio} \approx 0.463 \sim 0.539
  $$

即 template 比直接存定点系数更重。

所以 constant specialization 的主张应当是：

- selector/front-end 深度下降；
- row-update datapath 更专用；

而不是：

- 系数 ROM 必然更小。

### 4.3 Unified Stack Evaluation Supports the Specialized Path

[generated/specialized_stack_eval.md](./generated/specialized_stack_eval.md)
把当前 pre-RTL 版本统一比较成：

- `Ours-A`: generic-front-end iteration-fused proxy
- `Ours-B`: constant-coefficient-specialized row proxy
- `Ours-C`: `Ours-B + block_H certification`

结果很明确：

1. `Ours-B` 在 `18/18` 个 Jacobi case 中都优于 `Ours-A`；
2. `Ours-C` 在 `15/18` 个 case 中优于 `Ours-B`；
3. 因此当前 specialized + local-cert path 不是概念分叉，而是已被模型支持的正式 RTL 入口。

这也意味着后续第一版 RTL 不应再围绕 generic operator 外壳展开，而应直接围绕：

$$
\text{const-coeff row engine} + \text{block}_H \text{ certification}
$$

来搭建。

## 5. Bottom-Up Microarchitecture Optimizations

这一节是当前最重要的部分。

### M1. Replace Generic Selector Front-End

当前 generic operator 的问题不在 local reduction tree，而在它前面的：

- `vector_append`
- `append_and_select`
- `selector`

这一整段 variable-by-variable front-end。

优化方向应是新建：

$$
\texttt{online\_const\_coeff\_contrib}
$$

输入：

- `x_s` 的 digit stream
- 该非零系数的 template

输出：

- 若干个带符号 shifted contribution

这一步不再做通用 partial-product 选择。

### M2. Shared Row-Update / Delta Datapath

`delta` 路径不应单独再复制一套完整 row-update engine。当前最合理的是：

1. 先得到 `x^{(k+1)}` 的在线结果；
2. 与保存的 `x^{(k)}` 做并行 signed-digit subtraction；
3. 把 `d^{(k)}` 的 prefix 直接送认证网络。

也就是此前微架构规格中的：

$$
\text{D2: shared update + subtract}
$$

这比同时跑 `G` 和 `G-I` 两套矩阵流更经济。

### M3. Certification Engine Must Be Block-Oriented

认证引擎不应再做“一个全局 max + 一个全局阈值比较”这么粗的逻辑。当前最合理形式是：

1. 对 `d` prefix 形成 per-row upper bound；
2. 对每个 block 求 `\Delta_t`；
3. 乘以预存的 `c_{i,t}`；
4. 做 `max_i` 比较。

这实际上是一个非常小的 block-level dense matvec：

$$
u_i^{(j)} = \sum_t c_{i,t}\Delta_t^{(j)}
$$

由于 block 数远小于 `N`，这条路径是可实现的。

### M4. Keep Redundant/Internal Format on Chip

不要在 row-update core 和 certification core 之间过早做 rail-to-binary/full-width pack。更合理的边界是：

- row-update core 内部保持 online/redundant；
- `d` prefix upper bound 在 certification 边界转换为可比较量；
- full-width binary/state pack 只放在 state buffer 边界。

这个点直接关系关键路径。

### M5. Static Sparse Schedule Before General CSR

第一版不应上完整 CSR controller。更合理的路径是：

- 先支持 banded/fixed-degree structured sparse；
- 每行 template 数固定或上限固定；
- local reduction tree 拓扑固定；
- state 读顺序固定。

这会让第一版 RTL 把重心放在 solver datapath，而不是存储控制。

### M6. Certification Block Size Should Stay Small

当前模型表明：

- `block_size = 1` 最强；
- `block_size = 4` 常常接近最优；
- `block_size >= 8` 开始明显丢收益。

因此第一版 RTL 合理候选应是：

- `BLOCK_SIZE = 1`
- `BLOCK_SIZE = 4`

而不是更粗。

### M7. Weighted/Chebyshev Should Be Overlay, Not New Core

即使后续做 weighted Jacobi / Chebyshev，它也不该推翻 row-update core，而应实现为：

- 多一层系数 schedule ROM
- 多一条轻量 state mixing path

也就是“overlay on top of affine core”，不是第二套 datapath。

## 6. Recommended Overall Architecture

当前最合理的整体架构如下。

### 6.1 Top-Level Blocks

1. **Coefficient Template Memory**
   - 存 `G` 的 signed-digit template
   - 存 row pointer / fixed-degree metadata

2. **State Buffer Ping-Pong**
   - `x_old`
   - `x_new`
   - 可选 `x_prev`，供 weighted/Chebyshev overlay 使用

3. **Const-Coeff Row-Update Cluster**
   - 若干 row lanes
   - 每 lane 内含：
     - constant-coeff contribution generator
     - local online reduction
     - digit selection / residual update

4. **Delta Sidepath**
   - `x_new - x_old`
   - 只输出认证所需 prefix bound

5. **Block Certification Engine**
   - block maxima
   - `C * Delta` 小型 dense engine
   - `max_i <= eta` 比较

6. **Iteration Controller**
   - handoff
   - stop / continue
   - optional weighted/Chebyshev coefficient schedule

### 6.2 Dataflow

每轮数据流应固定成：

$$
x^{(k)}
\rightarrow
\text{const-coeff row update}
\rightarrow
x^{(k+1)}
\rightarrow
d^{(k)}
\rightarrow
\text{block certification}
\rightarrow
\text{handoff / stop}
$$

而不是：

$$
\text{row update}
\rightarrow
\text{store}
\rightarrow
\text{subtract}
\rightarrow
\text{store}
\rightarrow
\text{norm check}
\rightarrow
\text{restart}
$$

### 6.3 Recommended First RTL Regime

第一版建议固定：

- workload: structured sparse Jacobi
- `BLOCK_SIZE = 1` and `4`
- `ROW_LANES = 2/4`
- coefficient template: signed-digit, bounded term count
- no general CSR
- no weighted/Chebyshev yet

## 7. Hard Innovation Cuts Against Related Work

为了避免与已有工作重复，论文创新点必须硬切。

### Against the Prior Integrated Inner-Product Paper

对方贡献：

$$
\text{operator-level boundary removal}
$$

我们要切到：

$$
\text{iteration-level fusion}
+
\text{delta sidepath}
+
\text{provable local certification}
+
\text{constant-matrix specialization}
$$

### Against Online-Arithmetic SpMV 2024

对方贡献：

$$
\text{online SpMV / MAC datapath}
$$

我们要切到：

$$
\text{online affine solver engine with convergence-aware stopping}
$$

### Against Conventional Sparse FPGA Solvers

对方贡献：

- memory-system efficiency
- hierarchical row reductions
- DSP-centric throughput

我们不能和它们重复 claim。我们的切入点应是：

- constant-matrix online row engine
- no extra delta/norm pass
- local certification from prefix digits
- cycles to certified convergence

### Against Constant-Multiplier Papers

这些工作只能作为工具层来源，不能直接当论文主贡献。我们的切法必须是：

$$
\text{constant multiplier method}
\rightarrow
\text{specialized online affine solver datapath}
$$

即把 coefficient specialization 放到 solver 主线里，而不是单独写一个“更好的 KCM”。

## 8. Final Recommended Contribution Stack

当前最合理的论文贡献栈应固定为：

1. **Constant-matrix-specialized online affine row engine**
2. **Iteration-fused row-update / delta / certification datapath**
3. **Provable block-wise sensitivity certification using**

   $$
   H = G(I-G)^{-1}
   $$

4. **Optional weighted/Chebyshev solver overlay**

如果后续必须砍一条，优先保留前 3 条，第 4 条只作为增强。

## 9. Immediate Pre-RTL Tasks

在真正写 RTL 之前，顺序应固定为：

1. 把 constant-coeff proxy 并入主模型；
2. 固定 `BLOCK_SIZE = 1/4`；
3. 定义 coefficient template 格式；
4. 定义 block-weight memory 格式；
5. 定义 `online_const_coeff_contrib` 接口；
6. 再写最小 specialized row-update cluster。

## Sources

- Prior local PDF: `基于高效集成在线算术的高维线性系统计算.pdf`
- Sparse Matrix-Vector Multiplication Based on Online Arithmetic, IEEE Access 2024: https://doi.org/10.1109/ACCESS.2024.3416395
- Efficient FPGA Implementation of Digit Parallel Online Arithmetic Operators, FPT 2014: https://research.monash.edu/en/publications/efficient-fpga-implementation-of-digit-parallel-online-arithmetic/
- A High Memory Bandwidth FPGA Accelerator for Sparse Matrix-Vector Multiplication, FCCM 2014: https://www.microsoft.com/en-us/research/publication/a-high-memory-bandwidth-fpga-accelerator-for-sparse-matrix-vector-multiplication/
- HiHiSpMV: Sparse Matrix Vector Multiplication with Hierarchical Row Reductions on FPGAs with HBM, FCCM 2024: https://doi.org/10.1109/FCCM60383.2024.00014
- A Mathematical Framework for Online Constant Coefficient Multiplication, 2017: https://ojs.imeti.org/index.php/IJETI/article/view/412
- Reduced-Area Constant-Coefficient and Multiple-Constant Multipliers for Xilinx FPGAs, 2017: https://www.mdpi.com/2079-9292/6/4/101
- PageRank Beyond the Web, SIAM Review 2015: https://doi.org/10.1137/140976649
- Acceleration of the Scheduled Relaxation Jacobi method, JCP 2019: https://doi.org/10.1016/j.jcp.2019.108862
