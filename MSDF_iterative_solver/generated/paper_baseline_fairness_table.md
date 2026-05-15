# Paper Baseline Fairness Table

Purpose: define which rows can be compared and which rows are only references.

| ID | entry | scope | primary data | paper use |
| --- | --- | --- | --- | --- |
| P0 | Original paper integrated online inner product | operator-level only | n=32,m=32: integrated 10194 LUT / 6153 FF; cascaded 11195 LUT / 7202 FF | prior-work reference; not directly comparable to full wavefront/runtime top |
| P1 | Native serial-serial 32-input online operator | same-repo prior-style scalability baseline | K=4 degree32 DATA_WIDTH=32: 86 cycles; synth 1,438,937 LUT / 782,614 FF / 0 DSP | shows direct native32 scaling is resource-infeasible on U55C |
| P2 | Parallel-in online affine operator | operator/wavefront | degree4 K=4: 50 cycles; routed-pass WNS 0.104 ns / 85373 LUT / 10831 FF / 0 DSP; degree8 optimized: routed-pass WNS 0.001 ns / 116070 LUT / 11811 FF / 0 DSP | operator contribution and online-delay reduction evidence |
| P3 | Parallel-in digit-wavefront / feedback | wavefront-level | degree4 feedback: routed-pass WNS 0.040 ns / 116066 LUT / 27089 FF / 0 DSP; dense32 88 cycles/8 iter synth-only | main architecture contribution; dense32 needs route before timing claim |
| P4 | Conventional DSP-MAC affine baseline | hardware arithmetic baseline | one-stage 32-row x 8-MAC degree8/physical8: routed-pass WNS 1.284 ns / 62877 LUT / 24644 FF / 1024 DSP | fair FPGA arithmetic baseline; not CPU and not prior-online |
| CPU | NumPy/OpenBLAS 32-thread | software application baseline | kernel 1.365 Miter/s on Ryzen 9 9950X | application reference only; no LUT/DSP comparison |

Comparison rules:

- P0 operator-level LUT/FF must not be mixed with P2/P3 full wavefront/runtime resource rows.
- P1 vs P3 is valid for native serial-serial scaling versus parallel-in scaling, but only at the same stated shape/result type.
- P4 is the conventional FPGA arithmetic baseline; its DSP usage is part of the comparison, not a weakness in the baseline.
- CPU is a software throughput reference only.
