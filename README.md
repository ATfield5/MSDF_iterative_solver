# Online_Mul_Add

This repository is split from the original `MSDF` workspace and keeps the online multiply-add / iterative-solver research line.

## Scope

- `MSDF_iterative_solver/`: current solver-level digit-stream PageRank/Jacobi research code, RTL, testbenches, scripts, reports, generated fixtures, and local Vivado experiment outputs.
- `MSDF_operator_srcs/`: original integrated online multiply-add RTL/Vivado project used as the prior-operator reference.

The old exponential / softmax / scientific-exp work remains in the original `MSDF` workspace and is intentionally not part of this repository.

## Git Tracking Policy

All engineering files are copied into this directory for local reproducibility. Git should track only source-like project assets: RTL, testbenches, Python/Tcl scripts, Markdown documents, small JSON/MEMH fixtures, and compact reports. Vivado implementation folders, simulation products, logs, caches, and binary build artifacts are ignored.

## Main Entry Points

- `MSDF_iterative_solver/PAPER_RESULTS_INDEX.md`
- `MSDF_iterative_solver/PARALLEL_IN_OPERATOR_PAPER_MATH.md`
- `MSDF_iterative_solver/PAGERANK_RUNTIME_OPERATION_SPEC.md`
- `MSDF_iterative_solver/PARALLEL_IN_ONLINE_DELAY_DERIVATION.md`
- `MSDF_iterative_solver/run_parallel_in_bound_sweep.py`
- `MSDF_iterative_solver/run_parallel_in_paper_reports.py`
- `MSDF_iterative_solver/run_parallel_in_fractional_eval.py`
- `MSDF_iterative_solver/run_pagerank_fractional_same_scope_eval.py`
- `MSDF_iterative_solver/rtl/`
- `MSDF_iterative_solver/prior_rtl/`
- `MSDF_iterative_solver/tb/`
- `MSDF_operator_srcs/MSDF_Operators/MSDF_Operators/MSDF_Operators.srcs/sources_1/new/`

Use Vivado/Vitis 2023.2 by default:

```bash
source /tools/Xilinx/Vitis/2023.2/settings64.sh
```

Run the main functional comparison with:

```bash
conda run -n qas python MSDF_iterative_solver/run_pagerank_fractional_same_scope_eval.py
```

Run the new parallel-in online MAC checkpoint with:

```bash
conda run -n qas python MSDF_iterative_solver/run_parallel_in_fractional_eval.py
```

Regenerate the paper-facing experiment index and summary reports with:

```bash
conda run -n qas python MSDF_iterative_solver/run_parallel_in_bound_sweep.py
conda run -n qas python MSDF_iterative_solver/run_parallel_in_paper_reports.py
```
