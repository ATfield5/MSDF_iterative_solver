`timescale 1ns / 1ps

// Adapter from the solver row interface to the native 32-input prior-style
// integrated online MAC.  Unlike iter_prior_online_mma32_row_kernel, this does
// not compose four complete MSDF_MUL_ADD_8 operators.

module iter_prior_online_mma32_native_row_kernel #(
    parameter integer degree = 32,
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

    localparam integer NUM_TERMS = 32;

    reg [NUM_TERMS - 1 : 0] r_x_p;
    reg [NUM_TERMS - 1 : 0] r_x_n;
    reg [NUM_TERMS - 1 : 0] r_y_p;
    reg [NUM_TERMS - 1 : 0] r_y_n;
    integer ti;
    integer bit_sel;

    always @(*) begin
        bit_sel = bit_width - 1 - i_digit_idx;
        r_x_p = {NUM_TERMS{1'b0}};
        r_x_n = {NUM_TERMS{1'b0}};
        r_y_p = {NUM_TERMS{1'b0}};
        r_y_n = {NUM_TERMS{1'b0}};

        for (ti = 0; ti < degree; ti = ti + 1) begin
            if (ti < NUM_TERMS) begin
                r_x_p[ti] = i_state_digit_p_terms[ti];
                r_x_n[ti] = i_state_digit_n_terms[ti];
                r_y_p[ti] = i_coeff_p_terms[ti * bit_width + bit_sel];
                r_y_n[ti] = i_coeff_n_terms[ti * bit_width + bit_sel];
            end
        end
    end

    MSDF_MUL_ADD_32_NATIVE #(
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
