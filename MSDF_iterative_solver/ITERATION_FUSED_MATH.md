# Iteration-Fused Online Arithmetic: Mathematical Derivation

本文件给出新的论文主线的完整数学基础。目标不是重新发明单个 online inner product，而是把 affine fixed-point iteration

$$
x^{(k+1)} = Gx^{(k)} + c
$$

统一改写成一个适合 online arithmetic 的 solver-level 数据流，并严格推导：

- row-update 的 integrated online recurrence；
- `delta = x^{(k+1)} - x^{(k)}` 的在线生成方式；
- 基于 prefix digit 的严格收敛认证；
- 为什么这种方法在数学上高于 “inner-product-only integration”。

## 1. Scope and Assumptions

默认工作在以下前提下：

1. 先研究 affine fixed-point family：

$$
x^{(k+1)} = Gx^{(k)} + c,\qquad G\in\mathbb{R}^{n\times n},\;x^{(k)},c\in\mathbb{R}^n
$$

2. 数值先规约到 online arithmetic 易处理的区间。默认每个 streamed 分量都满足：

$$
|x_i^{(k)}|<1,\qquad |c_i|<1,\qquad |g_{ij}|<1
$$

如果需要更大动态范围，则通过 block scaling / dynamic fixed-point 在系统边界上处理；本文件只讨论归一化后的 mantissa 流。

3. 采用 radix-2 signed-digit 表示。任意标量 `a` 的展开写成：

$$
a=\sum_{\ell=1}^{\infty} a_{\ell}2^{-\ell},\qquad a_{\ell}\in\{-1,0,+1\}
$$

4. `G` 的非零结构可以是 dense、sparse 或 block-sparse；数学推导先按一般 `n` 维行向量写，再在实现阶段决定具体流式矩阵格式。

5. 收敛性分析默认基于某个诱导范数 `\|\cdot\|` 下的压缩条件：

$$
\|G\|\le \rho < 1
$$

这是 PageRank、power iteration 的稳定版本、Richardson/Jacobi 类固定点迭代的标准入口假设。

## 2. Why Iteration-Fused Is the Right Level

传统 solver 的逻辑边界通常是：

$$
Gx^{(k)} \;\rightarrow\; +c \;\rightarrow\; x^{(k+1)} \;\rightarrow\; x^{(k+1)}-x^{(k)} \;\rightarrow\; \| \cdot \| \text{ compare}
$$

这里至少有三类 boundary：

1. `inner product -> bias add`
2. `new iterate -> delta subtraction`
3. `delta vector -> convergence check -> next iteration restart`

在 online arithmetic 中，每个 boundary 不只是一个逻辑模块边界，还意味着：

- online delay 级联；
- 中间结果显式落地；
- 格式转换和对齐；
- iteration flush / restart 开销。

solver 级创新的关键不是再做一个更好的 dot-product primitive，而是观察到下面这个块映射仍然是仿射的：

$$
\begin{bmatrix}
x^{(k+1)} \\
d^{(k)}
\end{bmatrix}

=
\begin{bmatrix}
G \\
G-I
\end{bmatrix}
x^{(k)}
+
\begin{bmatrix}
c \\
c
\end{bmatrix},
\qquad
d^{(k)} \triangleq x^{(k+1)}-x^{(k)}
$$

因此，`new iterate` 与 `delta` 不是两个不同类别的问题，而是**同一输入向量 `x^{(k)}` 上的两个 affine outputs**。这就是 iteration-fused 数学上成立的根本原因。

## 3. Row-Wise Affine Update as Integrated Online Inner Product

对第 `i` 行，定义：

$$
y_i^{(k+1)} \triangleq x_i^{(k+1)} = \sum_{s=0}^{n-1} g_{is}x_s^{(k)} + c_i
$$

这正是“带 bias 项的内积”。

### 3.1 Prefix Representation

设 online delay 为 `\delta`。在 cycle `j`，第 `i` 行系数、输入状态、偏置和输出前缀分别记为：

$$
g_{is}[j] = \sum_{\ell=1}^{j+\delta} g_{is,\ell}2^{-\ell}
$$

$$
x_s^{(k)}[j] = \sum_{\ell=1}^{j+\delta} x_{s,\ell}^{(k)}2^{-\ell}
$$

$$
c_i[j] = \sum_{\ell=1}^{j+\delta} c_{i,\ell}2^{-\ell}
$$

$$
y_i^{(k+1)}[j] = \sum_{\ell=-\delta+1}^{j} y_{i,\ell}^{(k+1)}2^{-\ell}
$$

这里：

- `g_{is,\ell}`、`x_{s,\ell}^{(k)}`、`c_{i,\ell}`、`y_{i,\ell}^{(k+1)}` 都属于 `\{-1,0,+1\}`；
- 输出索引从 `-\delta+1` 开始，是标准 online arithmetic 对 online delay 的写法。

### 3.2 Residual Definition

定义第 `i` 行的 residual：

$$
w_i^{(k)}[j]
=
2^j
\left(
\sum_{s=0}^{n-1} g_{is}[j]x_s^{(k)}[j] + c_i[j] - y_i^{(k+1)}[j]
\right)
$$

只要 digit selection 设计正确，就要求该 residual 始终被某个常数 `\omega` 有界：

$$
|w_i^{(k)}[j]| < \omega
$$

### 3.3 Exact Recurrence

将前缀从 `j` 推到 `j+1`：

$$
g_{is}[j+1] = g_{is}[j] + g_{is,j+1+\delta}2^{-(j+1+\delta)}
$$

$$
x_s^{(k)}[j+1] = x_s^{(k)}[j] + x_{s,j+1+\delta}^{(k)}2^{-(j+1+\delta)}
$$

$$
c_i[j+1] = c_i[j] + c_{i,j+1+\delta}2^{-(j+1+\delta)}
$$

$$
y_i^{(k+1)}[j+1] = y_i^{(k+1)}[j] + y_{i,j+1}^{(k+1)}2^{-(j+1)}
$$

对双线性项有：

$$
g_{is}[j+1]x_s^{(k)}[j+1]
=
g_{is}[j]x_s^{(k)}[j]
+
2^{-(j+1+\delta)}
\left(
g_{is}[j]x_{s,j+1+\delta}^{(k)}
+
x_s^{(k)}[j+1]g_{is,j+1+\delta}
\right)
$$

因此定义第 `i` 行在 cycle `j` 的 partial-sum driver：

$$
\sigma_i^{(k)}[j]
\triangleq
\sum_{s=0}^{n-1}
\left(
g_{is}[j]x_{s,j+1+\delta}^{(k)}
+
x_s^{(k)}[j+1]g_{is,j+1+\delta}
\right)
$$

带入 residual 定义后，可得**精确递推**：

$$
w_i^{(k)}[j+1]
=
2w_i^{(k)}[j]
+
2^{-\delta}\left(\sigma_i^{(k)}[j] + c_{i,j+1+\delta}\right)
-
y_{i,j+1}^{(k+1)}
$$

记：

$$
v_i^{(k)}[j]
\triangleq
2w_i^{(k)}[j]
+
2^{-\delta}\left(\sigma_i^{(k)}[j] + c_{i,j+1+\delta}\right)
$$

则：

$$
w_i^{(k)}[j+1] = v_i^{(k)}[j] - y_{i,j+1}^{(k+1)}
$$

这就是从“带 bias 项内积”直接得到的 integrated online row-update recurrence。它不需要先显式生成每个乘积，再显式落一个 adder-tree 输出。

## 4. Digit Selection Condition

设 `\hat v_i^{(k)}[j]` 是对 `v_i^{(k)}[j]` 的 `t` 个 fractional bits 的估计，则 digit selection 写成：

$$
y_{i,j+1}^{(k+1)} = \operatorname{sel}\left(\hat v_i^{(k)}[j]\right)
$$

对 radix-2 signed-digit 输出集合 `\{-1,0,+1\}`，若估计精度 `t` 和 online delay `\delta` 选取满足标准 online arithmetic 的 admissible interval 条件，则存在固定的选择常数 `m_{-1},m_0,m_1` 使得 residual 始终有界。

对于“高维内积 + bias”这一类问题，[基于高效集成在线算术的高维线性系统计算.pdf](/home/sy/FPGA/MSDF/%E5%9F%BA%E4%BA%8E%E9%AB%98%E6%95%88%E9%9B%86%E6%88%90%E5%9C%A8%E7%BA%BF%E7%AE%97%E6%9C%AF%E7%9A%84%E9%AB%98%E7%BB%B4%E7%BA%BF%E6%80%A7%E7%B3%BB%E7%BB%9F%E8%AE%A1%E7%AE%97.pdf) 已给出一个可行设计点：

$$
t = 3
$$

$$
\delta \ge \left\lceil \log_2 \frac{2n+1}{3} \right\rceil + 3
$$

其意义是：

- `t` 固定，不随维度增长；
- `\delta` 只按 `O(\log n)` 增长；
- 因而 integrated row-update 对高维问题是可扩展的。

这也是本方向继续成立的基础。

## 5. Delta Tracking Is Also an Affine Operator

定义迭代差分：

$$
d^{(k)} \triangleq x^{(k+1)} - x^{(k)}
$$

对第 `i` 行：

$$
d_i^{(k)}
=
\sum_{s=0}^{n-1} g_{is}x_s^{(k)} + c_i - x_i^{(k)}
$$

将最后一项并入线性部分：

$$
d_i^{(k)}
=
\sum_{s=0}^{n-1} h_{is}x_s^{(k)} + c_i,
\qquad
h_{is}\triangleq g_{is} - \delta_{is}
$$

其中 `\delta_{is}` 为 Kronecker delta。于是：

$$
d^{(k)} = (G-I)x^{(k)} + c
$$

这说明 `delta` 不是一个额外的非线性后处理，而是与 `x^{(k+1)}` **同类的 affine row-update**。因此：

- 可以复用完全相同的 integrated online recurrence；
- 也可以在实现上把 `G` 与 `G-I` 两套 row stream 并排送入；
- 或者先得到 `x^{(k+1)}` 的 digit stream，再用零 online-delay 的并行 signed-digit 减法器与 `x^{(k)}` 形成 `d^{(k)}`。

数学上最干净的表述是前者：`delta` 本身就是第二个 affine output。

## 6. Solver-Level Convergence Structure

设固定点为 `x^\star`，满足：

$$
x^\star = Gx^\star + c
$$

定义误差：

$$
e^{(k)} \triangleq x^{(k)} - x^\star
$$

则：

$$
e^{(k+1)} = Ge^{(k)}
$$

另一方面，因为

$$
d^{(k)} = x^{(k+1)} - x^{(k)}
$$

所以：

$$
d^{(k+1)}
=
x^{(k+2)} - x^{(k+1)}
=
Gx^{(k+1)} + c - \left(Gx^{(k)} + c\right)
=
Gd^{(k)}
$$

这条式子非常关键。它说明迭代差分本身也满足同一个线性传播：

$$
d^{(k+1)} = Gd^{(k)}
$$

因此若在某个诱导范数下

$$
\|G\| \le \rho < 1
$$

就有：

$$
\|d^{(k+t)}\| \le \rho^t \|d^{(k)}\|
$$

## 7. From Delta to Fixed-Point Error Bounds

由 telescoping series：

$$
x^\star - x^{(k)}
=
\sum_{t=0}^{\infty} d^{(k+t)}
$$

以及

$$
x^\star - x^{(k+1)}
=
\sum_{t=1}^{\infty} d^{(k+t)}
$$

再结合 `\|d^{(k+t)}\|\le \rho^t \|d^{(k)}\|`，得到：

$$
\|x^\star - x^{(k)}\|
\le
\sum_{t=0}^{\infty}\rho^t \|d^{(k)}\|
=
\frac{1}{1-\rho}\|d^{(k)}\|
$$

$$
\|x^\star - x^{(k+1)}\|
\le
\sum_{t=1}^{\infty}\rho^t \|d^{(k)}\|
=
\frac{\rho}{1-\rho}\|d^{(k)}\|
$$

这两条界给了 solver 级 stopping rule。

若希望当前新迭代值 `x^{(k+1)}` 的误差满足：

$$
\|x^\star - x^{(k+1)}\| \le \eta
$$

只需保证：

$$
\|d^{(k)}\| \le \varepsilon_d,
\qquad
\varepsilon_d \triangleq \eta\frac{1-\rho}{\rho}
$$

因此，**问题被化成了对 `d^{(k)}` 范数的在线认证**。

### 7.1 Exact Sensitivity Form of the Error Bound

上面的

$$
\frac{\rho}{1-\rho}\|d^{(k)}\|
$$

是统一范数下的粗界，便于建立第一版 stopping rule，但它往往过于保守。

由

$$
d^{(k)} = (G-I)e^{(k)}
$$

可得：

$$
e^{(k)} = -(I-G)^{-1}d^{(k)}
$$

因此

$$
e^{(k+1)} = Ge^{(k)} = -G(I-G)^{-1}d^{(k)}
$$

定义灵敏度矩阵：

$$
H \triangleq G(I-G)^{-1}
$$

则有逐分量严格上界：

$$
|e^{(k+1)}| \le |H|\,|d^{(k)}|
$$

对第 `i` 个分量：

$$
|e_i^{(k+1)}|
\le
\sum_{s=0}^{n-1}|H_{is}|\,|d_s^{(k)}|
$$

这条式子比统一 `\rho` 粗界更强，因为它保留了不同列分量对误差传播的不同影响。

### 7.2 Block-Wise Sufficient Certification

将分量索引划分为若干 block：

$$
\{0,\dots,n-1\} = B_0 \cup B_1 \cup \cdots \cup B_{M-1}
$$

对每个 block `B_t`，定义 prefix-digit 推出的 block upper bound：

$$
\Delta_t^{(k,j)}
\triangleq
\max_{s\in B_t}
\left(
\left|\tilde d_s^{(k,j)}\right| + 2^{-j}
\right)
$$

因为

$$
|d_s^{(k)}|
\le
\left|\tilde d_s^{(k,j)}\right| + 2^{-j}
\le
\Delta_t^{(k,j)}
\qquad (s\in B_t)
$$

于是可预计算 block sensitivity weights：

$$
c_{i,t}
\triangleq
\sum_{s\in B_t}|H_{is}|
$$

并得到：

$$
|e_i^{(k+1)}|
\le
\sum_{t=0}^{M-1} c_{i,t}\,\Delta_t^{(k,j)}
$$

因此，一个严格充分的 block-wise 在线认证条件是：

$$
\max_i
\sum_{t=0}^{M-1} c_{i,t}\,\Delta_t^{(k,j)}
\le
\eta
$$

这给出了比统一 `\rho` 阈值更紧的认证规则，同时仍然只依赖：

- prefix-digit upper bound；
- block maxima；
- 预先离线计算好的 `c_{i,t}`。

### 7.3 Special Cases

若 `M=1`，整个向量只划为一个 block，则退化为单块灵敏度认证：

$$
\Delta_0^{(k,j)}
=
\max_s \left(|\tilde d_s^{(k,j)}| + 2^{-j}\right)
$$

$$
|e_i^{(k+1)}|
\le
\left(\sum_s |H_{is}|\right)\Delta_0^{(k,j)}
$$

这是统一粗界和完全逐分量认证之间的中间形式。

若每个 block 只含一个分量，即 `|B_t|=1`，则得到最强的 row-wise/entry-wise 认证：

$$
\Delta_t^{(k,j)} = |\tilde d_t^{(k,j)}| + 2^{-j}
$$

$$
|e_i^{(k+1)}|
\le
\sum_{t=0}^{n-1}|H_{it}|\,\Delta_t^{(k,j)}
$$

它的认证最紧，但硬件代价也最高。

因此当前主线的自然权衡是：

- `global rho`：最便宜，但最保守；
- `one-block H`：仍然很粗，但比 `rho` 更贴近矩阵实际；
- `block-wise H`：硬件可控且通常明显更紧；
- `row-wise H`：最强，但认证网络最重。

## 8. Prefix-Digit Bounds for Online Certification

设 `d_i^{(k)}` 的前 `j` 个 fractional digits 的 prefix 为：

$$
\tilde d_i^{(k,j)}
\triangleq
\sum_{\ell=1}^{j} d_{i,\ell}^{(k)}2^{-\ell}
$$

因为 signed-digit 尾项满足：

$$
\left|d_i^{(k)} - \tilde d_i^{(k,j)}\right|
\le
\sum_{\ell=j+1}^{\infty} 2^{-\ell}
=
2^{-j}
$$

所以每个分量都满足：

$$
|d_i^{(k)}|
\le
|\tilde d_i^{(k,j)}| + 2^{-j}
$$

$$
|d_i^{(k)}|
\ge
\max\left(0,\ |\tilde d_i^{(k,j)}| - 2^{-j}\right)
$$

### 8.1 `L_inf` Bounds

定义：

$$
U_\infty^{(k,j)}
\triangleq
\max_i |\tilde d_i^{(k,j)}| + 2^{-j}
$$

$$
L_\infty^{(k,j)}
\triangleq
\max_i \max\left(0,\ |\tilde d_i^{(k,j)}| - 2^{-j}\right)
$$

则有严格包围：

$$
L_\infty^{(k,j)}
\le
\|d^{(k)}\|_\infty
\le
U_\infty^{(k,j)}
$$

因此：

- 若
  $$
  U_\infty^{(k,j)} \le \varepsilon_d
  $$
  则可严格认证：
  $$
  \|d^{(k)}\|_\infty \le \varepsilon_d
  $$
  从而
  $$
  \|x^\star - x^{(k+1)}\|_\infty \le \eta
  $$

- 若
  $$
  L_\infty^{(k,j)} > \varepsilon_d
  $$
  则可严格认证当前迭代**尚未收敛**。

### 8.2 `L_1` Bounds

若选择 `L_1` 范数，则逐分量求和得到：

$$
U_1^{(k,j)}
\triangleq
\sum_i |\tilde d_i^{(k,j)}| + n2^{-j}
$$

$$
L_1^{(k,j)}
\triangleq
\max\left(0,\ \sum_i |\tilde d_i^{(k,j)}| - n2^{-j}\right)
$$

满足：

$$
L_1^{(k,j)}
\le
\|d^{(k)}\|_1
\le
U_1^{(k,j)}
$$

后续实现默认先采用 `L_inf`，因为它更适合并行比较和 hardware-friendly certification。

## 9. Why This Is Stronger Than Inner-Product-Only Integration

只做到 integrated inner product，最多只能消掉：

$$
\text{multiply} \rightarrow \text{add tree}
$$

之间的 boundary。

但 solver 级 iteration-fused 还能进一步消掉：

$$
x^{(k+1)}
\rightarrow
\text{full-width format conversion}
\rightarrow
d^{(k)}
\rightarrow
\text{norm check}
\rightarrow
\text{iteration restart}
$$

具体地说，数学上有三点新东西：

1. `delta` 仍然是 affine output：

$$
d^{(k)} = (G-I)x^{(k)} + c
$$

2. `delta` 自身满足同一线性传播：

$$
d^{(k+1)} = Gd^{(k)}
$$

3. prefix digit 自带严格尾项界，可在线认证收敛，而不是必须等 full-width vector 落地。

前两点把 solver 重新改写成 unified affine streaming problem；第三点把 stopping rule 也拉进了 online 数据流。

## 10. Cycle-Level Consequences

设：

- `\theta_{\text{row,cas}}` 为 cascaded online row update 的初始时延；
- `\theta_{\text{row,int}}` 为 integrated row update 的初始时延；
- `q` 为目标 fractional digit 数；
- `T_{\text{fmt}}` 为 full-width format conversion / buffering 开销；
- `T_{\text{chk}}` 为独立 convergence-check 开销；
- `T_{\text{restart}}` 为下一轮 restart / refill 开销。

### 10.1 Conventional Solver

传统 solver 每轮必须等：

1. row update 完成；
2. full-width `x^{(k+1)}` 落地；
3. 形成 `d^{(k)}`；
4. 做 norm compare；
5. 再启动下一轮。

因此其每轮成本可写成：

$$
T_{\text{conv}}^{(k)}
=
\theta_{\text{row,cas}} + q + T_{\text{fmt}} + T_{\text{chk}} + T_{\text{restart}}
$$

### 10.2 Iteration-Fused Solver

iteration-fused 路径中，row update、delta 跟踪和 convergence certification 共享同一 digit stream。记：

$$
j_k^\star \triangleq
\min\left\{
j:\;
U^{(k,j)} \le \varepsilon_d
\right\}
$$

若直到 `q` 位仍不能证实收敛，则取 `j_k^\star=q`。

则每轮 solver 成本变成：

$$
T_{\text{fused}}^{(k)}
=
\theta_{\text{row,int}} + j_k^\star + T_{\text{handoff}}
$$

其中 `T_{\text{handoff}}` 只表示把仍在 streaming 的 state 转给下一轮的固定小开销，不再包含完整的向量重打包和独立 norm-kernel 边界。

因此收益被拆成两部分：

$$
T_{\text{conv}}^{(k)} - T_{\text{fused}}^{(k)}
=
\left(\theta_{\text{row,cas}}-\theta_{\text{row,int}}\right)
+
\left(q-j_k^\star\right)
+
\left(T_{\text{fmt}}+T_{\text{chk}}+T_{\text{restart}}-T_{\text{handoff}}\right)
$$

这说明 solver 级收益不再只靠更好的 inner product，而是同时来自：

1. row-update integration；
2. certification-induced digit-depth reduction；
3. iteration boundary removal。

## 11. Immediate Architecture Consequences

上述推导直接固定了后续硬件模块边界：

1. `integrated online row-update engine`
   - 实现第 3 节的 recurrence；
   - 负责 `x^{(k+1)}` 的 digit stream。

2. `online delta engine`
   - 逻辑上实现 `(G-I)x^{(k)}+c`；
   - 或从 `x^{(k+1)}` 与 `x^{(k)}` 流做零-delay signed-digit subtraction。

3. `online norm-bounds engine`
   - 逐拍维护 `U_\infty^{(k,j)}` 与 `L_\infty^{(k,j)}`；
   - 输出三值控制：`converged / not-yet-provable / not-converged`.

4. `state handoff buffer`
   - 不要求把整轮结果先完全转成普通 fixed-point 再喂回下一轮；
   - 只需满足下一轮 online stream 的时序衔接。

## 12. What This Derivation Does Not Yet Solve

本文件故意不解决以下问题：

1. 完整浮点动态范围；
2. CG / GMRES 中的全局 dot / 除法链；
3. 最优 sparse matrix 存储格式；
4. 面向特定 FPGA 的 microarchitecture 参数点；
5. 精确的 place-and-route timing 模型。

这些都属于后续建模和 RTL 阶段，不属于本数学主文档的范围。

## 13. Final Statement

到这里，新的论文主线已经有了完整数学闭环：

1. 行更新是带 bias 项的 integrated online inner product。
2. `delta` 不是额外后处理，而是第二个 affine output。
3. `delta` 自身也满足同一线性传播。
4. prefix digit 自带严格尾项界，因此可做 solver-level online certification。
5. 因而 `row update + delta + convergence check` 可以统一成一个 iteration-fused online datapath。

这就是本项目从 `MSDF exp / softmax` 转向高维线性归约 / 固定点迭代核之后，最核心的理论基础。
