# Runtime Top Automated Resource Report

This report is generated from Vivado report files for `iter_dense_small_runtime_top`.

## Memory Style

- `runtime_mem_style=0`: distributed RAM, intended for tiny regression.
- `runtime_mem_style=1`: block RAM, default capacity-mode checkpoint.
- `runtime_mem_style=2`: UltraRAM, reserved for later larger-memory experiments.

## Storage-Depth Sweep

| NTC | NC | rows/cluster | degree | mem | src | global | halo | hr | hreg | cpipe | opipe | cmpipe | stage | WNS | LUT | LUTRAM | FF | CARRY8 | DSP | BRAM | URAM | Dynamic W | Total W |
| ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 2 | 2 | 4 | 4 | 1 | 2 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | routed | 0.898 | 3760 | 0 | 2162 | 132 | 16 | 8.500 | 0 | 0.252 | 3.529 |
| 8 | 2 | 4 | 4 | 1 | 2 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | routed | 0.858 | 3766 | 0 | 2170 | 132 | 16 | 8.500 | 0 | 0.256 | 3.534 |
| 16 | 2 | 4 | 4 | 1 | 2 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | routed | 0.860 | 3765 | 0 | 2174 | 132 | 16 | 8.500 | 0 | 0.260 | 3.538 |
| 32 | 2 | 4 | 4 | 1 | 2 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | routed | 0.966 | 3769 | 0 | 2177 | 132 | 16 | 8.500 | 0 | 0.258 | 3.536 |
| 64 | 2 | 4 | 4 | 1 | 2 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | synth | 1.437 | 3780 | 0 | 2181 | 132 | 16 | 8.500 | 0 | 0.247 | 3.525 |
| 128 | 2 | 4 | 4 | 1 | 2 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | synth | 1.437 | 3783 | 0 | 2186 | 132 | 16 | 8.500 | 0 | 0.250 | 3.528 |
| 256 | 2 | 4 | 4 | 1 | 2 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | synth | 1.437 | 3781 | 0 | 2189 | 132 | 16 | 8.500 | 0 | 0.248 | 3.526 |

## Memory-Style Check

| NTC | NC | rows/cluster | degree | mem | src | global | halo | hr | hreg | cpipe | opipe | cmpipe | stage | WNS | LUT | LUTRAM | FF | CARRY8 | DSP | BRAM | URAM | Dynamic W | Total W |
| ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 2 | 2 | 4 | 4 | 0 | 2 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | routed | 1.054 | 4035 | 276 | 2633 | 132 | 16 | 0 | 0 | 0.215 | 3.492 |
| 2 | 2 | 4 | 4 | 1 | 2 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | routed | 0.898 | 3760 | 0 | 2162 | 132 | 16 | 8.500 | 0 | 0.252 | 3.529 |

## Physical Active-Cluster Sweep

| NTC | NC | rows/cluster | degree | mem | src | global | halo | hr | hreg | cpipe | opipe | cmpipe | stage | WNS | LUT | LUTRAM | FF | CARRY8 | DSP | BRAM | URAM | Dynamic W | Total W |
| ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 2 | 2 | 4 | 4 | 1 | 2 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | routed | 0.898 | 3760 | 0 | 2162 | 132 | 16 | 8.500 | 0 | 0.252 | 3.529 |
| 4 | 4 | 4 | 4 | 1 | 2 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | routed | 0.462 | 6919 | 0 | 3949 | 220 | 32 | 8.500 | 0 | 0.419 | 3.700 |
| 8 | 8 | 4 | 4 | 1 | 2 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | routed | 0.643 | 10267 | 0 | 7520 | 396 | 64 | 8.500 | 0 | 0.620 | 3.905 |

## Global-Source Replay Checkpoint

| NTC | NC | rows/cluster | degree | mem | src | global | halo | hr | hreg | cpipe | opipe | cmpipe | stage | WNS | LUT | LUTRAM | FF | CARRY8 | DSP | BRAM | URAM | Dynamic W | Total W |
| ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 8 | 8 | 4 | 4 | 1 | 5 | 1 | 0 | 0 | 0 | 0 | 0 | 0 | routed | 0.028 | 35495 | 0 | 8495 | 652 | 64 | 9.500 | 0 | 1.903 | 5.216 |

## Halo-Window Replay Checkpoint

| NTC | NC | rows/cluster | degree | mem | src | global | halo | hr | hreg | cpipe | opipe | cmpipe | stage | WNS | LUT | LUTRAM | FF | CARRY8 | DSP | BRAM | URAM | Dynamic W | Total W |
| ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 8 | 8 | 4 | 4 | 1 | 4 | 0 | 1 | 1 | 0 | 0 | 0 | 0 | routed | 0.268 | 20217 | 0 | 8067 | 396 | 64 | 9 | 0 | 1.018 | 4.312 |
| 8 | 8 | 4 | 4 | 1 | 4 | 0 | 1 | 1 | 1 | 0 | 1 | 0 | routed | 0.679 | 20044 | 0 | 8246 | 396 | 64 | 9 | 0 | 0.891 | 4.182 |
| 8 | 8 | 4 | 4 | 1 | 4 | 0 | 1 | 1 | 1 | 0 | 0 | 0 | routed | 1.125 | 20040 | 0 | 8237 | 396 | 64 | 9 | 0 | 0.916 | 4.208 |
| 16 | 16 | 4 | 4 | 1 | 4 | 0 | 1 | 1 | 1 | 0 | 1 | 1 | routed | 0.646 | 41936 | 0 | 16908 | 748 | 128 | 9 | 0 | 1.728 | 5.037 |
| 16 | 16 | 4 | 4 | 1 | 4 | 0 | 1 | 1 | 1 | 0 | 1 | 0 | routed | 0.646 | 41935 | 0 | 16158 | 748 | 128 | 9 | 0 | 1.713 | 5.021 |
| 16 | 16 | 4 | 4 | 1 | 4 | 0 | 1 | 1 | 1 | 1 | 0 | 0 | routed | 0.409 | 43278 | 0 | 17569 | 940 | 128 | 9 | 0 | 1.763 | 5.073 |
| 16 | 16 | 4 | 4 | 1 | 4 | 0 | 1 | 1 | 1 | 0 | 0 | 0 | routed | 0.390 | 41928 | 0 | 16151 | 748 | 128 | 9 | 0 | 1.766 | 5.076 |

## Interpretation

- The storage-depth sweep changes `NUM_TOTAL_CLUSTERS` while keeping `NUM_CLUSTERS=2`; it tests memory capacity scaling.
- The physical active-cluster sweep changes `NUM_CLUSTERS`; it tests datapath replication and is the relevant trend for larger Jacobi row-cluster throughput.
- The memory-style check confirms whether tiny regression and capacity-mode storage are physically different.
- The global-source replay checkpoint is a functional inter-cluster routing baseline; it is expected to be more expensive than the optimized cluster-local path.
- The halo-window replay checkpoint restricts each cluster to a bounded neighboring-cluster source window; it is the intended replacement for the global-source mux on banded workloads.
- Current routed physical scaling reaches `NUM_CLUSTERS=8` (32 active rows) at WNS `0.643` ns.
- Current routed global-source checkpoint reaches `NUM_CLUSTERS=8` (32 active rows) at WNS `0.028` ns.
- Current routed halo-window checkpoint reaches `NUM_CLUSTERS=16` (64 active rows) at WNS `0.646` ns.
