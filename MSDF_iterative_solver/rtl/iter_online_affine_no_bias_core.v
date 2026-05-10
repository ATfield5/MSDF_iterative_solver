`timescale 1ns / 1ps

// Fixed-coefficient, no-bias affine contribution producer.
//
// This is the solver-native replacement for the old row-update front-end's
// "full bias every cycle" behavior.  It consumes one source-state digit per
// term and produces the local fixed-coefficient contribution vector.  Bias is
// streamed separately by iter_streamed_bias_source.

module iter_online_affine_no_bias_core #(
    parameter integer bit_width = 8,
    parameter integer degree = 4
) (
    input                                      i_clk,
    input                                      i_rst,
    input                                      i_ena,
    input      [degree-1:0]                    i_state_digit_p_terms,
    input      [degree-1:0]                    i_state_digit_n_terms,
    input      [degree*bit_width-1:0]          i_coeff_p_terms,
    input      [degree*bit_width-1:0]          i_coeff_n_terms,
    output reg                                 o_valid,
    output     [bit_width+1:0]                 o_sum_p,
    output     [bit_width+1:0]                 o_sum_n
);

    wire [bit_width-1:0] w_vec0_p;
    wire [bit_width-1:0] w_vec0_n;
    wire [bit_width-1:0] w_vec1_p;
    wire [bit_width-1:0] w_vec1_n;
    wire [bit_width-1:0] w_vec2_p;
    wire [bit_width-1:0] w_vec2_n;
    wire [bit_width-1:0] w_vec3_p;
    wire [bit_width-1:0] w_vec3_n;

    iter_const_coeff_digit_contrib_rail #(.bit_width(bit_width)) contrib0 (
        .i_digit_p(i_state_digit_p_terms[0]),
        .i_digit_n(i_state_digit_n_terms[0]),
        .i_coeff_vec_p(i_coeff_p_terms[0*bit_width +: bit_width]),
        .i_coeff_vec_n(i_coeff_n_terms[0*bit_width +: bit_width]),
        .o_vec_p(w_vec0_p),
        .o_vec_n(w_vec0_n)
    );

    iter_const_coeff_digit_contrib_rail #(.bit_width(bit_width)) contrib1 (
        .i_digit_p(i_state_digit_p_terms[1]),
        .i_digit_n(i_state_digit_n_terms[1]),
        .i_coeff_vec_p(i_coeff_p_terms[1*bit_width +: bit_width]),
        .i_coeff_vec_n(i_coeff_n_terms[1*bit_width +: bit_width]),
        .o_vec_p(w_vec1_p),
        .o_vec_n(w_vec1_n)
    );

    iter_const_coeff_digit_contrib_rail #(.bit_width(bit_width)) contrib2 (
        .i_digit_p(i_state_digit_p_terms[2]),
        .i_digit_n(i_state_digit_n_terms[2]),
        .i_coeff_vec_p(i_coeff_p_terms[2*bit_width +: bit_width]),
        .i_coeff_vec_n(i_coeff_n_terms[2*bit_width +: bit_width]),
        .o_vec_p(w_vec2_p),
        .o_vec_n(w_vec2_n)
    );

    iter_const_coeff_digit_contrib_rail #(.bit_width(bit_width)) contrib3 (
        .i_digit_p(i_state_digit_p_terms[3]),
        .i_digit_n(i_state_digit_n_terms[3]),
        .i_coeff_vec_p(i_coeff_p_terms[3*bit_width +: bit_width]),
        .i_coeff_vec_n(i_coeff_n_terms[3*bit_width +: bit_width]),
        .o_vec_p(w_vec3_p),
        .o_vec_n(w_vec3_n)
    );

    iter_parallel_online_adder_4_with_obuf #(.bit_width(bit_width)) sum4 (
        .i_clk(i_clk),
        .i_rst(i_rst),
        .i_ena(i_ena),
        .i_x0_p(w_vec0_p),
        .i_x0_n(w_vec0_n),
        .i_x1_p(w_vec1_p),
        .i_x1_n(w_vec1_n),
        .i_x2_p(w_vec2_p),
        .i_x2_n(w_vec2_n),
        .i_x3_p(w_vec3_p),
        .i_x3_n(w_vec3_n),
        .o_z_p(o_sum_p),
        .o_z_n(o_sum_n)
    );

    always @(posedge i_clk) begin
        if (i_rst) begin
            o_valid <= 1'b0;
        end else begin
            o_valid <= i_ena;
        end
    end

endmodule
