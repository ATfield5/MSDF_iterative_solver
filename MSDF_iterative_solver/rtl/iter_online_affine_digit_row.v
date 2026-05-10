`timescale 1ns / 1ps

// Single-row online datapath:
//
//   replayed source digits
//   -> affine accumulated vector
//   -> residual/output-update loop
//   -> final solver digit stream
//
// This is the first end-to-end row-level implementation of the all-digit-stream
// path.  It does not include delta/certification yet.

module iter_online_affine_digit_row #(
    parameter integer bit_width = 8,
    parameter integer data_width = bit_width + 3,
    parameter integer sample_width = 5,
    parameter integer residual_width = data_width + 1
) (
    input                               i_clk,
    input                               i_rst,
    input                               i_start,
    input                               i_ena,
    input                               i_x0_p,
    input                               i_x0_n,
    input                               i_x1_p,
    input                               i_x1_n,
    input                               i_x2_p,
    input                               i_x2_n,
    input                               i_x3_p,
    input                               i_x3_n,
    input      [bit_width - 1 : 0]      i_coeff0_vec_p,
    input      [bit_width - 1 : 0]      i_coeff0_vec_n,
    input      [bit_width - 1 : 0]      i_coeff1_vec_p,
    input      [bit_width - 1 : 0]      i_coeff1_vec_n,
    input      [bit_width - 1 : 0]      i_coeff2_vec_p,
    input      [bit_width - 1 : 0]      i_coeff2_vec_n,
    input      [bit_width - 1 : 0]      i_coeff3_vec_p,
    input      [bit_width - 1 : 0]      i_coeff3_vec_n,
    input      [bit_width + 1 : 0]      i_bias_vec_p,
    input      [bit_width + 1 : 0]      i_bias_vec_n,
    output                              o_valid,
    output                              o_z_p,
    output                              o_z_n,
    output     [data_width - 1 : 0]     o_affine_sum_p,
    output     [data_width - 1 : 0]     o_affine_sum_n,
    output     [residual_width - 1 : 0] o_residual_p,
    output     [residual_width - 1 : 0] o_residual_n
);

    wire w_affine_valid;
    wire [data_width - 1 : 0] w_affine_sum_p;
    wire [data_width - 1 : 0] w_affine_sum_n;
    reg  [1 : 0] r_start_pipe;

    online_affine_row_update_core #(
        .bit_width(bit_width)
    ) row_update_core (
        .i_clk(i_clk),
        .i_rst(i_rst),
        .i_ena(i_ena),
        .i_x0_p(i_x0_p),
        .i_x0_n(i_x0_n),
        .i_x1_p(i_x1_p),
        .i_x1_n(i_x1_n),
        .i_x2_p(i_x2_p),
        .i_x2_n(i_x2_n),
        .i_x3_p(i_x3_p),
        .i_x3_n(i_x3_n),
        .i_coeff0_vec_p(i_coeff0_vec_p),
        .i_coeff0_vec_n(i_coeff0_vec_n),
        .i_coeff1_vec_p(i_coeff1_vec_p),
        .i_coeff1_vec_n(i_coeff1_vec_n),
        .i_coeff2_vec_p(i_coeff2_vec_p),
        .i_coeff2_vec_n(i_coeff2_vec_n),
        .i_coeff3_vec_p(i_coeff3_vec_p),
        .i_coeff3_vec_n(i_coeff3_vec_n),
        .i_bias_vec_p(i_bias_vec_p),
        .i_bias_vec_n(i_bias_vec_n),
        .o_valid(w_affine_valid),
        .o_sum_p(w_affine_sum_p),
        .o_sum_n(w_affine_sum_n)
    );

    always @(posedge i_clk) begin
        if (i_rst) begin
            r_start_pipe <= 2'b00;
        end else begin
            r_start_pipe[0] <= i_start;
            r_start_pipe[1] <= r_start_pipe[0];
        end
    end

    iter_online_affine_digit_core #(
        .affine_width(data_width),
        .sample_width(sample_width),
        .residual_width(residual_width)
    ) digit_core (
        .i_clk(i_clk),
        .i_rst(i_rst),
        .i_start(r_start_pipe[1]),
        .i_valid(w_affine_valid),
        .i_affine_p(w_affine_sum_p),
        .i_affine_n(w_affine_sum_n),
        .o_valid(o_valid),
        .o_z_p(o_z_p),
        .o_z_n(o_z_n),
        .o_residual_p(o_residual_p),
        .o_residual_n(o_residual_n)
    );

    assign o_affine_sum_p = w_affine_sum_p;
    assign o_affine_sum_n = w_affine_sum_n;

endmodule
