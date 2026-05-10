`timescale 1ns / 1ps

// Prefix-safe two-stage scheduler.
//
// This wrapper is the practical boundary for cross-iteration stencil streaming:
//
//   producer prefix stream
//     -> prefix-safe per-row issue controller
//     -> row-start queue
//     -> next-iteration row-engine ready/valid command
//
// The issue controller registers issue pulses.  Therefore the digit index that
// caused an issue must be delayed by one cycle before it is attached to the
// row-start queue entry.

module iter_prefix_safe_two_stage_scheduler #(
    parameter integer num_rows = 4,
    parameter integer degree = 3,
    parameter integer data_width = 11,
    parameter integer coeff_width = 8,
    parameter integer margin_width = 24,
    parameter integer digit_idx_width = (data_width <= 2) ? 1 : $clog2(data_width),
    parameter integer row_id_width = (num_rows <= 2) ? 1 : $clog2(num_rows),
    parameter integer lead_width = digit_idx_width + 1,
    parameter integer count_width = $clog2(num_rows + 1)
) (
    input                                                   i_clk,
    input                                                   i_rst,
    input                                                   i_start,
    input                                                   i_valid_prefix,
    input      [digit_idx_width - 1 : 0]                    i_digit_idx,
    input      [num_rows * degree * coeff_width - 1 : 0]    i_coeff_abs_terms_rows,
    input      [num_rows * margin_width - 1 : 0]            i_selection_margin_rows,
    input                                                   i_consumer_ready,
    output                                                  o_consumer_valid,
    output     [row_id_width - 1 : 0]                       o_consumer_row_id,
    output     [digit_idx_width - 1 : 0]                    o_consumer_digit_idx,
    output     [lead_width - 1 : 0]                         o_consumer_lead_cycles,
    output     [num_rows - 1 : 0]                           o_row_issue_pulse,
    output     [num_rows - 1 : 0]                           o_row_issued_mask,
    output     [num_rows - 1 : 0]                           o_queue_pending_mask,
    output     [count_width - 1 : 0]                        o_queue_pending_count,
    output     [31 : 0]                                     o_dispatch_count,
    output                                                  o_duplicate_issue,
    output                                                  o_all_issued
);

    wire [num_rows - 1 : 0] w_row_issue_pulse;
    wire [num_rows - 1 : 0] w_row_issued_mask;
    reg [digit_idx_width - 1 : 0] r_issue_digit_idx;

    assign o_row_issue_pulse = w_row_issue_pulse;
    assign o_row_issued_mask = w_row_issued_mask;

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
        .o_row_issue_pulse(w_row_issue_pulse),
        .o_row_issued_mask(w_row_issued_mask),
        .o_all_issued(o_all_issued),
        .o_tail_bound_rows(),
        .o_weighted_tail_rows()
    );

    iter_prefix_safe_row_start_queue #(
        .num_rows(num_rows),
        .data_width(data_width),
        .digit_idx_width(digit_idx_width),
        .row_id_width(row_id_width),
        .lead_width(lead_width),
        .count_width(count_width)
    ) start_queue (
        .i_clk(i_clk),
        .i_rst(i_rst),
        .i_start(i_start),
        .i_issue_rows(w_row_issue_pulse),
        .i_issue_digit_idx(r_issue_digit_idx),
        .i_consumer_ready(i_consumer_ready),
        .o_consumer_valid(o_consumer_valid),
        .o_consumer_row_id(o_consumer_row_id),
        .o_consumer_digit_idx(o_consumer_digit_idx),
        .o_consumer_lead_cycles(o_consumer_lead_cycles),
        .o_pending_mask(o_queue_pending_mask),
        .o_pending_count(o_queue_pending_count),
        .o_dispatch_count(o_dispatch_count),
        .o_duplicate_issue(o_duplicate_issue)
    );

    always @(posedge i_clk) begin
        if (i_rst || i_start) begin
            r_issue_digit_idx <= {digit_idx_width{1'b0}};
        end else begin
            r_issue_digit_idx <= i_digit_idx;
        end
    end

endmodule
