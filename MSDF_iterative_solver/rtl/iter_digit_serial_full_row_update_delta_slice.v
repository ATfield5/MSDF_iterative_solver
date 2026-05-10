`timescale 1ns / 1ps

// Full-digit digit-serial row-update + delta slice.
//
// This is the numerical bridge needed before the automatic digit scheduler can
// drive the runtime solver.  The current online checkpoint consumes one replay
// digit and exposes that digit-slice result.  This module consumes all source
// state digits MSB-first, accumulates the full fixed-point row update, and emits
// the same rail-coded full-word contract as the conventional DSP-MAC baseline.
//
// The accumulation is written as an MSB-first Horner recurrence:
//
//   acc[j+1] = (acc[j] << 1) + sum_t coeff_t * digit_t[j]
//
// After the final digit, bias is added once.  This avoids a dynamic
// digit_idx-controlled shift network in the row datapath; digit_idx remains only
// part of the external scheduler/control contract.
//
// Runtime timing uses an input-localization stage: template coefficients,
// replayed state digits, old state and control are first registered inside the
// row slice, then consumed by the Horner datapath.  This cuts the long routed
// path from the runtime template bank into the row arithmetic.
//
// It is intentionally a conservative bridge, not the final residual-selection
// online operator: accumulation is binary signed internally so equivalence to
// the conventional baseline is easy to verify.  The next step is to replace the
// binary accumulator with the lower-cost online residual datapath once the
// full-digit runtime controller is stable.

module iter_digit_serial_full_row_update_delta_slice #(
    parameter integer degree = 4,
    parameter integer bit_width = 8,
    parameter integer data_width = bit_width + 3,
    parameter integer bias_width = bit_width + 2,
    parameter integer bound_width = bit_width + 5,
    parameter integer acc_width = 32,
    parameter integer enable_prefix_bound = 0,
    // Optional fractional product scaling for same-fixture PageRank tests.
    // The digit-serial Horner path reconstructs sum(state * coeff); when this
    // is positive, the final accumulated product sum is symmetrically rounded
    // by product_shift before adding bias.
    parameter integer product_shift = 0,
    parameter integer digit_idx_width = (data_width <= 2) ? 1 : $clog2(data_width)
) (
    input                                               i_clk,
    input                                               i_rst,
    input                                               i_start,
    input                                               i_valid_digit,
    input                                               i_last_digit,
    input      [digit_idx_width - 1 : 0]                i_digit_idx,
    input      [degree - 1 : 0]                         i_state_digit_p_terms,
    input      [degree - 1 : 0]                         i_state_digit_n_terms,
    input      [degree * bit_width - 1 : 0]             i_coeff_p_terms,
    input      [degree * bit_width - 1 : 0]             i_coeff_n_terms,
    input      [bias_width - 1 : 0]                     i_bias_p,
    input      [bias_width - 1 : 0]                     i_bias_n,
    input      [data_width - 1 : 0]                     i_old_state_p,
    input      [data_width - 1 : 0]                     i_old_state_n,
    input      [bound_width - 1 : 0]                    i_tail_bound,
    output reg                                          o_busy,
    output reg                                          o_valid,
    output reg signed [acc_width - 1 : 0]               o_sum,
    output reg [data_width - 1 : 0]                     o_sum_p,
    output reg [data_width - 1 : 0]                     o_sum_n,
    output reg [bound_width - 1 : 0]                    o_abs_upper,
    output reg                                          o_prefix_valid,
    output reg [bound_width - 1 : 0]                    o_prefix_abs_upper
);

    function automatic signed [acc_width - 1 : 0] sext_coeff;
        input signed [bit_width : 0] coeff_value;
        begin
            sext_coeff = {{(acc_width - bit_width - 1){coeff_value[bit_width]}}, coeff_value};
        end
    endfunction

    function automatic signed [acc_width - 1 : 0] digit_product;
        input digit_p;
        input digit_n;
        input signed [bit_width : 0] coeff_value;
        reg signed [acc_width - 1 : 0] coeff_ext;
        begin
            coeff_ext = sext_coeff(coeff_value);
            if (digit_p && !digit_n) begin
                digit_product = coeff_ext;
            end else if (!digit_p && digit_n) begin
                digit_product = -coeff_ext;
            end else begin
                digit_product = {acc_width{1'b0}};
            end
        end
    endfunction

    function automatic signed [acc_width - 1 : 0] sext_bias;
        input signed [bias_width : 0] bias_value;
        begin
            sext_bias = {{(acc_width - bias_width - 1){bias_value[bias_width]}}, bias_value};
        end
    endfunction

    function automatic signed [acc_width - 1 : 0] sext_state;
        input signed [data_width : 0] state_value;
        begin
            sext_state = {{(acc_width - data_width - 1){state_value[data_width]}}, state_value};
        end
    endfunction

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

    function automatic [acc_width - 1 : 0] coeff_abs;
        input signed [bit_width : 0] coeff_value;
        reg signed [acc_width - 1 : 0] coeff_ext;
        begin
            coeff_ext = sext_coeff(coeff_value);
            coeff_abs = coeff_ext[acc_width - 1] ? (~coeff_ext + 1'b1) : coeff_ext;
        end
    endfunction

    function automatic [acc_width - 1 : 0] residual_count_mask;
        input [digit_idx_width - 1 : 0] digit_idx;
        integer rem_bits;
        reg [acc_width - 1 : 0] one_word;
        begin
            rem_bits = data_width - 1 - digit_idx;
            one_word = {{(acc_width - 1){1'b0}}, 1'b1};
            if (rem_bits <= 0) begin
                residual_count_mask = {acc_width{1'b0}};
            end else begin
                residual_count_mask = (one_word << rem_bits) - one_word;
            end
        end
    endfunction

    integer ti;
    integer rem_bits;
    reg signed [bit_width : 0] w_coeff_term;
    reg signed [bias_width : 0] w_bias_term;
    reg signed [bias_width : 0] w_stage_bias_term;
    reg signed [data_width : 0] w_old_state_term;
    reg signed [acc_width - 1 : 0] w_digit_contrib;
    reg signed [acc_width - 1 : 0] w_base_acc;
    reg signed [acc_width - 1 : 0] w_digit_acc_next;
    reg signed [acc_width - 1 : 0] w_term_acc_next [0 : degree - 1];
    reg signed [acc_width - 1 : 0] w_base_term_acc;
    reg signed [acc_width - 1 : 0] w_term_product;
    reg signed [acc_width - 1 : 0] w_rounded_term_sum;
    reg signed [acc_width - 1 : 0] w_sum_next;
    reg signed [acc_width - 1 : 0] w_prefix_sum;
    reg signed [acc_width - 1 : 0] w_delta;
    reg [acc_width - 1 : 0] w_abs_delta;
    reg [acc_width - 1 : 0] w_abs_sum;
    reg [acc_width - 1 : 0] w_state_max;
    reg [acc_width - 1 : 0] w_coeff_abs_sum;
    reg [acc_width - 1 : 0] w_residual_count;
    reg [acc_width - 1 : 0] w_residual_bound;
    reg [acc_width - 1 : 0] w_abs_upper_full;
    reg [data_width - 1 : 0] w_sum_p;
    reg [data_width - 1 : 0] w_sum_n;
    reg [bound_width - 1 : 0] w_abs_upper;
    reg signed [acc_width - 1 : 0] r_acc;
    reg signed [acc_width - 1 : 0] r_term_acc [0 : degree - 1];
    reg signed [acc_width - 1 : 0] r_term_acc_stage [0 : degree - 1];
    reg r_prefix_pending;
    reg r_final_pending;
    reg signed [acc_width - 1 : 0] r_digit_acc_stage;
    reg [digit_idx_width - 1 : 0] r_digit_idx_stage;
    reg [acc_width - 1 : 0] r_coeff_abs_sum_stage;
    reg [bias_width - 1 : 0] r_bias_p_stage;
    reg [bias_width - 1 : 0] r_bias_n_stage;
    reg [data_width - 1 : 0] r_old_state_p_stage;
    reg [data_width - 1 : 0] r_old_state_n_stage;
    reg [bound_width - 1 : 0] r_tail_bound_stage;
    reg r_start;
    reg r_valid_digit;
    reg r_last_digit;
    reg [digit_idx_width - 1 : 0] r_digit_idx;
    reg [degree - 1 : 0] r_state_digit_p_terms;
    reg [degree - 1 : 0] r_state_digit_n_terms;
    reg [degree * bit_width - 1 : 0] r_coeff_p_terms;
    reg [degree * bit_width - 1 : 0] r_coeff_n_terms;
    reg [bias_width - 1 : 0] r_bias_p;
    reg [bias_width - 1 : 0] r_bias_n;
    reg [data_width - 1 : 0] r_old_state_p;
    reg [data_width - 1 : 0] r_old_state_n;
    reg [bound_width - 1 : 0] r_tail_bound;

    always @(*) begin
        w_bias_term = $signed({1'b0, r_bias_p}) - $signed({1'b0, r_bias_n});
        w_old_state_term = $signed({1'b0, r_old_state_p_stage}) - $signed({1'b0, r_old_state_n_stage});
        w_base_acc = r_start ? {acc_width{1'b0}} : r_acc;
        w_digit_contrib = {acc_width{1'b0}};
        w_coeff_abs_sum = {acc_width{1'b0}};
        w_rounded_term_sum = {acc_width{1'b0}};

        for (ti = 0; ti < degree; ti = ti + 1) begin
            w_coeff_term =
                $signed({1'b0, r_coeff_p_terms[(ti + 1) * bit_width - 1 -: bit_width]}) -
                $signed({1'b0, r_coeff_n_terms[(ti + 1) * bit_width - 1 -: bit_width]});
            w_coeff_abs_sum = w_coeff_abs_sum + coeff_abs(w_coeff_term);
            w_term_product = digit_product(
                r_state_digit_p_terms[ti],
                r_state_digit_n_terms[ti],
                w_coeff_term
            );
            w_digit_contrib = w_digit_contrib + w_term_product;
            w_base_term_acc = r_start ? {acc_width{1'b0}} : r_term_acc[ti];
            w_term_acc_next[ti] = (w_base_term_acc <<< 1) + w_term_product;
            w_rounded_term_sum = w_rounded_term_sum + round_shift_signed(r_term_acc_stage[ti]);
        end

        w_digit_acc_next = (w_base_acc <<< 1) + w_digit_contrib;
        w_sum_next = w_digit_acc_next + sext_bias(w_bias_term);

        w_stage_bias_term = $signed({1'b0, r_bias_p_stage}) - $signed({1'b0, r_bias_n_stage});
        rem_bits = data_width - 1 - r_digit_idx_stage;
        if (product_shift > 0 && enable_prefix_bound == 0) begin
            w_prefix_sum = w_rounded_term_sum + sext_bias(w_stage_bias_term);
        end else if (enable_prefix_bound != 0) begin
            w_prefix_sum = round_shift_signed(r_digit_acc_stage <<< rem_bits) + sext_bias(w_stage_bias_term);
        end else begin
            w_prefix_sum = round_shift_signed(r_digit_acc_stage) + sext_bias(w_stage_bias_term);
        end
        w_delta = w_prefix_sum - sext_state(w_old_state_term);
        w_abs_delta = w_delta[acc_width - 1] ? (~w_delta + 1'b1) : w_delta;
        if (enable_prefix_bound != 0) begin
            w_residual_count = residual_count_mask(r_digit_idx_stage);
            w_residual_bound = r_coeff_abs_sum_stage * w_residual_count;
        end else begin
            w_residual_count = {acc_width{1'b0}};
            w_residual_bound = {acc_width{1'b0}};
        end
        w_abs_upper_full = w_abs_delta + w_residual_bound + r_tail_bound_stage;
        if (w_abs_upper_full >= (1 << bound_width)) begin
            w_abs_upper = {bound_width{1'b1}};
        end else begin
            w_abs_upper = w_abs_upper_full[bound_width - 1 : 0];
        end

        w_state_max = {{(acc_width - data_width){1'b0}}, {data_width{1'b1}}};
        w_abs_sum = w_prefix_sum[acc_width - 1] ? (~w_prefix_sum + 1'b1) : w_prefix_sum;
        if (w_prefix_sum[acc_width - 1]) begin
            w_sum_p = {data_width{1'b0}};
            w_sum_n = (w_abs_sum > w_state_max)
                ? {data_width{1'b1}}
                : w_abs_sum[data_width - 1 : 0];
        end else begin
            w_sum_p = (w_abs_sum > w_state_max)
                ? {data_width{1'b1}}
                : w_abs_sum[data_width - 1 : 0];
            w_sum_n = {data_width{1'b0}};
        end
    end

    always @(posedge i_clk) begin
        if (i_rst) begin
            o_busy <= 1'b0;
            o_valid <= 1'b0;
            o_sum <= {acc_width{1'b0}};
            o_sum_p <= {data_width{1'b0}};
            o_sum_n <= {data_width{1'b0}};
            o_abs_upper <= {bound_width{1'b0}};
            o_prefix_valid <= 1'b0;
            o_prefix_abs_upper <= {bound_width{1'b0}};
            r_acc <= {acc_width{1'b0}};
            r_prefix_pending <= 1'b0;
            r_final_pending <= 1'b0;
            r_digit_acc_stage <= {acc_width{1'b0}};
            r_digit_idx_stage <= {digit_idx_width{1'b0}};
            r_coeff_abs_sum_stage <= {acc_width{1'b0}};
            r_bias_p_stage <= {bias_width{1'b0}};
            r_bias_n_stage <= {bias_width{1'b0}};
            r_old_state_p_stage <= {data_width{1'b0}};
            r_old_state_n_stage <= {data_width{1'b0}};
            r_tail_bound_stage <= {bound_width{1'b0}};
            r_start <= 1'b0;
            r_valid_digit <= 1'b0;
            r_last_digit <= 1'b0;
            r_digit_idx <= {digit_idx_width{1'b0}};
            r_state_digit_p_terms <= {degree{1'b0}};
            r_state_digit_n_terms <= {degree{1'b0}};
            r_coeff_p_terms <= {degree * bit_width{1'b0}};
            r_coeff_n_terms <= {degree * bit_width{1'b0}};
            r_bias_p <= {bias_width{1'b0}};
            r_bias_n <= {bias_width{1'b0}};
            r_old_state_p <= {data_width{1'b0}};
            r_old_state_n <= {data_width{1'b0}};
            r_tail_bound <= {bound_width{1'b0}};
            for (ti = 0; ti < degree; ti = ti + 1) begin
                r_term_acc[ti] <= {acc_width{1'b0}};
                r_term_acc_stage[ti] <= {acc_width{1'b0}};
            end
        end else begin
            o_valid <= 1'b0;
            o_prefix_valid <= (enable_prefix_bound != 0) ? r_prefix_pending : 1'b0;
            o_prefix_abs_upper <= (enable_prefix_bound != 0) ? w_abs_upper : {bound_width{1'b0}};
            r_start <= i_start;
            r_valid_digit <= i_valid_digit;
            r_last_digit <= i_last_digit;
            r_digit_idx <= i_digit_idx;
            r_state_digit_p_terms <= i_state_digit_p_terms;
            r_state_digit_n_terms <= i_state_digit_n_terms;
            r_coeff_p_terms <= i_coeff_p_terms;
            r_coeff_n_terms <= i_coeff_n_terms;
            r_bias_p <= i_bias_p;
            r_bias_n <= i_bias_n;
            r_old_state_p <= i_old_state_p;
            r_old_state_n <= i_old_state_n;
            r_tail_bound <= i_tail_bound;
            r_prefix_pending <= r_valid_digit;
            r_final_pending <= r_valid_digit && r_last_digit;

            if (r_start) begin
                o_busy <= 1'b1;
            end

            r_digit_acc_stage <= w_digit_acc_next;
            for (ti = 0; ti < degree; ti = ti + 1) begin
                r_term_acc_stage[ti] <= w_term_acc_next[ti];
            end
            r_digit_idx_stage <= r_digit_idx;
            r_coeff_abs_sum_stage <= w_coeff_abs_sum;
            r_bias_p_stage <= r_bias_p;
            r_bias_n_stage <= r_bias_n;
            r_old_state_p_stage <= r_old_state_p;
            r_old_state_n_stage <= r_old_state_n;
            r_tail_bound_stage <= r_tail_bound;

            if (r_final_pending) begin
                o_valid <= 1'b1;
                o_sum <= w_prefix_sum;
                o_sum_p <= w_sum_p;
                o_sum_n <= w_sum_n;
                o_abs_upper <= w_abs_upper;
            end

            if (r_valid_digit) begin
                r_acc <= w_digit_acc_next;
                for (ti = 0; ti < degree; ti = ti + 1) begin
                    r_term_acc[ti] <= w_term_acc_next[ti];
                end
                if (r_last_digit) begin
                    o_busy <= 1'b0;
                end
            end
        end
    end

endmodule
