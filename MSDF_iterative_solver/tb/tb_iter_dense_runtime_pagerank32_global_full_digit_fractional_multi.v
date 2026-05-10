`timescale 1ns / 1ps

// Full-digit digit-serial bridge on the same fractional fixture as P2/P4.
// This is a numerical reference for future solver-native digit-stream work:
// it still materializes full row words, but uses the same product shift as the
// strict fractional PageRank baseline.

`define PAGERANK32_GLOBAL
`define PAGERANK32_PRIOR_FRACTIONAL
`define JACOBI32_SIGNED_DIGIT_STATE_COMPARE
`define JACOBI32_BIT_WIDTH_VALUE 11
`define JACOBI32_CONV_PRODUCT_SHIFT_VALUE 14
`define JACOBI32_NUM_ITERS_VALUE 4
`define JACOBI32_NUM_GOLD_ITERS_VALUE 4
`include "MSDF_iterative_solver/tb/tb_iter_dense_runtime_jacobi32_blockdiag_multi.v"
