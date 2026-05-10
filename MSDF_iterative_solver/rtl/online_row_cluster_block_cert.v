`timescale 1ns / 1ps

// Minimal row-cluster wrapper:
//
//   row-local U_i -> block maxima Delta_t -> H-based certification
//
// This is the next integration step after row-local delta/L_inf certification.
// It does not yet implement a full iteration controller. Instead, it exposes a
// clean controller-ready cluster interface:
//
// - per-row strict upper bounds
// - precomputed block weights
// - single certified / max_error result for the cluster

module online_row_cluster_block_cert #(
    parameter integer num_rows = 4,
    parameter integer block_size = 2,
    parameter integer bound_width = 16,
    parameter integer coeff_width = 16,
    parameter integer acc_width = 40,
    parameter integer num_blocks = (num_rows + block_size - 1) / block_size,
    parameter integer cert_product_pipeline = 0,
    parameter integer cert_operand_pipeline = 0,
    parameter integer cert_compare_pipeline = 0,
    // Keep the block-bound register by default.  Exact digit-stream runtime
    // paths that do not consume o_block_bounds can bypass it to save one cycle.
    parameter integer input_pipeline = 1,
    // The certification engine already registers its outputs.  Keep this
    // wrapper output register by default for legacy timing, but allow exact
    // digit-stream runtimes to bypass the extra cycle.
    parameter integer output_pipeline = 1
) (
    input                                                  i_clk,
    input                                                  i_rst,
    input      [num_rows - 1 : 0]                       i_valid_rows,
    input      [num_rows * bound_width - 1 : 0]         i_row_abs_upper,
    input      [num_rows * num_blocks * coeff_width - 1 : 0] i_block_weights,
    input      [acc_width - 1 : 0]                      i_eta,
    output                                              o_valid,
    output     [num_blocks * bound_width - 1 : 0]       o_block_bounds,
    output                                              o_certified,
    output     [acc_width - 1 : 0]                      o_max_error
);

    wire w_valid_blocks;
    wire [num_blocks * bound_width - 1 : 0] w_block_bounds;
    wire w_cert_valid;
    wire w_certified;
    wire [acc_width - 1 : 0] w_max_error;
    (* keep = "true", dont_touch = "true" *) reg r_valid_blocks;
    (* keep = "true", dont_touch = "true" *) reg [num_blocks * bound_width - 1 : 0] r_block_bounds;
    reg r_cert_valid;
    reg r_certified;
    reg [acc_width - 1 : 0] r_max_error;
    wire w_cert_input_valid;
    wire [num_blocks * bound_width - 1 : 0] w_cert_input_bounds;

    block_bound_max_pool #(
        .num_rows(num_rows),
        .block_size(block_size),
        .bound_width(bound_width),
        .num_blocks(num_blocks)
    ) bound_pool (
        .i_valid_rows(i_valid_rows),
        .i_row_abs_upper(i_row_abs_upper),
        .o_valid(w_valid_blocks),
        .o_block_bounds(w_block_bounds)
    );

    block_h_cert_engine #(
        .num_rows(num_rows),
        .num_blocks(num_blocks),
        .bound_width(bound_width),
        .coeff_width(coeff_width),
        .acc_width(acc_width),
        .product_pipeline(cert_product_pipeline),
        .operand_pipeline(cert_operand_pipeline),
        .compare_pipeline(cert_compare_pipeline)
    ) cert_engine (
        .i_clk(i_clk),
        .i_rst(i_rst),
        .i_valid(w_cert_input_valid),
        .i_block_bounds(w_cert_input_bounds),
        .i_block_weights(i_block_weights),
        .i_eta(i_eta),
        .o_valid(w_cert_valid),
        .o_certified(w_certified),
        .o_max_error(w_max_error)
    );

    assign o_valid = (output_pipeline != 0) ? r_cert_valid : w_cert_valid;
    assign w_cert_input_valid = (input_pipeline != 0) ? r_valid_blocks : w_valid_blocks;
    assign w_cert_input_bounds = (input_pipeline != 0) ? r_block_bounds : w_block_bounds;

    assign o_block_bounds = (input_pipeline != 0) ? r_block_bounds : w_block_bounds;
    assign o_certified = (output_pipeline != 0) ? r_certified : w_certified;
    assign o_max_error = (output_pipeline != 0) ? r_max_error : w_max_error;

    always @(posedge i_clk) begin
        if (i_rst) begin
            r_valid_blocks <= 1'b0;
            r_block_bounds <= {num_blocks * bound_width{1'b0}};
            r_cert_valid <= 1'b0;
            r_certified <= 1'b0;
            r_max_error <= {acc_width{1'b0}};
        end else begin
            r_valid_blocks <= w_valid_blocks;
            r_block_bounds <= w_block_bounds;
            r_cert_valid <= w_cert_valid;
            r_certified <= w_certified;
            r_max_error <= w_max_error;
        end
    end

endmodule
