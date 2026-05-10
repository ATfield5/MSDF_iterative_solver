# Prior Online Original RTL Smoke Report

This is the finite P1 smoke entry for the original `MSDF_MUL_ADD_8` operator.
It verifies that the local copy of the prior paper RTL compiles and emits
operator-level output digits. It does not claim solver-level PageRank behavior.

## Command

```bash
python MSDF_iterative_solver/run_prior_online_original_smoke.py
```

## Icarus Output

```text
COUNTERS prior_mma8_smoke out=74 int=6 unit=1 frac=68 z_p_trace=0000000000000024 z_n_trace=0000000000000000
PASS tb_prior_mma8_smoke
/home/sy/FPGA/MSDF/MSDF_iterative_solver/tb/tb_prior_mma8_smoke.v:131: $finish called at 835000 (1ps)
```

## Interpretation

- `MSDF_MUL_ADD_8` is a valid operator-level integrated online inner-product RTL block.
- It has no state memory, PageRank source template, iteration controller, or convergence logic.
- P2 therefore must wrap this operator into the current runtime shell before it can be used as a fair prior-online baseline.
