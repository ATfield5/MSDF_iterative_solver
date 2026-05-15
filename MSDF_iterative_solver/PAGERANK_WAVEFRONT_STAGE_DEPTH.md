# PageRank Wavefront Stage Depth

本文档固定 PageRank online iteration wavefront 应该级联多少级。目标是把“高位 digit 经过 online delay 后立刻进入下一轮”落成可实现的 K-stage 结构，而不是继续做 full-iteration barrier。

## Core Idea

传统 barrier 执行是：

$$
x^{(k)}
\rightarrow
x^{(k+1)}_{\text{full word}}
\rightarrow
x^{(k+2)}_{\text{full word}}
$$

wavefront 执行是：

$$
x^{(k)}_j
\rightarrow
x^{(k+1)}_{j-\delta}
\rightarrow
x^{(k+2)}_{j-2\delta}
$$

其中 $\delta$ 是 online delay。只要第 $k+1$ 轮的某个 committed digit 已经有效，就不应等待整 word 完成，而应直接送入下一级 iteration stage。

## Cycle Model

设：

- $D$：committed state digit width；
- $\delta$：第一个可用输出 digit 的 online delay；
- $B$：full-wait 方案每轮额外 barrier / commit / restart 开销；
- $F$：级间寄存、ready/valid、routing FIFO 的额外延迟；
- $K$：级联 iteration stages。

full-wait baseline：

$$
T_{\mathrm{full}}(K)=K(D+\delta+B)
$$

K-stage digit-stream wavefront：

$$
T_{\mathrm{wave}}(K)=D+K\delta+(K-1)F
$$

加速比：

$$
S(K)=
\frac{K(D+\delta+B)}
{D+K\delta+(K-1)F}
$$

这个模型的含义很直接：K 越大，full-wait 要重复支付 $D+B$，而 wavefront 只主要重复支付 $\delta$。但硬件面积大约随 K 线性增长，因此 K 不能无限加。

## Current Parameters

当前 strict fractional PageRank checkpoint 使用：

| parameter | value | source |
| --- | ---: | --- |
| $D$ | 14 | `BIT_WIDTH=11`，`DATA_WIDTH=14` |
| $\delta$ | about 10 | prior operator first fractional output observed near feed index 10 |
| $B$ | about 4 | full-wait iteration barrier/control estimate |
| $F$ | 1 for first RTL sizing | reserve one register/FIFO stage between iteration stages |

对应自动模型入口：

```bash
conda run -n qas python MSDF_iterative_solver/model_wavefront_stage_depth.py \
  --data-width 14 \
  --online-delay 10 \
  --boundary 4 \
  --inter-stage-delay 1 \
  --max-stages 16 \
  --max-practical-stages 8
```

生成报告：

```text
MSDF_iterative_solver/generated/wavefront_stage_depth_model.md
```

## Stage Count Decision

当前推荐：

$$
\boxed{K=4\text{ for first RTL}}
$$

原因：

- K=2 只能证明局部 handoff，不足以形成强论文级 pipeline claim。
- K=4 已经能展示多轮 iteration wavefront，并且模型加速接近 $2\times$。
- K=5 在 $F=1$ 的保守模型下边际收益低于 5%，但资源继续线性增加。
- K=8 可作为 U55C 资源足够时的扩展 sweep，不建议作为第一版主线。
- K 不应超过实验中固定展开的 PageRank iteration count；如果模型只跑 4 轮，K=8 没有实际意义。

当前模型结果摘要：

| K | model speedup, F=1 |
| ---: | ---: |
| 2 | 1.600x |
| 3 | 1.826x |
| 4 | 1.965x |
| 5 | 2.059x |
| 8 | 2.218x |

## Current RTL Sweep

当前还补了一组 global-source PageRank `ROW_DATAPATH_MODE=4` 的实际 RTL cycle sweep，入口为：

```bash
conda run -n qas python MSDF_iterative_solver/run_pagerank_wavefront_stage_sweep.py
```

生成报告：

```text
MSDF_iterative_solver/generated/pagerank_wavefront_stage_sweep.md
```

当前 measured 结果：

| K stages | total cycles | issue cycles | cert-wait cycles | cycles / fused iter |
| ---: | ---: | ---: | ---: | ---: |
| 2 | 121 | 11 | 27 | 60.50 |
| 3 | 128 | 11 | 34 | 42.67 |
| 4 | 135 | 11 | 41 | 33.75 |

这个 measured sweep 说明级联后的 `issue_cycles` 没有按 $K\cdot D$ 增长，而是保持为一次 `DATA_WIDTH=11` 的输入流；每多一级只增加后端 pipeline / certification wait。也就是说，高位 digit 经过 online delay 后确实已经进入下一级，而不是等待 full word 后重启下一轮。

因此工程顺序应为：

1. 先实现 K=4 strict fractional PageRank wavefront；
2. 跑同 fixture 功能和 cycle；
3. 再做 K=2/4/8 sweep；
4. 最后根据 U55C route 结果决定论文主表用 K=4 还是 K=8。

当前第 1-2 步已经完成 standalone strict prior-fractional checkpoint：

```bash
conda run -n qas python MSDF_iterative_solver/run_prior_fractional_wavefront_sweep.py
```

生成报告：

```text
MSDF_iterative_solver/generated/prior_fractional_wavefront_sweep.md
```

结果摘要：

| K stages | total cycles | captured digits | cycles / fused iter | overlap flags |
| ---: | ---: | ---: | ---: | --- |
| 2 | 36 | 14 | 18.00 | `1` |
| 3 | 46 | 14 | 15.33 | `11` |
| 4 | 56 | 14 | 14.00 | `111` |

该结果使用原始 `MSDF_MUL_ADD_8`，并和 `pagerank32_global_prior_fractional` golden 做 `<=4 LSB` 对齐。它证明 strict prior operator 可以做 stage-to-stage digit wavefront，但还不是 runtime-shell 结果。

## Relation to Existing RTL

现有 `ROW_DATAPATH_MODE=4` / `iter_wavefront_superstep_cluster_state_top` 已经是 K-stage wavefront 原型，但它基于当前 solver-native bring-up row engine，不是 strict prior fractional contract。

当前 strict fractional 路线已经新增 standalone K-stage 版本：

```text
prior digit-stream stage 0
-> prior digit-stream stage 1
-> prior digit-stream stage 2
-> prior digit-stream stage 3
```

每一级必须有独立 `MSDF_MUL_ADD_8` residual state，不能复用同一个 prior operator instance。否则一个 instance 会同时保存不同 iteration 的 residual，数学上不成立。

## Acceptance Criteria

K=4 standalone RTL 已满足：

- 使用 `pagerank32_global_prior_fractional` fixture；
- final stage state 与 P4 fractional golden 在 `<=4 LSB` tolerance 内一致；
- counters 中 `issue_cycles` 不再按 `K * D` 增长，而接近 `D + pipeline_fill`；
- 相比 P3 prior digit-stream single-stage 的 `215 cycles` 有明显下降。

runtime acceptance 已完成：

- strict prior K=4 wavefront 已接入 runtime shell，本文统一称为 `P3`；
- last-stage L1 certification 已按 $x^{(k+4)}-x^{(k+3)}$ 接入，避免把 4 个 fused iteration 的总变化量误当收敛 residual；
- 同 shell 对比见 `generated/pagerank_fractional_same_scope_eval.md`：P3 为 `compute=70 / issue=14 / cert_wait=56 / observed_total=150`，P4 timing-clean conventional fractional 为 `compute=44 / issue=4 / cert_wait=40 / observed_total=143`。性能主表只使用 `compute=issue+cert_wait`，配置/state preload/window load 单独剥离。

当前结论：strict prior K=4 wavefront 证明了原始 online operator 的 committed digit 可以直接级联，并把 P3 prior digit-stream single-stage 从 `168` compute cycles 压到 `70` compute cycles；但它还没有击败 P4 timing-clean conventional fractional 的 `44` compute cycles。因此下一步不能只扩 K，而应拆解 operator feed/capture/flush、last-delta 和 certification 等核心等待，并评估 P3 是否能在资源/功耗上给出足够硬的优势。


## Continuous Feedback Checkpoint

固定 K-stage super-step 之后，当前新增 continuous feedback checkpoint：

```bash
conda run -n qas python MSDF_iterative_solver/run_prior_fractional_feedback_eval.py
```

生成报告：

```text
MSDF_iterative_solver/generated/prior_fractional_feedback_eval.md
```

该 checkpoint 仍然使用原始 `MSDF_MUL_ADD_8`，不使用 PageRank 4-term experimental core。结构为：

$$
x^{(k)}\rightarrow x^{(k+K)}\rightarrow \text{feedback FIFO}\rightarrow x^{(k+2K)}
$$

当前结果摘要：

| case | K | target supersteps | total cycles | final supersteps | feedback stall | converged stage |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| K2 feedback | 2 | 2 | 74 | 2 | 0 | n/a |
| K4 feedback | 4 | 2 | 101 | 2 | 0 | observed stage 0 in second super-step |
| K4 stage-L1 stop | 4 | 2 | 41 | 0 | 0 | 1 |

工程含义：

- feedback FIFO 存的是 committed digit packet，不是 full-word vector；
- 每个 stage 完成一个 word 后必须做 local clear，因为原始 `MSDF_MUL_ADD_8` 的 residual state 不能跨 PageRank operation 复用；
- K=2 需要检查下游 stage ready，否则 stage0 的下一段输出可能早于 stage1 清空；
- stage-wise L1 已经能发现最早收敛 stage，后续接 runtime shell 时应把它作为 P3 的 stop/control 入口。

4-term PageRank fractional core 现在只保留为 experimental resource-cleanup，不作为本文主线，也不进入默认 P3 结果。
