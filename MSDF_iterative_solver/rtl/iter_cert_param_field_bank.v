`timescale 1ns / 1ps

// Runtime-loadable certification parameter storage split into narrow banks.
//
// Payload layout is kept compatible with iter_cert_param_unpack:
//   [block_weights][eta]

module iter_cert_param_field_bank #(
    parameter integer num_total_clusters = 2,
    parameter integer num_clusters = 2,
    parameter integer num_rows = 4,
    parameter integer num_blocks = 2,
    parameter integer coeff_width = 8,
    parameter integer acc_width = 24,
    parameter integer cluster_addr_width = (num_total_clusters <= 2) ? 1 : $clog2(num_total_clusters),
    parameter integer block_weights_width = num_rows * num_blocks * coeff_width,
    parameter integer payload_width = block_weights_width + acc_width,
    parameter integer mem_style = 1
) (
    input                                               i_clk,
    input                                               i_rst,
    input                                               i_cfg_we,
    input      [cluster_addr_width - 1 : 0]             i_cfg_addr,
    input      [payload_width - 1 : 0]                  i_cfg_payload,
    input                                               i_window_load,
    input      [cluster_addr_width - 1 : 0]             i_base_addr,
    output reg                                          o_window_valid,
    output reg                                          o_window_busy,
    output reg [num_clusters * payload_width - 1 : 0]   o_cert_param_words_clusters
);

    localparam integer read_idx_width = (num_clusters <= 2) ? 1 : $clog2(num_clusters);
    localparam integer load_count_width = (num_clusters < 2) ? 1 : $clog2(num_clusters + 1);

    reg [cluster_addr_width - 1 : 0] r_base_addr;
    reg [load_count_width - 1 : 0] r_issue_idx;
    reg [read_idx_width - 1 : 0] r_read_idx;
    reg r_read_valid;
    reg r_read_in_range;
    reg [read_idx_width - 1 : 0] r_capture_idx;
    reg r_capture_valid;
    reg r_capture_in_range;
    reg r_field_rd_en;
    reg [cluster_addr_width - 1 : 0] r_field_rd_addr;

    wire [cluster_addr_width : 0] w_issue_addr_ext;
    wire [cluster_addr_width - 1 : 0] w_issue_addr;
    wire w_issue_in_range;
    wire [block_weights_width - 1 : 0] w_block_weights_rd_data;
    wire [acc_width - 1 : 0] w_eta_rd_data;

    assign w_issue_addr_ext = {1'b0, r_base_addr} + r_issue_idx;
    assign w_issue_addr = w_issue_addr_ext[cluster_addr_width - 1 : 0];
    assign w_issue_in_range = (w_issue_addr_ext < num_total_clusters);

    iter_runtime_sdp_field_ram #(
        .data_width(block_weights_width),
        .depth(num_total_clusters),
        .addr_width(cluster_addr_width),
        .mem_style(mem_style)
    ) block_weights_bank (
        .i_clk(i_clk),
        .i_wr_en(i_cfg_we),
        .i_wr_addr(i_cfg_addr),
        .i_wr_data(i_cfg_payload[block_weights_width - 1 : 0]),
        .i_rd_en(r_field_rd_en),
        .i_rd_addr(r_field_rd_addr),
        .o_rd_data(w_block_weights_rd_data)
    );

    iter_runtime_sdp_field_ram #(
        .data_width(acc_width),
        .depth(num_total_clusters),
        .addr_width(cluster_addr_width),
        .mem_style(mem_style)
    ) eta_bank (
        .i_clk(i_clk),
        .i_wr_en(i_cfg_we),
        .i_wr_addr(i_cfg_addr),
        .i_wr_data(i_cfg_payload[payload_width - 1 -: acc_width]),
        .i_rd_en(r_field_rd_en),
        .i_rd_addr(r_field_rd_addr),
        .o_rd_data(w_eta_rd_data)
    );

    always @(posedge i_clk) begin
        if (i_rst) begin
            r_base_addr <= {cluster_addr_width{1'b0}};
            r_issue_idx <= {load_count_width{1'b0}};
            r_read_idx <= {read_idx_width{1'b0}};
            r_read_valid <= 1'b0;
            r_read_in_range <= 1'b0;
            r_capture_idx <= {read_idx_width{1'b0}};
            r_capture_valid <= 1'b0;
            r_capture_in_range <= 1'b0;
            r_field_rd_en <= 1'b0;
            r_field_rd_addr <= {cluster_addr_width{1'b0}};
            o_window_valid <= 1'b0;
            o_window_busy <= 1'b0;
            o_cert_param_words_clusters <= {num_clusters * payload_width{1'b0}};
        end else begin
            r_field_rd_en <= 1'b0;

            if (i_window_load && !o_window_busy) begin
                r_base_addr <= i_base_addr;
                r_issue_idx <= {load_count_width{1'b0}};
                r_read_idx <= {read_idx_width{1'b0}};
                r_read_valid <= 1'b0;
                r_read_in_range <= 1'b0;
                r_capture_idx <= {read_idx_width{1'b0}};
                r_capture_valid <= 1'b0;
                r_capture_in_range <= 1'b0;
                r_field_rd_en <= 1'b0;
                o_window_valid <= 1'b0;
                o_window_busy <= 1'b1;
                o_cert_param_words_clusters <= {num_clusters * payload_width{1'b0}};
            end else if (o_window_busy) begin
                if (r_capture_valid) begin
                    if (r_capture_in_range) begin
                        o_cert_param_words_clusters[r_capture_idx * payload_width +: block_weights_width]
                            <= w_block_weights_rd_data;
                        o_cert_param_words_clusters[r_capture_idx * payload_width + block_weights_width +: acc_width]
                            <= w_eta_rd_data;
                    end else begin
                        o_cert_param_words_clusters[r_capture_idx * payload_width +: payload_width]
                            <= {payload_width{1'b0}};
                    end
                end

                r_capture_idx <= r_read_idx;
                r_capture_in_range <= r_read_in_range;
                r_capture_valid <= r_read_valid;

                if (r_issue_idx < num_clusters) begin
                    r_field_rd_en <= w_issue_in_range;
                    r_field_rd_addr <= w_issue_addr;
                    r_read_idx <= r_issue_idx[read_idx_width - 1 : 0];
                    r_read_in_range <= w_issue_in_range;
                    r_read_valid <= 1'b1;
                    r_issue_idx <= r_issue_idx + 1'b1;
                end else begin
                    r_read_valid <= 1'b0;
                end

                if ((r_issue_idx == num_clusters) && !r_read_valid && r_capture_valid) begin
                    o_window_busy <= 1'b0;
                    o_window_valid <= 1'b1;
                end
            end
        end
    end

endmodule
