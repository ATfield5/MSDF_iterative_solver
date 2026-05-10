# Iteration-Fused Online Arithmetic Plan

本文件把新的论文主线拆成可执行阶段。原则只有两个：

- 先数学和模型，后 RTL。
- 先证明 iteration-fused 值得做，再投入综合与实现。

## Stage 0: Freeze Old Mainline

目标：

- 把 `MSDF exp / softmax / attention` 当前结果固定为历史分支；
- 明确它们不是论文主线，只作为负结果和背景。

交付物：

- 一份负结果总结文档；
- 根 `README.md` 增加新主线入口。

验收：

- 新目录和索引已建立；
- 后续文档不再把 `MSDF exp` 当第一主线。

## Stage 1: Mathematical Foundation

目标：

- 推出 iteration-fused affine fixed-point solver 的统一递推；
- 给出在线差值尾项界和收敛判定界；
- 明确为什么该方法高于 integrated inner-product-only。

子任务：

1. 定义：
   $$
   x^{(k+1)} = Gx^{(k)} + c
   $$
2. 推导 integrated row-update residual recurrence。
3. 推导：
   $$
   d^{(k)} = x^{(k+1)} - x^{(k)}
   $$
   的 online 尾项界。
4. 推导 `L_inf` 收敛认证：
   - 可证收敛
   - 可证未收敛
   - 不确定区间
5. 建立 internal width / digit-slice 需求公式。

交付物：

- 数学推导 markdown
- 参数与假设表

验收：

- 所有边界是严格不等式，不是经验判据；
- 能明确指出哪些控制逻辑是必要的，哪些是可选优化。

## Stage 2: Workload and Baseline Definition

目标：

- 选两个负载；
- 固定 baseline；
- 固定所有报告口径。

默认工作负载：

### W1

`PageRank / power iteration`

### W2

`Richardson` 或 `Jacobi-style` solver

baseline：

### B1

conventional cascaded online arithmetic

### B2

conventional FPGA DSP MAC + standard reduction/check

### B3

CPU software reference

交付物：

- workload definition 文档
- baseline table
- 输入矩阵/向量集合规范

验收：

- 每个 baseline 的角色明确；
- 不再出现“只比自己定义的弱 baseline”的问题。

## Stage 3: Software Golden Model and Cycle Model

目标：

- 在 RTL 前完成数学正确性和性能趋势验证。

子任务：

1. 写 fused iteration 软件模型。
2. 写 cascaded online 对照模型。
3. 写 conventional FPGA-style 周期模型。
4. 对不同：
   - 维度
   - 稀疏度
   - 谱半径
   - 收敛阈值
   做 sweep。

要回答的问题：

- iteration boundary 融合到底省多少周期；
- convergence certification 平均能提前多少位停止；
- 收益来自 row-update 融合，还是来自 convergence-aware 认证。

交付物：

- golden model
- cycle model report
- matrix sweep report

验收：

- 有明确 go/no-go 门槛；
- 如果模型趋势不成立，停止 RTL。

## Stage 4: RTL Core Bring-Up

目标：

- 分层实现，先小闭环，再完整 top。

子任务：

1. `integrated online row-update core`
2. `online delta / bounds core`
3. `state buffer + iteration controller`
4. small dense top
5. sparse / block-sparse extension

第一版约束：

- 不做完整浮点动态范围；
- 不做 CG/GMRES；
- 不引入复杂除法链；
- 先 dense small matrix 验证，再上 sparse。

交付物：

- RTL
- testbench
- 基础综合结果

验收：

- 功能与 golden model 一致；
- 收敛认证无误判；
- timing 和资源没有明显违背 Stage 3 模型。

## Stage 5: FPGA Evaluation

目标：

- 跑到论文可用结果，不再停在单模块综合。

指标：

- `cycles / iteration`
- `cycles to convergence`
- `LUT / FF / DSP / BRAM`
- `Fmax / WNS`
- `energy / solve`
- `intermediate storage bytes`

交付物：

- OOC synth/route
- top-level synth/route
- benchmark reports

验收：

- 至少在一个 workload 上，相对 `B2` 或 `B1` 有明确优势；
- 优势必须来自 iteration-fused 主张，而不是偶然的参数点。

## Stage 6: Paper Packaging

论文叙事只保留一条主线：

$$
\textbf{convergence-aware iteration-fused online arithmetic}
$$

章节结构建议：

1. fixed-point iterative solver background
2. limitation of cascaded online and conventional iteration boundary
3. fused row-update recurrence
4. online convergence certification
5. architecture
6. evaluation

禁忌：

- 不再把 `MSDF exp` 写成主贡献；
- 不把 attention/softmax 作为主实验；
- 不把 CPU speedup 当硬件主证据。

## Go / No-Go Rule

只有满足下面条件，才继续投入完整 RTL 和论文：

1. Stage 3 模型显示 iteration-fused 相比 cascaded online 有稳定周期优势。
2. convergence certification 平均确实减少有效输出位数或有效 iteration cost。
3. 相比 conventional FPGA kernel，至少在一项核心指标上可证明有竞争力：
   - DSP
   - storage / interconnect
   - cycles to certified convergence

否则，项目应降级为：

$$
\text{integrated online inner-product study}
$$

而不是继续扩张到 solver 级论文。
