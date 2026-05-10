# Specialized Solver Stack Evaluation

This report compares the current solver-mainline variants before RTL.

## Variants

- `B1`: cascaded online
- `B2`: conventional FPGA proxy
- `Ours-A`: generic-front-end iteration-fused proxy
- `Ours-B`: constant-coefficient-specialized row proxy + global certification
- `Ours-C`: Ours-B + `block_H` certification with `block_size=4`

## Case Table

| case | n | rho | exact stop | generic stop | block stop | avg j generic | avg j block | cycles B1 | cycles B2 | cycles A | cycles B | cycles C | A vs B1 | B vs B1 | C vs B1 | C vs B2 |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| `jacobi_n32_rho0.50_deg4` | 32 | 0.495 | 10 | 11 | 10 | 24.00 | 22.00 | 14080 | 3520 | 13952 | 12896 | 11776 | 1.009 | 1.092 | 1.196 | 0.299 |
| `jacobi_n32_rho0.50_deg8` | 32 | 0.485 | 8 | 9 | 9 | 24.00 | 24.00 | 11264 | 3072 | 11680 | 10816 | 10816 | 0.964 | 1.041 | 1.041 | 0.284 |
| `jacobi_n32_rho0.70_deg4` | 32 | 0.698 | 13 | 15 | 13 | 24.00 | 21.00 | 18304 | 4576 | 19136 | 17696 | 15296 | 0.957 | 1.034 | 1.197 | 0.299 |
| `jacobi_n32_rho0.70_deg8` | 32 | 0.699 | 9 | 11 | 10 | 24.00 | 24.00 | 12672 | 3456 | 14368 | 13312 | 12032 | 0.882 | 0.952 | 1.053 | 0.287 |
| `jacobi_n32_rho0.90_deg4` | 32 | 0.890 | 28 | 35 | 30 | 24.00 | 24.00 | 39424 | 9856 | 44768 | 41408 | 35520 | 0.881 | 0.952 | 1.110 | 0.277 |
| `jacobi_n32_rho0.90_deg8` | 32 | 0.874 | 12 | 14 | 12 | 24.00 | 22.00 | 16896 | 4608 | 18336 | 16992 | 14528 | 0.921 | 0.994 | 1.163 | 0.317 |
| `jacobi_n64_rho0.50_deg4` | 64 | 0.496 | 10 | 11 | 10 | 24.00 | 21.00 | 28160 | 7040 | 27904 | 25792 | 23488 | 1.009 | 1.092 | 1.199 | 0.300 |
| `jacobi_n64_rho0.50_deg8` | 64 | 0.500 | 8 | 9 | 9 | 24.00 | 24.00 | 24064 | 6144 | 23360 | 21632 | 21632 | 1.030 | 1.112 | 1.112 | 0.284 |
| `jacobi_n64_rho0.70_deg4` | 64 | 0.694 | 15 | 16 | 15 | 24.00 | 21.00 | 42240 | 10560 | 40896 | 37824 | 35328 | 1.033 | 1.117 | 1.196 | 0.299 |
| `jacobi_n64_rho0.70_deg8` | 64 | 0.697 | 9 | 11 | 10 | 24.00 | 24.00 | 27072 | 6912 | 28736 | 26624 | 24064 | 0.942 | 1.017 | 1.125 | 0.287 |
| `jacobi_n64_rho0.90_deg4` | 64 | 0.891 | 16 | 21 | 18 | 24.00 | 24.00 | 45056 | 11264 | 53696 | 49664 | 42496 | 0.839 | 0.907 | 1.060 | 0.265 |
| `jacobi_n64_rho0.90_deg8` | 64 | 0.900 | 14 | 19 | 15 | 24.00 | 24.00 | 42112 | 10752 | 49856 | 46208 | 36288 | 0.845 | 0.911 | 1.160 | 0.296 |
| `jacobi_n128_rho0.50_deg4` | 128 | 0.499 | 10 | 11 | 10 | 24.00 | 20.00 | 56320 | 14080 | 55808 | 51584 | 46848 | 1.009 | 1.092 | 1.202 | 0.301 |
| `jacobi_n128_rho0.50_deg8` | 128 | 0.500 | 7 | 8 | 8 | 24.00 | 24.00 | 42112 | 10752 | 41472 | 38400 | 38400 | 1.015 | 1.097 | 1.097 | 0.280 |
| `jacobi_n128_rho0.70_deg4` | 128 | 0.700 | 14 | 16 | 15 | 24.00 | 24.00 | 78848 | 19712 | 81792 | 75648 | 70656 | 0.964 | 1.042 | 1.116 | 0.279 |
| `jacobi_n128_rho0.70_deg8` | 128 | 0.699 | 10 | 11 | 10 | 24.00 | 20.00 | 60160 | 15360 | 57472 | 53248 | 48128 | 1.047 | 1.130 | 1.250 | 0.319 |
| `jacobi_n128_rho0.90_deg4` | 128 | 0.892 | 21 | 26 | 22 | 24.00 | 24.00 | 118272 | 29568 | 132992 | 123008 | 103936 | 0.889 | 0.961 | 1.138 | 0.284 |
| `jacobi_n128_rho0.90_deg8` | 128 | 0.897 | 12 | 16 | 13 | 24.00 | 24.00 | 72192 | 18432 | 83968 | 77824 | 62848 | 0.860 | 0.928 | 1.149 | 0.293 |

## Interpretation

- `Ours-B vs Ours-A` isolates the value of constant-matrix specialization in the row-update front-end.
- `Ours-C vs Ours-B` isolates the value of stronger `block_H` certification.
- `C vs B2` is still a model-level proxy and must not be promoted to a final hardware claim.
