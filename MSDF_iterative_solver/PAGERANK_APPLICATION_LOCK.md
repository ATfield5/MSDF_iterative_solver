# PageRank Application Lock

本文件固定后续论文应用场景：主应用锁定为 PageRank-style fixed-point graph propagation。Jacobi 继续作为 RTL 数值压力测试和 signed-coefficient affine fixture，不再作为 headline application。

## Decision

主问题写成：

$$
r^{(k+1)}=\beta M r^{(k)}+(1-\beta)v
$$

其中：

$$
0<\beta<1,\quad M\ge 0,\quad \|r^{(k)}\|_1=1,\quad v_i\ge 0,\quad \|v\|_1=1
$$

这正好落在当前 online/MSDF 主线需要的 affine fixed-point family：

$$
x^{(k+1)}=Gx^{(k)}+c
$$

但比 generic Jacobi 更适合当前定点核心，因为 PageRank 的状态、系数和输出天然有界。默认定点设计可以围绕：

$$
0\le r_i^{(k)}\le 1
$$

而不是为可能超过 1 的 signed Jacobi state 预留更宽整数位。

## Why PageRank Fits The Current Core

1. **数值范围友好。** PageRank rank vector 是概率分布，主状态可以保持在 `[0,1]`。这和当前 MSB-first fixed-point / rail datapath 更匹配，减少额外整数位、饱和和动态范围扩展。

2. **系数非负且小。** 对常见列随机转移矩阵：

$$
G_{ij}=\beta M_{ij}
$$

通常满足：

$$
0\le G_{ij}\le \beta <1
$$

当前 fixed-coefficient template、signed-digit coefficient contribution 和 online adder tree 可以直接复用，其中负 rail 路径主要作为通用性保留。

3. **没有 Jacobi 的对角除法语义。** Jacobi 来自：

$$
x_i^{(k+1)}=\frac{1}{a_{ii}}\left(b_i-\sum_{j\ne i}a_{ij}x_j^{(k)}\right)
$$

即使离线吸收到系数里，论文叙事仍容易被“矩阵缩放后 state 可能大于 1”干扰。PageRank 没有这个问题。

4. **wavefront super-step 仍然有效。** PageRank 是 repeated affine propagation：

$$
r^{(k)}\rightarrow r^{(k+1)}\rightarrow r^{(k+2)}\rightarrow \cdots
$$

当前 mode4 的核心收益正是把多次 iteration 的 digit issue window 融合成一个 super-step。这个机制对 PageRank 和 Jacobi 都成立。

5. **halo 可以解释为 graph partition boundary。** 对分区后的图，每个 cluster 负责一组 vertices。若一个 vertex 的入邻居来自相邻 partition，就需要读取 neighbor partition 的 rank digit；这就是 PageRank 场景下的 halo。当前 `previous/current/next cluster` halo-window 可作为第一版 partitioned / locality-preserving graph benchmark。

## What Must Change From The Jacobi Fixture

当前 `jacobi32_*` RTL 测试不是最终 PageRank workload，它只是 affine solver 的结构 proxy。切到 PageRank 后至少要补三件事。

### 1. PageRank Template Generator

当前 template 字段已经能表达 fixed-degree sparse row update：

$$
x_i^{(k+1)}=\sum_{t=0}^{D-1}c_{i,t}x_{src(i,t)}^{(k)}+b_i
$$

PageRank 需要生成：

$$
r_i^{(k+1)}=\sum_{j\in In(i)}\beta\frac{1}{outdeg(j)}r_j^{(k)}+(1-\beta)v_i
$$

工程上第一版使用 bounded-degree / padded template：

$$
D_{\max}=4\ \text{or}\ 8
$$

高入度 vertex 后续用 edge tiling 或多 template row 累加处理，不在第一版直接承诺 arbitrary-degree graph。

### 2. PageRank Certification

Jacobi 当前使用 `block_H` certification。PageRank 更自然的 stopping rule 是 `L1` residual：

$$
d^{(k)}=r^{(k+1)}-r^{(k)}
$$

若：

$$
\|d^{(k)}\|_1\le \epsilon\frac{1-\beta}{\beta}
$$

则：

$$
\|r^\star-r^{(k+1)}\|_1\le \epsilon
$$

所以 PageRank 最终认证路径不应主打 `block_H`，而应实现 cluster-local `L1` delta accumulation + global reduction。当前 `block_H` 仍可作为 affine solver checkpoint，但不是 PageRank 论文主认证核。

### 3. Dangling Node Handling

真实 PageRank 常有 dangling nodes。标准处理会引入每轮全局 dangling mass：

$$
s^{(k)}=\sum_{j\in D}r_j^{(k)}
$$

并加入：

$$
\beta\frac{s^{(k)}}{n}e
$$

这会增加一个全局 reduction。第一版论文路线可以采用两种保守路线：

- 先使用无 dangling 或预处理后的 benchmark graph，验证核心 datapath。
- 后续扩展 dangling-mass reduction，把它作为 PageRank system extension，而不是第一版核心创新。

## Current RTL Reuse

可直接复用：

- runtime loader / template bank / cert parameter bank
- fixed-degree source replay
- registered halo-window replay
- solver-native digit-stream row engine
- digit-stream state ping-pong bank
- mode4 wavefront super-step
- binary I/O wrapper

需要替换或新增：

- `make_pagerank_runtime_vectors.py`
- PageRank graph-to-template compiler
- PageRank `L1` delta certification path
- PageRank-specific reports and baseline tables

## Baseline Policy

主 baseline 应从 Jacobi DSP-MAC runtime 改成 PageRank-equivalent runtime：

| baseline | role |
| --- | --- |
| `B0`: software PageRank reference | double / high-precision correctness oracle |
| `B1`: conventional fixed-point FPGA PageRank | full-word sparse row update + ping-pong state + same graph partition |
| `B2`: prior integrated-online PageRank operator | operator-level online baseline, matching the prior paper level |
| `Ours`: digit-stream wavefront PageRank | solver-level iteration-fused online/MSDF datapath |

公平口径必须保持：

- same graph
- same fixed-point precision
- same partition and degree padding
- same convergence threshold
- same maximum iteration count
- same U55C 5 ns route target

## Claim Boundary

可以主张：

$$
\text{PageRank exposes a bounded, nonnegative, repeated affine propagation pattern that matches digit-stream wavefront execution.}
$$

不应主张：

- 当前 `jacobi32_*` 测试已经是 PageRank；
- 当前 halo-window 支持任意 Web graph；
- 当前 `block_H` certification 是最终 PageRank certification；
- MSDF/online arithmetic 对所有 sparse linear solvers 都更优。

## Next Engineering Steps

1. 写 PageRank vector generator，先支持 bounded-degree graph 和 fixed partition。
2. 生成 `pagerank32_*` runtime memh，与现有 `jacobi32_*` fixture 同规模：`8 clusters x 4 rows`。
3. 新增 PageRank conventional runtime baseline，复用同一个 loader/state/halo/controller。
4. 新增 PageRank `L1` delta certification，先做 full-width/digit-final 版本，再考虑 prefix form。
5. 复跑 mode3/mode4 cycle、U55C route、dynamic energy proxy。
