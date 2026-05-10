# Cycle and Resource Model for Iteration-Fused Online Arithmetic

本文件建立新主线的解析模型。目标不是给出 RTL 级精确数字，而是先回答三个问题：

1. iteration-fused 相比 cascaded online 到底减少了哪些周期项；
2. 相比 conventional FPGA kernel，MSDF/online 的优势和代价分别来自哪里；
3. 在什么条件下值得继续做 RTL，否则应停止。

本文件与
[ITERATION_FUSED_MATH.md](./ITERATION_FUSED_MATH.md)
和
[WORKLOADS_AND_BASELINES.md](./WORKLOADS_AND_BASELINES.md)
配套使用。

## 1. Symbols

### Problem Parameters

- `N`：向量维度 / 矩阵行数
- `\nu_i`：第 `i` 行的非零数
- `\bar\nu`：平均非零数
- `\nu_{\max}`：最大非零数
- `q`：目标 fractional digit 数
- `j_k^\star`：第 `k` 次迭代中，在线认证给出的实际有效 digit 深度

### Parallelism Parameters

- `R`：并行 row engines 数
- `P_{\text{mac}}`：conventional baseline 的 DSP MAC 并行度
- `B_r \triangleq \left\lceil \frac{N}{R} \right\rceil`：每轮要处理的 row batches 数

### Online Arithmetic Delays

- `\delta_\times`：传统 online multiplier 的 online delay
- `\delta_+`：传统 serial online adder 的 online delay
- `\delta_{\text{IP}}(\nu)`：integrated online inner product with bias 的 online delay
- `\alpha_{\text{AT}}(\nu)`：local adder-tree / PSCU pipeline 开销

沿用已有 integrated inner-product 文献，对 `\nu` 维行更新可取：

$$
\delta_{\text{IP}}(\nu)
\approx
\left\lceil \log_2 \frac{2\nu+1}{3} \right\rceil + 3
$$

而当 adder tree 每两层插一级 pipeline 时：

$$
\alpha_{\text{AT}}(\nu)
\approx
\left\lceil \frac{\lceil \log_2(\nu+1)\rceil}{2} \right\rceil - 1
$$

这不是唯一实现方式，但足以作为第一版统一口径。

## 2. Row-Level Initial Delay Models

## 2.1 Cascaded Online Row Update

传统 cascaded online row-update 对应：

$$
\text{online multiply}
\rightarrow
\text{online adder tree}
\rightarrow
\text{bias add}
$$

若以 balanced adder tree 计算 `\nu` 项求和，则 row-level 初始时延写成：

$$
\theta_{\text{row,cas}}(\nu)
=
1 + \delta_\times + 1 + (\delta_+ + 1)\left\lceil \log_2(\nu+1) \right\rceil
$$

其中：

- 第一个 `1`：输入寄存 / 对齐
- `\delta_\times`：乘法 online delay
- 第二个 `1`：乘法输出寄存/隔离
- 每级 `(\delta_+ + 1)`：serial online adder delay 加级间寄存

这就是旧论文里反复提到的 operator-boundary accumulation。

## 2.2 Integrated Online Row Update

对 integrated recurrence，第 `i` 行 row update 的初始时延写成：

$$
\theta_{\text{row,int}}(\nu)
=
1 + \delta_{\text{IP}}(\nu) + \alpha_{\text{AT}}(\nu) + 1
$$

它的特征是：

- 不再显式形成 `\nu` 个乘积输出；
- 不再有 multiplier 到 adder tree 的级联 online delay；
- 只保留 local partial-sum network 的 pipeline 开销。

因此 row-level 纯收益是：

$$
\Delta\theta_{\text{row}}(\nu)
=
\theta_{\text{row,cas}}(\nu) - \theta_{\text{row,int}}(\nu)
$$

这是 solver 级收益的第一部分。

## 2.3 Conventional FPGA Row Update

对 DSP-based conventional kernel，row-level 解析模型不再用 online delay，而用 pipeline fill + throughput 表示。

若一行有 `\nu` 个非零项，DSP MAC 并行度为 `P_{\text{mac}}`，则可写：

$$
\theta_{\text{row,conv}}(\nu, P_{\text{mac}})
=
\theta_{\text{mac,fill}}
+
\left\lceil \frac{\nu}{P_{\text{mac}}} \right\rceil
+
\theta_{\text{red}}
+
\theta_{\text{bias}}
$$

其中：

- `\theta_{\text{mac,fill}}`：DSP pipeline fill latency
- `\lceil \nu/P_{\text{mac}}\rceil`：吞吐主项
- `\theta_{\text{red}}`：reduction / tree latency
- `\theta_{\text{bias}}`：bias add latency

这条式子不是为了证明谁一定更快，而是明确：

**conventional baseline 的优势来自更强的单拍并行乘法；online baseline 的优势不在这里。**

## 3. Iteration-Level Cycle Models

设 `T_{\text{fmt}}` 表示 full-width reformat / pack-unpack / state writeback，`T_{\Delta}` 表示显式 delta 生成，`T_{\text{chk}}` 表示独立 convergence check，`T_{\text{restart}}` 表示下一轮 restart 或 flush。

## 3.1 B1: Cascaded Online Solver

若每个 row batch 都必须：

1. 做 cascaded online row update；
2. 把 `x^{(k+1)}` 落成 full-width；
3. 独立做 `d^{(k)} = x^{(k+1)} - x^{(k)}`；
4. 独立做 norm compare；
5. 再重新启动下一轮；

则第 `k` 轮总周期近似为：

$$
T_{\text{B1}}^{(k)}
\approx
B_r
\left(
\theta_{\text{row,cas}}(\bar\nu)
+
q
+
T_{\text{fmt}}
+
T_{\Delta}
+
T_{\text{chk}}
+
T_{\text{restart}}
\right)
$$

这里故意把 `q` 保留成显式项，因为 B1 默认必须把每轮结果算到 full target precision，不能利用 solver-level 认证提前停止。

## 3.2 Fused Online Solver

iteration-fused 设计中：

- row update 与 delta 共享同一条 online stream；
- norm-bounds engine 与 row update 同步消费 prefix digits；
- 若在第 `j_k^\star` 位已经满足收敛认证，则本轮不用再算到 `q` 位。

因此第 `k` 轮总周期写成：

$$
T_{\text{fused}}^{(k)}
\approx
B_r
\left(
\theta_{\text{row,int}}(\bar\nu)
+
j_k^\star
+
T_{\text{handoff}}
\right)
$$

其中 `T_{\text{handoff}}` 是把在线状态交给下一轮的小开销。它与 `T_{\text{fmt}} + T_{\Delta} + T_{\text{chk}} + T_{\text{restart}}` 属于同类项，但量级应明显更小。

## 3.3 B2: Conventional FPGA Solver

若 conventional FPGA kernel 也使用同一 stopping rule，但必须在 full-width fixed-point 向量上执行 delta 和 norm check，则第 `k` 轮可写为：

$$
T_{\text{B2}}^{(k)}
\approx
B_r^{\text{conv}}
\left(
\theta_{\text{row,conv}}(\bar\nu, P_{\text{mac}})
+
T_{\text{store}}
+
T_{\Delta,\text{conv}}
+
T_{\text{chk},\text{conv}}
\right)
$$

这里：

$$
B_r^{\text{conv}} \triangleq \left\lceil \frac{N}{R_{\text{conv}}} \right\rceil
$$

表示 conventional kernel 的 row-parallelism。后续比较时必须明确给定 `R` 与 `R_{\text{conv}}` 的公平关系。

## 4. Where the Solver-Level Gain Actually Comes From

将 `T_{\text{B1}}^{(k)}` 与 `T_{\text{fused}}^{(k)}` 相减：

$$
T_{\text{B1}}^{(k)} - T_{\text{fused}}^{(k)}
\approx
B_r
\left[
\underbrace{\theta_{\text{row,cas}}-\theta_{\text{row,int}}}_{\text{row-update integration}}
+
\underbrace{(q-j_k^\star)}_{\text{online certification}}
+
\underbrace{(T_{\text{fmt}}+T_{\Delta}+T_{\text{chk}}+T_{\text{restart}}-T_{\text{handoff}})}_{\text{iteration boundary removal}}
\right]
$$

这条式子给了论文叙事一个非常清楚的结构。solver 级收益不是单来源，而是三项叠加：

1. row-update integration；
2. convergence-aware digit-depth reduction；
3. iteration-boundary removal。

如果某个 workload 上三项里只有第一项显著，而后两项几乎没有收益，那么项目就会退化成“更好的 integrated inner product”，论文层级不够。

## 5. Certified-Digit Depth Model

`j_k^\star` 是整个方法的关键随机变量。其定义是：

$$
j_k^\star
\triangleq
\min\left\{
j \in \{1,\dots,q\}\;:\;
U^{(k,j)} \le \varepsilon_d
\right\}
$$

其中 `U^{(k,j)}` 是在线上界：

- PageRank 默认用 `L_1`
- Jacobi 默认用 `L_\infty`

并且：

$$
\varepsilon_d =
\begin{cases}
\eta \dfrac{1-\beta}{\beta}, & \text{PageRank} \\
\eta \dfrac{1-\rho}{\rho}, & \text{Jacobi-style}
\end{cases}
$$

因此：

- 当 `\beta \to 1` 或 `\rho \to 1` 时，`\varepsilon_d` 会变小；
- 这会把 `j_k^\star` 推近 `q`；
- iteration-fused 的认证收益会下降。

这说明：

**谱半径越接近 1，solver-level certification 的收益越小。**

这个现象必须在后续软件 sweep 中显式验证。

## 6. Dense vs Sparse Trend

### 6.1 Dense Regime

若 `\bar\nu \approx N`，则：

$$
\theta_{\text{row,cas}} = O(\log N),\qquad
\theta_{\text{row,int}} = O(\log N)
$$

两者都只按 `\log N` 增长，但 conventional baseline 可能凭 `P_{\text{mac}}` 在吞吐主项上很强。因此 dense regime 下 online 方法要赢，必须明显依赖：

- 较小的 `j_k^\star`
- 较大的 iteration-boundary savings

仅靠 row-update integration 一般不够。

### 6.2 Sparse Regime

若矩阵稀疏，且每行平均非零数 `\bar\nu \ll N`，则 online 方法更有机会成立，因为：

1. `\theta_{\text{row,int}}(\bar\nu)` 本身较小；
2. global interconnect 和 storage width 变成更重要的代价；
3. digit-serial 的低宽度优势开始显现。

因此 solver 级主实验更应偏向 sparse / structured sparse，而不是 dense-only。

## 7. Storage and Buffering Model

对每次迭代，关心的不是输入矩阵和向量本身，而是**额外中间状态**。

## 7.1 B1 / B2 Intermediate State

传统结构至少显式保存：

1. `x^{(k)}`；
2. `x^{(k+1)}`；
3. `d^{(k)}`；
4. convergence-check 所需的全宽比较输入。

若每个元素 full-width 为 `W` bit，则额外中间状态规模近似：

$$
M_{\text{B1/B2}}
\gtrsim
2NW + NW
=
3NW
$$

这里没有把额外 pack/unpack、FIFO 和 tree scratchpad 算进去。

## 7.2 Fused Intermediate State

iteration-fused 设计中，最理想的情况不是完整保存 `x^{(k+1)}` 和 `d^{(k)}` 两份 full-width vector，而是只保存：

1. 供下一轮使用的 online state；
2. norm-bounds engine 的少量前缀统计；
3. 必要的 row handoff buffer。

因此中间状态的目标量级应是：

$$
M_{\text{fused}}
\approx
N W_{\text{state}} + M_{\text{bounds}} + M_{\text{handoff}}
$$

其中 `W_{\text{state}}` 不一定等于 full result width `W`；它可能对应 online internal slice width 或 delayed prefix buffer 宽度。

这个模型的重点不是现在就报一个具体数字，而是后续必须证明：

$$
M_{\text{fused}} < M_{\text{B1/B2}}
$$

否则 iteration-boundary removal 的一大优势就不成立。

## 8. Resource Proxy Model

第一版资源模型先不求绝对精确，只看主导项。

## 8.1 B1: Cascaded Online

资源近似：

$$
\text{LUT}_{\text{B1}}
\sim
R \cdot
\left(
L_{\times,\text{online}}
+
L_{\text{tree}}
+
L_{\Delta}
+
L_{\text{chk}}
\right)
$$

$$
\text{DSP}_{\text{B1}} \approx 0
$$

主要问题是 online primitive 级联和 boundary 逻辑。

## 8.2 Fused Online

资源近似：

$$
\text{LUT}_{\text{fused}}
\sim
R \cdot
\left(
L_{\text{row,int}}
+
L_{\text{bounds}}
+
L_{\text{handoff}}
\right)
$$

$$
\text{DSP}_{\text{fused}} \approx 0
$$

如果 fused 结构真的成功，则应满足：

$$
L_{\text{row,int}} + L_{\text{bounds}} + L_{\text{handoff}}
\lesssim
L_{\times,\text{online}} + L_{\text{tree}} + L_{\Delta} + L_{\text{chk}}
$$

即使 LUT 不一定更小，至少不应因为 solver-level 融合而爆炸。

## 8.3 B2: Conventional FPGA

资源近似：

$$
\text{DSP}_{\text{B2}}
\sim
R_{\text{conv}} \cdot P_{\text{mac}}
$$

$$
\text{LUT}_{\text{B2}}
\sim
R_{\text{conv}} \cdot
\left(
L_{\text{red,conv}} + L_{\Delta,\text{conv}} + L_{\text{chk,conv}}
\right)
$$

所以 conventional baseline 的主优势是 DSP 并行乘法，主代价是 DSP 数量和中间 full-width 数据流。

## 9. Workload-Specific Instantiations

## 9.1 PageRank

对 `W1`：

$$
G = \beta M,\qquad \|G\|_1 = \beta
$$

因此：

$$
\varepsilon_d^{\text{PR}} = \eta \frac{1-\beta}{\beta}
$$

其影响是：

- `\beta` 越大，越难提前认证；
- 但 `M` 与 `c` 自然有界，数值规约最简单；
- 很适合做第一版 closed-loop 仿真。

PageRank 的核心趋势实验应当 sweep：

- `N`
- 平均出度 `\bar\nu`
- `\beta`
- 误差阈值 `\eta`

## 9.2 Jacobi

对 `W2`：

$$
G = -D^{-1}(L+U),\qquad c=D^{-1}b
$$

若严格对角占优，则通常能建立：

$$
\|G\|_\infty \le \rho < 1
$$

因此：

$$
\varepsilon_d^{\text{J}} = \eta \frac{1-\rho}{\rho}
$$

Jacobi 的核心趋势实验应当 sweep：

- `N`
- 稀疏度 / 带宽
- `\rho`
- 误差阈值 `\eta`

Jacobi 的价值在于检验：

- 系数带符号时 fused online 是否仍稳定；
- online certification 是否仍有收益；
- 结构化 sparse 情况下 streaming 优势是否比 PageRank 更明显。

## 10. Go / No-Go Conditions from the Model

在进入软件 simulator 和 RTL 之前，解析模型给出三个明确门槛。

### Gate 1: Certification Must Matter

至少在一类 workload 上，必须出现：

$$
\mathbb{E}[j_k^\star] \ll q
$$

否则 solver 级创新只剩 row-update integration，不足以支撑完整论文。

### Gate 2: Boundary Savings Must Matter

必须存在：

$$
T_{\text{fmt}} + T_{\Delta} + T_{\text{chk}} + T_{\text{restart}}
\gg
T_{\text{handoff}}
$$

否则 iteration-fused 只是换了写法，没有本质工程收益。

### Gate 3: Conventional Comparison Must Still Be Defensible

至少在一个 workload 上，必须能清楚说明相对 `B2` 的优势来自哪一项：

- `DSP`
- `intermediate storage`
- `cycles to certified convergence`
- `streaming width / interconnect`

如果只能证明：

$$
\text{fused online} > \text{cascaded online}
$$

而不能解释对 `B2` 的意义，那么项目仍然太窄。

## 11. Immediate Next Step

这份解析模型文档之后，后续顺序应固定为：

1. 用软件模型实例化 `j_k^\star` 分布；
2. 对 PageRank / Jacobi 做参数 sweep；
3. 验证三条 gate 是否成立；
4. 成立后再进入 RTL。
