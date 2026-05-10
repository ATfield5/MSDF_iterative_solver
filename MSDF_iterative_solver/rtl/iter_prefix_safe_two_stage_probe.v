`timescale 1ns / 1ps

// Two-stage prefix-safe streaming probe.
//
// This module is a small standalone prototype for:
//
//   producer iteration prefix stream
//     -> prefix-safe issue controller
//     -> consumer iteration row-start mask
//
// It does not execute the consumer row arithmetic.  It records when each row
// would be allowed to start relative to full-word commit.  A positive lead cycle
// means the next iteration can begin before digit DATA_WIDTH-1 has arrived.

module iter_prefix_safe_two_stage_probe #(
    parameter integer num_rows = 4,
    parameter integer degree = 3,
    parameter integer data_width = 11,
    parameter integer coeff_width = 8,
    parameter integer margin_width = 24,
    parameter integer digit_idx_width = (data_width <= 2) ? 1 : $clog2(data_width),
    parameter integer lead_width = digit_idx_width + 1
) (
    input                                                   i_clk,
    input                                                   i_rst,
    input                                                   i_start,
    input                                                   i_valid_prefix,
    input      [digit_idx_width - 1 : 0]                    i_digit_idx,
    input      [num_rows * degree * coeff_width - 1 : 0]    i_coeff_abs_terms_rows,
    input      [num_rows * margin_width - 1 : 0]            i_selection_margin_rows,
    output     [num_rows - 1 : 0]                           o_consumer_issue_rows,
    output     [num_rows - 1 : 0]                           o_consumer_issued_mask,
    output reg [num_rows * digit_idx_width - 1 : 0]         o_issue_digit_idx_rows,
    output reg [num_rows * lead_width - 1 : 0]              o_lead_cycles_rows,
    output reg [lead_width - 1 : 0]                         o_max_lead_cycles,
    output reg [31 : 0]                                     o_early_issue_count,
    output                                                  o_all_issued
);

    wire [num_rows - 1 : 0] w_issue_pulse;
    wire [num_rows - 1 : 0] w_issued_mask;
    wire [lead_width - 1 : 0] w_digit_idx_ext;
    reg  [digit_idx_width - 1 : 0] r_issue_digit_idx;
    wire [lead_width - 1 : 0] w_current_lead;

    integer ri;

    assign o_consumer_issue_rows = w_issue_pulse;
    assign o_consumer_issued_mask = w_issued_mask;
    assign w_digit_idx_ext = {{(lead_width - digit_idx_width){1'b0}}, r_issue_digit_idx};
    assign w_current_lead =
        (r_issue_digit_idx >= data_width - 1)
            ? {lead_width{1'b0}}
            : (data_width - 1 - w_digit_idx_ext);

    iter_prefix_safe_issue_controller #(
        .num_rows(num_rows),
        .degree(degree),
        .data_width(data_width),
        .coeff_width(coeff_width),
        .margin_width(margin_width),
        .digit_idx_width(digit_idx_width)
    ) issue_ctrl (
        .i_clk(i_clk),
        .i_rst(i_rst),
        .i_start(i_start),
        .i_valid_prefix(i_valid_prefix),
        .i_digit_idx(i_digit_idx),
        .i_coeff_abs_terms_rows(i_coeff_abs_terms_rows),
        .i_selection_margin_rows(i_selection_margin_rows),
        .o_row_issue_pulse(w_issue_pulse),
        .o_row_issued_mask(w_issued_mask),
        .o_all_issued(o_all_issued),
        .o_tail_bound_rows(),
        .o_weighted_tail_rows()
    );

    always @(posedge i_clk) begin
        if (i_rst || i_start) begin
            r_issue_digit_idx <= {digit_idx_width{1'b0}};
            o_issue_digit_idx_rows <= {num_rows * digit_idx_width{1'b0}};
            o_lead_cycles_rows <= {num_rows * lead_width{1'b0}};
            o_max_lead_cycles <= {lead_width{1'b0}};
            o_early_issue_count <= 32'd0;
        end else begin
            r_issue_digit_idx <= i_digit_idx;
            for (ri = 0; ri < num_rows; ri = ri + 1) begin
                if (w_issue_pulse[ri]) begin
                    o_issue_digit_idx_rows[ri * digit_idx_width +: digit_idx_width] <= r_issue_digit_idx;
                    o_lead_cycles_rows[ri * lead_width +: lead_width] <= w_current_lead;
                    if (w_current_lead > o_max_lead_cycles) begin
                        o_max_lead_cycles <= w_current_lead;
                    end
                    if (w_current_lead != {lead_width{1'b0}}) begin
                        o_early_issue_count <= o_early_issue_count + 1'b1;
                    end
                end
            end
        end
    end

endmodule
