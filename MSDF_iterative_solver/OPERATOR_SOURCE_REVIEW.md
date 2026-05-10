# Prior Operator RTL Review

本文档记录对 `../MSDF_operator_srcs/` 中原始 Verilog 工程的代码审阅结论。目的不是复述每个模块，而是明确：

1. 那篇 integrated online inner-product 文章对应的 RTL 到底实现了什么；
2. 哪些底层单元可以复用；
3. 哪些接口和控制方式不能直接带入新的 solver 主线；
4. 后续正式 RTL 应该如何取舍。

## Source Scope

本次主要阅读了下面这些源码：

- `MSDF_MUL_ADD.v`
- `MSDF_MUL_ADD_8.v`
- `MSDF_MUL.v`
- `MSDF_ADD.v`
- `append_and_select.v`
- `vector_append.v`
- `selector.v`
- `parallel_online_adder.v`
- `parallel_online_adder_4.v`
- `parallel_online_adder_4_with_obuf.v`
- `parallel_online_adder_block.v`
- `serial_online_adder_block.v`
- `output_and_update.v`
- `output_and_update_0.v`
- `DFF.v`

这些模块已经足够反映原工程的真实组织方式。

## What the Original RTL Actually Implements

原工程实现的是 **operator-level integrated online inner product / multiply-accumulate**，不是 solver-level datapath。

它的核心数据流是：

$$
\langle x, y \rangle + a
$$

或者 8 路版本的局部归约：

$$
\sum_{t=0}^{7} x_t y_t + a
$$

实现方式不是 conventional multiplier + adder tree，而是：

1. 把输入 digit 流积累成局部向量窗口；
2. 按 digit 符号做 partial-product selection；
3. 用 rail-coded parallel online adder 做局部归约；
4. 维护 residual `w_j`；
5. 用高位采样决定输出 digit `z_j`，同时更新下一拍 residual。

所以，这份代码证明的是：

$$
\text{operator-level integrated online recurrence}
$$

而不是：

$$
\text{iteration-fused solver datapath}
$$

这两者必须分清。

## Key Structural Observations

### 1. It is rail-coded throughout

所有主算术路径都用正负 rail：

- `*_p`
- `*_n`

包括：

- 输入 digit
- 局部向量
- 局部和
- residual
- 输出 digit

这说明原工程默认的内部数制不是普通二进制，而是 signed-digit / redundant rail。后续新工程如果继续沿用这套内核，必须在模块边界上明确：

- 哪些路径保持 rail；
- 哪些路径允许转成普通 binary；
- 转换点放在哪里。

### 2. Multiplication is implemented as sign-controlled vector selection

`vector_append.v` 先把逐拍输入 digit 追加成固定位宽窗口。  
`append_and_select.v` 再通过 `selector.v` 用一个操作数当前 digit 的符号去选择另一个操作数的窗口：

- `+1`：保留
- `-1`：取反 rail
- `0`：清零

这不是通用并行乘法器，而是典型的 **digit-serial outside, vector-window inside** 的 online partial-product 生成。

### 3. Local reduction is already digit-parallel

`parallel_online_adder.v`、`parallel_online_adder_4.v`、`parallel_online_adder_4_with_obuf.v` 说明原工程并不是“纯串行 bit-by-bit”。

它的真正风格是：

$$
\text{digit-serial global flow} + \text{digit-parallel local reduction}
$$

这点和论文主张一致，也是后续新主线最值得继承的部分。

### 4. Residual update is encapsulated in output-and-update blocks

`output_and_update.v` / `output_and_update_0.v` 的作用很关键：

1. 从 `v_j` 的高位样本决定输出 digit `z_j`；
2. 对 residual 做补偿更新，得到 `w_{j+1}`。

这对应的是在线算术的 digit selection + residual maintenance。后续如果我们做 solver-level `row-update core`，这一逻辑层级仍然需要保留，但不能继续散落在顶层拼接里。

### 5. The top-level contract is operator-centric and ad-hoc

`MSDF_MUL_ADD.v`、`MSDF_MUL.v`、`MSDF_ADD.v` 都带有下面这类接口语义：

- `i_ena`
- `o_valid`
- `o_int / o_unit / o_frac`
- `i_dot / o_dot`

这些接口是为单 operator 演示和 testbench 驱动服务的，不是为正式 solver 工程设计的。  
它们缺少：

- 标准 `valid/ready`
- row / tile 元数据
- iteration 边界语义
- state handoff 语义
- backpressure

所以不能直接作为新工程的外部接口规范。

## Module-by-Module Reuse Judgment

### Modules worth reusing or porting with small cleanup

这些模块适合作为 **底层算术原语** 参考或直接移植：

- `full_adder.v`
- `parallel_online_adder_block.v`
- `parallel_online_adder.v`
- `parallel_online_adder_4.v`
- `parallel_online_adder_4_with_obuf.v`
- `DFF.v`

理由很简单：它们功能单一，接口干净，和 solver 语义弱耦合。

### Modules worth reusing only at the idea level

这些模块体现了关键算法思想，但不建议原样搬到新主线：

- `vector_append.v`
- `append_and_select.v`
- `selector.v`
- `output_and_update.v`
- `output_and_update_0.v`

原因：

1. 控制语义是 operator-oriented；
2. 缺少 row / iteration 元信息；
3. `vector_append` 是“一次填满固定窗口后再参与计算”的局部策略，后续可能需要重包成更清晰的 row-update 窗口缓存接口。

### Modules not suitable as new top-level templates

下面这些模块不应直接作为正式工程 top-level 雏形：

- `MSDF_MUL.v`
- `MSDF_ADD.v`
- `MSDF_MUL_ADD.v`
- `MSDF_MUL_ADD_8.v`
- `top_test.v`
- `top_test_8.v`

原因不是它们“写错了”，而是层级不对。它们是：

$$
\text{operator demo / validation RTL}
$$

而不是：

$$
\text{solver iteration datapath RTL}
$$

## Direct Impact on the New Mainline

这次阅读后，新的 `MSDF_iterative_solver/` 主线在 RTL 上应当遵守下面的取舍。

### 1. Reuse the local adder fabric, not the old top-level shell

新主线最值得复用的是 rail-coded local reduction fabric，而不是旧的 `MSDF_MUL_ADD_*` 外壳。

因此后续 RTL 的复用优先级应是：

1. `parallel_online_adder*`
2. `output_and_update*` 的思想
3. `append_and_select` 的思想
4. 最后才考虑旧 top-level

### 2. Build a new row-update contract

新工程必须重新定义 `row-update core` 的外部接口。  
它至少应显式区分：

- 输入 state stream
- 矩阵系数 / 向量 digit stream
- row begin / row end
- iteration begin / iteration end
- valid / ready

旧工程的 `i_ena + 固定拍计数` 不足以支撑 solver 级调度。

### 3. Keep operator-level recurrence inside, move solver semantics outside

后续推荐结构是：

- **内部**：保留 operator-level integrated recurrence
- **外部**：新增 solver-level `delta` 和 `L_inf certification` 边带

也就是：

$$
\text{integrated row-update core}
$$

作为一个明确子模块存在，而不是再把 solver 逻辑写进原始 operator shell。

### 4. Do not prematurely force everything into rail at the full system boundary

原工程几乎全程用 rail。  
但新主线要面对：

- state buffer
- norm bound
- controller
- iteration handoff

这些控制和存储路径不一定适合无条件延续 rail 表示。  
更合理的策略是：

- row-update 主算术核继续保留 rail；
- controller / metadata / counters 保持普通 binary；
- `delta` / certification 路径根据时序和接口再决定是否 rail 化。

## Immediate RTL Guidance

基于这次阅读，后续正式 RTL 的实现顺序保持不变，但模块来源更清楚了：

1. `integrated_online_row_update_core`
   - 继承 `MSDF_MUL_ADD_8` 的局部归约思想；
   - 但重写顶层接口和状态控制。

2. `online_delta_sidepath`
   - 不从旧工程直接复用；
   - 只复用并行 online adder fabric。

3. `online_linf_cert_core`
   - 基本需要新写；
   - 旧工程没有 solver-level norm/certification 逻辑。

## Bottom Line

这批原始 RTL 很有价值，但价值主要在两个层面：

1. **证明 integrated online inner-product 的底层算术组织已经存在可参考实现；**
2. **提供一套可复用的 rail-coded local reduction primitive。**

它不能直接变成新的 solver 主线顶层。  
新的 `MSDF_iterative_solver/` 论文价值来自：

$$
\text{iteration fusion + delta sidepath + online convergence certification}
$$

而这些都不在原始 operator RTL 里，必须在新工程中单独建立。
