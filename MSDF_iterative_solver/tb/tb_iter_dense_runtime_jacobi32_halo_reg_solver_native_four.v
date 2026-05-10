`timescale 1ns / 1ps

`define JACOBI32_HALO
`define JACOBI32_HALO_REG
`define JACOBI32_SOLVER_NATIVE_RUNTIME
`define JACOBI32_FOUR_ITER_COMPARE
`define JACOBI32_NUM_ITERS_VALUE 4
`define JACOBI32_NUM_GOLD_ITERS_VALUE 6
`define JACOBI32_SIGNED_DIGIT_STATE_COMPARE
`include "tb_iter_dense_runtime_jacobi32_blockdiag_multi.v"
