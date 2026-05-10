`timescale 1ns / 1ps

// Conventional DSP-MAC PageRank runtime using the same fractional fixture as
// the prior-online P2 adapter.  This is the strict P4 same-shell counterpart:
// same graph, same coefficient/bias quantization, same L1 certification, and
// same product scaling contract.

`define PAGERANK32_GLOBAL
`define PAGERANK32_CONV_RUNTIME
`define PAGERANK32_PRIOR_FRACTIONAL
`define JACOBI32_SIGNED_DIGIT_STATE_COMPARE
`define JACOBI32_BIT_WIDTH_VALUE 11
`define JACOBI32_CONV_PRODUCT_SHIFT_VALUE 14
`define JACOBI32_NUM_ITERS_VALUE 4
`define JACOBI32_NUM_GOLD_ITERS_VALUE 4
`include "MSDF_iterative_solver/tb/tb_iter_dense_runtime_jacobi32_blockdiag_multi.v"
