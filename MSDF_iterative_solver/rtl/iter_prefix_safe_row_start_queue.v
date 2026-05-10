`timescale 1ns / 1ps

// Prefix-safe next-iteration row-start queue.
//
// The prefix-safe issue controller can assert multiple row issue pulses in the
// same digit cycle.  A physical row engine usually accepts one row-start command
// per lane per cycle, so this module converts the issue mask into a ready/valid
// command stream.
//
// One bit of storage is kept per row.  This matches the safety contract: each
// row can become prefix-safe only once per scheduler epoch.  New issue pulses
// are recorded with the digit index that made the row safe; the consumer drains
// pending rows in increasing row-id order.

module iter_prefix_safe_row_start_queue #(
    parameter integer num_rows = 4,
    parameter integer data_width = 11,
    parameter integer digit_idx_width = (data_width <= 2) ? 1 : $clog2(data_width),
    parameter integer row_id_width = (num_rows <= 2) ? 1 : $clog2(num_rows),
    parameter integer lead_width = digit_idx_width + 1,
    parameter integer count_width = $clog2(num_rows + 1)
) (
    input                                       i_clk,
    input                                       i_rst,
    input                                       i_start,
    input      [num_rows - 1 : 0]               i_issue_rows,
    input      [digit_idx_width - 1 : 0]        i_issue_digit_idx,
    input                                       i_consumer_ready,
    output                                      o_consumer_valid,
    output     [row_id_width - 1 : 0]           o_consumer_row_id,
    output     [digit_idx_width - 1 : 0]        o_consumer_digit_idx,
    output     [lead_width - 1 : 0]             o_consumer_lead_cycles,
    output     [num_rows - 1 : 0]               o_pending_mask,
    output reg [count_width - 1 : 0]            o_pending_count,
    output reg [31 : 0]                         o_dispatch_count,
    output reg                                  o_duplicate_issue
);

    reg [num_rows - 1 : 0] r_pending_mask;
    reg [num_rows * digit_idx_width - 1 : 0] r_pending_digit_idx;
    reg [num_rows * lead_width - 1 : 0] r_pending_lead_cycles;

    reg [row_id_width - 1 : 0] r_selected_row;
    reg r_selected_valid;

    wire w_fire;
    wire [lead_width - 1 : 0] w_issue_digit_idx_ext;
    wire [lead_width - 1 : 0] w_issue_lead_cycles;

    integer ri;
    integer ci;

    assign o_pending_mask = r_pending_mask;
    assign o_consumer_valid = r_selected_valid;
    assign o_consumer_row_id = r_selected_row;
    assign o_consumer_digit_idx =
        r_pending_digit_idx[r_selected_row * digit_idx_width +: digit_idx_width];
    assign o_consumer_lead_cycles =
        r_pending_lead_cycles[r_selected_row * lead_width +: lead_width];
    assign w_fire = r_selected_valid && i_consumer_ready;
    assign w_issue_digit_idx_ext =
        {{(lead_width - digit_idx_width){1'b0}}, i_issue_digit_idx};
    assign w_issue_lead_cycles =
        (i_issue_digit_idx >= data_width - 1)
            ? {lead_width{1'b0}}
            : (data_width - 1 - w_issue_digit_idx_ext);

    always @(*) begin
        r_selected_valid = 1'b0;
        r_selected_row = {row_id_width{1'b0}};
        for (ri = num_rows - 1; ri >= 0; ri = ri - 1) begin
            if (r_pending_mask[ri]) begin
                r_selected_valid = 1'b1;
                r_selected_row = ri[row_id_width - 1 : 0];
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

            if (w_fire) begin
                r_pending_mask[r_selected_row] <= 1'b0;
                o_dispatch_count <= o_dispatch_count + 1'b1;
            end

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
