`timescale 1ns / 1ps

// Multi-lane full-word baseline scheduler.
//
// This no-overlap baseline waits for full-word commit and then enqueues all rows
// into the same multi-lane dispatcher used by the prefix-safe path.

module iter_fullword_row_start_multilane_scheduler #(
    parameter integer num_rows = 4,
    parameter integer num_lanes = 2,
    parameter integer data_width = 11,
    parameter integer digit_idx_width = (data_width <= 2) ? 1 : $clog2(data_width),
    parameter integer row_id_width = (num_rows <= 2) ? 1 : $clog2(num_rows),
    parameter integer lead_width = digit_idx_width + 1,
    parameter integer count_width = $clog2(num_rows + 1)
) (
    input                                           i_clk,
    input                                           i_rst,
    input                                           i_start,
    input                                           i_full_commit_valid,
    input      [num_lanes - 1 : 0]                  i_lane_ready,
    output     [num_lanes - 1 : 0]                  o_lane_valid,
    output     [num_lanes * row_id_width - 1 : 0]   o_lane_row_id,
    output     [num_lanes * digit_idx_width - 1 : 0] o_lane_digit_idx,
    output     [num_lanes * lead_width - 1 : 0]     o_lane_lead_cycles,
    output     [num_rows - 1 : 0]                   o_queue_pending_mask,
    output     [count_width - 1 : 0]                o_queue_pending_count,
    output     [31 : 0]                             o_dispatch_count,
    output                                          o_duplicate_issue,
    output reg                                      o_all_issued
);

    localparam [digit_idx_width - 1 : 0] last_digit = data_width - 1;
    wire [num_rows - 1 : 0] w_issue_rows;

    assign w_issue_rows = i_full_commit_valid ? {num_rows{1'b1}} : {num_rows{1'b0}};

    iter_prefix_safe_row_start_multi_lane_dispatcher #(
        .num_rows(num_rows),
        .num_lanes(num_lanes),
        .data_width(data_width),
        .digit_idx_width(digit_idx_width),
        .row_id_width(row_id_width),
        .lead_width(lead_width),
        .count_width(count_width)
    ) dispatcher (
        .i_clk(i_clk),
        .i_rst(i_rst),
        .i_start(i_start),
        .i_issue_rows(w_issue_rows),
        .i_issue_digit_idx(last_digit),
        .i_lane_ready(i_lane_ready),
        .o_lane_valid(o_lane_valid),
        .o_lane_row_id(o_lane_row_id),
        .o_lane_digit_idx(o_lane_digit_idx),
        .o_lane_lead_cycles(o_lane_lead_cycles),
        .o_pending_mask(o_queue_pending_mask),
        .o_pending_count(o_queue_pending_count),
        .o_dispatch_count(o_dispatch_count),
        .o_duplicate_issue(o_duplicate_issue)
    );

    always @(posedge i_clk) begin
        if (i_rst || i_start) begin
            o_all_issued <= 1'b0;
        end else if (i_full_commit_valid) begin
            o_all_issued <= 1'b1;
        end
    end

endmodule
