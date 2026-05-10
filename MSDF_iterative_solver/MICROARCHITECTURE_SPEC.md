# Iteration-Fused Solver Microarchitecture Specification

本文件把新的 solver 主线落实到硬件模块边界。它建立在以下结论之上：

1. 数学上，iteration-fused 主张已经成立；
2. 软件模型中，`Gate 1` 和 `Gate 2` 已通过；
3. `Gate 3` 仍未通过，因此当前微架构优先强调：
   - iteration-boundary removal
   - online state handoff
   - intermediate storage reduction
   - DSP-free / low-DSP datapath

而不是先声称 raw cycle 一定打赢 optimistic conventional FPGA proxy。

## 1. Design Goal

目标系统不是一个单独的 online inner-product IP，而是一个 solver-level engine：

$$
x^{(k)} \rightarrow x^{(k+1)} \rightarrow d^{(k)} \rightarrow \text{certification} \rightarrow x^{(k+1)}
$$

其中：

- `x^{(k+1)}` 的生成和 `d^{(k)}` 的生成共享同一行更新过程；
- convergence decision 与 digit stream 同步，而不是 full-width 后处理；
- 下一轮输入直接来自在线状态缓存，而不是完整格式转换后的中间向量。

## 2. Top-Level Block Diagram

顶层固定为五块：

1. `matrix streaming engine`
2. `state streaming engine`
3. `integrated row-update cluster`
4. `online norm-bounds engine`
5. `iteration controller + state handoff buffer`

逻辑数据流为：

$$
G,\;x^{(k)},\;c
\rightarrow
\text{row-update cluster}
\rightarrow
\left(
x^{(k+1)},\;
d^{(k)}
\right)
\rightarrow
\text{norm-bounds}
\rightarrow
\text{certification}
\rightarrow
\text{next iteration handoff}
$$

## 3. Matrix Streaming Engine

### Function

负责按 row streaming 的顺序供应：

$$
\{g_{is}\}_{s \in \mathcal{N}(i)}
$$

以及偏置：

$$
c_i
$$

对 dense 场景，`G` 可以按连续 row-major 流出。对 sparse 场景，建议一开始就按每行非零序列流出，而不是先做 dense 版本再硬改。

### Why It Matters

对于 online arithmetic，矩阵流式组织比传统 MAC 阵列更关键，因为它直接决定：

- operand alignment 成本
- partial-sum tree 输入装配成本
- row handoff 是否会出现 bubble

### First Implementation Choice

第一版固定支持两种矩阵模式：

1. `dense row stream`
2. `CSR-like sparse row stream`

不在第一版做 block-sparse 特化。

## 4. State Streaming Engine

### Function

负责把当前迭代状态：

$$
x^{(k)}
$$

送到 row-update cluster。这个模块的关键不是“把向量读出来”，而是保证：

- digit-serial 输出稳定；
- 同一时刻多 row engines 能拿到对应的 streamed 状态；
- 下一轮 handoff 时不需要完整 repack。

### Two Candidate Organizations

#### Option A: Full-Vector Re-serialization

每轮先把 `x^{(k+1)}` 存成 full-width，再重序列化成下一轮 digit stream。

优点：

- 最简单；
- 便于和软件模型对齐。

缺点：

- iteration-fused 的核心优势被削弱；
- `T_handoff` 可能接近 `T_fmt + T_restart`。

#### Option B: Prefix-State Handoff

不强制先存 full-width，而是保留在线前缀状态或延迟缓冲，直接喂给下一轮。

优点：

- 更符合主线；
- 可以显著压低 handoff boundary。

缺点：

- 控制更复杂；
- 对 state buffer 组织要求更高。

### First Implementation Choice

第一版 RTL 建议先实现 `Option A` 做功能闭环，再在同一接口下升级到 `Option B`。这样不会在最早期就把控制问题做死。

## 5. Integrated Row-Update Cluster

这是整个系统的核心。

### Function

对每个被分配的 row `i`，实现：

$$
x_i^{(k+1)} = \sum_{s=0}^{n-1} g_{is}x_s^{(k)} + c_i
$$

并尽量同时得到：

$$
d_i^{(k)} = x_i^{(k+1)} - x_i^{(k)}
$$

### Internal Structure

每个 row engine 内部包含：

1. `PSCU bank` 或等价 partial-product drivers
2. local `parallel online adder tree`
3. `sel / residual update`
4. optional `delta side-path`

其中第 1 到第 3 点对齐那篇 integrated inner-product 工作；第 4 点才是本项目相对它的新东西。

### Delta Generation Options

#### Option D1: Dual-Affine Path

直接并行实现：

$$
x^{(k+1)} = Gx^{(k)} + c
$$

和：

$$
d^{(k)} = (G-I)x^{(k)} + c
$$

优点：

- 数学最干净；
- 不依赖 `x^{(k+1)}` 已经完整生成。

缺点：

- 需要额外 affine datapath；
- LUT 增长更明显。

#### Option D2: Shared Update + Parallel Online Subtract

先生成 `x^{(k+1)}` 的在线 digit，再通过 digit-parallel / zero-delay online subtract 与 `x^{(k)}` 形成 `d^{(k)}`。

优点：

- 结构更紧凑；
- 更像“从 row update 派生 delta”。

缺点：

- 对 `x^{(k)}` 的并行可见性要求更高；
- 需要仔细控制 subtract 的对齐点。

### First Implementation Choice

第一版推荐 `D2`。原因是：

- 它更接近“iteration-fused 但不过度扩资源”；
- 软件模型已经表明当前更大的机会在 boundary reduction，不在加第二套 full affine path。

## 6. Online Norm-Bounds Engine

### Function

对 `d^{(k)}` 的 prefix stream，逐拍维护：

- `L_inf` 下的 `U_\infty^{(k,j)}`、`L_\infty^{(k,j)}`
- 或 `L_1` 下的 `U_1^{(k,j)}`、`L_1^{(k,j)}`

并输出三值状态：

1. `CERT_CONVERGED`
2. `CERT_NOT_CONVERGED`
3. `CERT_UNDECIDED`

### Workload Mapping

- PageRank：默认 `L_1`
- Jacobi：默认 `L_inf`

### Why It Is a Real Module

这个模块不是“多做一个 comparator”。它直接决定：

- `j_k^*` 是否明显小于 `q`
- Gate 1 是否持续成立
- iteration-fused 是否真的比 integrated-inner-product-only 更高一层

### First Implementation Choice

第一版只做一条 active path：

- `L_inf` support mandatory
- `L_1` support software-first, RTL-second

原因是 `L_inf` 更易做硬件并行。PageRank 的 `L_1` 路径先在软件模型里保留，RTL 阶段再决定是否值得做。

这条早期结论只解释了为什么 Jacobi 被保留为 stress fixture：它的 `L_inf/block_H` 认证更容易在现有 RTL 中观察到收益。但当前论文应用已经转为 PageRank first，因此 PageRank 需要补自己的 `L1` delta certification，而不是继续沿用 Jacobi 的 `block_H` 作为主认证路径。

## 7. Iteration Controller and State Handoff Buffer

### Function

负责：

- row scheduling
- iteration start / end
- certification aggregation
- state swap：`x^{(k)}` 与 `x^{(k+1)}`

### Required Outputs

控制器必须给出：

1. `iteration_done`
2. `certified_converged`
3. `need_next_iteration`
4. `final_state_valid`

### Why This Is Not Just FSM Glue

对本项目而言，controller 的设计是否成功，决定了：

$$
T_{\text{handoff}}
$$

到底是接近一个小常数，还是重新膨胀回：

$$
T_{\text{fmt}} + T_{\text{restart}}
$$

因此 controller 本身就是论文主线的一部分，不是可忽略的外围逻辑。

## 8. Resource Priorities

根据当前软件模型，资源优先级应该这样排：

### First Priority

减少 iteration boundary 成本：

- 少做 full-width dual buffering
- 少做 repack / reserialize
- 让认证逻辑直接吃 prefix stream

### Second Priority

控制 row-update cluster 的 LUT 增长。当前阶段不追求打赢 DSP baseline 的 raw cycles，因此不要为了双路径并行 `x_next + delta` 把 LUT 翻倍。

### Third Priority

保留 low-DSP 叙事，但不要把它写成唯一价值。当前模型已经说明：

- 相对 `B1`，cycle 优势是可信的；
- 相对 `B2`，第一版更可能靠 storage / handoff / DSP 去建立价值，而不是先靠 cycles。

## 9. First RTL Bring-Up Order

RTL 顺序固定如下：

1. `integrated online row-update core`
2. `delta side-path (D2)`
3. `L_inf norm-bounds core`
4. `simple iteration controller`
5. `dense small closed-loop top`
6. `Jacobi sparse top`

在完成第 5 步之前，不做：

- `L_1` RTL norm engine
- complex sparse banking
- block-sparse scheduler
- prefix-state handoff optimization

## 10. Current RTL Bring-Up Status

目前已经实现的不是完整 solver top，而是第一版 specialized RTL slice：

1. `online_const_coeff_contrib.v`
   - 用固定 coefficient rail-vector 替换 generic variable-by-variable selector front-end

2. `online_affine_row_update_core.v`
   - 4-term constant-coefficient row-update accumulation slice
   - 复用 local online reduction fabric
   - 当前输出是 affine accumulated vector，不是最终 solver digit stream

3. `online_delta_linf_cert_core.v`
   - shared `delta + L_inf` 功能切片
   - 从 `x^{(k+1)}` 与 `x^{(k)}` 的 rail-coded row state 直接生成
     row-local `delta`、`U_i/L_i` 和三值认证状态
   - 当前定位是 functional-first row-local bound engine，供后续 controller
     汇聚成全局 `L_inf` 或 block-wise `H` 认证

4. `online_row_update_delta_slice.v`
   - 最小 integrated wrapper
   - 明确锁定 `row-update -> row-local delta/L_inf certification` 的模块边界
   - 作为后续 iteration controller 接入点

5. `block_h_cert_engine.v`
   - 第一版 `H`-based block certification engine
   - 当前是 functional-first、word-parallel 版本

6. `block_bound_max_pool.v`
   - row-level `U_i` 到 block-level `\Delta_t` 的第一版聚合
   - 先做 `max-pool` 语义，不引入更复杂的 block scheduler

7. `online_row_cluster_block_cert.v`
   - `row abs-upper -> block bounds -> H-certification` 的 cluster wrapper
   - 明确锁定 cluster 级认证边界

8. `online_row_cluster_delta_cert.v`
   - `row-update + delta/L_inf + block_H` 的 cluster-level datapath wrapper
   - 给 iteration controller 提供直接可消费的 `cluster_valid / certified`

9. `iter_cluster_cert_controller.v`
   - 最小 iteration controller
   - 当前语义已经收敛为 “每轮只上报一次” 的 one-shot `done/converged/continue`

10. `iter_dense_small_closed_loop_top.v`
   - 第一版 dense small closed-loop top
   - 把 cluster datapath 与 iteration controller 接成最小 solver 级控制闭环
   - 当前不包含复杂 state handoff / sparse scheduler，只验证 iteration-loop closure

11. `iter_row_state_handoff_buffer.v`
   - 第一版 row-state handoff buffer
   - 作用是把上一轮 row-update 输出保留下来，作为下一轮 `x_old`
   - 当前只闭合 `x_old` 传递，不负责把 `x^(k+1)` 重放成新的 source digit stream

12. `iter_dense_small_handoff_top.v`
   - 在 `dense small closed-loop top` 基础上加入真实 `x_old` handoff
   - 已验证两轮迭代下：
     - 第一轮 `continue`
     - 第二轮在相同输入下利用内部 handoff 变成 `converged`

13. `iter_fixed_degree_state_replay.v`
   - 第一版 fixed-degree state replay scheduler
   - 把保存下来的 row-state 按固定 source-row 映射重新吐成下一轮 `x0..x3` digit
   - 当前作为独立 contract block 先验证 bit-order / row-index / term-index 语义

14. `iter_dense_small_replay_top.v`
   - 第一版 replay-integrated dense small top
   - 在 handoff 之上加入 `state replay -> x0..x3 mux -> row-update` 的真实接回路径
   - 当前已验证：
     - replay 驱动位与 handoff state + fixed mapping 严格一致
     - replay 驱动下一轮后 controller 仍能正常闭环

15. `iter_state_ping_pong_bank.v`
   - 第一版双 bank state storage
   - 明确区分 current read bank 与 current write bank
   - `commit_swap` 后把新写出的 row-state 提升为下一轮 active `x_old`

16. `iter_dense_small_ping_pong_top.v`
   - 第一版 multi-iteration ping-pong top
   - 在 replay-integrated datapath 基础上引入真实 `x_old/x_new` 银行切换
   - 当前已验证：
     - bank flip 语义正确
     - commit 后 active read bank 确实切换
     - replay 驱动下一轮时控制闭环仍成立

17. `iter_fixed_degree_row_scheduler.v`
   - 第一版 structured sparse / fixed-degree row scheduler
   - 把 template contract 变成：
     - `row_active_mask`
     - masked `src_row_idx`
     - term-major `coeff0..3` rail vectors
   - 这是从“手工喂 coeff/src”转向“正式模板接口”的第一步

18. `iter_dense_small_sched_top.v`
   - 第一版 scheduler-integrated top
   - 在 ping-pong top 前面接入 row scheduler
   - 当前已验证模板接口已经可以替代手工展开的 `coeff0..3/src_idx`

19. `compile_coeff_templates.py`
   - 把矩阵与 bias 编译为第一版 rail-coded coefficient vectors
   - 当前已补 `fixed_degree` 与每行 `fixed_degree_terms`

20. `pack_fixed_degree_templates.py`
   - 把 `fixed_degree_terms` 进一步打包成 one-word-per-cluster payload
   - 当前 payload 已固定为：
     - `valid_mask`
     - `src_row_idx`
     - `coeff_p_terms`
     - `coeff_n_terms`
     - `bias_p_rows`
     - `bias_n_rows`

21. `iter_fixed_degree_template_rom.v`
   - 第一版 template-ROM 包装
   - 直接 `$readmemh` 载入每 cluster 一条 packed payload

22. `iter_fixed_degree_template_unpack.v`
   - 第一版 payload unpack
   - 把 packed word 还原为 scheduler 需要的六组总线

23. `iter_dense_small_template_top.v`
   - 第一版 template-ROM-integrated top
   - 当前已验证：
     - `ROM -> unpack -> scheduler -> ping-pong`
       整条链可以替代 testbench 手填 scheduler 端口
     - payload contract 与 `fixed_degree_terms` 一致

24. `pack_cert_params.py`
   - 把 `block_H` 的 `block_weights` 和 `eta` 打包为 one-word-per-cluster payload
   - 当前 payload 为 `[block_weights][eta]`

25. `iter_fixed_degree_template_bank.v`
   - 多 cluster template bank
   - 支持用 `base_cluster_idx` 从较大的 cluster memory 中读取一个活动 cluster window

26. `iter_cert_param_bank.v` / `iter_cert_param_unpack.v`
   - 多 cluster 认证参数 bank 与 unpack
   - 把 `block_weights/eta` 从手填 top 端口推进到 memory packaging 路径

27. `iter_dense_small_param_bank_top.v`
   - 第一版 template-bank + cert-param-bank integrated top
   - 当前已验证：
     - row template 和 certification 参数都来自 packed banks
     - `base_cluster_idx` bank window 选择语义单测通过
     - bank 参数驱动下完整 iteration controller 闭环通过

28. `run_iter_rtl_vector_gen.py`
   - 第一版 file-driven RTL vector generator
   - 串接：
     - `compile_coeff_templates.py`
     - `pack_fixed_degree_templates.py`
     - `pack_cert_params.py`
   - 生成 RTL 可直接读取的输入 digit、template/cert memh 和 observable golden
   - golden 对齐当前 RTL 的 rail-coded observable contract，而不是假设普通整数加法器语义

29. `tb_online_row_cluster_delta_cert_file.v`
   - 第一版 file-driven 数值闭环 testbench
   - 检查：
     - generated template bank / cert-param bank
     - scheduler 输出
     - row sum rail vectors
     - block bounds
     - `max_error`
     - certification flag

30. `tb_iter_dense_small_param_bank_top_file.v`
   - 第一版完整 top 的 file-driven 检查
   - 复用 `run_iter_rtl_vector_gen.py` 生成的 vectors
   - 检查：
     - template/cert banks 驱动完整 top
     - `o_cluster_max_error`
     - per-cluster certification flag
     - iteration controller 的 `continue/converged` 决策

31. `iter_runtime_word_bank.v`
   - 第一版 runtime-loadable packed-word bank
   - 用显式 `cfg_we/cfg_addr/cfg_wdata` 替代纯 `$readmemh`
   - 当前已改为同步读 + window cache
   - host 写入 payload 后 pulse `i_window_load`
   - bank 用 `num_read_words` 个周期把 active window 装入 output cache，并用 `o_window_valid/o_window_busy` 暴露状态
   - 这个结构避免大规模 cluster memory 直接参与组合 window read，更接近后续 BRAM/URAM 实现

32. `iter_runtime_sdp_field_ram.v`
   - runtime field banks 内部使用的标准同步 1W1R RAM wrapper
   - 写端口服务 host payload load，读端口服务 active-window cache load
   - 目标是让综合看到窄端口 RAM，而不是在 field bank 内部直接动态读宽 packed 数组
   - `mem_style=0/1/2` 分别选择 distributed/BRAM/URAM；当前 capacity-mode 默认 `1`

33. `iter_template_field_bank.v` / `iter_cert_param_field_bank.v`
   - runtime payload storage 的 field-split 版本
   - 外部仍写 packed payload，内部按 template/cert 字段拆库存储
   - active window load 时再把字段拼回 scheduler/unpack 需要的 packed contract
   - 当前 sweep 证明它能消除旧 packed-bank 的 FF 线性增长；配合 `iter_runtime_sdp_field_ram.v` 后，Vivado 已把 template/cert storage 推断为 BRAM

34. `iter_dense_small_runtime_top.v`
   - 第一版 runtime-loadable solver top
   - 支持 runtime 写入：
     - row template payload
     - `block_H` certification payload
     - ping-pong state bank row word
   - 支持 `i_load_window / o_window_valid / o_window_busy`
   - 支持基础 counters：
     - `o_total_cycles`
     - `o_issue_cycles`
     - `o_cert_wait_cycles`
     - `o_iter_count`
     - `o_converged_iter`
   - 保留 external digit input，便于与旧 param-bank top 做同输入回归

35. `tb_iter_dense_small_runtime_top.v`
   - 第一版 runtime loader 检查
   - 检查：
     - template/cert bank runtime 写入后窗口输出正确
     - state bank runtime load 后 `x_old` 输出正确
     - runtime-loaded 参数驱动下完整 iteration controller 闭环通过

36. `make_jacobi32_blockdiag_runtime_vectors.py` / `tb_iter_dense_runtime_jacobi32_blockdiag.v`
   - 第一版 32 active-row single-iteration runtime workload 功能检查
   - 生成 `8` clusters x `4` rows 的 block-diagonal Jacobi-family fixture
   - 检查：
     - `32 x 32` cluster-local matrix 的 template/cert payload 生成与 runtime 写入
     - RAM-wrapper field-bank window load
     - ping-pong state-load port
     - all-row scheduler active mask
     - one full row-update / delta / `block_H` certification / iteration-controller pass
     - loader/window/iteration counters

37. `make_jacobi32_blockdiag_multi_runtime_vectors.py` / `tb_iter_dense_runtime_jacobi32_blockdiag_multi.v`
   - 第一版 32 active-row multi-iteration solver checkpoint
   - 生成同一 `8` clusters x `4` rows block-diagonal fixture 的 `6` 轮 RTL-contract golden
   - 检查：
     - all-zero runtime-loaded initial state
     - committed ping-pong state replay
     - per-round `max_error/certified` flags
     - per-round committed state bank contents
     - `iter_count / issue_cycles / cert_wait_cycles / converged_iter`

38. `make_jacobi32_global_runtime_vectors.py` / `tb_iter_dense_runtime_jacobi32_global_multi.v`
   - 第一版 raw banded `32x32` inter-cluster source replay checkpoint
   - 将 template source field 从 cluster-local index 扩展为 active-window global row index
   - 启用 `global_source_replay=1` 后，每个 cluster 的 replay mux 可从全部 `32` 个 active rows 取源 digit
   - 这是功能正确性 checkpoint，不是最终低成本 routing 方案

39. `make_jacobi32_halo_runtime_vectors.py` / `tb_iter_dense_runtime_jacobi32_halo_multi.v`
   - 第一版 raw banded `32x32` bounded halo-window source replay checkpoint
   - 将 template source field 编码到“前一簇 + 本簇 + 后一簇”的 `12` 行 source window
   - 启用 `halo_source_replay=1` 后，每个 cluster 的 replay mux 不再连接全部 active rows，而只连接相邻 cluster halo
   - 这是后续 banded solver 的默认物理方向，用来替代 global-source 全局 mux

40. `tb_iter_dense_runtime_jacobi32_halo_reg_multi.v`
   - registered halo-window source replay checkpoint
   - 启用 `halo_replay_output_register=1`，在 halo source digit selection 后增加一拍寄存
   - 现有 runtime scheduler 已经在 issue 前保持 replay control 稳定，因此该寄存不会增加 solver-level cycle
   - `online_row_cluster_block_cert.v` 中的 block-bound pipeline register 需要保持为真实物理切点，避免 Vivado 把 `block_bound_max_pool -> cert_engine` 边界优化穿透
   - `iter_template_field_bank.v` 使用 slot-based window cache，把超宽 packed output cache 拆成 per-cluster slot register，降低 window capture control fanout
   - 该路径把 routed worst path 从 halo replay / certification arithmetic 移到 template-cache control route，成为 banded solver 的默认实现形态

41. `tb_iter_dense_runtime_jacobi32_halo_reg_cpipe_multi.v`
   - certification product pipeline ablation
   - 启用 `cert_product_pipeline=1` 后，`block_H` certification 先寄存 `block_bound * block_weight` 乘积，再在下一拍做 row sum / max / eta compare
   - 功能上 `cert_wait_delta` 从 `8` 增加到 `9`，多轮 solver golden 仍然对齐
   - NC16 route 结果表明该拍不是默认优化：WNS 仅 `+0.390 ns -> +0.409 ns`，但 LUT/FF/CARRY8 分别增加到 `43278 / 17569 / 940`
   - 结论是 NC16 的关键路径不是简单 product-to-sum 级联，而是 block-bound 寄存器到 DSP 乘法器输出寄存器的路由与 DSP 内部乘法路径；后续应优化 certification 数据布局/产品缓存，而不是继续粗暴插拍

42. `tb_iter_dense_runtime_jacobi32_halo_reg_opipe_multi.v`
   - certification operand-localization pipeline
   - 启用 `cert_operand_pipeline=1` 后，`block_H` certification 先在 `cert_engine` 内部按 product term 复制并寄存 `{block_bound, block_weight}`，下一拍再由局部 operand 驱动 DSP 乘法
   - 功能上 `cert_wait_delta` 从 `8` 增加到 `9`，多轮 solver golden 仍然对齐
   - NC16 route 结果有效：WNS 从 `+0.390 ns` 提升到 `+0.646 ns`，资源基本不变，dynamic power 从 `1.766 W` 降到 `1.713 W`
   - NC8 route 下 WNS 从 `+1.125 ns` 降到 `+0.679 ns` 但仍满足 5 ns，说明该选项不是小规模 latency-default，而是 NC16+ scaling / timing-closure 模式
   - 该实验确认 NC16 的真实瓶颈是 block-bound/weight 到 DSP 的物理局部性，而不是单纯缺一个 product-to-sum 寄存器

43. `tb_iter_dense_runtime_jacobi32_halo_reg_opipe_cmpipe_multi.v`
   - certification compare pipeline ablation
   - 启用 `cert_compare_pipeline=1` 后，在 opipe 基础上把 `row_sums -> max_sum` 与 `max_sum <= eta` 再拆成两拍
   - 功能上 `cert_wait_delta` 从 `9` 增加到 `10`，多轮 solver golden 仍然对齐
   - NC16 route 结果没有收益：WNS 仍为 `+0.646 ns`，FF 从 `16158` 增加到 `16908`，dynamic power 从 `1.713 W` 增加到 `1.728 W`
   - 结论是 opipe 后的瓶颈已经离开 certification arithmetic，回到 runtime template-window cache routing；后续不要继续在 certification 链上盲目插拍

当前验证状态：

- Python/compiler 自检通过
- 四十一个 TB 在 `iverilog` 下通过，最新全量结果为 `SUMMARY PASS 41/41`
- Xilinx 2023.2 `xvlog/xelab` 对 runtime top、`jacobi32_blockdiag` single-iteration testbench、`jacobi32_blockdiag_multi` solver testbench、`jacobi32_global_multi` global-source testbench、`jacobi32_halo_multi` halo-window testbench、`jacobi32_halo_reg_multi` registered halo-window testbench、`jacobi32_halo_reg_cpipe_multi` product-pipeline ablation testbench、`jacobi32_halo_reg_opipe_multi` operand-localization testbench 和 `jacobi32_halo_reg_opipe_cmpipe_multi` compare-pipeline ablation testbench 编译/elaborate 通过
- `xsim` 运行阶段在当前环境里有一致的 runtime exception，表现为 simulator shell 问题，而不是 compile/elab 失败
- `iter_dense_small_param_bank_top` 已完成 U55C 5 ns OOC route，routed WNS `+0.964 ns`，资源为 `858 LUT / 508 FF / 16 DSP / 0 BRAM / 0 URAM`
- `iter_dense_small_runtime_top` RAM-wrapper field-bank 版本已完成 U55C 5 ns OOC route，`NUM_TOTAL_CLUSTERS=2` routed WNS `+0.898 ns`，资源为 `3760 LUT / 2162 FF / 16 DSP / 8.5 BRAM / 0 URAM`
- runtime top 已完成旧 packed-bank、direct field-bank、RAM-wrapper field-bank 对比 sweep：旧 packed-bank 在 `NUM_TOTAL_CLUSTERS=2/8/16/32` 下 FF 从 `2912` 增至 `17075`；direct field-bank 解决 FF 增长但仍是 LUTRAM；RAM-wrapper field-bank 保持 `LUTRAM=0` 且 BRAM 固定为 `8.5`
- RAM-wrapper field-bank 已完成 `NUM_TOTAL_CLUSTERS=64/128/256` synth-only 存储探针，LUT/FF 基本不随深度增长
- runtime top 已增加 loader/window/cache counters：template/cert/state write count、accepted window load count、window busy cycles、window ready cycles
- physical active-cluster sweep 已完成 `NUM_CLUSTERS=2/4/8` U55C 5 ns OOC route；`NUM_CLUSTERS=8` 对应 `32` active rows，routed WNS `+0.643 ns`，资源为 `10267 LUT / 7520 FF / 64 DSP / 8.5 BRAM`
- [`summarize_runtime_top_reports.py`](./summarize_runtime_top_reports.py) 已加入，用于自动扫描 Vivado runtime top 报告并生成 [`generated/runtime_top_auto_report.md`](./generated/runtime_top_auto_report.md)
- 32 active-row `jacobi32_blockdiag` runtime workload 功能测试已通过：counter line 为 `total=71 issue=1 cert_wait=8 iter=1 conv_iter=1 cfg_template=8 cfg_cert=8 cfg_state=16 window_load=1 window_busy=10 window_ready=44`
- 32 active-row `jacobi32_blockdiag_multi` solver checkpoint 已通过：`6` 轮 committed-state replay，counter line 为 `total=157 issue=6 cert_wait=48 iter=6 conv_iter=6 cfg_template=8 cfg_cert=8 cfg_state=32 window_load=1 window_busy=10 window_ready=130`
- raw banded `32x32` `jacobi32_global_multi` global-source checkpoint 已通过：`6` 轮 committed-state replay，counter line 为 `total=157 issue=6 cert_wait=48 iter=6 conv_iter=6 cfg_template=8 cfg_cert=8 cfg_state=32 window_load=1 window_busy=10 window_ready=130`
- global-source NC8 U55C 5 ns OOC route 已通过，WNS `+0.028 ns`，资源为 `35495 LUT / 8495 FF / 64 DSP / 9.5 BRAM`；相对 cluster-local NC8 的 `10267 LUT / WNS +0.643 ns`，它证明跨 cluster 功能可行，但 full global mux 不适合作为最终论文级物理结构
- raw banded `32x32` `jacobi32_halo_reg_multi` registered halo-window checkpoint 已通过：`6` 轮 committed-state replay，counter line 为 `total=157 issue=6 cert_wait=48 iter=6 conv_iter=6 cfg_template=8 cfg_cert=8 cfg_state=32 window_load=1 window_busy=10 window_ready=130`
- registered halo-window NC8 U55C 5 ns OOC route 已通过，WNS `+1.125 ns`，资源为 `20040 LUT / 8237 FF / 64 DSP / 9 BRAM`；相对 global-source，它降低 `43.54%` LUT、`51.87%` dynamic power，并把 WNS 提升 `1.097 ns`
- registered halo-window NC16 U55C 5 ns OOC route 已通过，WNS `+0.390 ns`，资源为 `41928 LUT / 16151 FF / 128 DSP / 9 BRAM`；`cert_product_pipeline=1` ablation 也 route 通过，WNS `+0.409 ns`，但资源涨到 `43278 LUT / 17569 FF / 940 CARRY8`，因此不设为默认
- `cert_operand_pipeline=1` scaling mode 已完成 NC8/NC16 U55C 5 ns OOC route：NC8 WNS `+0.679 ns`，资源 `20044 LUT / 8246 FF / 64 DSP / 9 BRAM`；NC16 WNS `+0.646 ns`，资源 `41935 LUT / 16158 FF / 128 DSP / 9 BRAM`。它牺牲每轮 1 cycle certification latency 换取 NC16 timing margin，是后续大规模 scaling 的候选默认
- `cert_compare_pipeline=1` ablation 已完成 NC16 U55C 5 ns OOC route：WNS 仍为 `+0.646 ns`，资源为 `41936 LUT / 16908 FF / 128 DSP / 9 BRAM`，因此不作为默认；下一步优化目标应切到 template-window cache/control fanout

最新 OOC checkpoint 记录在
[`generated/u55c_param_bank_ooc_checkpoint.md`](./generated/u55c_param_bank_ooc_checkpoint.md)
和
[`generated/u55c_runtime_top_ooc_checkpoint.md`](./generated/u55c_runtime_top_ooc_checkpoint.md)。
规模化 sweep 记录在
[`generated/runtime_top_scale_sweep.md`](./generated/runtime_top_scale_sweep.md)。
自动资源/时序汇总记录在
[`generated/runtime_top_auto_report.md`](./generated/runtime_top_auto_report.md)。
32 active-row runtime 功能 checkpoint 记录在
[`generated/runtime_jacobi32_blockdiag_function_report.md`](./generated/runtime_jacobi32_blockdiag_function_report.md)。
32 active-row multi-iteration solver checkpoint 记录在
[`generated/runtime_jacobi32_blockdiag_multi_solver_report.md`](./generated/runtime_jacobi32_blockdiag_multi_solver_report.md)。
raw banded `32x32` global-source checkpoint 记录在
[`generated/runtime_jacobi32_global_solver_report.md`](./generated/runtime_jacobi32_global_solver_report.md)。
raw banded `32x32` halo-window checkpoint 记录在
[`generated/runtime_jacobi32_halo_solver_report.md`](./generated/runtime_jacobi32_halo_solver_report.md)。

这次时序收敛依赖一个关键微架构修正：`block_H` certification 不再把 row bound、DSP 加权和、row max、`eta` 比较和 controller 判定压在同一拍，而是拆成 block-bound register、row-sum register、max/compare register 和 wrapper output register。这个固定延迟是合理代价，因为认证路径不应成为 iteration datapath 的组合控制闭环。

因此下一步 RTL 不应再回到 generic operator，而应在当前 specialized stack 基础上继续推进：

- loader/window/cache counters
- loader and iteration counters
- larger Jacobi cluster sweep

## 11. Implication of the First Software Report

当前第一版软件报告在
[generated/iterative_solver_model_report.md](./generated/iterative_solver_model_report.md)
中的关键信号是：

1. `PageRank` 的认证收益很弱，很多 case 在 `q=24` 内无法提早认证。
2. `Jacobi` 的认证收益明显存在，`avg j^*` 可比 `q` 小约 `1-4` 位。
3. `fused > B1` 已成立。
4. `fused > B2` 尚未成立。

因此微架构优先级重新调整为：

- 第一论文应用 workload 优先 `PageRank`
- `Jacobi` 保留为 signed coefficient、halo-window 和更宽动态范围的 RTL stress fixture
- PageRank 主线必须新增 graph-to-template generator、bounded-degree / partitioned graph fixture、`L1` delta certification 和 PageRank-equivalent conventional baseline
- 下一步若要继续撑 Gate 3，重点是把已经验证的 digit-stream wavefront 从 Jacobi fixture 迁移到 PageRank graph propagation，而不是继续堆 raw arithmetic

## 12. Immediate Next Step

这份文档之后，建议立即做两件事：

1. 保留 `jacobi32_*` 作为 routed regression 和 stress fixture，不再继续扩大 Jacobi 应用叙事；
2. 新增 `pagerank32_*` generator，把 bounded-degree / partitioned graph 编译成现有 fixed-degree template；
3. 新增 PageRank `L1` delta certification，与现有 Jacobi `block_H` certification 分开记录；
4. 在 PageRank template-ROM 和 baseline 稳定前，不引入完整 CSR/HBM 稀疏控制。

## 13. Prefix Scheduler / Stencil Halo Checkpoint

当前 checkpoint 记录在
[`generated/prefix_scheduler_stencil_halo_checkpoint.md`](./generated/prefix_scheduler_stencil_halo_checkpoint.md)。

- `iter_digit_prefix_scheduler` 已实现自动 digit sweep、active-cluster mask 和 prefix gating counters；
- runtime top 已暴露 `active_digit_cycles / gated_digit_cycles / cert_prefix_digit_sum / certified_block_count`；
- `STENCIL_HALO_R1` 已作为 radius-1 halo replay ablation 接入并通过功能测试；
- 全量 Icarus 回归已随 full-digit runtime checkpoint 更新到 `SUMMARY PASS 41/41`。

U55C 5 ns OOC route 结论是：`STENCIL_HALO_R1` 不能直接作为默认主线。NC8 下 WNS 从 `+0.474 ns` 到 `+0.742 ns`，dynamic 从 `0.896 W` 到 `0.883 W`；但 NC16 下 WNS 从 `+0.754 ns` 降到 `+0.491 ns`，LUT 从 `43015` 增到 `43216`。因此当前默认仍保持 generic registered halo replay，后续如果继续做 stencil 优化，必须进一步移除 source-index 存储/控制，而不是只重排 replay mux 层级。

## 14. Full-Digit Bridge Checkpoint

当前 checkpoint 记录在
[`generated/full_digit_bridge_checkpoint.md`](./generated/full_digit_bridge_checkpoint.md)。

- `iter_digit_serial_full_row_update_delta_slice` 已实现 `DATA_WIDTH` digit 的 full-word row update；
- `iter_digit_serial_full_row_cluster_delta_cert` 已把该 row slice 扩展到 cluster，并复用现有 `block_H` certification；
- `iter_dense_small_runtime_top` 已新增 `auto_full_digit=1`，由 `iter_digit_prefix_scheduler` 自动发出 `digit_idx=0..DATA_WIDTH-1`；
- `iter_dense_small_ping_pong_top` 已新增 `row_datapath_mode=2`，把 halo replay digit stream 接入 full-digit cluster bridge；
- full-digit row slice 已从动态 shift 改为 MSB-first Horner recurrence，并加入 input-localization 与 final-sum/abs-upper 两级切分；
- prefix-bound sideband 已参数化为 `enable_prefix_cert`，默认关闭以避免污染 timing-clean 主路径；
- row-level、cluster-level 和 6 轮 Jacobi runtime full-word golden testbench 均已通过；
- 全量 Icarus 回归为 `SUMMARY PASS 41/41`。

U55C NC8 OOC route 已通过 5 ns：`28731 LUT / 15451 FF / 64 DSP / 9 BRAM / WNS +0.261 ns / dynamic 1.223 W`。6 轮 runtime counter 为 `total=223 issue=66 cert_wait=114`。

这一步的定位仍是 correctness bridge：它使用 signed binary accumulator 来证明 MSB-first digit replay 可以恢复 conventional full-word Jacobi row-update contract，并且已经接入 runtime 多轮闭环和 routed timing-clean checkpoint。它还不是最终论文级低成本 online residual datapath。`AUTO_PREFIX_GATING=1` 已作为负向 ablation 验证：功能上 `gated_digit=0`，route 结果为 `36845 LUT / 16294 FF / 224 DSP / WNS -1.185 ns / dynamic 1.550 W`，因此当前 prefix-bound 实现不能作为主线优化。

## 15. Digit-Stream State Boundary Checkpoint

当前 checkpoint 记录在
[`generated/digit_stream_state_checkpoint.md`](./generated/digit_stream_state_checkpoint.md)。

- `iter_digit_stream_state_ping_pong_bank` 已把 state commit 从 full-word row 写入改成逐 digit 写入 inactive bank；
- `iter_digit_stream_state_replay_top` 已把 digit-wise write、`commit_swap` 和 fixed-degree replay 接成独立 shell；
- `tb_iter_digit_stream_state_ping_pong_bank` 覆盖 host load、MSB-first digit write、commit swap 和第二轮写回；
- `tb_iter_digit_stream_state_replay_top` 覆盖 digit-written committed state 的下一轮 source replay。

这个 checkpoint 的边界是：

```text
output_digit[p/n] -> digit-wise state bank write -> commit swap -> replay digit[p/n]
```

它只移除了 state/replay 侧的 full-word commit 要求，还没有替换 full-digit row-update bridge。下一步要做的是把 row-update 结果本身改成最终 `x_new` digit stream，并把 convergence/certification 从 full-word delta 改为 digit-stream safe certificate。当前 full-digit bridge 应保留为 numerical regression/reference，直到新的 digit-stream row-update path 与 golden 对齐。

## 16. Digit-Stream Row-Output Exploration

当前探索记录在
[`generated/digit_stream_row_update_exploration.md`](./generated/digit_stream_row_update_exploration.md)。

- `iter_online_output_update` 已把原始 operator 代码中的 `output_and_update` 抽成 solver-side 通用 primitive；
- `tb_iter_online_output_update` 已验证该 primitive 在正/负/零 directed case 上与原始行为一致；
- `iter_online_affine_digit_core` 已实现 `v_j = 2w_j + s_j`、`z_j = select(v_j)`、`w_{j+1} = update(v_j, z_j)` 的 residual/output-update 回路；
- `iter_online_affine_digit_row` 已尝试把 `online_affine_row_update_core` 直接接入上述 residual loop。

这次探索的重要结论是负面的，但有价值：

1. 当前 `online_affine_row_update_core` 输出仍然是 digit-slice affine checkpoint，不是可直接闭环成最终 `x_new` 的 row-output stream；
2. 当前 bias 仍是 full-word rail-vector 每拍注入，这和 all-digit-stream solver 所需的 streamed-bias 或 once-per-row seed contract 不一致。

因此下一步不是继续把现有 affine core 硬接进 runtime，而是：

- 先拆出 no-bias affine digit-slice producer；
- 再补 streamed-bias 或严格推导的 bias seed；
- 最后再让 row-output stream 接入 digit-stream state bank。

## 17. Solver-Native Digit-Stream Checkpoint

当前 checkpoint 记录在
[`generated/solver_native_digit_stream_checkpoint.md`](./generated/solver_native_digit_stream_checkpoint.md)。

新增边界如下：

```text
state digit terms
  -> fixed-coefficient no-bias contribution
  -> streamed bias digit add
  -> residual/output-update
  -> x_new digit
```

同时新增 inline delta path：

```text
x_new digit + x_old digit -> prefix delta + conservative tail bound
```

对应 RTL：

- `iter_streamed_bias_source`：把 bias full rail word 对齐成 MSB-first digit stream；
- `iter_const_coeff_digit_contrib_rail`：为 solver-native magnitude p/n rail 执行固定系数 signed digit contribution，负 digit 使用 p/n 交换；
- `iter_online_affine_no_bias_core`：固定系数、无 bias 的 4-term contribution producer；
- `iter_digit_stream_delta_bound`：维护 old/new digit 的 prefix delta bound；
- `iter_solver_native_row_digit_engine`：把 no-bias contribution、streamed bias 和 residual/output-update loop 串成 row-level digit-output boundary。
- `iter_solver_native_commit_adapter`：跳过固定 online latency digits，只把后续 `DATA_WIDTH` 个 state digits 写入 state bank，避免迭代间 state 位宽增长。
- `iter_solver_native_cluster_digit_stream_top`：把 replay mux、row digit engine、commit adapter 和 digit-stream state bank 封装成 cluster shell，是后续 runtime `ROW_DATAPATH_MODE=3` 的接入边界。
- `iter_solver_native_cluster_delta_cert_top`：在 cluster shell 的 write-digit stream 上并联 delta bound 和 `block_H` certification，不等待 full-word row reconstruction。
- `tb/iter_tb_signed_digit_reconstruct.vh`：testbench 侧 signed-digit rail numerical checker，用于 mode3 与 magnitude-rail golden 的数值比较。

`iter_solver_native_row_digit_engine` 使用 `affine_guard_shift=3` 与 `sample_offset=3`。这对应原论文带 bias integrated inner product 的 `t=3` 估计宽度：贡献向量进入 residual datapath 时保留 3 位 guard/fractional estimate，selector 的采样窗口也同步下移 3 位。

当前 directed tests 已通过：

- `tb_iter_streamed_bias_source`
- `tb_iter_digit_stream_delta_bound`
- `tb_iter_solver_native_row_digit_engine`
- `tb_iter_solver_native_row_digit_characterization`
- `tb_iter_solver_native_state_commit_replay`
- `tb_iter_solver_native_multirow_state_commit_replay`
- `tb_iter_solver_native_state_delta_bound`
- `tb_iter_solver_native_replayed_state_identity_update`
- `tb_iter_solver_native_two_iter_affine_cluster`
- `tb_iter_solver_native_cluster_digit_stream_top`
- `tb_iter_solver_native_cluster_delta_cert_top`
- `tb_iter_dense_runtime_solver_native_mode3_smoke`

该 checkpoint 已证明 row-level 非零数值等价：

$$
\text{assembled solver-native digit output}
=
\text{full-digit bridge output}
$$

注意二者不是 bit pattern 等价。solver-native path 输出 signed-digit rail trace，full-digit bridge 输出 magnitude rail word。下一阶段接入 state bank 和 replay 时必须按 signed-digit rail state contract 处理。

`tb_iter_solver_native_state_commit_replay` 已验证该 signed-digit rail state contract：solver-native row engine 的输出 trace 直接写入 digit-stream state bank，`commit_swap` 后通过 fixed-degree replay 读出并重构，得到 full bridge 参考值 `170`。该测试证明 state/replay 边界可以承载 solver-native signed-digit trace，不需要先转换成 magnitude rail word。

`tb_iter_solver_native_multirow_state_commit_replay` 已验证两个 solver-native row engines 可以并行提交到同一个 digit-stream state bank，commit/replay 后得到 `row0=170`、`row1=-92`。`tb_iter_solver_native_state_delta_bound` 已验证 replayed new-state digits 和 old-state digits 可直接进入 inline delta bound，最终得到 `delta=165`。下一步是 closed-loop two-iteration cluster，使 replayed signed-digit state 直接成为下一轮 row engine 输入。

`tb_iter_solver_native_replayed_state_identity_update` 已完成最小 closed-loop 验证：预加载 signed-digit state 后，state replay 直接驱动 solver-native row engine 的 identity update，再经 commit adapter 写回 inactive bank，commit 后 replay 仍得到 `row0=170`、`row1=-92`。这证明 signed-digit state contract 可以跨越一次 iteration boundary，不只是 state-bank readback。

`tb_iter_solver_native_two_iter_affine_cluster` 已完成非恒等两轮 affine cluster 验证。第一轮使用 direct source digit streams 和非零 bias 得到 `row0=170`、`row1=-92` 并以 signed-digit state 写入 bank；第二轮直接 replay 这两个 state，计算 `row0'=row0+row1=78`、`row1'=row0-row1=262`，再提交并 replay 验证。该测试仍与 full-digit bridge 同步对照，所以当前结论不是 hardcoded readback，而是 replayed signed-digit state 能作为下一轮非恒等 row-update 的真实输入。

`tb_iter_solver_native_cluster_digit_stream_top` 使用正式 cluster shell 重跑两轮 affine 场景，并把第二轮改成 scaled-coefficient replay：`row0'=2*row0+3*row1=64`、`row1'=3*row0-2*row1=694`。RTL 结果为 `iter1=(170,-92)`、`iter2=(64,694)`。这一步把此前 testbench 手工连接的物理链路收敛为一个 RTL 模块，并验证 signed-digit replay 在系数大于 1 时仍可作为下一轮输入。

`tb_iter_solver_native_cluster_delta_cert_top` 已验证 cluster shell 的 commit digit stream 可以直接驱动 inline delta/certification。测试预加载旧状态 `(5,2)`，写入新状态 `(7,-3)`，delta bound 得到 `max_error=5` 并通过 `block_H` certification，commit 后 replay 新状态为 `(7,-3)`。这一步证明 certification 边界已经可以跟随 digit-stream state commit，而不是依赖 full-word row-update bridge。

`ROW_DATAPATH_MODE=3` 已接入 `iter_dense_small_ping_pong_top`。该模式跳过原来的 full-word `iter_state_ping_pong_bank`，改由 `iter_solver_native_cluster_delta_cert_top` 内部的 digit-stream state bank 提交和 replay；`iter_dense_small_runtime_top` 仍复用原有 template/cert loader、row scheduler、auto digit scheduler、iteration controller 和 counters。由于 solver-native row engine 有 online drain latency，`iter_solver_native_cluster_digit_stream_top` 内部新增固定 `skip_digits` drain FSM：runtime 只发 `DATA_WIDTH` 个输入 digit，cluster shell 自动补零 drain 并写满 state。`iter_solver_native_cluster_delta_cert_top` 已接入 runtime `tail_bound`，因此 inline delta/certification 与 full-digit golden 的 error contract 对齐。runtime 默认使用 `affine_guard_shift=7, skip_digits=4`，这是 strict blockdiag+halo sweep 中最短的稳健组合；底层 cluster 模块默认仍保留旧 `3/8` 以维持 directed 单元测试的历史期望。`tb_iter_dense_runtime_solver_native_mode3_smoke` 已通过两轮 runtime 验证，状态序列为 `(5,2)->(7,-3)->(9,2)`，最终 `max_error=5`、`issue_cycles=22`。

`tb_iter_dense_runtime_jacobi32_blockdiag_solver_native_multi` 已从诊断测试升级为 strict runtime 回归。它使用新生成的 `generated/rtl_vectors/jacobi32_blockdiag_full_digit_f4`，该向量是 full-digit blockdiag contract，不再是旧 `jacobi32_blockdiag_multi` 的单 digit-slice demo。testbench 用 `tb/iter_tb_signed_digit_reconstruct.vh` 将 mode3 signed-digit state 重构为数值，再和 magnitude-rail golden 比较，因此比较的是数值等价而不是 p/n bit pattern 等价。该测试连续运行 `8 clusters x 4 rows x 6 iterations`；fast-done 后结果为 `total=229`、`issue=66`、`cert_wait=120`、`iter=6`、`conv_iter=6`。

runtime mode3 现在复用顶层 `w_drv_x*` source-select streams，而不是让 solver-native cluster shell 自行做 internal local replay。因此顶层 halo-window replay 可以直接驱动 solver-native row digit engine。`tb_iter_dense_runtime_jacobi32_halo_reg_solver_native_multi` 使用 `generated/rtl_vectors/jacobi32_halo_conv_f2` 完成 `8 clusters x 4 rows x 6 iterations` strict halo 回归。带 halo replay 输出寄存器时结果为 `total=241`、`issue=66`、`cert_wait=132`；关闭该寄存器后结果为 `total=235`、`issue=66`、`cert_wait=126`；加入 fast-done 结果 bypass 后结果为 `total=229`、`issue=66`、`cert_wait=120`，并仍通过 U55C 5 ns route。当前限制收缩为：arbitrary global-source mode3 尚未接入；radius-1 halo-window 已经功能闭环。

U55C NC8 5 ns OOC route 已通过。`solver_native_mode3_halo_nc8_finalonly` 启用 `iter_digit_stream_delta_bound.final_only=1` 后，结果为 `27102 LUT / 10054 FF / 64 DSP / 9 BRAM / WNS +0.750 ns / dynamic 0.828 W`，相对优化前 `31897 LUT / 10095 FF / 600 CARRY8 / WNS +0.222 ns / dynamic 0.993 W` 明显减少了未使用的 prefix-bound 逻辑。certification wrapper I/O bypass 将 halo runtime 从 `277` 压到 `265`。当前 route tag 为 `solver_native_mode3_halo_nc8_g7s4_noreg_fastdone`，使用 `affine_guard_shift=7, skip_digits=4, HALO_REPLAY_OUTPUT_REGISTER=0` 和 fast-done result bypass，结果为 `26779 LUT / 9083 FF / 64 DSP / 9 BRAM / WNS +0.128 ns / dynamic 0.711 W`，runtime counter 为 `total=229 issue=66 cert_wait=120`。带 halo replay 输出寄存器的 timing-protection ablation 为 `26009 LUT / 9384 FF / WNS +0.436 ns / total=241`。

`affine_guard_shift/skip_digits` 已在 strict halo 和 strict blockdiag 上联合 sweep。稳健通过组合为 `1/10`、`2/9`、`3/8`、`4/7`、`5/6`、`6/5`、`7/4`；`8/3` 和 `9/2` 虽然通过 halo，但在 blockdiag 上失败，因此不能作为默认。这说明 cycle 收益来自 digit 对齐微架构，而不是减少输入位数或放松精度。

层级报告显示每个 solver-native cluster datapath 约 `1536..1539 LUT / 539 FF / 8 DSP`，其中 row digit engine 本体每行约 `109..111 LUT / 25 FF`，较大的部分仍是 halo replay、commit adapter、delta bound 和 block-H certification 边界。最新 no-register fast-done halo 最坏路径仍为 `delta_bound/o_abs_upper_reg -> cluster_cert/cert_engine/r_row_sums0/DSP_OUTPUT_INST/ALU_OUT`，WNS 为 `+0.128 ns`，logic level 约 `12`，包含 `3` 个 `CARRY8` 和 DSP 内部路径。这说明 mode3 现在可布线且资源明显下降，但仍不是 latency/throughput 胜利；下一步优化应集中在 state-ready/certification overlap，而不是继续微调 row digit engine 的 online adder tree。
