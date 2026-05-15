# Online_Mul_Add

This repository is the cleaned paper-mainline repository for the **Parallel-In Digit-Serial Online Affine Operator** work.

Previous non-mainline explorations are intentionally not tracked here. They remain outside this repository and should not be pushed to `MSDF_iterative_solver`.

## Scope

- `MSDF_iterative_solver/`: current operator math, PageRank fixture generation, RTL, testbenches, Tcl scripts, and paper-facing reports.
- `MSDF_operator_srcs/`: original integrated online multiply-add RTL used as the prior-operator reference.

The main operator is:

$$
x^{(k+1)} = Gx^{(k)} + c
$$

PageRank is used as the representative bounded affine workload. The repository does not claim to be a general graph accelerator.

## Main Documents

- [`MSDF_iterative_solver/PAPER_RESULTS_INDEX.md`](./MSDF_iterative_solver/PAPER_RESULTS_INDEX.md)
- [`MSDF_iterative_solver/PARALLEL_IN_OPERATOR_PAPER_MATH.md`](./MSDF_iterative_solver/PARALLEL_IN_OPERATOR_PAPER_MATH.md)
- [`MSDF_iterative_solver/PARALLEL_IN_ONLINE_DELAY_DERIVATION.md`](./MSDF_iterative_solver/PARALLEL_IN_ONLINE_DELAY_DERIVATION.md)
- [`MSDF_iterative_solver/PAGERANK_RUNTIME_OPERATION_SPEC.md`](./MSDF_iterative_solver/PAGERANK_RUNTIME_OPERATION_SPEC.md)
- [`MSDF_iterative_solver/PRIOR_ONLINE_COMPARISON.md`](./MSDF_iterative_solver/PRIOR_ONLINE_COMPARISON.md)
- [`MSDF_iterative_solver/WORKLOADS_AND_BASELINES.md`](./MSDF_iterative_solver/WORKLOADS_AND_BASELINES.md)

## Main Commands

Use Vivado/Vitis 2023.2 by default:

```bash
source /tools/Xilinx/Vitis/2023.2/settings64.sh
```

Run the main functional checkpoint:

```bash
conda run -n qas python MSDF_iterative_solver/run_parallel_in_fractional_eval.py
```

Regenerate paper-facing reports:

```bash
conda run -n qas python MSDF_iterative_solver/run_parallel_in_bound_sweep.py
conda run -n qas python MSDF_iterative_solver/run_parallel_in_paper_reports.py
```

Run the optional U55C route sweep:

```bash
conda run -n qas python MSDF_iterative_solver/run_parallel_in_route_sweep.py --kinds p3sp p4sp --stages 4 --degree 8 --physical-degree 8 --clk-ns 5.0
```

## Git Policy

Track source-like assets only: RTL, testbenches, Python/Tcl scripts, Markdown reports, compact JSON/CSV/MEMH fixtures, and prior-reference RTL. Do not track Vivado runs, simulation products, logs, caches, or unrelated historical research branches.
