# Coefficient Template Format

本文档固定 specialized iterative-solver RTL 的 coefficient template contract。

目标不是生成最终 bitstream-ready ROM，而是先把：

- 软件模型
- template compiler
- specialized RTL

三者之间的接口固定下来。

## 1. Why a Template Format Is Needed

当前 generic operator 默认每个乘项都是：

$$
g_{is} \times x_s^{(k)}
$$

的 variable-by-variable 在线乘法。  
对 solver 来说，`g_{is}` 是固定常数，这个假设过于保守。

因此 specialized row engine 的输入不应再是：

- 一个通用 coefficient digit stream；
- 一个通用 variable selector front-end；

而应改成：

- 一个固定系数 template；
- 一个在线状态 `x_s` digit stream。

## 2. Mathematical Form

每个定点量化后的系数写成：

$$
\hat g_{is} = \sum_{m=0}^{M_{is}-1}\gamma_{is,m} 2^{-b_{is,m}},
\qquad
\gamma_{is,m}\in\{-1,+1\}
$$

则：

$$
\hat g_{is} x_s^{(k)}
=
\sum_{m=0}^{M_{is}-1}
\gamma_{is,m}\left(x_s^{(k)} \gg b_{is,m}\right)
$$

在 RTL 上，这意味着每个 nonzero coefficient 只需要提供：

- sign
- shift
- term count

而不再需要 generic partial-product selection。

## 3. JSON Compiler Output

当前 compiler:

[compile_coeff_templates.py](./compile_coeff_templates.py)

对每个 nonzero coefficient 输出四类信息：

1. `quant`  
   量化后的有符号整数系数。

2. `rail`  
   预展开的 `vec_p/vec_n`，用于第一版 rail-coded 贡献生成实验。

3. `csd_terms_full`  
   完整 signed-digit 展开。

4. `template_terms`  
   受 `max_terms` 限制后的 template，供 specialized RTL 直接消费。

同时编译器还会输出：

- `degree`
- `fixed_degree`
- `fixed_degree_terms`
- `avg_degree`
- `max_degree`
- `avg_terms_full`
- `avg_terms_kept`
- `dropped_terms_total`

用于 pre-RTL 复杂度评估。

## 4. Intended RTL Contract

specialized row-update 路径里，每个 nonzero coefficient 最终应映射到类似如下接口：

```verilog
typedef struct packed {
    logic [COL_W-1:0] col_idx;
    logic [TERM_CNT_W-1:0] term_count;
    logic [TERM_CNT*SHIFT_W-1:0] shifts;
    logic [TERM_CNT-1:0] signs;
} coeff_template_t;
```

其中：

- `col_idx` 指向 `x_s`
- `term_count` 表示当前 nonzero 保留的 term 数
- `shifts` 表示每个 term 的右移量
- `signs` 表示每个 term 的符号

第一版可以不引入真正的 packed struct，而先在 Verilog-2001 里用平铺总线实现相同语义。

当前 compiler 还会额外输出每行的固定度数 padded 视图：

```json
"fixed_degree_terms": [
  {"valid": 1, "col": 5, "quant": 123, "rail": {...}, "template_terms": [...]},
  {"valid": 1, "col": 9, "quant": -87, "rail": {...}, "template_terms": [...]},
  {"valid": 0, "col": 0, "quant": 0, "rail": {...}, "template_terms": []},
  {"valid": 0, "col": 0, "quant": 0, "rail": {...}, "template_terms": []}
]
```

这正是当前 `iter_fixed_degree_row_scheduler.v` 的直接软件契约：

- `valid` -> `term_valid_mask`
- `col` -> `src_row_idx`
- `rail.vec_p/vec_n` -> `coeff_p_terms / coeff_n_terms`

## 4.5 Packed Payload for Template ROM

当前已经补上第一版 memory packaging 脚本：

- [pack_fixed_degree_templates.py](./pack_fixed_degree_templates.py)

它把 `fixed_degree_terms` 进一步打包成 **one-word-per-cluster** 的 payload，供
`iter_fixed_degree_template_rom.v` 直接 `$readmemh` 读取。

当前 payload 从 LSB 到 MSB 的布局固定为：

$$
[\text{valid\_mask}]
[\text{src\_row\_idx}]
[\text{coeff\_p\_terms}]
[\text{coeff\_n\_terms}]
[\text{bias\_p\_rows}]
[\text{bias\_n\_rows}]
$$

也就是：

- `valid_mask`：`num_rows * degree`
- `src_row_idx`：`num_rows * degree * row_idx_width`
- `coeff_p_terms`：`num_rows * degree * bit_width`
- `coeff_n_terms`：`num_rows * degree * bit_width`
- `bias_p_rows`：`num_rows * (bit_width + 2)`
- `bias_n_rows`：`num_rows * (bit_width + 2)`

当前这条路径的用途不是做最终大规模 ROM 系统，而是先把：

`compiled JSON -> packed memh -> ROM -> unpack -> scheduler`

这条正式工程链路立住。

对应的 bank/loader 升级已经落地：

- `iter_fixed_degree_template_bank.v`
- `iter_dense_small_param_bank_top.v`

bank 版本支持从更大的 cluster memory 中按 `base_cluster_idx` 取出一个
`num_clusters` 宽度的活动窗口。越界窗口会自动补 0，便于后续接真实 tile
scheduler。

## 4.6 Packed Certification Parameters

`block_H` 认证参数也已经按同样方式打包。脚本为：

- [pack_cert_params.py](./pack_cert_params.py)

它读取如下形式的 JSON：

```json
{
  "clusters": [
    {"block_weights": [1, 2, 2, 1, 1, 1, 3, 0], "eta": 3}
  ]
}
```

payload 从 LSB 到 MSB 固定为：

$$
[\text{block\_weights}]
[\eta]
$$

对应 RTL 为：

- `iter_cert_param_bank.v`
- `iter_cert_param_unpack.v`

这意味着当前 top 的固定参数来源已经分成两条独立 bank：

- row-update template bank
- certification parameter bank

## 5. First RTL Assumptions

为了避免一开始就陷入过于复杂的调度器，第一版应固定：

1. `max_terms` 很小，例如 `4`
2. 每行 degree 有固定上限，例如 `4` 或 `8`
3. structured sparse / banded sparse 优先
4. 不做 runtime variable term scheduling

当前默认是：

- `max_terms = 4`
- `fixed_degree = 4`

也就是说，第一版目标不是“最优模板压缩”，而是：

$$
\text{eliminate generic selector depth}
$$

## 6. What the Current Model Already Tells Us

[generated/const_coeff_specialization_report.md](./generated/const_coeff_specialization_report.md)
已经给出两个关键信号：

1. constant specialization 的价值主要来自前端深度下降；
2. signed-digit template 的静态系数存储不一定比直接定点更省。

因此后续 RTL 设计必须据此取舍：

- 优先保证 contribution generator 简洁；
- 不要为了追求系数存储压缩而引入更复杂的 template 解码。

## 7. Recommended Next Step

在进入 specialized RTL 前，建议先生成一个实际 Jacobi case 的 template JSON，并检查：

- `max_terms=4` 是否足够；
- degree 分布是否适合 fixed-degree first RTL；
- bias 项是否也应使用同一 template contract。

这一步现在已经完成，样例见：

- [generated/jacobi32_coeff_templates.json](./generated/jacobi32_coeff_templates.json)

它已经包含：

- `fixed_degree`
- 每行 `fixed_degree_terms`

可直接喂给当前的 scheduler 生成脚本或后续的 ROM 打包流程。

当前最小样例还额外提供了：

- [testdata/blockdiag8_matrix.json](./testdata/blockdiag8_matrix.json)
- [generated/blockdiag8_coeff_templates.json](./generated/blockdiag8_coeff_templates.json)
- [generated/blockdiag8_fixed4_templates.memh](./generated/blockdiag8_fixed4_templates.memh)

配套 RTL 路径是：

- [rtl/iter_fixed_degree_template_rom.v](./rtl/iter_fixed_degree_template_rom.v)
- [rtl/iter_fixed_degree_template_unpack.v](./rtl/iter_fixed_degree_template_unpack.v)
- [rtl/iter_dense_small_template_top.v](./rtl/iter_dense_small_template_top.v)
- [rtl/iter_fixed_degree_template_bank.v](./rtl/iter_fixed_degree_template_bank.v)
- [rtl/iter_cert_param_bank.v](./rtl/iter_cert_param_bank.v)
- [rtl/iter_cert_param_unpack.v](./rtl/iter_cert_param_unpack.v)
- [rtl/iter_dense_small_param_bank_top.v](./rtl/iter_dense_small_param_bank_top.v)
