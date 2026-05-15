# Parallel-In Correctness Sweep

Purpose: collect paper-facing PASS/fail status for P2/P3/P4 and the bound sweep.
This report is not a routed resource report.

- git commit: `85344f9ced19e368576ff08d7f5cdb1b033b8a60`
- P3/P4 model max absolute raw-state drift: `31334310`
- P3/P4 model sum absolute raw-state drift: `1002697920`

| entry | status | evidence |
| --- | --- | --- |
| P2 parallel-in online wavefront | PASS | `parallel_in_fractional_eval.md` |
| P3 feedback loop | PASS | `parallel_in_fractional_eval.md` |
| P4 conventional DSP-MAC | PASS | `parallel_in_fractional_eval.md` |
| E1 bound sweep | PASS | `parallel_in_bound_sweep.json` |

The drift row compares generated P3 signed-digit model output with the generated conventional fixed-point model in the same fixture.  The P4 RTL test compares against `conv_gold_state_*` directly.
