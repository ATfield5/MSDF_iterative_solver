# From Prior Operator RTL to the New Solver Mainline

本文档在 [`OPERATOR_SOURCE_REVIEW.md`](./OPERATOR_SOURCE_REVIEW.md) 的基础上继续往前走一步，回答四个问题：

1. 原始 `MSDF_operator_srcs/` 代码到底完成了什么；
2. 它真实解决了什么痛点；
3. 它没有解决什么，因此新主线必须新增什么；
4. 从论文角度，新的 solver 主线真正的创新点应写在哪里。

这份文档的定位是：**把 prior operator RTL 和新的 iteration-fused solver 主线连接起来。**

## 1. What the Prior RTL Really Does

如果只看原始 Verilog，而不看论文摘要，它做的事情可以归纳成一句话：

$$
\text{把一个固定规模的在线内积/乘加算子做成 integrated online recurrence}
$$

最接近论文主张的代码是：

- `MSDF_MUL_ADD.v`
- `MSDF_MUL_ADD_8.v`

其中：

- `MSDF_MUL_ADD.v` 是单 operator 版本；
- `MSDF_MUL_ADD_8.v` 是 8 路局部归约版本，更接近“高维内积核”的实际组织。

### 1.1 Datapath decomposition in the code

按代码实际结构，它的运算链是：

1. `vector_append.v`  
   把逐拍输入 digit 追加成前缀向量窗口。

2. `append_and_select.v` + `selector.v`  
   用一个输入 digit 的符号去选择另一个输入的前缀窗口，形成 partial-product contribution。

3. `parallel_online_adder.v` / `parallel_online_adder_4.v` / `parallel_online_adder_4_with_obuf.v`  
   对多个 contribution 做 rail-coded 并行在线归约。

4. `output_and_update.v` / `output_and_update_0.v`  
   从 residual 高位决定输出 digit，并更新下一拍 residual。

因此它不是 conventional datapath：

$$
\text{multiplier} \rightarrow \text{adder tree} \rightarrow \text{bias add}
$$

而是：

$$
\text{prefix-window build}
\rightarrow
\text{digit-controlled partial product}
\rightarrow
\text{parallel online reduction}
\rightarrow
\text{digit selection + residual update}
$$

### 1.2 What exactly is integrated

这里所谓 integrated，不是“整个 solver 集成了”，而是：

$$
\text{inner product / MAC operator itself is integrated}
$$

也就是传统 online arithmetic 里最容易出现的边界：

$$
\text{online multiplier} \rightarrow \text{online adder}
$$

在这个 RTL 里被折叠掉了。

这正是那篇文章真正成立的地方。

## 2. What Pain Point the Prior RTL Solves

原始代码解决的真实痛点，不是“通用内积都比 DSP 更强”，而是：

$$
\text{在 online arithmetic 框架内部，primitive cascade 的边界太重}
$$

### 2.1 Operator-boundary pain point

如果采用常规 online 乘法器和 online 加法树级联，典型数据流是：

$$
x_sy_s
\rightarrow
\text{online multiplier output}
\rightarrow
\text{online adder tree}
\rightarrow
z
$$

这里的问题有三个：

1. 每一级 primitive 都有自己的 online delay；
2. primitive 之间必须显式传递中间值；
3. 对齐和同步寄存会把小延迟堆成大延迟。

原始代码通过 integrated recurrence 把这三点压掉了。

### 2.2 Why the code can do that

因为内积本身是线性的：

$$
\langle x, y \rangle = \sum_s x_s y_s
$$

而且可以被写成统一 residual recurrence。  
这意味着：

$$
\text{multiply boundary} + \text{accumulate boundary}
$$

都能被算子级 folding 吃掉。

这就是它能成立的根本原因。

## 3. Where the Prior RTL Stops

这批代码到这里就停了。它没有往 solver 级再走一步。

### 3.1 It is still operator-scoped

即使是 `MSDF_MUL_ADD_8.v`，它也只知道：

$$
\sum_{t=0}^{7} x_t y_t + a
$$

它不知道：

- `row_id`
- `iteration_id`
- `x^{(k)}`
- `x^{(k+1)}`
- `d^{(k)} = x^{(k+1)} - x^{(k)}`
- `\|d^{(k)}\| \le \varepsilon ?`

因此它解决的是：

$$
\text{how to produce one online affine row update}
$$

而不是：

$$
\text{how to run an affine fixed-point solver efficiently}
$$

### 3.2 It does not solve the iteration boundary

原始 operator RTL 之后，solver 仍要做下面这些事情：

1. 把 `x^{(k+1)}` 落成完整状态；
2. 再和 `x^{(k)}` 做差得到 `d^{(k)}`；
3. 再把 `d^{(k)}` 送去做 norm / convergence check；
4. 再决定是否进入下一轮。

也就是：

$$
\text{row update}
\rightarrow
\text{state materialization}
\rightarrow
\Delta
\rightarrow
\text{norm check}
\rightarrow
\text{next iteration}
$$

这条链在原始代码里完全没有被折叠。

### 3.3 It does not solve sparse/streaming system orchestration

对于真实的迭代求解器，痛点不只是一个 row update 的 online delay，还包括：

- 稀疏矩阵流组织
- 多 row 并行
- state buffer
- next-iteration handoff
- convergence certification timing

原始工程没有这些内容。

## 4. Code-Level Pain Points Visible in the Existing RTL

这里只谈从代码本身能直接看到的问题，不谈论文里抽象的优点。

### 4.1 The shell is hard-coded and not scalable

`MSDF_MUL_ADD_8.v` 的局部归约树是手工写死的：

- 8 路输入
- 两级 `parallel_online_adder_4_with_obuf`
- 手工 `valid` 延迟链
- 手工 `a` 对齐链

这说明原始工程更像“验证一个 8 路结构”，不是一个适合扩成 solver row-cluster 的参数化 IP。

直接问题有两个：

1. 后续扩到 `LANES=16/32` 时代码不可维护；
2. pipeline 对齐完全依赖手工 DFF 链，容易在系统级整合时失控。

### 4.2 The interfaces are demo-oriented

原始顶层接口使用：

- `i_ena`
- `o_valid`
- `o_int`
- `o_unit`
- `o_frac`
- `i_dot`
- `o_dot`

这些信号说明它本来就是面向 testbench 演示的：

- `o_int/o_unit/o_frac` 是数值区域标记；
- `i_dot/o_dot` 是结果终止标记；
- 没有 `ready/backpressure`；
- 没有 row/iteration sideband。

这类接口无法直接承接 solver 调度。

### 4.3 Rail-coded storage cost is pushed out of sight

原始代码全程使用正负 rail：

$$
(x_p, x_n),\ (y_p, y_n),\ (w_p, w_n),\ (z_p, z_n)
$$

这对 local arithmetic 是合理的，但对于系统级意味着：

- state buffer 宽度翻倍；
- interconnect 宽度翻倍；
- delta / norm sidepath 也要决定是否继续 rail 化。

在 operator demo 里，这个成本是隐藏的；到了 solver 主线，它会直接变成 BRAM/布线/时序问题。

### 4.4 The current code has no direct support for solver-level early certification

原始 `output_and_update*` 只负责当前 operator 的 digit 选择与 residual 更新。  
它不维护：

$$
d^{(k)} = x^{(k+1)} - x^{(k)}
$$

也不维护：

$$
U_\infty^{(k,j)},\ L_\infty^{(k,j)}
$$

因此它完全不能支持新主线最关键的收益来源：

$$
q - j_k^\star
$$

## 5. What the New Mainline Adds on Top of This RTL

新的主线不是“重写一个更大的 `MSDF_MUL_ADD_8`”，而是把 prior operator 变成 solver 的一个子模块。

### 5.1 New abstraction boundary

旧边界：

$$
\text{integrated inner-product operator}
$$

新边界：

$$
\text{iteration-fused affine solver engine}
$$

也就是说，后续正式工程必须新增三层语义：

1. **row-update cluster**
2. **delta sidepath**
3. **online convergence certification**

### 5.2 Shared-update + delta sidepath

你当前数学主线已经固定：

$$
x^{(k+1)} = Gx^{(k)} + c
$$

$$
d^{(k)} = x^{(k+1)} - x^{(k)}
$$

因此，新的关键不是“再来一个 subtract kernel”，而是：

$$
\text{row update output} \rightarrow \text{delta sidepath}
$$

必须同步发生。

这正是 prior operator RTL 没有做的。

### 5.3 Online convergence certification

新的 solver 主线真正多出来的理论抓手是：

$$
|d_i^{(k)} - \tilde d_i^{(k,j)}| \le 2^{-j}
$$

从而：

$$
U_\infty^{(k,j)} = \max_i |\tilde d_i^{(k,j)}| + 2^{-j}
$$

如果：

$$
U_\infty^{(k,j)} \le \varepsilon
$$

则可严格提前认证收敛。  
这一步和 prior operator 论文完全不在一个层级。

## 6. Where the Actual Improvement Comes From

新的改进不能再写成“更好的 integrated inner product”，否则层级不够。

后续真正的提升应写成三项叠加：

### 6.1 Row-update integration reuse

这一项来自 prior paper，本质是：

$$
\theta_{\text{row,cas}}-\theta_{\text{row,int}}
$$

这是基础，不是新论文的主 claim。

### 6.2 Delta / norm fusion

prior operator-based solver shell 需要：

$$
\text{row update}
\rightarrow
\text{materialize } x^{(k+1)}
\rightarrow
\Delta
\rightarrow
\text{norm check}
$$

新主线应把它压成：

$$
\text{row update}
\rightarrow
\text{delta sidepath}
\rightarrow
\text{online bounds}
$$

因此节省的不是一个 primitive，而是**一次完整后处理 pass**。

### 6.3 Early certified stop

如果本轮只需要跑到 `j_k^\star` 就能严格判定：

$$
U_\infty^{(k,j_k^\star)} \le \varepsilon
$$

那么相对 full-width `q` 位计算，节省为：

$$
q-j_k^\star
$$

这部分收益是原始 operator RTL 完全没有的，也是 solver 主线最硬的新增点。

## 7. What Should Be Optimized Next

基于代码和数学一起看，后续优化顺序应该是下面这样，不要走偏。

### 7.1 First optimize the abstraction, not the full system shell

先做一个新的：

$$
\texttt{integrated\_online\_row\_update\_core}
$$

要求：

- 内部仍保留 rail-coded local reduction；
- 接口改成 row / iteration aware；
- 把原始 `MSDF_MUL_ADD_8` 的 adder tree 和 residual update 重新打包。

这一步是“继承 prior RTL”的正确方式。

### 7.2 Then add delta sidepath

不建议先做独立 `online subtract kernel` 再外接。  
更合理的是：

- row-update core 输出 `x^{(k+1)}` digit；
- 同时旁路对齐后的 `x^{(k)}` digit；
- 用共享 online adder fabric 形成 `d^{(k)}`。

也就是之前在文档里定下的 D2 路径：

$$
\text{shared update + subtract}
$$

### 7.3 Then add certification, not a full generic norm engine

第一版不要做过宽泛的 norm 模块。  
先做：

$$
L_\infty / U_\infty
$$

因为：

- 数学界最直接；
- 控制最简单；
- 最容易把 `j_k^\star` 测出来。

## 8. Paper-Level Innovation: What to Claim and What Not to Claim

这里必须写得很严格。

### 8.1 What not to claim

不应继续把论文主张写成：

1. “一个新的 online inner product”
2. “MSDF arithmetic 本身比所有传统 MAC 更快”
3. “这套 operator RTL 直接就是 solver accelerator”

这些说法都站不住。

### 8.2 What the real innovation is

新的论文主线如果要成立，创新点应明确写成下面三条。

#### I1. Lift online integration from operator level to iteration level

prior paper 解决：

$$
\text{operator boundary}
$$

新主线解决：

$$
\text{iteration boundary}
$$

这是贡献层级上的第一差异。

#### I2. Shared row-update / delta / certification datapath

不是三个 kernel 串起来，而是：

$$
x^{(k)}
\rightarrow
x^{(k+1)}
\rightarrow
d^{(k)}
\rightarrow
\text{certification}
$$

在一条在线数据流里推进。

这才是新的系统级微架构点。

#### I3. Provable online convergence certification

这条是最硬的理论点。  
不是启发式早停，而是利用 prefix tail bound 做严格认证：

$$
U_\infty^{(k,j)} \le \varepsilon
\Rightarrow
\text{certified convergence}
$$

如果后续 RTL 和实验能把这条坐实，它会比“更快的 operator”更像论文主贡献。

## 9. Bottom-Line Assessment

结合代码看，prior operator RTL 的价值很清楚：

- 它已经把 integrated online inner-product 的底层算术实现出来了；
- 它提供了可复用的 rail-coded local reduction primitive；
- 它说明 operator-level online integration 是可落地的。

但它没有解决 solver 主线最关键的三件事：

1. `x^{(k+1)}` 与 `d^{(k)}` 的共享生成；
2. 在线收敛认证；
3. 迭代边界与 state handoff 的系统级消除。

因此，新主线的正确姿势不是“继续扩写 `MSDF_MUL_ADD_8`”，而是：

$$
\text{把 prior operator core 作为子模块，重建 solver-level datapath}
$$

这也是后续 RTL 必须遵守的总原则。
