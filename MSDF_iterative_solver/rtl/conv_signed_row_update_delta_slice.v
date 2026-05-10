`timescale 1ns / 1ps

// Conventional signed fixed-point row-update + delta slice.
//
// This is a B2-style datapath baseline, not an online arithmetic block. It
// consumes full rail-coded state words, reconstructs signed binary values,
// performs DEGREE parallel coefficient*state products, adds bias, and forms a
// row-local absolute delta bound.

module conv_signed_row_update_delta_slice #(
    parameter integer degree = 4,
    parameter integer bit_width = 8,
    parameter integer data_width = bit_width + 3,
    parameter integer bias_width = bit_width + 2,
    parameter integer bound_width = bit_width + 5,
    parameter integer acc_width = 32,
    // Product scaling for fractional fixed-point baselines.  A value of zero
    // preserves the original integer-affine contract:
    //   sum = bias + sum(state * coeff).
    // A positive value uses symmetric round-to-nearest:
    //   sum = bias + sum(round((state * coeff) / 2^product_shift)).
    parameter integer product_shift = 0
) (
    input                                               i_clk,
    input                                               i_rst,
    input                                               i_valid,
    input      [degree * data_width - 1 : 0]            i_state_p_terms,
    input      [degree * data_width - 1 : 0]            i_state_n_terms,
    input      [degree * bit_width - 1 : 0]             i_coeff_p_terms,
    input      [degree * bit_width - 1 : 0]             i_coeff_n_terms,
    input      [bias_width - 1 : 0]                     i_bias_p,
    input      [bias_width - 1 : 0]                     i_bias_n,
    input      [data_width - 1 : 0]                     i_old_state_p,
    input      [data_width - 1 : 0]                     i_old_state_n,
    input      [bound_width - 1 : 0]                    i_tail_bound,
    output reg                                          o_valid,
    output reg signed [acc_width - 1 : 0]               o_sum,
    output reg [data_width - 1 : 0]                     o_sum_p,
    output reg [data_width - 1 : 0]                     o_sum_n,
    output reg [bound_width - 1 : 0]                    o_abs_upper
);

    integer ti;
    reg signed [data_width : 0] state_term;
    reg signed [bit_width : 0] coeff_term;
    reg signed [bias_width : 0] bias_term;
    reg signed [data_width : 0] old_state_term;
    reg signed [acc_width - 1 : 0] sum_comb;
    reg signed [acc_width - 1 : 0] delta_comb;
    reg [acc_width - 1 : 0] abs_delta_comb;
    reg [bound_width - 1 : 0] abs_saturated_comb;
    reg [acc_width - 1 : 0] abs_sum_comb;
    reg [acc_width - 1 : 0] state_max_comb;
    reg signed [acc_width - 1 : 0] product_comb;
    reg [data_width - 1 : 0] sum_p_comb;
    reg [data_width - 1 : 0] sum_n_comb;

    function signed [acc_width - 1 : 0] round_shift_signed;
        input signed [acc_width - 1 : 0] value;
        reg [acc_width - 1 : 0] abs_value;
        reg [acc_width - 1 : 0] rounded_abs;
        begin
            if (product_shift <= 0) begin
                round_shift_signed = value;
            end else begin
                abs_value = value[acc_width - 1] ? (~value + 1'b1) : value;
                rounded_abs = (abs_value + ({{(acc_width - 1){1'b0}}, 1'b1} << (product_shift - 1))) >> product_shift;
                round_shift_signed = value[acc_width - 1]
                    ? -$signed(rounded_abs)
                    : $signed(rounded_abs);
            end
        end
    endfunction

    always @(*) begin
        bias_term = $signed({1'b0, i_bias_p}) - $signed({1'b0, i_bias_n});
        old_state_term = $signed({1'b0, i_old_state_p}) - $signed({1'b0, i_old_state_n});
        sum_comb = {{(acc_width - bias_width - 1){bias_term[bias_width]}}, bias_term};

        for (ti = 0; ti < degree; ti = ti + 1) begin
            state_term =
                $signed({1'b0, i_state_p_terms[(ti + 1) * data_width - 1 -: data_width]}) -
                $signed({1'b0, i_state_n_terms[(ti + 1) * data_width - 1 -: data_width]});
            coeff_term =
                $signed({1'b0, i_coeff_p_terms[(ti + 1) * bit_width - 1 -: bit_width]}) -
                $signed({1'b0, i_coeff_n_terms[(ti + 1) * bit_width - 1 -: bit_width]});
            (* use_dsp = "yes" *) product_comb = state_term * coeff_term;
            sum_comb = sum_comb + round_shift_signed(product_comb);
        end

        delta_comb = sum_comb - {{(acc_width - data_width - 1){old_state_term[data_width]}}, old_state_term};
        abs_delta_comb = delta_comb[acc_width - 1] ? (~delta_comb + 1'b1) : delta_comb;
        if (abs_delta_comb + i_tail_bound >= (1 << bound_width)) begin
            abs_saturated_comb = {bound_width{1'b1}};
        end else begin
            abs_saturated_comb = abs_delta_comb[bound_width - 1 : 0] + i_tail_bound;
        end

        state_max_comb = {{(acc_width - data_width){1'b0}}, {data_width{1'b1}}};
        abs_sum_comb = sum_comb[acc_width - 1] ? (~sum_comb + 1'b1) : sum_comb;
        if (sum_comb[acc_width - 1]) begin
            sum_p_comb = {data_width{1'b0}};
            sum_n_comb = (abs_sum_comb > state_max_comb)
                ? {data_width{1'b1}}
                : abs_sum_comb[data_width - 1 : 0];
        end else begin
            sum_p_comb = (abs_sum_comb > state_max_comb)
                ? {data_width{1'b1}}
                : abs_sum_comb[data_width - 1 : 0];
            sum_n_comb = {data_width{1'b0}};
        end
    end

    always @(posedge i_clk) begin
        if (i_rst) begin
            o_valid <= 1'b0;
            o_sum <= {acc_width{1'b0}};
            o_sum_p <= {data_width{1'b0}};
            o_sum_n <= {data_width{1'b0}};
            o_abs_upper <= {bound_width{1'b0}};
        end else begin
            o_valid <= i_valid;
            o_sum <= sum_comb;
            o_sum_p <= sum_p_comb;
            o_sum_n <= sum_n_comb;
            o_abs_upper <= abs_saturated_comb;
        end
    end

endmodule
