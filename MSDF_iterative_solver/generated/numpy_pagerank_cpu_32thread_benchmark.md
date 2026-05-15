# NumPy 32-Thread PageRank CPU Throughput Benchmark

This report records the local CPU software baseline for the dense PageRank32 fixture.
It is a software reference only; it must not be mixed with FPGA LUT/DSP resource rows.

## Platform

| Item | Value |
| --- | --- |
| CPU | AMD Ryzen 9 9950X 16-Core Processor |
| Logical threads | 32 |
| NumPy | measured in `benchmark_numpy_pagerank_cpu.py` runtime environment |
| BLAS | NumPy/OpenBLAS through current conda `qas` environment |
| Thread env | `{'OPENBLAS_NUM_THREADS': '32', 'OMP_NUM_THREADS': '32', 'MKL_NUM_THREADS': '32', 'NUMEXPR_NUM_THREADS': '32'}` |
| Fixture | `pagerank32_global_parallel_in_fractional_deg32` |
| Matrix shape | dense `32 x 32` |
| Terms per iteration | `1024` |
| Estimated FLOPs per iteration | `2080` |

## Measured CPU Throughput

| CPU measurement | Mean time | Throughput |
| --- | ---: | ---: |
| Full 13-iteration PageRank run | `9.696834017e-06 s` | `103126.443 runs/s` |
| Full-run iteration throughput | same run | `1.340644e+06 iter/s` |
| Full-run term throughput | same run | `1.372819 Gterm/s` |
| Full-run estimated FLOP throughput | same run | `2.788539 GFLOP/s` |
| Repeated single-iteration kernel | `7.326629573e-07 s/iter` | `1.364884e+06 iter/s` |
| Kernel term throughput | same kernel | `1.397641 Gterm/s` |
| Kernel estimated FLOP throughput | same kernel | `2.838959 GFLOP/s` |

## Notes

The benchmark repeats:

$$
r^{(k+1)} = A r^{(k)} + b
$$

For this small `32 x 32` matrix, Python/NumPy call overhead remains visible even with 32 OpenBLAS threads.
