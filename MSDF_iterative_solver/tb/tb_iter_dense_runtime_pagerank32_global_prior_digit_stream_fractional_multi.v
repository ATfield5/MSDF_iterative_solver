`timescale 1ns / 1ps

// P3 candidate: original prior online row operator with solver-level
// digit-stream state commit.  It uses the same fractional fixture as P2/P4 but
// removes the P2 full-word assembler boundary.

`define PAGERANK32_GLOBAL
`define PAGERANK32_PRIOR_DIGIT_STREAM_RUNTIME
`define PAGERANK32_PRIOR_FRACTIONAL
`define PAGERANK32_PRIOR_FRACTIONAL_CAPTURE
`define PAGERANK32_PRIOR_TOLERANT_CHECK
`define PAGERANK32_PRIOR_TOLERANCE_VALUE 4
`define JACOBI32_SIGNED_DIGIT_STATE_COMPARE
`define JACOBI32_BIT_WIDTH_VALUE 11
`define JACOBI32_NUM_ITERS_VALUE 4
`define JACOBI32_NUM_GOLD_ITERS_VALUE 4
`include "MSDF_iterative_solver/tb/tb_iter_dense_runtime_jacobi32_blockdiag_multi.v"
