# PageRank Same-Scope Runtime Checkpoint

本文档记录当前 PageRank 同口径实验入口。它不是最终论文结果，而是把应用从 Jacobi stress fixture 切换到 PageRank 的第一版可执行 checkpoint。

## Fixture

生成脚本：

```bash
conda run -n qas python MSDF_iterative_solver/make_pagerank_runtime_vectors.py
```

默认参数：

| 参数 | 值 |
| --- | --- |
| `N` | 32 |
| `NUM_CLUSTERS` | 8 |
| `NUM_ROWS/cluster` | 4 |
| `DEGREE` | 4 |
| source model | global `src_id`, no halo-window |
| graph | bounded-degree circulant |
| state init | zero |
| certification | digit-final global L1(delta) |
| RTL precision checkpoint | `BIT_WIDTH=8`, `DATA_WIDTH=11`, `FRAC_BITS=2` |

当前 graph topology 保留 PageRank 的静态全局 source 语义：

$$
r_i^{(k+1)}=(1-\beta)v_i+\sum_t \beta\frac{1}{outdeg(src_t)}r_{src_t}^{(k)}
$$

但生成器为了先对接现有 rail-coded integer runtime bridge，会把系数和 teleport seed 量化到当前 RTL contract。这个 checkpoint 用来验证调度、global source replay、L1 decision 和同 shell baseline，不作为最终 32-bit fractional PageRank 数值结果。

## Implemented Entries

| ID | 当前入口 | 说明 |
| --- | --- | --- |
| P2-proxy | `tb_iter_dense_runtime_pagerank32_global_full_digit_multi.v` | full-digit bridge，保留 full-word state commit，是 same-shell prior-online 的临时 proxy |
| P2-adapter | `tb_iter_prior_online_mma8_row_kernel.v` | 将当前 4-term row digit interface 映射到原始 `MSDF_MUL_ADD_8`，尚未接 runtime shell |
| P2-word | `tb_iter_prior_online_mma8_word_assembler.v` | 显式封装原始 operator 的 enable/flush/output flag 行为，产出 full-word rail result |
| P2-cluster | `tb_iter_prior_online_mma8_row_cluster_delta_cert.v` | row-parallel prior operator wrapper，产出 full-word row results、delta bounds 和 cluster certification |
| P2-runtime smoke | `tb_iter_dense_runtime_pagerank32_global_prior_online_multi.v` | 原始 operator wrapper 已接入同一个 PageRank runtime/state/controller shell，当前使用 relaxed numerical check |
| P2-fractional | `tb_iter_dense_runtime_pagerank32_global_prior_fractional_multi.v` | prior-compatible fractional fixture，`BIT_WIDTH=11/DATA_WIDTH=14`，fraction-only capture，`<=4 LSB` online rounding tolerance |
| P2-proxy fractional | `tb_iter_dense_runtime_pagerank32_global_full_digit_fractional_multi.v` | full-digit digit-serial bridge，同一 fractional fixture，per-term rounded product shift |
| P3-prior-stream fractional | `tb_iter_dense_runtime_pagerank32_global_prior_digit_stream_fractional_multi.v` | 原始 prior operator 输出 digit 直接写入 digit-stream state bank，移除 P2 full-word output assembler |
| P3-mode3 | `tb_iter_dense_runtime_pagerank32_global_solver_native_multi.v` | solver-native digit-stream state path |
| P3-mode4 | `tb_iter_dense_runtime_pagerank32_global_wavefront_superstep.v` | K-stage digit-stream wavefront super-step |
| P4 | `tb_iter_dense_runtime_pagerank32_global_conv_multi.v` | conventional fixed-point DSP-MAC shell |
| P4-fractional | `tb_iter_dense_runtime_pagerank32_global_conv_fractional_multi.v` | same fixture as P2-fractional；DSP-MAC 执行 `round((state*coeff)/2^DATA_WIDTH)` |

P2 已经完成 runtime-shell smoke，但还不能写成最终公平数值 baseline：当前 smoke 放宽了 state/golden 精确比较，只验证原始 operator wrapper 能进入同一个 PageRank graph、loader、state bank、controller 和 L1 report。下一步需要把原始 operator 的 signed-digit / scaling contract 与 PageRank fixed-point golden 对齐。

## L1 Certification

PageRank v1 不使用 Jacobi `block_H`。每个 cluster 先计算 local L1(delta)：

$$
L_{1,c}^{(k)} = \sum_{i\in c}|r_i^{(k+1)}-r_i^{(k)}|
$$

runtime top 再做全局汇总：

$$
L_1^{(k)}=\sum_c L_{1,c}^{(k)}
$$

$$
\text{converged} = \left[L_1^{(k)} \le \eta\right]
$$

RTL 实现上复用现有 `online_row_cluster_block_cert`，但将 `BLOCK_SIZE=1`，所有 block weight 设为 1，使 cluster `max_error` 等于 local L1(delta)。`iter_dense_small_ping_pong_top` 新增 `global_l1_cert=1` 后，对所有 cluster 的 `max_error` 求和并生成 iteration-level converged/continue。

## Current Limitations

- 还没有完成 P1 原始 RTL same-device rerun；
- 还没有完成真正 P2：原论文 integrated online operator + runtime shell；
- 当前 PageRank RTL fixture 是 bounded-degree graph，不支持 arbitrary-degree CSR；
- 当前 online full-digit bridge 使用整数 rail recurrence，不等价于最终 32-bit fractional PageRank datapath；
- 当前报告先跑 Icarus 功能，不包含 U55C route 数据。

这些限制必须在论文表格中单独标注，不能把当前 checkpoint 写成最终主结果。

## Icarus Checkpoint

本轮生成：

```bash
conda run -n qas python MSDF_iterative_solver/make_pagerank_runtime_vectors.py --num-iters 4
```

生成的 global L1(delta)：

| iteration | global L1(delta) | converged |
| ---: | ---: | ---: |
| 0 | 64 | 1 |
| 1 | 160 | 1 |
| 2 | 544 | 0 |
| 3 | 2080 | 0 |

Targeted Icarus 结果。性能相关行使用 `compute cycles = issue + cert_wait`；配置、state preload、window load 和 testbench/controller overhead 不进入该列。

| entry | PASS | compute cycles | issue cycles | cert_wait cycles | observed total | notes |
| --- | ---: | ---: | ---: | ---: | ---: | --- |
| P1 original `MSDF_MUL_ADD_8` smoke | yes | n/a | n/a | n/a | n/a | finite wrapper around original RTL, `out=74` |
| P2 row-kernel adapter smoke | yes | n/a | n/a | n/a | n/a | maps 4-term row digit interface to original 8-lane operator, `out=83` |
| P2 word assembler smoke | yes | n/a | n/a | n/a | n/a | captures 11 output digits, `cycles=22`, `sum_p=010`, `sum_n=004` |
| P2 cluster wrapper smoke | yes | n/a | n/a | n/a | n/a | row-parallel wrapper, `cycles=24`, `max_error=8` |
| P2 runtime-shell smoke | yes | 108 | 4 | 104 | 207 | relaxed numerical checks; proves scheduling/state/cert integration only |
| P2 prior-compatible fractional | yes | 128 | 4 | 124 | 227 | `BIT_WIDTH=11`, `DATA_WIDTH=14`, fraction-only capture, `<=4 LSB` tolerance |
| P2-proxy full-digit fractional | yes | 136 | 56 | 80 | 183 | digit-serial bridge，per-term rounded product shift，same fractional fixture |
| P3 prior digit-stream fractional | yes | 168 | 56 | 112 | 215 | prior operator output digit 直接 commit；`<=4 LSB` tolerance |
| P3 prior K=4 wavefront standalone | yes | 56 | 14 captured | n/a | 56 | original `MSDF_MUL_ADD_8` 4-stage direct digit cascade；excludes runtime loader/cert |
| P4 conventional fractional | yes | 36 | 4 | 32 | 135 | same `pagerank32_global_prior_fractional` fixture，DSP-MAC rounded product shift |
| P2-proxy full-digit bridge | yes | 112 | 44 | 68 | 171 | full-word boundary reference |
| P3-mode3 solver-native | yes | 124 | 44 | 80 | 183 | digit-stream state path |
| P3-mode4 wavefront K=4 | yes | 52 | 11 | 41 | 135 | one super-step checks iteration 3 golden |
| P4 conventional DSP-MAC | yes | 36 | 4 | 32 | 135 | same graph / same loader / same L1 controller |

当前数字只用于功能和链路拆解。P2 runtime-shell smoke 已接入原始论文 operator wrapper，但还没有完成严格数值等价；当前 PageRank fixture 仍是 `DATA_WIDTH=11` bring-up 配置，所以不能把这张表作为最终论文性能表。

PageRank global-source mode4 已补 K-stage sweep，报告见 [`generated/pagerank_wavefront_stage_sweep.md`](./generated/pagerank_wavefront_stage_sweep.md)：

| K stages | total cycles | issue cycles | cert_wait cycles | cycles / fused iter |
| ---: | ---: | ---: | ---: | ---: |
| 2 | 121 | 11 | 27 | 60.50 |
| 3 | 128 | 11 | 34 | 42.67 |
| 4 | 135 | 11 | 41 | 33.75 |

这组结果的意义是：级联深度增加时，输入 issue 仍是一次 `DATA_WIDTH=11` digit stream，而不是 `K*DATA_WIDTH`；额外成本主要来自级间/认证等待。因此当前实现已经验证“高位 digit 经过 online delay 后进入下一轮”的结构事实。第一版应固定 `K=4`，因为它匹配当前 4 轮 PageRank golden，并且足以展示 solver-level wavefront；`K=8` 要等扩展 fixture 和 U55C route 后再判断。

本轮进一步补了 strict prior-fractional standalone wavefront，报告见 [`generated/prior_fractional_wavefront_sweep.md`](./generated/prior_fractional_wavefront_sweep.md)。该入口直接使用原始 `MSDF_MUL_ADD_8`，不经过 solver-native row engine：

| K stages | total cycles | captured digits | cycles / fused iter | overlap flags |
| ---: | ---: | ---: | ---: | --- |
| 2 | 36 | 14 | 18.00 | `1` |
| 3 | 46 | 14 | 15.33 | `11` |
| 4 | 56 | 14 | 14.00 | `111` |

这组 standalone 结果说明：原始 prior operator 的 committed fraction digit 可以直接喂入下一轮 PageRank stage，并且最终 state 与 `pagerank32_global_prior_fractional` golden 在 `<=4 LSB` 内一致。它还不是 same-shell runtime 结果，因为暂时没有计入 template loader、state bank、L1 certification 和 iteration controller；下一步要把它包装为 runtime mode，才能和 P4 conventional fractional 做最终公平比较。

## Prior Operator Semantics Finding

本轮新增 `tb_iter_prior_online_mma8_semantics`，确认原始 `MSDF_MUL_ADD_8` 不是当前 conventional baseline 的普通 integer MAC。典型输出：

| state | coeff | bias | output |
| ---: | ---: | ---: | ---: |
| 0 | 0 | 1 | 1 |
| 1 | 1 | 0 | 0 |
| 1024 | 1024 | 0 | 256 |
| 1024 | 512 | 0 | 128 |
| 512 | 512 | 0 | 64 |

另外，原始 `vector_append` 内部状态需要每个 operation reset；`iter_prior_online_mma8_word_assembler` 已补 per-operation reset。因此 P2 relaxed smoke 从 `total=191 / cert_wait=88` 变为 `total=207 / cert_wait=104`，这是更接近原始 operator 使用方式的结果。

结论：严格 P2 baseline 不能直接使用当前 integer PageRank golden。因此新增了 `pagerank32_global_prior_fractional` fixture：系数/bias 按 fraction stream 量化，P2 采用 fraction-only capture，Python golden 使用 round-to-nearest product model，并对原始 online selection/rounding 保留 `<=4 LSB` 容差。该入口现在已经 PASS。

本轮同时补齐了 P4 strict same-fixture 对照。`conv_signed_row_update_delta_slice(_pipe)` 新增 `product_shift` 参数，P4-fractional 使用同一个 `pagerank32_global_prior_fractional` fixture，并在 DSP-MAC 内执行：

$$
\text{product}_{\text{P4-frac}} =
\operatorname{round}\left(\frac{x\cdot a}{2^{DATA\_WIDTH}}\right)
$$

自动报告入口为：

```bash
conda run -n qas python MSDF_iterative_solver/run_pagerank_fractional_same_scope_eval.py
```

当前严格同 fixture 结果为：

| comparison | P2 prior-online fractional | P4 conventional fractional |
| --- | ---: | ---: |
| compute cycles | 128 | 36 |
| observed total | 227 | 135 |
| cert_wait cycles | 124 | 32 |
| issue cycles | 4 | 4 |

另外，full-digit bridge 也已经切到同 fixture：`P2-proxy full-digit fractional = compute=136 / observed_total=183 / issue=56 / cert_wait=80`。该入口严格匹配 golden，但仍保留 full-word/iteration boundary，因此只能作为数值参考层。

本轮新增 `P3-prior-stream fractional = compute=168 / observed_total=215 / issue=56 / cert_wait=112`。它复用原始 `MSDF_MUL_ADD_8`，但把 prior output digit 直接写入 digit-stream state bank，移除了 P2 的 full-word output assembler。当前它仍慢于 P2-proxy 和 P4，说明瓶颈主要不在 output assembly，而在 prior operator 的 feed/capture/flush 延迟和 runtime 仍按 full-digit scheduler 发起 56 个 digit issue 周期。

这个结果说明：只把原论文 integrated online operator 接到同一个 PageRank runtime shell 并不足以打过干净的 DSP-MAC baseline。后续论文主线必须证明 solver-level digit-stream / iteration-boundary fusion 相比 P4 也能减少实际 cycles、资源或能耗，而不是只相对 P2 prior-online 更好。
