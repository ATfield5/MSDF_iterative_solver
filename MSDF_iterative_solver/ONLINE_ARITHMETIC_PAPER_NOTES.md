# Online Arithmetic Paper Notes for PageRank Microarchitecture

This document records the literature pulled into the local ignored cache under
`external/papers/online_arithmetic/` and how it changes the PageRank RTL plan.
The local PDFs/HTML snapshots are not versioned; only this analysis is tracked.

## Sources Cached Locally

| work | local cache | usable content | key relevance |
| --- | --- | --- | --- |
| Shi, Boland, Constantinides, "Efficient FPGA implementation of digit parallel online arithmetic operators", FPT 2014 | `monash_digit_parallel_online_arithmetic_2014.html` | metadata/abstract | FPGA-aware online adder/multiplier primitives; direct RTL synthesis is area-heavy |
| Usman, Ercegovac, Lee, "Low-Latency Online Multiplier with Reduced Activities and Minimized Interconnect for Inner Product Arrays", 2023 | `low_latency_online_multiplier_2023.pdf/.txt` | open PDF | conversion/append and interconnect reduction for inner-product arrays |
| Usman, Lee, Ercegovac, "Multiplier with Reduced Activities and Minimized Interconnect for Inner Product Arrays", 2022 | `reduced_activity_online_multiplier_2022.pdf/.txt` | open PDF | variable-activity / truncated working precision ideas; not mainline for exact PageRank |
| "Low-cost constant time signed digit selection for most significant bit first multiplication", Microprocessors and Microsystems 2024 | `scidirect_low_cost_digit_selection_2024.html` | access-limited landing/cache only | candidate future selector optimization; do not use as a quantitative baseline until full text is available |
| Moradi Cherati, Jaberipur, Sousa, "Sparse Matrix-Vector Multiplication Based on Online Arithmetic", IEEE Access 2024 | `ulisboa_spmv_online_arithmetic_2024.html` | metadata/abstract; PDF direct download blocked | direct support for online arithmetic in sparse matrix-vector streaming workloads |
| Ibrahim, Usman, Lee, "ECHO: Energy-Efficient Computation Harnessing Online Arithmetic", Electronics 2024 | attempted MDPI cache blocked by CDN; web source used | web metadata/abstract | confirms dependent-operator digit chaining and memory-traffic reduction as the correct online-arithmetic claim |

## Extracted Lessons

1. The FPT 2014 FPGA paper is a warning: naive online arithmetic RTL has large
   FPGA overhead. Their reported result reduces online adder/multiplier area
   overhead substantially by mapping primitives to Xilinx LUT/carry resources.
   Our current P3 LUT/FF overhead is therefore not surprising; the old RTL is
   functional but not FPGA-primitive-aware.

2. The low-latency online multiplier papers focus on conversion/append and
   interconnect. This maps directly to the original `vector_append` and
   `append_and_select` path, which currently replicates eight term lanes even
   when PageRank only needs four effective source terms.

3. The 2024 signed-digit selection work is relevant by topic, but the local
   cache does not include a usable full text. Treat it as a candidate direction
   only: residual digit selection remains a likely v3 optimization, but any
   approximate selection plus correction scheme must be re-derived and tested
   before replacing the current `output_and_update` logic.

4. Online SpMV is the closest workload-level match. It explicitly argues that
   online arithmetic is beneficial for sequential sparse MAC streams, while
   dense matrices can be served efficiently by many conventional units. This
   supports PageRank / bounded-degree sparse iteration as the right workload.

5. Dependent-operator chaining is the defensible solver-level claim: an output
   digit from stage `s` can feed stage `s+1` after online delay. The claim is
   not that a single online MAC is always faster than a DSP MAC.

## Microarchitecture Decision

The 4-term PageRank fractional core is now classified as an experimental resource-cleanup path, not the main paper mechanism. It removes unused term slots, but it does not change the solver execution model and did not change the standalone wavefront cycle count.

The mainline mechanism is therefore solver-level digit feedback:

```text
prior MSDF_MUL_ADD_8 stage 0
-> prior MSDF_MUL_ADD_8 stage 1
-> ...
-> prior MSDF_MUL_ADD_8 stage K-1
-> committed-digit feedback FIFO
-> stage 0 of the next super-step
```

This keeps the bottom operator identical to the prior work and moves the novelty to the solver boundary: committed digits are reused by the next PageRank super-step without requiring a full solver restart.

## Next RTL Steps

1. Keep the 4-term core behind an explicit experimental switch only.
2. Use `iter_prior_online_mma8_global_feedback_top` as the main architectural checkpoint.
3. Integrate the feedback path into the same-shell P3 runtime only after the standalone feedback report proves correctness and stage-wise L1 behavior.
4. Start FPGA-aware online-adder/selector rewrites only after the solver-level feedback path has a measurable throughput story.
