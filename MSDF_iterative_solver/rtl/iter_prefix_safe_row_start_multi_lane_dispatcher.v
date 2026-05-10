`timescale 1ns / 1ps

// Multi-lane row-start dispatcher.
//
// This is the multi-lane counterpart of iter_prefix_safe_row_start_queue.  It
// stores one pending command per row and dispatches up to NUM_LANES ready row
// lanes per cycle.  New issue pulses become dispatchable on the next cycle.

module iter_prefix_safe_row_start_multi_lane_dispatcher #(
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
    input      [num_rows - 1 : 0]                   i_issue_rows,
    input      [digit_idx_width - 1 : 0]            i_issue_digit_idx,
    input      [num_lanes - 1 : 0]                  i_lane_ready,
    output reg [num_lanes - 1 : 0]                  o_lane_valid,
    output reg [num_lanes * row_id_width - 1 : 0]   o_lane_row_id,
    output reg [num_lanes * digit_idx_width - 1 : 0] o_lane_digit_idx,
    output reg [num_lanes * lead_width - 1 : 0]     o_lane_lead_cycles,
    output     [num_rows - 1 : 0]                   o_pending_mask,
    output reg [count_width - 1 : 0]                o_pending_count,
    output reg [31 : 0]                             o_dispatch_count,
    output reg                                      o_duplicate_issue
);

    reg [num_rows - 1 : 0] r_pending_mask;
    reg [num_rows * digit_idx_width - 1 : 0] r_pending_digit_idx;
    reg [num_rows * lead_width - 1 : 0] r_pending_lead_cycles;
    reg [num_rows - 1 : 0] r_remaining_mask;
    reg [31 : 0] r_fire_count;

    wire [lead_width - 1 : 0] w_issue_digit_idx_ext;
    wire [lead_width - 1 : 0] w_issue_lead_cycles;

    integer li;
    integer ri;
    integer ci;
    reg r_found;

    assign o_pending_mask = r_pending_mask;
    assign w_issue_digit_idx_ext =
        {{(lead_width - digit_idx_width){1'b0}}, i_issue_digit_idx};
    assign w_issue_lead_cycles =
        (i_issue_digit_idx >= data_width - 1)
            ? {lead_width{1'b0}}
            : (data_width - 1 - w_issue_digit_idx_ext);

    always @(*) begin
        r_remaining_mask = r_pending_mask;
        r_fire_count = 32'd0;
        o_lane_valid = {num_lanes{1'b0}};
        o_lane_row_id = {num_lanes * row_id_width{1'b0}};
        o_lane_digit_idx = {num_lanes * digit_idx_width{1'b0}};
        o_lane_lead_cycles = {num_lanes * lead_width{1'b0}};

        for (li = 0; li < num_lanes; li = li + 1) begin
            r_found = 1'b0;
            if (i_lane_ready[li]) begin
                for (ri = 0; ri < num_rows; ri = ri + 1) begin
                    if (!r_found && r_remaining_mask[ri]) begin
                        o_lane_valid[li] = 1'b1;
                        o_lane_row_id[li * row_id_width +: row_id_width] =
                            ri;
                        o_lane_digit_idx[li * digit_idx_width +: digit_idx_width] =
                            r_pending_digit_idx[ri * digit_idx_width +: digit_idx_width];
                        o_lane_lead_cycles[li * lead_width +: lead_width] =
                            r_pending_lead_cycles[ri * lead_width +: lead_width];
                        r_remaining_mask[ri] = 1'b0;
                        r_fire_count = r_fire_count + 1'b1;
                        r_found = 1'b1;
                    end
                end
            end
        end
    end

    always @(*) begin
        o_pending_count = {count_width{1'b0}};
        for (ci = 0; ci < num_rows; ci = ci + 1) begin
            if (r_pending_mask[ci]) begin
                o_pending_count = o_pending_count + 1'b1;
            end
        end
    end

    always @(posedge i_clk) begin
        if (i_rst || i_start) begin
            r_pending_mask <= {num_rows{1'b0}};
            r_pending_digit_idx <= {num_rows * digit_idx_width{1'b0}};
            r_pending_lead_cycles <= {num_rows * lead_width{1'b0}};
            o_dispatch_count <= 32'd0;
            o_duplicate_issue <= 1'b0;
        end else begin
            o_duplicate_issue <= |(i_issue_rows & r_pending_mask);
            for (li = 0; li < num_lanes; li = li + 1) begin
                if (o_lane_valid[li]) begin
                    r_pending_mask[o_lane_row_id[li * row_id_width +: row_id_width]]
                        <= 1'b0;
                end
            end
            o_dispatch_count <= o_dispatch_count + r_fire_count;

            for (ri = 0; ri < num_rows; ri = ri + 1) begin
                if (i_issue_rows[ri]) begin
                    r_pending_mask[ri] <= 1'b1;
                    r_pending_digit_idx[ri * digit_idx_width +: digit_idx_width]
                        <= i_issue_digit_idx;
                    r_pending_lead_cycles[ri * lead_width +: lead_width]
                        <= w_issue_lead_cycles;
                end
            end
        end
    end

endmodule
