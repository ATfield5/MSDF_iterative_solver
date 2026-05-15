# Parallel-In Bound Sweep

Purpose: validate the paper math for the parallel-in online affine operator.
This is a fixed-point model sweep, not a routed hardware report.

- git commit: `24bdc91531326314d71a18b4efff580e9bdbf7ae`
- command: `conda run -n qas python MSDF_iterative_solver/run_parallel_in_bound_sweep.py`
- iterations generated per case: `8`

| degree | data width | coeff width | beta | max_i(A_i+B_i) | derived delay | impl delay | delta=2 safe | acc min | max drift raw | max drift real | final Linf P3/P4 |
| ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | --- |
| 4 | 16 | 14 | 0.85 | 0.85467529 | 2 | 2 | 1 | 17 | 480 | 1.464844e-02 | 49 / 0 |
| 4 | 16 | 14 | 0.95 | 0.95150757 | 2 | 2 | 1 | 17 | 248 | 7.568359e-03 | 36 / 0 |
| 4 | 24 | 22 | 0.85 | 0.85468745 | 2 | 2 | 1 | 25 | 122400 | 1.459122e-02 | 12606 / 100 |
| 4 | 24 | 22 | 0.95 | 0.95156229 | 2 | 2 | 1 | 25 | 63329 | 7.549405e-03 | 9153 / 72 |
| 4 | 32 | 30 | 0.85 | 0.85468750 | 2 | 2 | 1 | 33 | 31334310 | 1.459118e-02 | 3227035 / 25212 |
| 4 | 32 | 30 | 0.95 | 0.95156250 | 2 | 2 | 1 | 33 | 16212712 | 7.549632e-03 | 2343231 / 18308 |
| 8 | 16 | 14 | 0.85 | 0.85479736 | 2 | 2 | 1 | 17 | 481 | 1.467896e-02 | 50 / 0 |
| 8 | 16 | 14 | 0.95 | 0.95150757 | 2 | 2 | 1 | 17 | 252 | 7.690430e-03 | 36 / 0 |
| 8 | 24 | 22 | 0.85 | 0.85468793 | 2 | 2 | 1 | 25 | 122400 | 1.459122e-02 | 12606 / 104 |
| 8 | 24 | 22 | 0.95 | 0.95156229 | 2 | 2 | 1 | 25 | 63325 | 7.548928e-03 | 9153 / 72 |
| 8 | 32 | 30 | 0.85 | 0.85468750 | 2 | 2 | 1 | 33 | 31334311 | 1.459118e-02 | 3227035 / 25216 |
| 8 | 32 | 30 | 0.95 | 0.95156250 | 2 | 2 | 1 | 33 | 16212716 | 7.549634e-03 | 2343231 / 18304 |
| 32 | 16 | 14 | 0.85 | 0.85430908 | 2 | 2 | 1 | 17 | 495 | 1.510620e-02 | 49 / 0 |
| 32 | 16 | 14 | 0.95 | 0.95175171 | 2 | 2 | 1 | 17 | 261 | 7.965088e-03 | 36 / 0 |
| 32 | 24 | 22 | 0.85 | 0.85468602 | 2 | 2 | 1 | 25 | 122399 | 1.459110e-02 | 12606 / 96 |
| 32 | 24 | 22 | 0.95 | 0.95156324 | 2 | 2 | 1 | 25 | 63317 | 7.547975e-03 | 9153 / 64 |
| 32 | 32 | 30 | 0.85 | 0.85468749 | 2 | 2 | 1 | 33 | 31334309 | 1.459117e-02 | 3227035 / 25216 |
| 32 | 32 | 30 | 0.95 | 0.95156250 | 2 | 2 | 1 | 33 | 16212732 | 7.549642e-03 | 2343231 / 18304 |

Interpretation:

- `derived delay <= 2` means the workload satisfies the current implementation's `online_delay=2` contract.
- `max drift` compares the generated parallel-in signed-digit model against the generated conventional rounded fixed-point model for the same fixture.
- This report is used for the paper math table; it does not claim routed FPGA timing.

Machine-readable files: `/home/sy/FPGA/Online_Mul_Add/MSDF_iterative_solver/generated/parallel_in_bound_sweep.json` and `/home/sy/FPGA/Online_Mul_Add/MSDF_iterative_solver/generated/parallel_in_bound_sweep.csv`.
