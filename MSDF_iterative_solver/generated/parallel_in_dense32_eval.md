# Parallel-In Dense 32-Term PageRank Checkpoint

This checkpoint tests the real dense `32 x 32` PageRank/inner-product shape:
`32` rows in parallel, `32` real input terms per row, and `32` physical term slots per row.

## Functional Configuration

| item | value |
| --- | ---: |
| rows | 32 |
| real terms per row | 32 |
| physical term slots per row | 32 |
| total physical term slots | 1024 |
| K stages | 4 |
| state digit width | 32 |
| coefficient width | 30 |
| online delay | 2 |
| core accumulator width | 33 |
| DSP | 0 |

The generated fixture is:

`MSDF_iterative_solver/generated/rtl_vectors/pagerank32_global_parallel_in_fractional_deg32`

The bound check still supports `online_delay=2`:

| metric | value |
| --- | ---: |
| max_i(A_i+B_i) | 0.85468749 |
| derived online delay | 2 |
| minimum accumulator width | 33 |

## Icarus Functional Result

The dense-32 feedback test passes with the same cycle count as degree-4 because all 32 terms are consumed in parallel inside each row core:

| metric | value |
| --- | ---: |
| total cycles | 88 |
| final supersteps | 2 |
| captured final-stage digits | 64 |
| first stage0 valid | 4 |
| first stage1 valid | 7 |
| first gap | 3 |
| feedback stall | 0 |
| cert late cycles | 28 |

The key point is that dense-32 does not increase digit count or K-stage control cycles.  It increases the physical contribution tree width and therefore area/routing pressure.

## U55C OOC Synthesis

This is synthesis-only, not routed timing.

| metric | value |
| --- | ---: |
| WNS synth | +0.362 ns |
| LUT | 489773 |
| FF | 25732 |
| CARRY8 | 39244 |
| DSP | 0 |
| BRAM | 0 |
| dynamic power estimate | 8.007 W |

Log:

`logs/parallel_in_dense32_synth_wrapper.log`

Synthesis output directory:

`MSDF_iterative_solver/generated/vivado_parallel_in_wavefront_p3spfbfast2_k4_deg32_pdeg32_u55c_synth`

## Interpretation

Dense-32 is functionally supported after changing the fast2 core contribution reduction from fixed 8-term logic to a 32-term balanced tree.  The architecture still has `first_gap01=3`, so high-bit wavefront timing behavior is preserved.

However, resource cost is large: the design instantiates `32 rows x 4 stages x 32 term slots = 4096` parallel term slots.  This is a valid dense inner-product test, but it is not area-efficient for sparse PageRank.  A routed test is still needed before using dense-32 as a timing claim.
