# Parallel-In P3-SP/P4-SP U55C Route Sweep

Vivado/Vitis: `2023.2`; part: `xcu55c-fsvh2892-2L-e`; clock target: `5.000 ns`.
This is a standalone OOC route sweep for the P3-SP wavefront/feedback datapaths and the P4-SP one-stage conventional baseline.
Current P3-SP default contract is `DATA_WIDTH=32`, `BIT_WIDTH=30`, `BIAS_WIDTH=32`, `ACC_WIDTH=33`, `ONLINE_DELAY=2`.
Current P3-SP feedback kind is `p3spfb`: same four-stage online wavefront plus feedback FIFO and `L∞ <= 1 LSB` termination datapath.
Current P4-SP baseline is one-stage conventional: `32` row lanes in parallel, `8` full-word MAC slots per row, no K-stage physical expansion, `DATA_WIDTH=32`, `ACC_WIDTH=40`, `PRODUCT_WIDTH=66`, `PRODUCT_SHIFT=32`.

| kind | K | status | WNS ns | LUT | FF | CARRY8 | DSP | BRAM | Dynamic W | route status | log |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | --- | --- |
| p4sp | 4 | 0 | 1.284 | 62877 | 24644 | 8896 | 1024 | 0 | 3.046 | fully routed=140517, errors=0 | `/home/sy/FPGA/Online_Mul_Add/logs/parallel_in_route_p4sp_k4_deg8_pdeg8_data32_u55c_clk5.000_route1_mt2.log` |

## Notes

- P3-SP keeps state as MSB-first digit stream and has one online stage per K level.
- P3-SP currently keeps direct stage-to-stage digit cascading, uses a contribution register before residual update, and implements contribution as an explicit balanced tree.
- P4-SP is no longer the historical same-shape full-unrolled wavefront.  It is a one-stage conventional baseline: 32 rows run in parallel and each row has eight full-word MAC slots.
- The P4-SP route entry therefore measures a one-iteration 32-row datapath, not a K-stage wavefront.
- `p3spfb` includes feedback FIFO and Linf certification control; `p3sp` intentionally excludes them.
- This report intentionally excludes runtime loader and external state memory.
