# Original Integrated Online Inner-Product Paper Reanalysis

本文档重新分析本地论文：

[`../基于高效集成在线算术的高维线性系统计算.pdf`](../%E5%9F%BA%E4%BA%8E%E9%AB%98%E6%95%88%E9%9B%86%E6%88%90%E5%9C%A8%E7%BA%BF%E7%AE%97%E6%9C%AF%E7%9A%84%E9%AB%98%E7%BB%B4%E7%BA%BF%E6%80%A7%E7%B3%BB%E7%BB%9F%E8%AE%A1%E7%AE%97.pdf)

分析原则：如果本文档、现有 RTL 注释、或我们先前工程判断与论文正文冲突，以论文正文为准；源码只用于确认论文中的硬件结构如何落地。

## Paper Problem Statement

原论文的出发点不是一般意义上的 Jacobi solver，也不是完整迭代求解器，而是 **高维内积在线算术的级联延迟问题**。

传统 online arithmetic 的优势是 MSB-first、signed-digit 冗余表示、短进位链和较低中间存储；但如果直接用标准 online multiplier 和 online adder 级联实现高维内积：

$$
\langle x,y\rangle = \sum_{s=0}^{n-1}x_s y_s
$$

或者带 bias 的仿射内积：

$$
\langle x,y\rangle + b
$$

每一级 online operator 都有自己的 online delay。级联结构会导致：

$$
\theta_{\mathrm{cas}}
=1+\delta_\times+1+(\delta_+ + 1)\log_2(n+1)
$$

其中论文采用：

$$
\delta_\times=3,\quad \delta_+=2
$$

所以问题本质是：

$$
\text{online primitives are compact, but cascaded online operators accumulate latency.}
$$

这不是 conventional DSP-MAC 与 online MAC 的总比较，而是 **cascaded online inner product** 与 **integrated online inner product** 的比较。

## Paper Method

论文提出的是 integrated online inner product。它把：

$$
\text{online multiplication}
\rightarrow
\text{online accumulation}
\rightarrow
\text{bias addition}
$$

折叠成一个统一的 residual recurrence。

对不带 bias 的高维内积，论文定义前缀：

$$
x_s[j]=\sum_{i=1}^{j+\delta}x_{s,i}2^{-i},
\quad
y_s[j]=\sum_{i=1}^{j+\delta}y_{s,i}2^{-i},
\quad
z[j]=\sum_{i=-\delta+1}^{j}z_i2^{-i}
$$

残差为：

$$
w[j]=2^j\left(\sum_{s=0}^{n-1}x_s[j]y_s[j]-z[j]\right)
$$

并得到：

$$
\sigma_n(x,y)
=
\sum_{s=0}^{n-1}
\left(
x_s[j]y_{s,j+1+\delta}
+
y_s[j+1]x_{s,j+1+\delta}
\right)
$$

$$
v[j]=2w[j]+2^{-\delta}\sigma_n(x,y)
$$

$$
w[j+1]=v[j]-z_{j+1}
$$

对带 bias 的内积，论文扩展为：

$$
v[j]=2w[j]+2^{-\delta}\left(\sigma_n(x,y)+b_{j+1+\delta}\right)
$$

$$
z_{j+1}=\mathrm{sel}(\hat v[j])
$$

$$
w[j+1]=v[j]-z_{j+1}
$$

这里的关键不是“少算几位”，而是把乘法产生 partial product、归约、bias 注入和输出 digit 选择统一在同一个 residual loop 中。

## Selection Rule and Delay Choice

论文选择 radix-2 signed-digit：

$$
z_j\in\{-1,0,1\}
$$

并采用固定 selection threshold：

$$
m_0=-\frac{1}{2},\quad m_1=\frac{1}{2}
$$

因此：

$$
\mathrm{sel}(\hat v[j])=
\begin{cases}
1, & \hat v[j]\ge \frac{1}{2}\\
0, & -\frac{1}{2}\le \hat v[j] < \frac{1}{2}\\
-1, & \hat v[j] < -\frac{1}{2}
\end{cases}
$$

对带 bias 的内积，论文给出的可扩展参数选择是：

$$
t=3,
\quad
\delta=\left\lceil \log_2\left(\frac{2n+1}{3}\right)\right\rceil+3
$$

其中 `t` 是估计 `v[j]` 所需 fractional bits，`delta` 是 integrated inner product 的 online delay。这个推导非常关键：论文不是简单地把 multiplier 和 adder 写到一个模块里，而是通过 residual bound 证明 selection 只需要固定小位数估计，并且 delay 随维度按对数增长。

## Source-Level Correspondence

原始源码位于：

[`../MSDF_operator_srcs/MSDF_Operators/MSDF_Operators/MSDF_Operators.srcs/sources_1/new`](../MSDF_operator_srcs/MSDF_Operators/MSDF_Operators/MSDF_Operators.srcs/sources_1/new)

源码和论文结构对应如下：

| Paper Concept | RTL Evidence | Meaning |
| --- | --- | --- |
| digit-serial operand stream | `vector_append.v` | 把逐拍 `p/n` digit 组装成局部 digit vector 窗口 |
| partial product by signed digit selection | `append_and_select.v`, `selector.v` | 当前 digit 为 `+1/-1/0` 时选择、反选或清零另一个 operand 窗口 |
| parallel online local reduction | `parallel_online_adder*.v` | 在本地 digit-vector 上用 online adder fabric 归约 partial sums |
| residual loop | `MSDF_MUL.v`, `MSDF_MUL_ADD.v` | 保存 `w[j]`，计算 `2w[j] + sum` |
| output digit selection and residual update | `output_and_update.v`, `output_and_update_0.v` | 从 `v[j]` 高位估计选择 `z[j+1]`，并更新 `w[j+1]` |
| integrated multiply-add | `MSDF_MUL_ADD.v`, `MSDF_MUL_ADD_8.v` | 把乘法 partial sum、bias/addend 和 residual update 放在同一个 operator 内 |

源码确认了论文说法：这是 **operator-level integrated online inner-product / MAC architecture**。它不是 solver-level architecture。`o_int/o_unit/o_frac`、`o_valid` 等接口是 operator/testbench 驱动语义，不包含 iteration、state bank、delta/certification 或 solver control。

## Paper Architecture

论文硬件结构可以分成三层。

第一层是 `PSCU`，即 partial sum computing unit。它处理每个 `s` 项：

$$
x_s[j]y_{s,j+1+\delta}
+
y_s[j+1]x_{s,j+1+\delta}
$$

对应源码里的 `vector_append + selector + parallel_online_adder` 风格。

第二层是 adder-tree reduction。多个 `PSCU` 的输出进入 parallel online adder tree，得到：

$$
\sigma_n(x,y)
$$

论文为了频率，在 adder tree 中插入 pipeline register，并把 pipeline tree delay 写进 initial delay 公式。

第三层是 residual/output-update loop：

$$
v[j]=2w[j]+2^{-\delta}(\sigma_n+b)
$$

$$
z_{j+1}=\mathrm{sel}(\hat v[j])
$$

$$
w[j+1]=v[j]-z_{j+1}
$$

这也是源码中 `POA_V + output_and_update + DFF_W` 的真实含义。

## Evaluation Scenarios in the Paper

论文验证了两类东西。

第一类是 integrated online inner product 与 cascaded online counterpart 的 operator-level 对比。

评价指标包括：

- initial delay；
- delay reduction ratio；
- LUT；
- FF；
- post-place-and-route `fmax`。

论文报告 integrated architecture 的 initial delay 最多接近 50% reduction，资源与 cascaded online 接近，FF 通常更低。

第二类是 PageRank case study。

论文把 PageRank 写成：

$$
r^{(k+1)}=\beta M r^{(k)}+(1-\beta)n^{-1}e
$$

令：

$$
A=\beta M,
\quad
b=(1-\beta)n^{-1}e
$$

得到：

$$
r=Ar+b
$$

这正好可以用带 bias 的 integrated online inner product array 实现 matrix-vector update。论文选择 PageRank 的原因是：

- 数据值自然在小于 1 的概率范围内；
- 适合 online arithmetic 的定点 signed-digit 表示；
- 每轮都是大量 matrix-vector / inner-product；
- 可展示高维并行 digit-serial array 的优势。

论文实验平台是 Xilinx Zynq UltraScale+ MPSoC `xczu15eg-ffvb1156-2-i`，Vivado 2023.2，175 MHz。论文给出的 PageRank case 是 32 dimension、32-bit precision、13 iterations，FPGA 相对 Intel Core i9-12900K CPU / NumPy / OpenBLAS 获得 13.4x speedup。

## What the Paper Does Not Solve

这部分是我们后续创新的空间，必须写得严格。

原论文没有解决完整 solver-level online digit-stream execution。它的 PageRank 顶层仍然把每一轮的输出送入 `Digit2Vector`，再做相邻迭代比较，然后通过 `Vector2Digit` 重新进入下一轮。这意味着它保留了：

$$
\text{operator output}
\rightarrow
\text{digit-parallel/vector storage}
\rightarrow
\text{compare}
\rightarrow
\text{re-serialization}
\rightarrow
\text{next iteration}
$$

这些边界。

因此，原论文解决的是：

$$
\text{multiplier/addition boundary inside inner product}
$$

但没有解决：

$$
\text{iteration boundary of solver}
$$

具体未解决问题包括：

1. `x^{(k+1)}` 仍需要落到 vector-level buffer 后再进入比较和下一轮。
2. `r^{(k+1)}-r^{(k)}` 或 solver delta 不是 integrated recurrence 的一部分。
3. convergence check 是后处理，不是与 output digit 同步推进的 prefix certificate。
4. 每轮迭代之间仍存在 reset、latch、re-serialization 和 restart cycles。
5. 矩阵结构没有被充分利用；论文 operator 面向 generic high-dimension inner product，而不是固定矩阵 solver 的 constant-coefficient / stencil / block structure。
6. 它的主要强对比是 cascaded online 和 CPU PageRank，不是现代 conventional FPGA DSP-MAC sparse/dense solver baseline。

## Updated Application Position: PageRank First, Jacobi As Fixture

早期判断认为 Jacobi / stencil / banded solver 更适合作为第一主线，因为它的 halo/stencil 数据路径更规则。随着当前工程收敛到定点 MSDF / digit-stream wavefront，论文应用场景改为 PageRank first，Jacobi 保留为 RTL stress fixture。

PageRank 的核心优点是数值范围自然适合概率向量：

$$
0\le r_i\le 1
$$

这比 Jacobi 更匹配当前定点核心，因为 Jacobi state 可能大于 1，需要额外整数位、缩放和 signed dynamic-range 解释。PageRank 的非负、有界、重复 affine propagation 更适合论文叙事。

需要保留的限制是：第一版 PageRank 不是任意 Web graph accelerator，而是 bounded-degree / partitioned PageRank。它仍写成固定矩阵 affine row update：

$$
r_i^{(k+1)}=(1-\beta)v_i+\sum_{j\in In(i)}\beta\frac{1}{outdeg(j)}r_j^{(k)}
$$

因此：

1. PageRank 是 headline application；
2. Jacobi / stencil / banded fixed-point solver 是 signed-coefficient 和 halo-window RTL validation fixture；
3. 真实 PageRank 仍需要补 graph-to-template compiler、PageRank `L1` certification 和 dangling-node handling。

PageRank 的收敛检测自然依赖：

$$
d_i^{(k)}=r_i^{(k+1)}-r_i^{(k)}
$$

这仍然暴露原论文没有解决的 solver boundary。

## Architecture Innovation Direction

后续不能把创新停在“少跑几轮”或“K schedule”。这类做法本质是精度/周期 knob，不是新的数学架构。

更强的方向是 **solver-native integrated online recurrence**。它把原论文 operator 内部的 residual idea 扩展到 solver iteration boundary。

### I1. Solver-Native Row Digit Engine

原论文 recurrence 是：

$$
v[j]=2w[j]+2^{-\delta}\left(\sigma_n(x,y)+b_{j+1+\delta}\right)
$$

我们应把它改造成固定矩阵 affine row update 的 solver-native recurrence：

$$
v_i^{(k)}[j]
=
2w_i^{(k)}[j]
+
\mathcal{S}_i
\left(
\{x_t^{(k)}[\cdot]\}_{t\in N(i)},
\{g_{it}\}_{t\in N(i)},
c_i
\right)
$$

$$
x_{i,j+1}^{(k+1)}
=
\mathrm{sel}
\left(
\hat v_i^{(k)}[j]
\right)
$$

$$
w_i^{(k)}[j+1]
=
v_i^{(k)}[j]-x_{i,j+1}^{(k+1)}
$$

这里 `g_it` 是固定系数，不应该再按两个 variable operands 的 generic inner product 处理。底层应从 `append_and_select` 的思想升级为 constant-coefficient digit contribution network。

### I2. Digit-Stream State Commit

原论文 PageRank 顶层需要：

$$
\text{Digit2Vector}
\rightarrow
\text{compare}
\rightarrow
\text{Vector2Digit}
$$

我们的目标是：

$$
x_{i,j}^{(k+1)}
\rightarrow
\text{state digit bank write}
\rightarrow
\text{next replay}
$$

如果仍然跑满全部 `W` 位，这不是近似，数值仍是完整精度。区别只是数据流边界改变。

### I3. Digit-Stream Delta and Prefix Certification

在 `x_new` digit 输出时同步计算：

$$
d_{i,j}^{(k)}
=
x_{i,j}^{(k+1)}-x_{i,j}^{(k)}
$$

并维护 prefix bound：

$$
|d_i^{(k)}|
\le
|d_{i,\mathrm{prefix}}^{(k)}[j]|
+
B_{\mathrm{tail}}(j)
$$

这一步的贡献不是“少算几位”，而是把 convergence check 从 full-word 后处理改成 output stream 的一部分。只有在严格证明安全时，才可以进一步做 certified block freeze 或 tail skip。

### I4. Constant-Matrix Specialized Online Contribution

原论文是 high-dimension generic inner product。固定矩阵 solver 里：

$$
g_{it}
$$

是编译期已知或运行时模板化的。应吸收 constant-coefficient online multiplication / multiple constant multiplication 的思想，把：

$$
g_{it}x_t^{(k)}
$$

从 generic signed-digit selector 改成常系数贡献网络。这样才是底层数学/架构创新，而不是工程优化。

### I5. Operator Boundary to Solver Boundary

最终论文差异应写成：

| Level | Prior Paper | New Target |
| --- | --- | --- |
| Main problem | cascaded online inner-product latency | full solver iteration boundary |
| Core operator | generic integrated inner product with bias | solver-native affine row digit engine |
| State handling | digit output to vector buffer | digit-stream state commit |
| Convergence | full/vector compare after iteration | inline digit delta/certification |
| Matrix structure | generic dimension `n` | fixed/stencil/block sparse structure |
| Strong workload | PageRank case study | structured Jacobi / affine fixed-point solver |

## External Ideas Worth Absorbing

下面这些相关方向可以吸收，但不能直接复制成 claim。

### Online Arithmetic Implementation

Zhao, Wickerson and Constantinides, “An Efficient Implementation of Online Arithmetic,” FPT 2016, and Shi, Boland and Constantinides, “Efficient FPGA Implementation of Digit Parallel Online Arithmetic Operators,” FPT 2014, both point to a practical fact: online arithmetic only becomes competitive on FPGA when primitive structure is FPGA-aware. This supports rewriting the bottom operator rather than directly copying old RTL.

Useful source links:

- FPT 2014 digit-parallel online operators: <https://research.monash.edu/en/publications/efficient-fpga-implementation-of-digit-parallel-online-arithmetic>
- DOI: <https://doi.org/10.1109/FPT.2014.7082763>
- FPT 2016 online arithmetic implementation: <https://doi.org/10.1109/FPT.2016.7929191>

### Digit Elision / Iterative Compute

Li et al., “Architect: Arbitrary-precision Hardware with Digit Elision for Efficient Iterative Compute,” IEEE TVLSI 2019, shows that iterative workloads can benefit from digit-level execution control. The difference is that our mainline should not be generic digit elision; it should be solver-specific digit stream, delta, and certification.

Useful source link:

- Architect / digit elision: <https://cir.nii.ac.jp/crid/1360869863223352704>

### Multioperand Streaming Online Addition

Villalba, Lang and Hormigo, “Radix-2 Multioperand and Multiformat Streaming Online Addition,” IEEE TC 2011, is relevant because our row update is a multi-source affine accumulation. The useful idea is not a new top-level solver, but a cleaner multioperand online adder fabric for the row engine.

Useful source link:

- Radix-2 multioperand streaming online addition: <https://www.ac.uma.es/HPACuma/pubs/publicationsJ-113.html>

### Sparse / Structured Linear Algebra

SpMV and Jacobi FPGA literature should be treated as conventional architecture baseline, not as the source of the online claim. It reminds us that raw DSP-MAC sparse kernels are strong. Therefore the paper metric must include solver-level boundary removal, state traffic, digit-stream certification, and total cycles to certified convergence, not only row-update latency.

## Immediate Research Decision

The next mainline should be:

$$
\textbf{solver-native digit-stream affine iteration engine}
$$

not:

$$
\text{generic integrated inner product reimplementation}
$$

and not:

$$
\text{low precision K schedule}
$$

Implementation should start from a new bottom operator that preserves the paper-correct recurrence structure, but changes the operand model from generic variable-by-variable inner product to fixed-matrix affine row update:

1. Reuse the original `output_and_update` residual concept.
2. Rebuild the partial contribution generator for constant coefficients.
3. Stream bias as a digit source or prove a residual seed formulation.
4. Output `x_new` digit directly into digit-stream state bank.
5. Feed old/new digit streams into inline delta/certification.
6. Compare against both prior integrated online operator shell and clean conventional DSP-MAC runtime.

This is the strongest available path because it solves a real limitation of the original paper: it moves online integration from the inner-product operator boundary to the iterative solver boundary.
