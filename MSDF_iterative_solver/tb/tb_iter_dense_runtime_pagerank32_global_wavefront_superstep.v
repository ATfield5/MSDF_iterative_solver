`timescale 1ns / 1ps

`define PAGERANK32_GLOBAL
`define PAGERANK32_WAVEFRONT_RUNTIME
`define JACOBI32_NUM_ITERS_VALUE 4
`define JACOBI32_NUM_GOLD_ITERS_VALUE 4
`include "MSDF_iterative_solver/tb/tb_iter_dense_runtime_jacobi32_blockdiag_multi.v"
