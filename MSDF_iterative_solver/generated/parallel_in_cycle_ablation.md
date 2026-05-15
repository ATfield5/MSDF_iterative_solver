# Parallel-In Cycle And Throughput Ablation

Purpose: collect the current cycle/throughput evidence for P1-P4 and CPU.
Rows marked `synth-only` or `CPU measured` must not be mixed with routed FPGA rows.

- git commit: `24bdc91531326314d71a18b4efff580e9bdbf7ae`
- hardware cycle-model clock: `200 MHz`

| entry | scope | degree | iterations | cycles | cycles/iter | iter/s @200MHz | Gterm/s @200MHz | status |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | --- |
| P1 native serial-serial prior32 | measured RTL sim, standalone K=4 | 32 | 4 | 86 | 21.500 | 9302325.581 | 9.526 | PASS; not routed; native32 synth exceeds U55C LUT budget |
| P2 parallel-in online wavefront | measured RTL sim, degree4 default | 4 | 4 | 50 | 12.500 | 16000000 | 2.048 | PASS |
| P3 parallel-in feedback | measured RTL sim, degree4 default | 4 | 8 | 94 | 11.750 | 17021276.596 | 2.179 | PASS |
| P3 dense32 feedback | measured RTL sim + synth-only resource | 32 | 8 | 88 | 11 | 18181818.182 | 18.618 | PASS; synth-only |
| P4 conventional DSP-MAC | measured RTL sim, one-stage degree4/physical8 | 4 | 4 | 17 | 4.250 | 47058823.529 | 6.024 | PASS; not same physical wavefront shape |
| P4 conventional DSP-MAC degree8/physical8 | measured RTL sim, one-stage degree8/physical8 | 8 | 4 | 17 | 4.250 | 47058823.529 | 12.047 | PASS; same 8-MAC/row physical datapath as routed P4 degree8 |
| CPU NumPy/OpenBLAS 32-thread | CPU measured kernel | 32 | measured | NA | NA | 1364884.071 | 1.398 | software reference; no FPGA resource comparison |

Interpretation:

- P1 and dense32 P3 are the direct dense 32-term operator scalability rows.
- P4 is a conventional DSP-MAC arithmetic baseline, but the current route-clean row is a one-stage datapath rather than a K-stage online wavefront.
- CPU is measured software throughput and is included only as an application reference.
