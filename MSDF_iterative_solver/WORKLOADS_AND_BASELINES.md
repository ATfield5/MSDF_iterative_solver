# Iterative Solver Workloads and Baselines

本文件固定新主线的两个代表 workload、baseline 口径和后续实验禁止项。目标是尽快结束“做什么问题、和谁比”这两个最容易发散的部分。

## 1. Selection Principle

新主线只选满足下面四条的问题：

1. 能写成 affine fixed-point iteration：

$$
x^{(k+1)} = Gx^{(k)} + c
$$

2. 迭代主成本确实在高维 row-wise reduction，而不是在除法、归一化或全局复杂控制。

3. 在线收敛认证有意义，也就是：

$$
\|x^\star - x^{(k+1)}\|
\le
\frac{\rho}{1-\rho}\|d^{(k)}\|
$$

这类界能直接用于 stopping rule。

4. baseline 既能做 online arithmetic 内部对照，也能做 conventional FPGA 工程对照。

## 2. Final Workload Choice

最终固定两个 workload 层级：PageRank 是论文 headline application；Jacobi-style solver 是 RTL validation / stress fixture，用来覆盖 signed coefficient、halo replay 和更宽动态范围，不再作为第一应用叙事。

## W1: PageRank

写成：

$$
r^{(k+1)} = \beta M r^{(k)} + (1-\beta)\frac{1}{n}e
$$

记：

$$
G = \beta M,\qquad
c = (1-\beta)\frac{1}{n}e
$$

则：

$$
r^{(k+1)} = Gr^{(k)} + c
$$

### Why W1

它适合作为第一主 workload，原因很明确：

- 完全符合 affine fixed-point 形式；
- 系数和状态天然有界，容易做在线算术；
- 与现有 integrated online inner-product 论文有继承关系，但层级更高；
- 能清楚展示 iteration boundary 与 convergence certification 的收益。
- 更符合当前定点核心的限制：rank/state 默认位于 `[0,1]`，不像部分 Jacobi case 需要额外整数位或矩阵缩放解释。
- mode4 wavefront super-step 可以直接解释为多次 PageRank power iteration 的 digit-stream fusion。

### Contraction Property

若 `M` 是列随机或按实现约定转成等价随机传播矩阵，则在 `L_1` 范数下：

$$
\|G\|_1 = \beta < 1
$$

因此：

$$
\|r^\star - r^{(k+1)}\|_1
\le
\frac{\beta}{1-\beta}\|d^{(k)}\|_1
$$

这是 W1 的理论 stopping rule。

### Immediate Dataset Families

第一版先用两类图：

1. synthetic stochastic matrices
   - Erdős–Rényi
   - Barabási–Albert
   - 可控稀疏度和度分布

2. small-to-medium real graph snapshots
   - 后续可接公开 graph benchmark
   - 第一阶段先不把数据集依赖作为 blocker

## W2: Jacobi-Style Fixed-Point Solver

对线性系统：

$$
Ax=b
$$

拆分：

$$
A = D + L + U
$$

Jacobi 迭代写成：

$$
x^{(k+1)} = -D^{-1}(L+U)x^{(k)} + D^{-1}b
$$

记：

$$
G = -D^{-1}(L+U),\qquad
c = D^{-1}b
$$

则：

$$
x^{(k+1)} = Gx^{(k)} + c
$$

### Why W2

它适合作为 RTL validation fixture，因为它补足了 W1 没有覆盖的点：

- 系数允许为有符号实数；
- 不再局限于概率/随机传播场景；
- 直接对应更一般的稀疏线性系统；
- 仍然没有 CG/GMRES 那种额外 dot/divider 负担。

但它不再作为论文第一应用。原因是 Jacobi state 可能大于 1，矩阵缩放、额外整数位和 signed dynamic range 会分散当前定点 MSDF 核心叙事。PageRank 更适合作为“有界固定点图传播”的主场景。

### Contraction Property

若矩阵满足严格对角占优等条件，使得：

$$
\|G\|_\infty \le \rho < 1
$$

则：

$$
\|x^\star - x^{(k+1)}\|_\infty
\le
\frac{\rho}{1-\rho}\|d^{(k)}\|_\infty
$$

这是 W2 的默认 stopping rule。

### Immediate Dataset Families

第一版先用三类矩阵：

1. synthetic strictly diagonally dominant dense matrices
2. synthetic sparse diagonally dominant matrices
3. structured banded / stencil-derived matrices

后续再接：

- 2D/3D Poisson 类离散化矩阵
- SuiteSparse 风格的真实 sparse matrices

## 3. Why Not the Other Candidates

### Not Power Iteration as a Main Workload

标准 power iteration 需要每轮归一化：

$$
x^{(k+1)} = \frac{Ax^{(k)}}{\|Ax^{(k)}\|}
$$

它不是 affine fixed-point。除非做带外 normalization 或只做带 damping 的传播版本，否则会过早把系统拖回全局除法/归一化问题。

因此 power iteration 只作为 W1 的近邻问题，不作为当前主 workload。

### Not Richardson as the Second Main Workload

Richardson 当然也可写成：

$$
x^{(k+1)} = (I-\omega A)x^{(k)} + \omega b
$$

它是合法候选，但会把应用叙事从 PageRank 图传播转回通用线性系统。当前不把 Richardson 作为主 workload；它只作为 affine fixed-point family 的扩展对照保留。Jacobi 也只作为 W2 validation fixture，不再改变 PageRank first 的应用定位。

### Not CG / GMRES

CG / GMRES 的问题不是不能做，而是太早引入：

- 多个全局 dot product
- step-size 更新
- 除法
- 更复杂的同步边界

这会把“iteration-fused affine fixed-point solver”这个主张冲淡。当前阶段明确不选。

## 4. Baseline Hierarchy

baseline 固定成三层。

## B1: Cascaded Online Baseline

这是 online arithmetic 内部基线，作用是回答：

$$
\text{iteration-fused 相比 conventional online cascade 到底省了什么?}
$$

它的结构是：

$$
\text{online multiply}
\rightarrow
\text{online adder tree}
\rightarrow
\text{bias add}
\rightarrow
\text{full-width } x^{(k+1)}
\rightarrow
\text{delta}
\rightarrow
\text{norm compare}
$$

特征：

- 保留 online arithmetic 的数制；
- 不做 solver-level 融合；
- `delta` 和 convergence check 是独立后处理。

## B2: Conventional FPGA Kernel

这是工程主 baseline，作用是回答：

$$
\text{为什么不用标准 DSP MAC / BRAM / comparator 流?}
$$

它的结构默认是：

$$
\text{DSP MAC tree}
\rightarrow
\text{bias add}
\rightarrow
\text{stored } x^{(k+1)}
\rightarrow
\text{full-width delta}
\rightarrow
\text{norm compare}
$$

这里不需要强行做浮点。为了公平，第一版应使用与 online 设计相匹配的 fixed-point / dynamic fixed-point 数值契约，而不是故意给 conventional baseline 加额外负担。

## B3: CPU Software Reference

CPU 只做应用级参考，不混 FPGA 资源表。它回答：

$$
\text{端到端 solve time 是否有实际意义?}
$$

第一版建议：

- `float64` reference
- 同样 stopping rule
- 同样矩阵与初值

## 5. Fairness Rules

后续所有报告必须满足下面四条。

### Rule 1

所有 baseline 使用同一数学问题、同一 stopping rule、同一误差阈值。

### Rule 2

不能让 online 设计用 solver-level certification，而 conventional baseline 用更保守的 full-precision fixed-iteration；否则 cycle 对比不公平。

### Rule 3

CPU 结果不替代 FPGA 主 baseline。CPU speedup 只能做附属应用级结果。

### Rule 4

如果某个结果只证明了：

$$
\text{fused online} > \text{cascaded online}
$$

但没有证明相对 `B2` 的工程意义，就不能写成最终主 claim。

## 6. First Experiment Matrix

第一轮实验不求大而全，只固定能快速判断 go/no-go 的组合。

### E1

`PageRank`, dense/small:

- `n = 8, 16, 32, 64`
- `\beta = 0.85, 0.90, 0.95`

目的：

- 验证数学正确性；
- 验证在线 stopping rule；
- 初看 cycle model。

### E2

`PageRank`, sparse:

- `n = 64, 128, 256`
- 不同平均出度

目的：

- 看 streaming / storage 优势是否开始出现。

### E3

`PageRank`, partitioned bounded-degree RTL fixture:

- `n = 32`
- `8 clusters x 4 vertices`
- `D_max = 4`
- locality-preserving partition, matching current halo-window contract

目的：

- 生成第一版 `pagerank32_*` memh；
- 对接现有 mode3/mode4 runtime；
- 与 PageRank-equivalent conventional runtime baseline 做公平 cycle/resource 对比。

### E4

`Jacobi`, sparse / banded validation:

- `n = 64, 128, 256`
- 不同带宽和稀疏度

目的：

- 只作为 signed-coefficient / wider-dynamic-range stress test；
- 不作为论文第一应用结果。

## 7. Go / No-Go Gate for Continuing to RTL

只有满足下面三条，才值得继续 RTL：

1. 对 PageRank 数学上能给出严格 stopping bound。
2. cycle model 显示 iteration-fused PageRank 相比 B1 有稳定优势。
3. PageRank RTL fixture 相比 B2 存在明确可讲的优势来源：
   - 较低 DSP
   - 更低中间存储
   - 更少 iteration-level boundary cost
   - 更少 cycles to certified convergence

如果这三条里有一条不成立，就不应该继续扩张到 solver 顶层 RTL。

## 8. Immediate Next Step

下一步不写 RTL，先做：

1. `PageRank` graph-to-template generator；
2. PageRank `L1` delta certification；
3. PageRank-equivalent `B1/B2/B3` 统一报告口径；
4. `pagerank32_*` runtime memh 和软件 golden model。
