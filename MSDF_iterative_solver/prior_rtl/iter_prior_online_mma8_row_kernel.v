`timescale 1ns / 1ps

// Adapter from the current fixed-degree solver row interface to the prior
// paper's MSDF_MUL_ADD_8 operator.
//
// This is the first P2 building block.  It deliberately preserves the original
// operator's digit-stream boundary: source state digits and coefficient digits
// are fed for bit_width cycles, and the operator emits online output digits
// with its own int/unit/frac flags.  Full-word assembly, state commit and
// PageRank L1 certification stay outside this adapter.
//
// Dependency: compile this module together with MSDF_operator_srcs/.../
// MSDF_MUL_ADD_8.v and its primitive modules.

module iter_prior_online_mma8_row_kernel #(
    parameter integer degree = 4,
    parameter integer bit_width = 8,
    parameter integer digit_idx_width = (bit_width <= 2) ? 1 : $clog2(bit_width)
) (
    input                                               i_clk,
    input                                               i_rst,
    input                                               i_valid_digit,
    input      [digit_idx_width - 1 : 0]                i_digit_idx,
    input      [degree - 1 : 0]                         i_state_digit_p_terms,
    input      [degree - 1 : 0]                         i_state_digit_n_terms,
    input      [degree * bit_width - 1 : 0]             i_coeff_p_terms,
    input      [degree * bit_width - 1 : 0]             i_coeff_n_terms,
    input                                               i_bias_digit_p,
    input                                               i_bias_digit_n,
    output                                              o_z_p,
    output                                              o_z_n,
    output                                              o_int,
    output                                              o_unit,
    output                                              o_frac
);

    reg [7 : 0] r_x_p;
    reg [7 : 0] r_x_n;
    reg [7 : 0] r_y_p;
    reg [7 : 0] r_y_n;
    integer ti;
    integer bit_sel;

    always @(*) begin
        bit_sel = bit_width - 1 - i_digit_idx;
        r_x_p = 8'h00;
        r_x_n = 8'h00;
        r_y_p = 8'h00;
        r_y_n = 8'h00;

        for (ti = 0; ti < degree; ti = ti + 1) begin
            if (ti < 8) begin
                r_x_p[ti] = i_state_digit_p_terms[ti];
                r_x_n[ti] = i_state_digit_n_terms[ti];
                r_y_p[ti] = i_coeff_p_terms[ti * bit_width + bit_sel];
                r_y_n[ti] = i_coeff_n_terms[ti * bit_width + bit_sel];
            end
        end
    end

    MSDF_MUL_ADD_8 #(
        .bit_width(bit_width)
    ) prior_op (
        .i_clk(i_clk),
        .i_rst(i_rst),
        .i_ena(i_valid_digit),
        .i_x_p(r_x_p),
        .i_x_n(r_x_n),
        .i_y_p(r_y_p),
        .i_y_n(r_y_n),
        .i_a_p(i_bias_digit_p),
        .i_a_n(i_bias_digit_n),
        .o_z_p(o_z_p),
        .o_z_n(o_z_n),
        .o_int(o_int),
        .o_unit(o_unit),
        .o_frac(o_frac)
    );

endmodule
