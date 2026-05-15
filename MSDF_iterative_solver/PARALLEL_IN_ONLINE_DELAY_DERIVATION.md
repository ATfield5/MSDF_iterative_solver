# Parallel-In Online Delay Derivation

本文档记录 P3-SP 的数学合同。目标是沿用《基于高效集成在线算术的高维线性系统计算.pdf》中 Eq. (5)-(31) 的推导口径，把原始 serial-serial integrated online inner product 推广到 PageRank 更自然的 parallel-coefficient / serial-state 形式。

## 1. 原论文 serial-serial inner product

原论文考虑：

$$
z=
\sum_{s=0}^{n-1}x_sy_s+b
$$

radix-2 signed-digit 前缀定义为：

$$
x_s[j]=\sum_{\ell=1}^{j+\delta}x_{s,\ell}2^{-\ell}
$$

$$
y_s[j]=\sum_{\ell=1}^{j+\delta}y_{s,\ell}2^{-\ell}
$$

$$
z[j]=\sum_{\ell=-\delta+1}^{j}z_{\ell}2^{-\ell}
$$

残差为：

$$
w[j]=2^j\left(\sum_{s=0}^{n-1}x_s[j]y_s[j]+b[j]-z[j]\right)
$$

推进到下一拍时，双线性项给出：

$$
\sigma_n(x,y)=
\sum_{s=0}^{n-1}
\left(
x_s[j]y_{s,j+1+\delta}
+
y_s[j+1]x_{s,j+1+\delta}
\right)
$$

因此：

$$
v[j]=2w[j]+2^{-\delta}\left(\sigma_n(x,y)+b_{j+1+\delta}\right)
$$

$$
z_{j+1}=\mathrm{sel}(\hat v[j])
$$

$$
w[j+1]=v[j]-z_{j+1}
$$

对 $|x_s|<1, |y_s|<1$，每一项有两个未知尾项贡献，所以：

$$
\max|\sigma_n(x,y)+b_{j+1+\delta}|\le 2n+1
$$

原论文得到：

$$
\omega_{\mathrm{SS}}=1-2^{-\delta}(2n+1)
$$

selection admissibility 条件为：

$$
\lfloor \omega \rfloor_t\ge \frac12(1+2^{-t})
$$

取原论文 bias inner product 的 case 3：

$$
t=3
$$

得到：

$$
\delta_{\mathrm{SS}}\ge
\left\lceil\log_2\frac{2n+1}{3}\right\rceil+3
$$

32 维时：

$$
\delta_{\mathrm{SS}}=
\left\lceil\log_2\frac{65}{3}\right\rceil+3=8
$$

## 2. Parallel-In / Serial-State Affine Form

PageRank row update 更自然的形式是：

$$
z_i=\sum_{s=0}^{n-1}a_{is}x_s+b_i
$$

其中 $a_{is}$ 来自外部矩阵存储，可以作为并行 fixed-point word 输入；$x_s$ 是上一轮 rank/state，保留 MSDF digit stream。

此时只需要对 $x_s$ 建前缀：

$$
x_s[j]=\sum_{\ell=1}^{j+\delta}x_{s,\ell}2^{-\ell}
$$

矩阵系数 $a_{is}$ 不再有未知 digit 尾项。残差定义为：

$$
w_i[j]=2^j\left(\sum_{s=0}^{n-1}a_{is}x_s[j]+b_i[j]-z_i[j]\right)
$$

推进一拍：

$$
x_s[j+1]=x_s[j]+x_{s,j+1+\delta}2^{-(j+1+\delta)}
$$

所以：

$$
w_i[j+1]=
2w_i[j]
+
2^{-\delta}
\left(
\sum_{s=0}^{n-1}a_{is}x_{s,j+1+\delta}+b_{i,j+1+\delta}
\right)
-
z_{i,j+1}
$$

定义：

$$
\sigma_i^{\mathrm{SP}}(a,x)=
\sum_{s=0}^{n-1}a_{is}x_{s,j+1+\delta}
$$

则 P3-SP recurrence 为：

$$
v_i[j]=
2w_i[j]
+
2^{-\delta_{\mathrm{SP}}}
\left(\sigma_i^{\mathrm{SP}}(a,x)+b_{i,j+1+\delta_{\mathrm{SP}}}\right)
$$

$$
z_{i,j+1}=\mathrm{sel}(\hat v_i[j])
$$

$$
w_i[j+1]=v_i[j]-z_{i,j+1}
$$

## 3. Delay Bound

若只使用最坏界 $|a_{is}|<1$，则：

$$
\max|\sigma_i^{\mathrm{SP}}+b_i|\le n+1
$$

因此：

$$
\omega_{\mathrm{SP}}=1-2^{-\delta}(n+1)
$$

同样取 $t=3$：

$$
\delta_{\mathrm{SP,worst}}\ge
\left\lceil\log_2\frac{n+1}{3}\right\rceil+3
$$

32 维时：

$$
\delta_{\mathrm{SP,worst}}=
\left\lceil\log_2\frac{33}{3}\right\rceil+3=7
$$

但是 PageRank 的 row 系数有更强结构。定义每行 bound：

$$
A_i=\sum_s |a_{is}|,
\qquad
B_i=|b_i|
$$

则：

$$
\max|\sigma_i^{\mathrm{SP}}+b_i|\le A_i+B_i
$$

所以：

$$
\delta_{\mathrm{SP},i}\ge
\left\lceil\log_2\frac{A_i+B_i}{3}\right\rceil+3
$$

serial-parallel online multiplier primitive 还需要两拍初始化，因此工程上取：

$$
\delta_{\mathrm{SP}}=
\max\left(
2,
\left\lceil\log_2\frac{\max_i(A_i+B_i)}{3}\right\rceil+3
\right)
$$

当前 `pagerank32_global_parallel_in_fractional` fixture 由生成器计算 $A_i+B_i$。若强制 `--force-delay 2`，但 bound 推导结果大于 2，生成器会直接报错。

## 4. 32-bit External Contract and Internal Widths

P3-SP 的外部数制不由 `ACC_WIDTH` 决定。外部仍是：

$$
DATA\_WIDTH=32
$$

也就是输出 $z[j]$ 的 32 个 MSB-first signed digits。`ACC_WIDTH` 只决定 RTL 内部 residual $w[j]$、贡献项 $c[j]$ 和选择前变量 $v[j]$ 的承载位宽。因此只要内部不溢出，内部位宽缩减不改变输出精度，也不改变 online recurrence。

设：

$$
F=DATA\_WIDTH-1
$$

$$
S=2^F
$$

当前 PageRank32 parallel-in fixture 中：

$$
F=31,\qquad S=2^{31}=2147483648
$$

PageRank 使用 $N=32, degree=4, \beta=0.85$，每个有效系数为：

$$
a=\frac{\beta}{degree}=0.2125
$$

量化后的系数整数为：

$$
a_q=\mathrm{round}(aS)
=456340275
$$

因此系数幅度最小位宽为：

$$
BIT\_WIDTH_{\min}
=
\left\lceil\log_2(a_q+1)\right\rceil
=29
$$

工程实现取：

$$
BIT\_WIDTH=30
$$

这不是增加数值精度，而是给外部模板系数保留 1 bit guard，并且让已有模板打包格式中的：

$$
BIAS\_WIDTH=BIT\_WIDTH+2=32
$$

正好覆盖 32-bit bias digit stream。teleport bias 为：

$$
b=\frac{1-\beta}{N}=0.0046875
$$

量化整数为：

$$
b_q=\mathrm{round}(bS)=10066330
$$

它本身只需要：

$$
\left\lceil\log_2(b_q+1)\right\rceil=24
$$

但 bias 在 P3-SP recurrence 中以 32-bit MSB-first digit stream 输入，所以 `BIAS_WIDTH` 必须不小于 `DATA_WIDTH`，最终取 32。

RTL 每拍贡献项为：

$$
c_i[j]=\sum_s a_{is}x_s[j]+S b_i[j]
$$

其中 $a_{is}$ 是已经量化后的 parallel coefficient integer，$x_s[j]\in\{-1,0,1\}$，$b_i[j]\in\{-1,0,1\}$ 是 bias digit。注意这里的 bias bound 必须按 **instantaneous digit contribution** 计算，而不是只按 bias 数值 $|b_i|$ 计算；因为某一拍 bias digit 为 1 时，RTL 加入的是 $S$。

因此：

$$
|c_i[j]|
\le
\sum_s |a_{is}|+S
$$

定义：

$$
C_{\max}=\max_i\left(\sum_s |a_{is}|+S\right)
$$

当前 fixture 的 PageRank 系数量化为：

$$
a_{is}=456340275,\qquad degree=4
$$

所以：

$$
C_{\max}
=4\times456340275+2147483648
=3972844748
$$

online delay 为：

$$
\delta=2
$$

进入 residual update 的缩放贡献为：

$$
u_i[j]=2^{-\delta}c_i[j]
$$

Verilog arithmetic shift 对负数向负无穷取整，因此保守取：

$$
U_{\max}=
\left\lceil\frac{C_{\max}}{2^\delta}\right\rceil
=
\left\lceil\frac{3972844748}{4}\right\rceil
=993211187
$$

selector 使用阈值：

$$
\pm\frac{S}{2}
$$

并更新：

$$
v[j]=2w[j]+u[j]
$$

$$
w[j+1]=v[j]-z[j+1]S
$$

如果：

$$
U_{\max}\le\frac{S}{2}
$$

则由归纳可得：

$$
|w[j]|\le\frac{S}{2}
$$

因为：

$$
|v[j]|
\le
2|w[j]|+|u[j]|
\le
S+U_{\max}
$$

当 $v[j]\ge S/2$ 时：

$$
|w[j+1]|=|v[j]-S|\le U_{\max}
$$

当 $v[j]\le -S/2$ 时同理；当 $|v[j]|<S/2$ 时：

$$
|w[j+1]|=|v[j]|<S/2
$$

当前：

$$
U_{\max}=993211187<1073741824=\frac{S}{2}
$$

所以 residual bound 成立。内部需要承载的最大幅度来自 $c[j]$、$v[j]$ 和 $w[j]$：

$$
M_{\max}
=
\max\left(C_{\max}, S+U_{\max}, S\right)
=
\max(3972844748,3140694835,2147483648)
=3972844748
$$

有符号 $W$ bit 二进制的正范围为：

$$
2^{W-1}-1
$$

因此最小安全位宽为：

$$
W_{\min}
=
1+\left\lceil\log_2(M_{\max}+1)\right\rceil
$$

代入：

$$
W_{\min}
=
1+\left\lceil\log_2(3972844749)\right\rceil
=33
$$

工程实现取数学最小安全宽度：

$$
ACC\_WIDTH=33
$$

这是当前 PageRank32 parallel-in fixture 的 workload-specific 合同：外部仍输出 32 个 MSB-first signed digits，内部 residual 只需要承载 $c[j]$、$u[j]$、$v[j]$ 和 $w[j]$ 的有界整数幅度。原先的 36-bit guard 版本功能正确，但 U55C 5 ns feedback route 只剩极小负 slack；改为 33 bit 后保留精度、cycle 不变，并使 4-cycle feedback loop route-clean。注意 32-bit 外部输出时，`ACC_WIDTH=18` 已经不安全；它只适用于旧的 14-digit checkpoint。当前 P3-SP 的有效合同是：

$$
DATA\_WIDTH=32,\quad BIT\_WIDTH=30,\quad BIAS\_WIDTH=32,\quad ACC\_WIDTH=33
$$

若更换 workload，生成器必须重新计算 $C_{\max}$，并检查：

$$
U_{\max}\le\frac{S}{2}
$$

以及：

$$
ACC\_WIDTH
\ge
1+\left\lceil
\log_2\left(
\max(C_{\max},S+U_{\max},S)+1
\right)
\right\rceil
$$

否则不能安全使用当前 `ACC_WIDTH=33`；若新的 workload 超出该界，必须提高 `ACC_WIDTH` 或重新证明更紧的 $C_{\max}$ bound。

## 5. 与原论文的差异

| item | 原论文 integrated inner product | P3-SP parallel-in affine MAC |
| --- | --- | --- |
| coefficient operand | MSDF digit stream | external parallel word |
| state operand | MSDF digit stream | MSDF digit stream |
| driver bound | $2n+1$ | $A_i+B_i$ |
| 32-row PageRank delay | 8 | expected 2 |
| innovation level | operator boundary fusion | coefficient-bound-aware operator recurrence |

P3-SP 不是固定系数特化。矩阵仍由外部 template 输入；只是系数进入算子时不再伪装成第二个 serial operand。
