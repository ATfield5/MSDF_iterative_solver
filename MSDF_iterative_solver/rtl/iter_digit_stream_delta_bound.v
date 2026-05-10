`timescale 1ns / 1ps

// Inline digit-stream delta prefix bound.
//
// Consumes aligned old/new MSB-first p/n digits and maintains a signed prefix
// accumulator for delta = x_new - x_old.  The final cycle produces the exact
// full-word delta magnitude; earlier cycles produce a conservative upper bound
// by adding the maximum possible remaining signed-digit tail.

module iter_digit_stream_delta_bound #(
    parameter integer data_width = 11,
    parameter integer bound_width = 13,
    parameter integer acc_width = 32,
    // When set, only the final full-width delta bound is produced.  This is
    // the mode used by the exact solver runtime, where intermediate prefix
    // bounds do not drive scheduling decisions.
    parameter integer final_only = 0,
    parameter integer digit_idx_width = (data_width <= 2) ? 1 : $clog2(data_width)
) (
    input                                      i_clk,
    input                                      i_rst,
    input                                      i_start,
    input                                      i_valid,
    input      [digit_idx_width-1:0]           i_digit_idx,
    input                                      i_new_digit_p,
    input                                      i_new_digit_n,
    input                                      i_old_digit_p,
    input                                      i_old_digit_n,
    output reg                                 o_valid,
    output reg signed [acc_width-1:0]          o_prefix_delta,
    output reg [bound_width-1:0]               o_abs_upper,
    output reg                                 o_final
);

    function automatic signed [acc_width-1:0] digit_to_signed;
        input digit_p;
        input digit_n;
        begin
            if (digit_p && !digit_n) begin
                digit_to_signed = {{(acc_width-1){1'b0}}, 1'b1};
            end else if (!digit_p && digit_n) begin
                digit_to_signed = -{{(acc_width-1){1'b0}}, 1'b1};
            end else begin
                digit_to_signed = {acc_width{1'b0}};
            end
        end
    endfunction

    function automatic [acc_width-1:0] abs_signed;
        input signed [acc_width-1:0] value;
        begin
            abs_signed = value[acc_width-1] ? (~value + 1'b1) : value;
        end
    endfunction

    function automatic [acc_width-1:0] tail_bound_for_remaining;
        input integer remaining_bits;
        reg [acc_width-1:0] one_word;
        begin
            one_word = {{(acc_width-1){1'b0}}, 1'b1};
            if (remaining_bits <= 0) begin
                tail_bound_for_remaining = {acc_width{1'b0}};
            end else begin
                tail_bound_for_remaining = ((one_word << remaining_bits) - one_word) << 1;
            end
        end
    endfunction

    reg signed [acc_width-1:0] r_prefix;
    reg signed [acc_width-1:0] w_delta_digit;
    reg signed [acc_width-1:0] w_prefix_base;
    reg signed [acc_width-1:0] w_prefix_next;
    reg signed [acc_width-1:0] w_prefix_scaled;
    reg [acc_width-1:0] w_abs_upper_full;
    reg [acc_width-1:0] w_abs_final_full;
    reg w_is_final_digit;
    integer w_remaining_bits;

    always @(*) begin
        w_is_final_digit = (i_digit_idx == data_width - 1);
        w_delta_digit =
            digit_to_signed(i_new_digit_p, i_new_digit_n) -
            digit_to_signed(i_old_digit_p, i_old_digit_n);
        w_prefix_base = i_start ? {acc_width{1'b0}} : r_prefix;
        w_prefix_next = (w_prefix_base <<< 1) + w_delta_digit;
        w_abs_final_full = abs_signed(w_prefix_next);
        if (final_only != 0) begin
            w_remaining_bits = 0;
            w_prefix_scaled = w_prefix_next;
            w_abs_upper_full = w_is_final_digit ? w_abs_final_full : {acc_width{1'b0}};
        end else begin
            w_remaining_bits = data_width - 1 - i_digit_idx;
            if (w_remaining_bits <= 0) begin
                w_prefix_scaled = w_prefix_next;
            end else begin
                w_prefix_scaled = w_prefix_next <<< w_remaining_bits;
            end
            w_abs_upper_full =
                abs_signed(w_prefix_scaled) +
                tail_bound_for_remaining(w_remaining_bits);
        end
    end

    always @(posedge i_clk) begin
        if (i_rst) begin
            r_prefix <= {acc_width{1'b0}};
            o_valid <= 1'b0;
            o_prefix_delta <= {acc_width{1'b0}};
            o_abs_upper <= {bound_width{1'b0}};
            o_final <= 1'b0;
        end else begin
            o_valid <= i_valid;
            o_final <= i_valid && w_is_final_digit;
            if (i_valid) begin
                r_prefix <= w_prefix_next;
                o_prefix_delta <= w_prefix_next;
                if (w_abs_upper_full >= (1 << bound_width)) begin
                    o_abs_upper <= {bound_width{1'b1}};
                end else begin
                    o_abs_upper <= w_abs_upper_full[bound_width-1:0];
                end
            end
        end
    end

endmodule
