`timescale 1ns / 1ps

// Minimal integrated slice:
//
//   const-coeff row update -> row-local delta/L_inf certification
//
// This is not the final solver top. It exists to lock the intended boundary
// between the specialized affine row-update datapath and the row-local
// certification path before the iteration controller is introduced.

module online_row_update_delta_slice #(
    parameter integer bit_width = 8,
    parameter integer bound_width = bit_width + 5
) (
    input                               i_clk,
    input                               i_rst,
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
    input      [bit_width + 2 : 0]      i_x_old_p,
    input      [bit_width + 2 : 0]      i_x_old_n,
    input      [bound_width - 1 : 0]    i_tail_bound,
    input      [bound_width - 1 : 0]    i_eps_d,
    output                              o_valid,
    output     [bit_width + 2 : 0]      o_sum_p,
    output     [bit_width + 2 : 0]      o_sum_n,
    output signed [bit_width + 4 : 0]   o_delta_word,
    output     [bound_width - 1 : 0]    o_abs_prefix,
    output     [bound_width - 1 : 0]    o_abs_upper,
    output     [bound_width - 1 : 0]    o_abs_lower,
    output                              o_cert_converged,
    output                              o_cert_not_converged,
    output     [1 : 0]                  o_cert_state
);

    wire                            w_valid;
    wire [bit_width + 2 : 0]        w_sum_p;
    wire [bit_width + 2 : 0]        w_sum_n;

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
        .o_valid(w_valid),
        .o_sum_p(w_sum_p),
        .o_sum_n(w_sum_n)
    );

    online_delta_linf_cert_core #(
        .data_width(bit_width + 3),
        .bound_width(bound_width)
    ) delta_cert_core (
        .i_valid(w_valid),
        .i_x_new_p(w_sum_p),
        .i_x_new_n(w_sum_n),
        .i_x_old_p(i_x_old_p),
        .i_x_old_n(i_x_old_n),
        .i_tail_bound(i_tail_bound),
        .i_eps_d(i_eps_d),
        .o_valid(o_valid),
        .o_delta_word(o_delta_word),
        .o_abs_prefix(o_abs_prefix),
        .o_abs_upper(o_abs_upper),
        .o_abs_lower(o_abs_lower),
        .o_cert_converged(o_cert_converged),
        .o_cert_not_converged(o_cert_not_converged),
        .o_cert_state(o_cert_state)
    );

    assign o_sum_p = w_sum_p;
    assign o_sum_n = w_sum_n;

endmodule
