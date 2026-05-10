# Digit-Stream Row-Update Exploration

This note records the first attempt to remove the full-word bridge not only at
the state boundary, but also at the row-update output boundary.

## Implemented Experimental RTL

| file | role |
| --- | --- |
| `rtl/iter_online_output_update.v` | generic solver-side version of the original operator library's `output_and_update` primitive |
| `rtl/iter_online_affine_digit_core.v` | residual/output-update loop `v_j = 2 w_j + s_j`, `z_j = select(v_j)`, `w_{j+1} = update(v_j, z_j)` |
| `rtl/iter_online_affine_digit_row.v` | row-level experiment: `online_affine_row_update_core -> iter_online_affine_digit_core` |
| `tb/tb_iter_online_output_update.v` | unit test for the extracted output/update primitive |

## What Passed

The extracted `iter_online_output_update` primitive matches the original
operator behavior on directed positive / negative / zero cases and is suitable
for reuse in the solver path.

## What Failed

The first row-level experiment did **not** match the full-digit bridge when
driven by the current `online_affine_row_update_core`.

Two concrete issues were exposed:

1. `online_affine_row_update_core` emits a per-cycle affine accumulated vector,
   but that vector is still a digit-slice checkpoint signal, not yet a proven
   final online solver-state stream source.

2. Bias handling is architecturally wrong for the all-digit-stream path.
   The current specialized core injects the full bias rail-vector every enabled
   cycle.  A real online solver path needs bias as a digit stream or as a
   mathematically equivalent once-per-row seed, not a repeated per-cycle full
   word.

## Practical Conclusion

The project can keep the new primitives, but the next valid integration step is
not "hook residual update directly to the existing affine core".

The correct next step is:

1. split the current affine row-update into a **no-bias digit-slice producer**;
2. add a **streamed bias path** or a rigorously derived bias seed contract;
3. only then reconnect the row output to the digit-stream state bank and
   replace the full-digit bridge in the runtime top.

Until that redesign lands, the full-digit bridge remains the only validated
row-output path for runtime-level Jacobi closure.
