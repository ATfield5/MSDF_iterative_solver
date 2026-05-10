`timescale 1ns / 1ps

// Strict PageRank same-shell checkpoint for the original paper's fractional
// MSDF_MUL_ADD_8 contract.  Unlike the relaxed integer bring-up wrapper, this
// test uses a prior-compatible fixture and fraction-only output capture.

`define PAGERANK32_GLOBAL
`define PAGERANK32_PRIOR_RUNTIME
`define PAGERANK32_PRIOR_FRACTIONAL
`define PAGERANK32_PRIOR_FRACTIONAL_CAPTURE
`define PAGERANK32_PRIOR_TOLERANT_CHECK
`define PAGERANK32_PRIOR_TOLERANCE_VALUE 4
`define JACOBI32_BIT_WIDTH_VALUE 11
`define JACOBI32_NUM_ITERS_VALUE 4
`define JACOBI32_NUM_GOLD_ITERS_VALUE 4
`include "MSDF_iterative_solver/tb/tb_iter_dense_runtime_jacobi32_blockdiag_multi.v"
