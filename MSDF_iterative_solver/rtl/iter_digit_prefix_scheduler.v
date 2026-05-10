`timescale 1ns / 1ps

// Digit-prefix replay scheduler for the next solver checkpoint.
//
// This module is intentionally independent from the current runtime top.  The
// existing solver still exposes a manual digit-slice contract; this scheduler
// defines the production control contract for automatic MSB-first replay and
// safe intra-iteration prefix gating.
//
// Contract:
// - pulse i_start to begin one full digit sweep;
// - while o_busy is high, o_digit_idx advances from 0 to DATA_WIDTH-1;
// - o_issue_rows masks the base row issue vector by the currently active
//   clusters;
// - if prefix gating is enabled, a cluster is disabled for the remaining digits
//   only after it reports both valid and certified within the same iteration;
// - o_done pulses when the sweep ends, either after the last digit or after all
//   clusters have been gated off.

module iter_digit_prefix_scheduler #(
    parameter integer num_clusters = 8,
    parameter integer num_rows = 4,
    parameter integer data_width = 11,
    parameter integer digit_idx_width = (data_width <= 2) ? 1 : $clog2(data_width)
) (
    input                                               i_clk,
    input                                               i_rst,
    input                                               i_start,
    input                                               i_enable_prefix_gating,
    input      [num_clusters * num_rows - 1 : 0]        i_base_issue_rows,
    input      [num_clusters - 1 : 0]                   i_cluster_valid,
    input      [num_clusters - 1 : 0]                   i_cluster_certified,
    output reg                                          o_busy,
    output reg                                          o_done,
    output reg [digit_idx_width - 1 : 0]                o_digit_idx,
    output reg [num_clusters * num_rows - 1 : 0]        o_issue_rows,
    output reg [num_clusters - 1 : 0]                   o_active_clusters,
    output reg [31 : 0]                                 o_active_digit_cycles,
    output reg [31 : 0]                                 o_gated_digit_cycles,
    output reg [31 : 0]                                 o_cert_prefix_digit_sum,
    output reg [31 : 0]                                 o_certified_block_count
);

    integer ci;
    reg [num_clusters - 1 : 0] r_gate_now;
    reg [num_clusters - 1 : 0] r_next_active_clusters;
    reg [31 : 0] r_inactive_count;
    reg [31 : 0] r_new_cert_count;

    always @(*) begin
        r_gate_now = {num_clusters{1'b0}};
        r_next_active_clusters = o_active_clusters;
        r_inactive_count = 32'd0;
        r_new_cert_count = 32'd0;
        o_issue_rows = {num_clusters * num_rows{1'b0}};

        for (ci = 0; ci < num_clusters; ci = ci + 1) begin
            if (o_busy && o_active_clusters[ci]) begin
                o_issue_rows[ci * num_rows +: num_rows] =
                    i_base_issue_rows[ci * num_rows +: num_rows];
            end

            if (o_busy && !o_active_clusters[ci]) begin
                r_inactive_count = r_inactive_count + 1'b1;
            end

            if (i_enable_prefix_gating &&
                o_busy &&
                o_active_clusters[ci] &&
                i_cluster_valid[ci] &&
                i_cluster_certified[ci]) begin
                r_gate_now[ci] = 1'b1;
                r_new_cert_count = r_new_cert_count + 1'b1;
            end
        end

        r_next_active_clusters = o_active_clusters & ~r_gate_now;
    end

    always @(posedge i_clk) begin
        if (i_rst) begin
            o_busy <= 1'b0;
            o_done <= 1'b0;
            o_digit_idx <= {digit_idx_width{1'b0}};
            o_active_clusters <= {num_clusters{1'b0}};
            o_active_digit_cycles <= 32'd0;
            o_gated_digit_cycles <= 32'd0;
            o_cert_prefix_digit_sum <= 32'd0;
            o_certified_block_count <= 32'd0;
        end else begin
            o_done <= 1'b0;

            if (i_start && !o_busy) begin
                o_busy <= 1'b1;
                o_digit_idx <= {digit_idx_width{1'b0}};
                o_active_clusters <= {num_clusters{1'b1}};
                o_active_digit_cycles <= 32'd0;
                o_gated_digit_cycles <= 32'd0;
                o_cert_prefix_digit_sum <= 32'd0;
                o_certified_block_count <= 32'd0;
            end else if (o_busy) begin
                if (|o_active_clusters) begin
                    o_active_digit_cycles <= o_active_digit_cycles + 1'b1;
                end
                o_gated_digit_cycles <= o_gated_digit_cycles + r_inactive_count;
                o_certified_block_count <= o_certified_block_count + r_new_cert_count;
                o_cert_prefix_digit_sum <=
                    o_cert_prefix_digit_sum + (r_new_cert_count * ({{(32 - digit_idx_width){1'b0}}, o_digit_idx} + 1'b1));

                if ((o_digit_idx == data_width - 1) || (r_next_active_clusters == {num_clusters{1'b0}})) begin
                    o_busy <= 1'b0;
                    o_done <= 1'b1;
                    o_active_clusters <= r_next_active_clusters;
                end else begin
                    o_digit_idx <= o_digit_idx + 1'b1;
                    o_active_clusters <= r_next_active_clusters;
                end
            end
        end
    end

endmodule
