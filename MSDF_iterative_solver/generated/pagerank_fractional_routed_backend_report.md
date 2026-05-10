# PageRank Fractional Routed Backend Report

This report records the U55C / Vivado 2023.2 / 5 ns OOC routed comparison between the strict prior-fractional K=4 wavefront runtime and the conventional fractional DSP-MAC runtime. Both use the same `pagerank32_global_prior_fractional` parameters: `NUM_CLUSTERS=8`, `NUM_ROWS=4`, `DEGREE=4`, `BIT_WIDTH=11`, `DATA_WIDTH=14`, global source replay, BRAM runtime banks, and the same PageRank L1 certification shell.

The fairness baseline now includes an 8-slot conventional physical MAC configuration. The PageRank math still has four valid sparse terms per row, but `MSDF_CONV_BASELINE_DEGREE=8` preserves four extra conventional MAC slots per row so the DSP-MAC baseline reserves the same input-slot width as the prior `MSDF_MUL_ADD_8` operator.

| entry | compute cycles | observed total | routed WNS | timing-clean @ 5 ns | LUT | FF | DSP | BRAM | dynamic W | log |
| --- | ---: | ---: | ---: | --- | ---: | ---: | ---: | ---: | ---: | --- |
| P3 prior K=4 wavefront fractional | 70 | 150 | +0.114 ns | yes | 121364 | 64706 | 64 | 10.5 | 1.247 | `logs/vivado_mode7_prior_wavefront_route.log` |
| P4 conventional fractional DSP-MAC | 36 | 135 | -2.852 ns | no | 57828 | 15069 | 192 | 10.5 | 1.853 | `logs/vivado_p4_conv_fractional_route.log` |
| P4 timing-clean conventional fractional | 44 | 143 | +0.204 ns | yes | 55084 | 19657 | 192 | 10.5 | 2.019 | `logs/vivado_p4_conv_fractional_greg_rpipe_route.log` |
| P4 timing-clean conventional fractional, reserved 8-slot MAC | 44 | 143 | +0.052 ns | yes | 59482 | 23753 | 320 | 10.5 | 2.390 | `logs/vivado_p4_conv8_reserved_fractional_greg_rpipe_route.log` |

Derived comparison:

- The table uses compute cycles: `issue + cert_wait`. Configuration, state preload, and window load are excluded from the performance cycle column.
- P3 is `1.944x` slower than the non-clean P4 functional lower bound by compute cycles: `70 / 36`.
- P3 is `1.591x` slower than both timing-clean P4 routed baselines by compute cycles: `70 / 44`.
- The observed-total ratio including overhead is much closer, `150 / 143 = 1.049x`, but that is not the performance headline because it includes setup/controller overhead.
- Versus the reserved 8-slot P4 baseline, P3 uses `2.04x` LUT and `2.72x` FF.
- Versus the reserved 8-slot P4 baseline, P3 uses `5.00x` fewer DSP and `47.82%` lower vectorless dynamic power.
- The original P4 does not meet the 5 ns target. Its worst path implies this exact RTL would need about `7.852 ns` period before further pipelining, so the 135-cycle number is only a functional lower bound.
- The timing-clean P4 adds a global replay register and a product-rounding pipeline. It raises compute latency to `44` cycles and observed total to `143` cycles, but routes at `WNS +0.204 ns`.

Critical paths:

- Non-clean P4 worst path starts at the full-word state bank read-bank select, passes through global source replay mux logic, then through DSP pre-add/multiply/ALU and CARRY8 rounding/product logic before `r_product_reg`. Vivado reports `21` logic levels and `7.826 ns` data path delay, split roughly `48.59%` logic and `51.41%` route.
- Timing-clean P4 fixes this by registering global replay terms and by splitting DSP product from product rounding. For the fairest routed comparison against `MSDF_MUL_ADD_8`, use the reserved 8-slot P4 row because the clean 4-slot row otherwise gives conventional logic a narrower physical operator.
- P3 worst path is not the MSDF arithmetic recurrence. It is a route-dominated committed digit fanout path from a prior-stage `DFF_Z` output to the penultimate-stage cache. Vivado reports one LUT level, `4.837 ns` data path delay, and `96.05%` route.

Interpretation:

The wavefront idea is physically viable at 5 ns, but the current implementation pays a very large LUT/FF replication cost because it instantiates four stages of the original prior operator across 32 rows. After repairing P4 timing and reserving the same 8 input slots, P3 still does not have a latency win: `70` vs `44` compute cycles. Its defensible hardware advantages are much lower DSP and lower dynamic power, while its disadvantages are substantially higher LUT/FF and higher core compute cycle count.

Immediate next optimization target for P3 is not increasing `K`. The routed P3 critical path is committed-digit fanout into the last-delta cache, so the concrete RTL target is to localize stage-output capture per cluster or register-slice the stage-to-cache bus. The larger issue is area and core latency: a paper-grade P3 needs either stage sharing, cluster-local wavefront partitioning, or a solver-native prior recurrence that avoids replicating the full original `MSDF_MUL_ADD_8` four times per row.
