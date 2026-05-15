# Parallel-In Digit-Serial Online Affine Operator

This directory contains the current paper mainline. The target operator is a bounded affine fixed-point iteration:

$$
x^{(k+1)} = Gx^{(k)} + c
$$

The research question is whether a parallel-in, digit-serial online affine operator can reduce online delay and DSP usage relative to the original serial-serial integrated online operator, while retaining a defensible comparison against a conventional fixed-point DSP-MAC baseline.

PageRank is the representative workload because its state, coefficients, and convergence rule are naturally bounded:

$$
r^{(k+1)} = \beta M r^{(k)} + (1-\beta)\frac{1}{n}e
$$

## Current Scope

The repository keeps four comparison layers:

- `P0`: original paper reported PageRank result, used only as prior-work reference.
- `P1`: original serial-serial online operator rerun or wrapper, used as prior RTL reference.
- `P3-SP`: this work, parallel-in digit-serial online affine operator.
- `P4-SP`: conventional fixed-point DSP-MAC baseline with the same PageRank fixture.

Old non-mainline solver explorations have been removed from the tracked repository. They are not part of the current paper claim.

## Documents

- [`PAPER_RESULTS_INDEX.md`](./PAPER_RESULTS_INDEX.md): paper-facing result index.
- [`PARALLEL_IN_OPERATOR_PAPER_MATH.md`](./PARALLEL_IN_OPERATOR_PAPER_MATH.md): operator definition, numerical contract, and paper math.
- [`PARALLEL_IN_ONLINE_DELAY_DERIVATION.md`](./PARALLEL_IN_ONLINE_DELAY_DERIVATION.md): strict derivation of the parallel-in online delay.
- [`PRIOR_ONLINE_COMPARISON.md`](./PRIOR_ONLINE_COMPARISON.md): original paper and baseline comparison contract.
- [`PAGERANK_RUNTIME_OPERATION_SPEC.md`](./PAGERANK_RUNTIME_OPERATION_SPEC.md): PageRank workload and cycle accounting.
- [`WORKLOADS_AND_BASELINES.md`](./WORKLOADS_AND_BASELINES.md): current workload and baseline policy.
- [`BOUNDED_ESTIMATE_SELECTOR.md`](./BOUNDED_ESTIMATE_SELECTOR.md): selector/timing optimization notes.
- [`ONLINE_ARITHMETIC_PAPER_NOTES.md`](./ONLINE_ARITHMETIC_PAPER_NOTES.md): external online-arithmetic notes.
- [`OPERATOR_SOURCE_REVIEW.md`](./OPERATOR_SOURCE_REVIEW.md): review of the prior RTL.
- [`ORIGINAL_PAPER_REANALYSIS.md`](./ORIGINAL_PAPER_REANALYSIS.md): reanalysis of the original paper scope and limitations.

## Main Scripts

- [`make_pagerank_parallel_in_fractional_vectors.py`](./make_pagerank_parallel_in_fractional_vectors.py): generates the current PageRank fractional fixture.
- [`run_parallel_in_fractional_eval.py`](./run_parallel_in_fractional_eval.py): runs P3-SP and P4-SP functional/cycle checkpoints.
- [`run_parallel_in_bound_sweep.py`](./run_parallel_in_bound_sweep.py): sweeps the parallel-in delay bound.
- [`run_parallel_in_paper_reports.py`](./run_parallel_in_paper_reports.py): regenerates paper-facing summary reports.
- [`run_parallel_in_route_sweep.py`](./run_parallel_in_route_sweep.py): runs U55C out-of-context route sweeps.
- [`run_prior_fractional_wavefront_sweep.py`](./run_prior_fractional_wavefront_sweep.py): prior serial-serial wavefront reference.
- [`run_prior_fractional_feedback_eval.py`](./run_prior_fractional_feedback_eval.py): prior feedback-loop reference.
- [`benchmark_numpy_pagerank_cpu.py`](./benchmark_numpy_pagerank_cpu.py): CPU NumPy/OpenBLAS reference measurement.

## RTL Entry Points

- [`prior_rtl/iter_parallel_in_online_mma8_frac_core.v`](./prior_rtl/iter_parallel_in_online_mma8_frac_core.v): P3-SP online affine core.
- [`prior_rtl/iter_parallel_in_online_mma8_global_wavefront_top.v`](./prior_rtl/iter_parallel_in_online_mma8_global_wavefront_top.v): P3-SP wavefront top.
- [`prior_rtl/iter_parallel_in_online_mma8_global_feedback_top.v`](./prior_rtl/iter_parallel_in_online_mma8_global_feedback_top.v): P3-SP feedback top.
- [`prior_rtl/iter_parallel_in_conv_mma8_parallel_rows_top.v`](./prior_rtl/iter_parallel_in_conv_mma8_parallel_rows_top.v): P4-SP conventional parallel-row baseline.
- [`prior_rtl/iter_prior_online_mma8_global_wavefront_top.v`](./prior_rtl/iter_prior_online_mma8_global_wavefront_top.v): P1 prior wavefront reference.
- [`prior_rtl/iter_prior_online_mma8_global_feedback_top.v`](./prior_rtl/iter_prior_online_mma8_global_feedback_top.v): P1 prior feedback reference.
- [`rtl/iter_fixed_degree_template_unpack.v`](./rtl/iter_fixed_degree_template_unpack.v): fixed-degree template unpacking support.
- [`rtl/conv_signed_row_update_delta_slice_pipe.v`](./rtl/conv_signed_row_update_delta_slice_pipe.v): conventional fixed-point row-update support.

## Generated Reports

- [`generated/parallel_in_fractional_eval.md`](./generated/parallel_in_fractional_eval.md)
- [`generated/parallel_in_bound_sweep.md`](./generated/parallel_in_bound_sweep.md)
- [`generated/parallel_in_cycle_ablation.md`](./generated/parallel_in_cycle_ablation.md)
- [`generated/parallel_in_routed_main_results.md`](./generated/parallel_in_routed_main_results.md)
- [`generated/paper_baseline_fairness_table.md`](./generated/paper_baseline_fairness_table.md)
- [`generated/numpy_pagerank_cpu_32thread_benchmark.md`](./generated/numpy_pagerank_cpu_32thread_benchmark.md)

## Current Status

The current routed evidence is not a latency win over the conventional DSP-MAC baseline. The defensible result is that P3-SP provides a zero-DSP online affine datapath and lower dynamic power in selected routed checkpoints, at the cost of more LUT/CARRY and longer cycles. The next paper-quality step is to tighten the same-shape baseline and report these tradeoffs without mixing operator-level, feedback-loop, and CPU-only measurements.
