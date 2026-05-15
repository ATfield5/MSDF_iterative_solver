# Parallel-In Routed Main Results

Purpose: collect current U55C implementation evidence.  This report separates routed rows from synth-only rows.

- git commit: `24bdc91531326314d71a18b4efff580e9bdbf7ae`
- device: `xcu55c-fsvh2892-2L-e`
- Vivado/Vitis: `2023.2`
- clock target: `5 ns`

| entry | type | result | WNS ns | LUT | FF | CARRY8 | DSP | BRAM | Dynamic W | out dir |
| --- | --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | --- |
| P1 native prior32 | native serial-serial 32-input online | synth-only | 3.145 | 1438937 | 782614 | 16 | 0 | 0 | 4.342 | `/home/sy/FPGA/Online_Mul_Add/MSDF_iterative_solver/generated/vivado_prior32_native_k4_rows32_deg32_bw29_data32_synth` |
| P2 p3sp K4 degree4/physical8 | parallel-in wavefront | routed-pass | 0.104 | 85373 | 10831 | 7568 | 0 | 0 | 0.966 | `/home/sy/FPGA/Online_Mul_Add/MSDF_iterative_solver/generated/vivado_parallel_in_wavefront_p3sp_k4_u55c_clk5.000_route1` |
| P2 p3sp K4 degree8/physical8 | parallel-in wavefront degree8 trend | synth-only | 2.019 | 149450 | 10082 | 12560 | 0 | 0 | 1.524 | `/home/sy/FPGA/Online_Mul_Add/MSDF_iterative_solver/generated/vivado_parallel_in_wavefront_p3sp_k4_deg8_pdeg8_data32_synth` |
| P2 p3sp K4 degree8/physical8 routed probe | parallel-in wavefront degree8 trend | routed-fail | -0.338 | 148120 | 10082 | 12560 | 0 | 0 | 1.622 | `/home/sy/FPGA/Online_Mul_Add/MSDF_iterative_solver/generated/vivado_parallel_in_wavefront_p3sp_k4_deg8_pdeg8_data32_u55c_clk5.000_route1_mt2` |
| P2 p3sp K4 degree8/physical8 nonnegative+maxfanout | parallel-in wavefront degree8 optimized | routed-pass | 0.001 | 116070 | 11811 | 8464 | 0 | 0 | 0.710 | `/home/sy/FPGA/Online_Mul_Add/MSDF_iterative_solver/generated/vivado_parallel_in_wavefront_p3sp_k4_deg8_pdeg8_data32_nonneg_mf_route` |
| P3 p3sp feedback route-clean | parallel-in feedback | routed-pass | 0.040 | 116066 | 27089 | 9676 | 0 | 0 | 1.749 | `/home/sy/FPGA/Online_Mul_Add/MSDF_iterative_solver/generated/vivado_parallel_in_wavefront_p3spfb_k4_4cycle_fifo32_core33_route` |
| P3 dense32 feedback | dense32 parallel-in feedback | synth-only | 0.362 | 489773 | 25732 | 39244 | 0 | 0 | 8.007 | `/home/sy/FPGA/Online_Mul_Add/MSDF_iterative_solver/generated/vivado_parallel_in_wavefront_p3spfbfast2_k4_deg32_pdeg32_u55c_synth` |
| P4 conventional one-stage | conventional DSP-MAC | routed-pass | 1.284 | 62877 | 24644 | 8896 | 1024 | 0 | 3.046 | `/home/sy/FPGA/Online_Mul_Add/MSDF_iterative_solver/generated/vivado_parallel_in_wavefront_p4sp_k4_u55c_clk5.000_route1` |
| P4 conventional degree8/physical8 one-stage | conventional DSP-MAC degree8 | routed-pass | 1.284 | 62877 | 24644 | 8896 | 1024 | 0 | 3.046 | `/home/sy/FPGA/Online_Mul_Add/MSDF_iterative_solver/generated/vivado_parallel_in_wavefront_p4sp_k4_deg8_pdeg8_data32_u55c_clk5.000_route1_mt2` |

Paper-use rules:

- `routed-pass` rows can enter hardware implementation tables.
- `routed-fail` rows are implementation evidence but cannot be used as timing-clean main results.
- Synth-only rows can only support scalability/resource-trend claims.
- Dense32 P3 is not a routed timing claim yet.
- P1 native prior32 exceeds the U55C LUT budget in synthesis and should not be routed as a main result.
