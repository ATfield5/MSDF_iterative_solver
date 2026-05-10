`timescale 1ns / 1ps

// Runtime-loadable template storage split into narrow field banks.
//
// External writes still use the existing packed payload format, but storage is
// physically split into fields. This avoids scaling one ultra-wide memory word
// and gives Vivado a clearer path to infer block RAM for larger designs.

module iter_template_field_bank #(
    parameter integer num_total_clusters = 2,
    parameter integer num_clusters = 2,
    parameter integer num_rows = 4,
    parameter integer degree = 4,
    parameter integer bit_width = 8,
    parameter integer bias_width = bit_width + 2,
    parameter integer row_idx_width = (num_rows <= 2) ? 1 : $clog2(num_rows),
    parameter integer cluster_addr_width = (num_total_clusters <= 2) ? 1 : $clog2(num_total_clusters),
    parameter integer valid_width = num_rows * degree,
    parameter integer src_width = num_rows * degree * row_idx_width,
    parameter integer coeff_terms_width = num_rows * degree * bit_width,
    parameter integer bias_vec_width = num_rows * bias_width,
    parameter integer payload_width = valid_width + src_width + 2 * coeff_terms_width + 2 * bias_vec_width,
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
    output     [num_clusters * payload_width - 1 : 0]   o_template_words_clusters
);

    localparam integer read_idx_width = (num_clusters <= 2) ? 1 : $clog2(num_clusters);
    localparam integer load_count_width = (num_clusters < 2) ? 1 : $clog2(num_clusters + 1);
    localparam integer off_valid = 0;
    localparam integer off_src = off_valid + valid_width;
    localparam integer off_coeff_p = off_src + src_width;
    localparam integer off_coeff_n = off_coeff_p + coeff_terms_width;
    localparam integer off_bias_p = off_coeff_n + coeff_terms_width;
    localparam integer off_bias_n = off_bias_p + bias_vec_width;

    reg [cluster_addr_width - 1 : 0] r_base_addr;
    reg [load_count_width - 1 : 0] r_issue_idx;
    reg [read_idx_width - 1 : 0] r_read_idx;
    reg r_read_valid;
    reg r_read_in_range;
    reg [read_idx_width - 1 : 0] r_capture_idx;
    reg r_capture_valid;
    reg [num_clusters - 1 : 0] r_capture_slot_valid;
    reg r_capture_in_range;
    reg r_field_rd_en;
    reg [cluster_addr_width - 1 : 0] r_field_rd_addr;
    reg [payload_width - 1 : 0] r_template_word_slots [0 : num_clusters - 1];

    wire [cluster_addr_width : 0] w_issue_addr_ext;
    wire [cluster_addr_width - 1 : 0] w_issue_addr;
    wire w_issue_in_range;

    wire [valid_width - 1 : 0] w_valid_rd_data;
    wire [src_width - 1 : 0] w_src_rd_data;
    wire [coeff_terms_width - 1 : 0] w_coeff_p_rd_data;
    wire [coeff_terms_width - 1 : 0] w_coeff_n_rd_data;
    wire [bias_vec_width - 1 : 0] w_bias_p_rd_data;
    wire [bias_vec_width - 1 : 0] w_bias_n_rd_data;
    wire [payload_width - 1 : 0] w_capture_payload;

    assign w_capture_payload = {
        w_bias_n_rd_data,
        w_bias_p_rd_data,
        w_coeff_n_rd_data,
        w_coeff_p_rd_data,
        w_src_rd_data,
        w_valid_rd_data
    };

    assign w_issue_addr_ext = {1'b0, r_base_addr} + r_issue_idx;
    assign w_issue_addr = w_issue_addr_ext[cluster_addr_width - 1 : 0];
    assign w_issue_in_range = (w_issue_addr_ext < num_total_clusters);

    iter_runtime_sdp_field_ram #(
        .data_width(valid_width),
        .depth(num_total_clusters),
        .addr_width(cluster_addr_width),
        .mem_style(mem_style)
    ) valid_bank (
        .i_clk(i_clk),
        .i_wr_en(i_cfg_we),
        .i_wr_addr(i_cfg_addr),
        .i_wr_data(i_cfg_payload[off_valid +: valid_width]),
        .i_rd_en(r_field_rd_en),
        .i_rd_addr(r_field_rd_addr),
        .o_rd_data(w_valid_rd_data)
    );

    iter_runtime_sdp_field_ram #(
        .data_width(src_width),
        .depth(num_total_clusters),
        .addr_width(cluster_addr_width),
        .mem_style(mem_style)
    ) src_bank (
        .i_clk(i_clk),
        .i_wr_en(i_cfg_we),
        .i_wr_addr(i_cfg_addr),
        .i_wr_data(i_cfg_payload[off_src +: src_width]),
        .i_rd_en(r_field_rd_en),
        .i_rd_addr(r_field_rd_addr),
        .o_rd_data(w_src_rd_data)
    );

    iter_runtime_sdp_field_ram #(
        .data_width(coeff_terms_width),
        .depth(num_total_clusters),
        .addr_width(cluster_addr_width),
        .mem_style(mem_style)
    ) coeff_p_bank (
        .i_clk(i_clk),
        .i_wr_en(i_cfg_we),
        .i_wr_addr(i_cfg_addr),
        .i_wr_data(i_cfg_payload[off_coeff_p +: coeff_terms_width]),
        .i_rd_en(r_field_rd_en),
        .i_rd_addr(r_field_rd_addr),
        .o_rd_data(w_coeff_p_rd_data)
    );

    iter_runtime_sdp_field_ram #(
        .data_width(coeff_terms_width),
        .depth(num_total_clusters),
        .addr_width(cluster_addr_width),
        .mem_style(mem_style)
    ) coeff_n_bank (
        .i_clk(i_clk),
        .i_wr_en(i_cfg_we),
        .i_wr_addr(i_cfg_addr),
        .i_wr_data(i_cfg_payload[off_coeff_n +: coeff_terms_width]),
        .i_rd_en(r_field_rd_en),
        .i_rd_addr(r_field_rd_addr),
        .o_rd_data(w_coeff_n_rd_data)
    );

    iter_runtime_sdp_field_ram #(
        .data_width(bias_vec_width),
        .depth(num_total_clusters),
        .addr_width(cluster_addr_width),
        .mem_style(mem_style)
    ) bias_p_bank (
        .i_clk(i_clk),
        .i_wr_en(i_cfg_we),
        .i_wr_addr(i_cfg_addr),
        .i_wr_data(i_cfg_payload[off_bias_p +: bias_vec_width]),
        .i_rd_en(r_field_rd_en),
        .i_rd_addr(r_field_rd_addr),
        .o_rd_data(w_bias_p_rd_data)
    );

    iter_runtime_sdp_field_ram #(
        .data_width(bias_vec_width),
        .depth(num_total_clusters),
        .addr_width(cluster_addr_width),
        .mem_style(mem_style)
    ) bias_n_bank (
        .i_clk(i_clk),
        .i_wr_en(i_cfg_we),
        .i_wr_addr(i_cfg_addr),
        .i_wr_data(i_cfg_payload[off_bias_n +: bias_vec_width]),
        .i_rd_en(r_field_rd_en),
        .i_rd_addr(r_field_rd_addr),
        .o_rd_data(w_bias_n_rd_data)
    );

    genvar ogi;
    generate
        for (ogi = 0; ogi < num_clusters; ogi = ogi + 1) begin : gen_output_pack
            assign o_template_words_clusters[(ogi + 1) * payload_width - 1 -: payload_width] =
                r_template_word_slots[ogi];
        end
    endgenerate

    integer si;
    always @(posedge i_clk) begin
        if (i_rst) begin
            r_base_addr <= {cluster_addr_width{1'b0}};
            r_issue_idx <= {load_count_width{1'b0}};
            r_read_idx <= {read_idx_width{1'b0}};
            r_read_valid <= 1'b0;
            r_read_in_range <= 1'b0;
            r_capture_idx <= {read_idx_width{1'b0}};
            r_capture_valid <= 1'b0;
            r_capture_slot_valid <= {num_clusters{1'b0}};
            r_capture_in_range <= 1'b0;
            r_field_rd_en <= 1'b0;
            r_field_rd_addr <= {cluster_addr_width{1'b0}};
            o_window_valid <= 1'b0;
            o_window_busy <= 1'b0;
            for (si = 0; si < num_clusters; si = si + 1) begin
                r_template_word_slots[si] <= {payload_width{1'b0}};
            end
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
                r_capture_slot_valid <= {num_clusters{1'b0}};
                r_capture_in_range <= 1'b0;
                r_field_rd_en <= 1'b0;
                o_window_valid <= 1'b0;
                o_window_busy <= 1'b1;
                for (si = 0; si < num_clusters; si = si + 1) begin
                    r_template_word_slots[si] <= {payload_width{1'b0}};
                end
            end else if (o_window_busy) begin
                for (si = 0; si < num_clusters; si = si + 1) begin
                    if (r_capture_slot_valid[si]) begin
                        if (r_capture_in_range) begin
                            r_template_word_slots[si] <= w_capture_payload;
                        end else begin
                            r_template_word_slots[si] <= {payload_width{1'b0}};
                        end
                    end
                end

                r_capture_idx <= r_read_idx;
                r_capture_in_range <= r_read_in_range;
                r_capture_valid <= r_read_valid;
                r_capture_slot_valid <= {num_clusters{1'b0}};
                if (r_read_valid) begin
                    r_capture_slot_valid[r_read_idx] <= 1'b1;
                end

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
