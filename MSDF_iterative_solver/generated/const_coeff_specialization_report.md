# Constant-Coefficient Specialization Proxy Report

This report estimates whether fixed-matrix specialization is structurally promising before RTL.

## Model Scope

- Coefficients are quantized to `q` fractional bits and converted to a signed-digit form.
- `coeff_bits_generic` is the baseline storage proxy for directly storing `q+1` signed bits per nonzero coefficient.
- `coeff_bits_template` is the template-storage proxy for signed-digit terms plus shift metadata.
- `theta_row_generic_proxy` adds a variable-selector front-end depth to the integrated row-update proxy.
- `theta_row_const_proxy` replaces that front-end with a local constant-coefficient contribution-generator depth.
- These are architecture proxies, not post-route timing claims.

## Configuration

- q sweep: `[16, 20, 24]`

## Case Table

| case | n | rho | avg nu | max nu | q | avg CSD terms | max CSD terms | generic coeff bits | template coeff bits | storage ratio | generic row proxy | const row proxy | row speedup |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| `jacobi_n32_rho0.50_deg4_q16` | 32 | 0.498 | 3.81 | 4 | 16 | 4.98 | 7 | 2074 | 4120 | 0.503 | 15 | 11 | 1.364 |
| `jacobi_n32_rho0.50_deg8_q16` | 32 | 0.497 | 7.38 | 8 | 16 | 4.77 | 7 | 4012 | 7663 | 0.524 | 16 | 12 | 1.333 |
| `jacobi_n32_rho0.70_deg4_q16` | 32 | 0.699 | 3.81 | 4 | 16 | 5.17 | 8 | 2074 | 4271 | 0.486 | 15 | 12 | 1.250 |
| `jacobi_n32_rho0.70_deg8_q16` | 32 | 0.696 | 7.38 | 8 | 16 | 4.65 | 7 | 4012 | 7500 | 0.535 | 16 | 12 | 1.333 |
| `jacobi_n32_rho0.90_deg4_q16` | 32 | 0.897 | 3.81 | 4 | 16 | 5.19 | 8 | 2074 | 4276 | 0.485 | 15 | 12 | 1.250 |
| `jacobi_n32_rho0.90_deg8_q16` | 32 | 0.898 | 7.38 | 8 | 16 | 4.97 | 7 | 4012 | 7961 | 0.504 | 16 | 12 | 1.333 |
| `jacobi_n64_rho0.50_deg4_q16` | 64 | 0.499 | 3.91 | 4 | 16 | 4.90 | 8 | 4250 | 8326 | 0.510 | 15 | 12 | 1.250 |
| `jacobi_n64_rho0.50_deg8_q16` | 64 | 0.498 | 7.69 | 8 | 16 | 4.71 | 7 | 8364 | 15796 | 0.530 | 16 | 12 | 1.333 |
| `jacobi_n64_rho0.70_deg4_q16` | 64 | 0.698 | 3.91 | 4 | 16 | 5.14 | 7 | 4250 | 8700 | 0.489 | 15 | 11 | 1.364 |
| `jacobi_n64_rho0.70_deg8_q16` | 64 | 0.691 | 7.69 | 8 | 16 | 4.89 | 7 | 8364 | 16371 | 0.511 | 16 | 12 | 1.333 |
| `jacobi_n64_rho0.90_deg4_q16` | 64 | 0.897 | 3.91 | 4 | 16 | 5.25 | 8 | 4250 | 8868 | 0.479 | 15 | 12 | 1.250 |
| `jacobi_n64_rho0.90_deg8_q16` | 64 | 0.878 | 7.69 | 8 | 16 | 4.99 | 8 | 8364 | 16668 | 0.502 | 16 | 13 | 1.231 |
| `jacobi_n128_rho0.50_deg4_q16` | 128 | 0.497 | 3.95 | 4 | 16 | 5.05 | 8 | 8602 | 17307 | 0.497 | 15 | 12 | 1.250 |
| `jacobi_n128_rho0.50_deg8_q16` | 128 | 0.497 | 7.84 | 8 | 16 | 4.61 | 7 | 17068 | 31669 | 0.539 | 16 | 12 | 1.333 |
| `jacobi_n128_rho0.70_deg4_q16` | 128 | 0.695 | 3.95 | 4 | 16 | 5.24 | 8 | 8602 | 17916 | 0.480 | 15 | 12 | 1.250 |
| `jacobi_n128_rho0.70_deg8_q16` | 128 | 0.698 | 7.84 | 8 | 16 | 4.85 | 8 | 17068 | 33134 | 0.515 | 16 | 13 | 1.231 |
| `jacobi_n128_rho0.90_deg4_q16` | 128 | 0.896 | 3.95 | 4 | 16 | 5.32 | 8 | 8602 | 18164 | 0.474 | 15 | 12 | 1.250 |
| `jacobi_n128_rho0.90_deg8_q16` | 128 | 0.890 | 7.84 | 8 | 16 | 4.91 | 8 | 17068 | 33502 | 0.509 | 16 | 13 | 1.231 |
| `jacobi_n32_rho0.50_deg4_q20` | 32 | 0.486 | 3.81 | 4 | 20 | 6.43 | 10 | 2562 | 5221 | 0.491 | 15 | 12 | 1.250 |
| `jacobi_n32_rho0.50_deg8_q20` | 32 | 0.498 | 7.38 | 8 | 20 | 5.97 | 9 | 4956 | 9419 | 0.526 | 16 | 13 | 1.231 |
| `jacobi_n32_rho0.70_deg4_q20` | 32 | 0.682 | 3.81 | 4 | 20 | 6.44 | 9 | 2562 | 5226 | 0.490 | 15 | 12 | 1.250 |
| `jacobi_n32_rho0.70_deg8_q20` | 32 | 0.687 | 7.38 | 8 | 20 | 6.13 | 9 | 4956 | 9650 | 0.514 | 16 | 13 | 1.231 |
| `jacobi_n32_rho0.90_deg4_q20` | 32 | 0.891 | 3.81 | 4 | 20 | 6.80 | 9 | 2562 | 5500 | 0.466 | 15 | 12 | 1.250 |
| `jacobi_n32_rho0.90_deg8_q20` | 32 | 0.895 | 7.38 | 8 | 20 | 6.27 | 9 | 4956 | 9861 | 0.503 | 16 | 13 | 1.231 |
| `jacobi_n64_rho0.50_deg4_q20` | 64 | 0.499 | 3.91 | 4 | 20 | 6.42 | 9 | 5250 | 10678 | 0.492 | 15 | 12 | 1.250 |
| `jacobi_n64_rho0.50_deg8_q20` | 64 | 0.497 | 7.69 | 8 | 20 | 6.07 | 9 | 10332 | 19928 | 0.518 | 16 | 13 | 1.231 |
| `jacobi_n64_rho0.70_deg4_q20` | 64 | 0.698 | 3.91 | 4 | 20 | 6.51 | 9 | 5250 | 10809 | 0.486 | 15 | 12 | 1.250 |
| `jacobi_n64_rho0.70_deg8_q20` | 64 | 0.697 | 7.69 | 8 | 20 | 6.17 | 9 | 10332 | 20233 | 0.511 | 16 | 13 | 1.231 |
| `jacobi_n64_rho0.90_deg4_q20` | 64 | 0.898 | 3.91 | 4 | 20 | 6.84 | 10 | 5250 | 11335 | 0.463 | 15 | 12 | 1.250 |
| `jacobi_n64_rho0.90_deg8_q20` | 64 | 0.892 | 7.69 | 8 | 20 | 6.32 | 9 | 10332 | 20701 | 0.499 | 16 | 13 | 1.231 |
| `jacobi_n128_rho0.50_deg4_q20` | 128 | 0.497 | 3.95 | 4 | 20 | 6.36 | 9 | 10626 | 21402 | 0.496 | 15 | 12 | 1.250 |
| `jacobi_n128_rho0.50_deg8_q20` | 128 | 0.499 | 7.84 | 8 | 20 | 6.01 | 9 | 21084 | 40306 | 0.523 | 16 | 13 | 1.231 |
| `jacobi_n128_rho0.70_deg4_q20` | 128 | 0.699 | 3.95 | 4 | 20 | 6.59 | 10 | 10626 | 22164 | 0.479 | 15 | 12 | 1.250 |
| `jacobi_n128_rho0.70_deg8_q20` | 128 | 0.695 | 7.84 | 8 | 20 | 6.18 | 9 | 21084 | 41355 | 0.510 | 16 | 13 | 1.231 |
| `jacobi_n128_rho0.90_deg4_q20` | 128 | 0.896 | 3.95 | 4 | 20 | 6.53 | 10 | 10626 | 21945 | 0.484 | 15 | 12 | 1.250 |
| `jacobi_n128_rho0.90_deg8_q20` | 128 | 0.897 | 7.84 | 8 | 20 | 6.29 | 9 | 21084 | 42075 | 0.501 | 16 | 13 | 1.231 |
| `jacobi_n32_rho0.50_deg4_q24` | 32 | 0.499 | 3.81 | 4 | 24 | 7.61 | 11 | 3050 | 6122 | 0.498 | 15 | 12 | 1.250 |
| `jacobi_n32_rho0.50_deg8_q24` | 32 | 0.499 | 7.38 | 8 | 24 | 7.42 | 10 | 5900 | 11556 | 0.511 | 16 | 13 | 1.231 |
| `jacobi_n32_rho0.70_deg4_q24` | 32 | 0.689 | 3.81 | 4 | 24 | 7.83 | 11 | 3050 | 6295 | 0.485 | 15 | 12 | 1.250 |
| `jacobi_n32_rho0.70_deg8_q24` | 32 | 0.700 | 7.38 | 8 | 24 | 7.54 | 11 | 5900 | 11748 | 0.502 | 16 | 13 | 1.231 |
| `jacobi_n32_rho0.90_deg4_q24` | 32 | 0.895 | 3.81 | 4 | 24 | 7.80 | 11 | 3050 | 6264 | 0.487 | 15 | 12 | 1.250 |
| `jacobi_n32_rho0.90_deg8_q24` | 32 | 0.878 | 7.38 | 8 | 24 | 7.65 | 11 | 5900 | 11909 | 0.495 | 16 | 13 | 1.231 |
| `jacobi_n64_rho0.50_deg4_q24` | 64 | 0.498 | 3.91 | 4 | 24 | 7.65 | 11 | 6250 | 12619 | 0.495 | 15 | 12 | 1.250 |
| `jacobi_n64_rho0.50_deg8_q24` | 64 | 0.499 | 7.69 | 8 | 24 | 7.36 | 11 | 12300 | 23921 | 0.514 | 16 | 13 | 1.231 |
| `jacobi_n64_rho0.70_deg4_q24` | 64 | 0.683 | 3.91 | 4 | 24 | 7.80 | 11 | 6250 | 12855 | 0.486 | 15 | 12 | 1.250 |
| `jacobi_n64_rho0.70_deg8_q24` | 64 | 0.697 | 7.69 | 8 | 24 | 7.48 | 11 | 12300 | 24298 | 0.506 | 16 | 13 | 1.231 |
| `jacobi_n64_rho0.90_deg4_q24` | 64 | 0.896 | 3.91 | 4 | 24 | 7.91 | 11 | 6250 | 13026 | 0.480 | 15 | 12 | 1.250 |
| `jacobi_n64_rho0.90_deg8_q24` | 64 | 0.880 | 7.69 | 8 | 24 | 7.73 | 11 | 12300 | 25077 | 0.490 | 16 | 13 | 1.231 |
| `jacobi_n128_rho0.50_deg4_q24` | 128 | 0.498 | 3.95 | 4 | 24 | 7.77 | 11 | 12650 | 25900 | 0.488 | 15 | 12 | 1.250 |
| `jacobi_n128_rho0.50_deg8_q24` | 128 | 0.500 | 7.84 | 8 | 24 | 7.38 | 11 | 25100 | 48932 | 0.513 | 16 | 13 | 1.231 |
| `jacobi_n128_rho0.70_deg4_q24` | 128 | 0.696 | 3.95 | 4 | 24 | 7.89 | 11 | 12650 | 26289 | 0.481 | 15 | 12 | 1.250 |
| `jacobi_n128_rho0.70_deg8_q24` | 128 | 0.697 | 7.84 | 8 | 24 | 7.57 | 11 | 25100 | 50152 | 0.500 | 16 | 13 | 1.231 |
| `jacobi_n128_rho0.90_deg4_q24` | 128 | 0.899 | 3.95 | 4 | 24 | 7.95 | 12 | 12650 | 26501 | 0.477 | 15 | 12 | 1.250 |
| `jacobi_n128_rho0.90_deg8_q24` | 128 | 0.899 | 7.84 | 8 | 24 | 7.57 | 11 | 25100 | 50129 | 0.501 | 16 | 13 | 1.231 |

## Interpretation

- `storage ratio > 1` means signed-digit coefficient templates reduce coefficient storage/bandwidth versus direct `q`-bit storage.
- `row speedup > 1` means the constant-coefficient front-end is shallower than the generic variable-by-variable selector front-end in this proxy.
- This report is only intended to answer whether constant specialization is worth modeling and then implementing in RTL.
