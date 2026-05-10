`timescale 1ns / 1ps

// Pipelined conventional signed fixed-point row-update + delta slice.
//
// Pipeline:
// - stage 1: reconstruct signed rail values and register DEGREE products;
// - stage 2: sum registered products with bias;
// - stage 3: form delta, absolute bound, and rail-coded state writeback.

module conv_signed_row_update_delta_slice_pipe #(
    parameter integer degree = 4,
    parameter integer bit_width = 8,
    parameter integer data_width = bit_width + 3,
    parameter integer bias_width = bit_width + 2,
    parameter integer bound_width = bit_width + 5,
    parameter integer acc_width = 32,
    // Product scaling for fractional fixed-point baselines.  A value of zero
    // preserves the original integer-affine contract.  A positive value stores
    // round((state * coeff) / 2^product_shift) in the product pipeline stage.
    parameter integer product_shift = 0,
    // Insert one extra register between the DSP product and the rounding /
    // shift carry chain.  This is intended for timing-clean fractional
    // conventional baselines at 5 ns.
    parameter integer round_pipeline = 0
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
    reg r_valid_raw;
    reg r_valid_s1;
    reg r_valid_s2;
    reg signed [acc_width - 1 : 0] r_product_raw [0 : degree - 1];
    reg signed [acc_width - 1 : 0] r_bias_raw;
    reg signed [data_width : 0] r_old_state_raw;
    reg [bound_width - 1 : 0] r_tail_raw;
    reg signed [acc_width - 1 : 0] r_product [0 : degree - 1];
    reg signed [acc_width - 1 : 0] r_bias_s1;
    reg signed [data_width : 0] r_old_state_s1;
    reg [bound_width - 1 : 0] r_tail_s1;
    reg signed [acc_width - 1 : 0] r_sum_s2;
    reg signed [data_width : 0] r_old_state_s2;
    reg [bound_width - 1 : 0] r_tail_s2;

    reg signed [data_width : 0] state_term;
    reg signed [bit_width : 0] coeff_term;
    reg signed [bias_width : 0] bias_term;
    reg signed [data_width : 0] old_state_term;
    reg signed [acc_width - 1 : 0] product_stage;
    reg signed [acc_width - 1 : 0] sum_stage;
    reg signed [acc_width - 1 : 0] delta_stage;
    reg [acc_width - 1 : 0] abs_delta_stage;
    reg [acc_width - 1 : 0] abs_sum_stage;
    reg [acc_width - 1 : 0] state_max_stage;

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

    always @(posedge i_clk) begin
        if (i_rst) begin
            r_valid_raw <= 1'b0;
            r_valid_s1 <= 1'b0;
            r_valid_s2 <= 1'b0;
            o_valid <= 1'b0;
            r_bias_raw <= {acc_width{1'b0}};
            r_old_state_raw <= {(data_width + 1){1'b0}};
            r_tail_raw <= {bound_width{1'b0}};
            r_bias_s1 <= {acc_width{1'b0}};
            r_old_state_s1 <= {(data_width + 1){1'b0}};
            r_tail_s1 <= {bound_width{1'b0}};
            r_sum_s2 <= {acc_width{1'b0}};
            r_old_state_s2 <= {(data_width + 1){1'b0}};
            r_tail_s2 <= {bound_width{1'b0}};
            o_sum <= {acc_width{1'b0}};
            o_sum_p <= {data_width{1'b0}};
            o_sum_n <= {data_width{1'b0}};
            o_abs_upper <= {bound_width{1'b0}};
            for (ti = 0; ti < degree; ti = ti + 1) begin
                r_product_raw[ti] <= {acc_width{1'b0}};
                r_product[ti] <= {acc_width{1'b0}};
            end
        end else begin
            r_valid_raw <= i_valid;
            r_valid_s1 <= (round_pipeline != 0) ? r_valid_raw : i_valid;
            r_valid_s2 <= r_valid_s1;
            o_valid <= r_valid_s2;

            bias_term = $signed({1'b0, i_bias_p}) - $signed({1'b0, i_bias_n});
            old_state_term = $signed({1'b0, i_old_state_p}) - $signed({1'b0, i_old_state_n});
            r_bias_raw <= {{(acc_width - bias_width - 1){bias_term[bias_width]}}, bias_term};
            r_old_state_raw <= old_state_term;
            r_tail_raw <= i_tail_bound;
            for (ti = 0; ti < degree; ti = ti + 1) begin
                state_term =
                    $signed({1'b0, i_state_p_terms[(ti + 1) * data_width - 1 -: data_width]}) -
                    $signed({1'b0, i_state_n_terms[(ti + 1) * data_width - 1 -: data_width]});
                coeff_term =
                    $signed({1'b0, i_coeff_p_terms[(ti + 1) * bit_width - 1 -: bit_width]}) -
                    $signed({1'b0, i_coeff_n_terms[(ti + 1) * bit_width - 1 -: bit_width]});
                product_stage = state_term * coeff_term;
                r_product_raw[ti] <= product_stage;
                r_product[ti] <= (round_pipeline != 0)
                    ? round_shift_signed(r_product_raw[ti])
                    : round_shift_signed(product_stage);
            end

            r_bias_s1 <= (round_pipeline != 0)
                ? r_bias_raw
                : {{(acc_width - bias_width - 1){bias_term[bias_width]}}, bias_term};
            r_old_state_s1 <= (round_pipeline != 0)
                ? r_old_state_raw
                : old_state_term;
            r_tail_s1 <= (round_pipeline != 0)
                ? r_tail_raw
                : i_tail_bound;

            sum_stage = r_bias_s1;
            for (ti = 0; ti < degree; ti = ti + 1) begin
                sum_stage = sum_stage + r_product[ti];
            end
            r_sum_s2 <= sum_stage;
            r_old_state_s2 <= r_old_state_s1;
            r_tail_s2 <= r_tail_s1;

            delta_stage = r_sum_s2 - {{(acc_width - data_width - 1){r_old_state_s2[data_width]}}, r_old_state_s2};
            abs_delta_stage = delta_stage[acc_width - 1] ? (~delta_stage + 1'b1) : delta_stage;
            if (abs_delta_stage + r_tail_s2 >= (1 << bound_width)) begin
                o_abs_upper <= {bound_width{1'b1}};
            end else begin
                o_abs_upper <= abs_delta_stage[bound_width - 1 : 0] + r_tail_s2;
            end

            state_max_stage = {{(acc_width - data_width){1'b0}}, {data_width{1'b1}}};
            abs_sum_stage = r_sum_s2[acc_width - 1] ? (~r_sum_s2 + 1'b1) : r_sum_s2;
            o_sum <= r_sum_s2;
            if (r_sum_s2[acc_width - 1]) begin
                o_sum_p <= {data_width{1'b0}};
                o_sum_n <= (abs_sum_stage > state_max_stage)
                    ? {data_width{1'b1}}
                    : abs_sum_stage[data_width - 1 : 0];
            end else begin
                o_sum_p <= (abs_sum_stage > state_max_stage)
                    ? {data_width{1'b1}}
                    : abs_sum_stage[data_width - 1 : 0];
                o_sum_n <= {data_width{1'b0}};
            end
        end
    end

endmodule
