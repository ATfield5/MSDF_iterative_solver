`timescale 1ns / 1ps

// Same-shell PageRank smoke for the original paper's operator-level online
// path.  The checks are intentionally relaxed because this checkpoint proves
// runtime integration only; the original MSDF_MUL_ADD_8 numerical contract is
// still being aligned against the PageRank fixed-point golden.

`define PAGERANK32_GLOBAL
`define PAGERANK32_PRIOR_RUNTIME
`define PAGERANK32_PRIOR_RELAXED_CHECK
`define JACOBI32_NUM_ITERS_VALUE 4
`define JACOBI32_NUM_GOLD_ITERS_VALUE 4
`include "MSDF_iterative_solver/tb/tb_iter_dense_runtime_jacobi32_blockdiag_multi.v"
