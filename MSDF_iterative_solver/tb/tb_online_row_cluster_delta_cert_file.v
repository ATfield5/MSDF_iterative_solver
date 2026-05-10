`timescale 1ns / 1ps

module tb_online_row_cluster_delta_cert_file;
    localparam integer NUM_CLUSTERS = 2;
    localparam integer NUM_ROWS = 4;
    localparam integer BIT_WIDTH = 8;
    localparam integer BOUND_WIDTH = BIT_WIDTH + 5;
    localparam integer BLOCK_SIZE = 2;
    localparam integer NUM_BLOCKS = (NUM_ROWS + BLOCK_SIZE - 1) / BLOCK_SIZE;
    localparam integer COEFF_WIDTH = 8;
    localparam integer ACC_WIDTH = 24;
    localparam integer DATA_WIDTH = BIT_WIDTH + 3;
    localparam integer DEGREE = 4;
    localparam integer ROW_IDX_WIDTH = 2;
    localparam integer BIAS_WIDTH = BIT_WIDTH + 2;
    localparam integer VALID_WIDTH = NUM_ROWS * DEGREE;
    localparam integer SRC_WIDTH = NUM_ROWS * DEGREE * ROW_IDX_WIDTH;
    localparam integer COEFF_TERMS_WIDTH = NUM_ROWS * DEGREE * BIT_WIDTH;
    localparam integer BIAS_VEC_WIDTH = NUM_ROWS * BIAS_WIDTH;
    localparam integer TEMPLATE_PAYLOAD_WIDTH =
        VALID_WIDTH + SRC_WIDTH + 2 * COEFF_TERMS_WIDTH + 2 * BIAS_VEC_WIDTH;
    localparam integer BLOCK_WEIGHTS_WIDTH = NUM_ROWS * NUM_BLOCKS * COEFF_WIDTH;
    localparam integer CERT_PAYLOAD_WIDTH = BLOCK_WEIGHTS_WIDTH + ACC_WIDTH;

    reg i_clk;
    reg i_rst;
    reg [NUM_ROWS - 1 : 0] i_ena_rows;
    reg [NUM_ROWS - 1 : 0] x0_p_mem [0 : NUM_CLUSTERS - 1];
    reg [NUM_ROWS - 1 : 0] x1_p_mem [0 : NUM_CLUSTERS - 1];
    reg [NUM_ROWS - 1 : 0] x2_p_mem [0 : NUM_CLUSTERS - 1];
    reg [NUM_ROWS - 1 : 0] x3_p_mem [0 : NUM_CLUSTERS - 1];
    reg [NUM_ROWS * DATA_WIDTH - 1 : 0] gold_sum_p_mem [0 : NUM_CLUSTERS - 1];
    reg [NUM_ROWS * DATA_WIDTH - 1 : 0] gold_sum_n_mem [0 : NUM_CLUSTERS - 1];
    reg [NUM_BLOCKS * BOUND_WIDTH - 1 : 0] gold_block_bounds_mem [0 : NUM_CLUSTERS - 1];
    reg [ACC_WIDTH - 1 : 0] gold_max_error_mem [0 : NUM_CLUSTERS - 1];

    wire [NUM_CLUSTERS * TEMPLATE_PAYLOAD_WIDTH - 1 : 0] template_words;
    wire [NUM_CLUSTERS * VALID_WIDTH - 1 : 0] term_valid_mask_clusters;
    wire [NUM_CLUSTERS * SRC_WIDTH - 1 : 0] src_row_idx_clusters;
    wire [NUM_CLUSTERS * COEFF_TERMS_WIDTH - 1 : 0] coeff_p_terms_clusters;
    wire [NUM_CLUSTERS * COEFF_TERMS_WIDTH - 1 : 0] coeff_n_terms_clusters;
    wire [NUM_CLUSTERS * BIAS_VEC_WIDTH - 1 : 0] bias_p_clusters;
    wire [NUM_CLUSTERS * BIAS_VEC_WIDTH - 1 : 0] bias_n_clusters;
    wire [NUM_CLUSTERS * CERT_PAYLOAD_WIDTH - 1 : 0] cert_words;
    wire [NUM_CLUSTERS * BLOCK_WEIGHTS_WIDTH - 1 : 0] block_weights_clusters;
    wire [NUM_CLUSTERS * ACC_WIDTH - 1 : 0] eta_clusters;

    iter_fixed_degree_template_bank #(
        .num_total_clusters(NUM_CLUSTERS),
        .num_clusters(NUM_CLUSTERS),
        .payload_width(TEMPLATE_PAYLOAD_WIDTH),
        .cluster_addr_width(1),
        .template_mem_init("MSDF_iterative_solver/generated/rtl_vectors/blockdiag8/templates.memh")
    ) template_bank (
        .i_base_cluster_idx(1'b0),
        .o_template_words_clusters(template_words)
    );

    iter_fixed_degree_template_unpack #(
        .num_clusters(NUM_CLUSTERS),
        .num_rows(NUM_ROWS),
        .degree(DEGREE),
        .bit_width(BIT_WIDTH),
        .bias_width(BIAS_WIDTH),
        .row_idx_width(ROW_IDX_WIDTH)
    ) template_unpack (
        .i_template_words_clusters(template_words),
        .o_term_valid_mask_clusters(term_valid_mask_clusters),
        .o_src_row_idx_clusters(src_row_idx_clusters),
        .o_coeff_p_terms_clusters(coeff_p_terms_clusters),
        .o_coeff_n_terms_clusters(coeff_n_terms_clusters),
        .o_bias_vec_p_rows_clusters(bias_p_clusters),
        .o_bias_vec_n_rows_clusters(bias_n_clusters)
    );

    iter_cert_param_bank #(
        .num_total_clusters(NUM_CLUSTERS),
        .num_clusters(NUM_CLUSTERS),
        .payload_width(CERT_PAYLOAD_WIDTH),
        .cluster_addr_width(1),
        .cert_param_mem_init("MSDF_iterative_solver/generated/rtl_vectors/blockdiag8/cert_params.memh")
    ) cert_bank (
        .i_base_cluster_idx(1'b0),
        .o_cert_param_words_clusters(cert_words)
    );

    iter_cert_param_unpack #(
        .num_clusters(NUM_CLUSTERS),
        .num_rows(NUM_ROWS),
        .num_blocks(NUM_BLOCKS),
        .coeff_width(COEFF_WIDTH),
        .acc_width(ACC_WIDTH)
    ) cert_unpack (
        .i_cert_param_words_clusters(cert_words),
        .o_block_weights_clusters(block_weights_clusters),
        .o_eta_clusters(eta_clusters)
    );

    wire [NUM_CLUSTERS * NUM_ROWS - 1 : 0] valid_rows_clusters;
    wire [NUM_CLUSTERS * NUM_ROWS * DATA_WIDTH - 1 : 0] sum_p_clusters;
    wire [NUM_CLUSTERS * NUM_ROWS * DATA_WIDTH - 1 : 0] sum_n_clusters;
    wire [NUM_CLUSTERS * NUM_BLOCKS * BOUND_WIDTH - 1 : 0] block_bounds_clusters;
    wire [NUM_CLUSTERS - 1 : 0] cluster_valid;
    wire [NUM_CLUSTERS - 1 : 0] cluster_certified;
    wire [NUM_CLUSTERS * ACC_WIDTH - 1 : 0] cluster_max_error;

    genvar gi;
    generate
        for (gi = 0; gi < NUM_CLUSTERS; gi = gi + 1) begin : gen_clusters
            wire [NUM_ROWS - 1 : 0] row_active_mask;
            wire [SRC_WIDTH - 1 : 0] src_row_idx_unused;
            wire [NUM_ROWS * BIT_WIDTH - 1 : 0] coeff0_p, coeff0_n;
            wire [NUM_ROWS * BIT_WIDTH - 1 : 0] coeff1_p, coeff1_n;
            wire [NUM_ROWS * BIT_WIDTH - 1 : 0] coeff2_p, coeff2_n;
            wire [NUM_ROWS * BIT_WIDTH - 1 : 0] coeff3_p, coeff3_n;
            wire [BIAS_VEC_WIDTH - 1 : 0] bias_p, bias_n;
            wire [NUM_ROWS * BOUND_WIDTH - 1 : 0] abs_upper_unused;

            iter_fixed_degree_row_scheduler #(
                .num_rows(NUM_ROWS),
                .degree(DEGREE),
                .bit_width(BIT_WIDTH),
                .bias_width(BIAS_WIDTH),
                .row_idx_width(ROW_IDX_WIDTH)
            ) row_sched (
                .i_term_valid_mask(term_valid_mask_clusters[(gi + 1) * VALID_WIDTH - 1 -: VALID_WIDTH]),
                .i_src_row_idx(src_row_idx_clusters[(gi + 1) * SRC_WIDTH - 1 -: SRC_WIDTH]),
                .i_coeff_p_terms(coeff_p_terms_clusters[(gi + 1) * COEFF_TERMS_WIDTH - 1 -: COEFF_TERMS_WIDTH]),
                .i_coeff_n_terms(coeff_n_terms_clusters[(gi + 1) * COEFF_TERMS_WIDTH - 1 -: COEFF_TERMS_WIDTH]),
                .i_bias_vec_p_rows(bias_p_clusters[(gi + 1) * BIAS_VEC_WIDTH - 1 -: BIAS_VEC_WIDTH]),
                .i_bias_vec_n_rows(bias_n_clusters[(gi + 1) * BIAS_VEC_WIDTH - 1 -: BIAS_VEC_WIDTH]),
                .o_row_active_mask(row_active_mask),
                .o_src_row_idx(src_row_idx_unused),
                .o_coeff0_vec_p_rows(coeff0_p),
                .o_coeff0_vec_n_rows(coeff0_n),
                .o_coeff1_vec_p_rows(coeff1_p),
                .o_coeff1_vec_n_rows(coeff1_n),
                .o_coeff2_vec_p_rows(coeff2_p),
                .o_coeff2_vec_n_rows(coeff2_n),
                .o_coeff3_vec_p_rows(coeff3_p),
                .o_coeff3_vec_n_rows(coeff3_n),
                .o_bias_vec_p_rows(bias_p),
                .o_bias_vec_n_rows(bias_n)
            );

            online_row_cluster_delta_cert #(
                .num_rows(NUM_ROWS),
                .bit_width(BIT_WIDTH),
                .bound_width(BOUND_WIDTH),
                .coeff_width(COEFF_WIDTH),
                .acc_width(ACC_WIDTH),
                .block_size(BLOCK_SIZE),
                .num_blocks(NUM_BLOCKS)
            ) dut_cluster (
                .i_clk(i_clk),
                .i_rst(i_rst),
                .i_ena_rows(i_ena_rows & row_active_mask),
                .i_x0_p_rows(x0_p_mem[gi]),
                .i_x0_n_rows({NUM_ROWS{1'b0}}),
                .i_x1_p_rows(x1_p_mem[gi]),
                .i_x1_n_rows({NUM_ROWS{1'b0}}),
                .i_x2_p_rows(x2_p_mem[gi]),
                .i_x2_n_rows({NUM_ROWS{1'b0}}),
                .i_x3_p_rows(x3_p_mem[gi]),
                .i_x3_n_rows({NUM_ROWS{1'b0}}),
                .i_coeff0_vec_p_rows(coeff0_p),
                .i_coeff0_vec_n_rows(coeff0_n),
                .i_coeff1_vec_p_rows(coeff1_p),
                .i_coeff1_vec_n_rows(coeff1_n),
                .i_coeff2_vec_p_rows(coeff2_p),
                .i_coeff2_vec_n_rows(coeff2_n),
                .i_coeff3_vec_p_rows(coeff3_p),
                .i_coeff3_vec_n_rows(coeff3_n),
                .i_bias_vec_p_rows(bias_p),
                .i_bias_vec_n_rows(bias_n),
                .i_x_old_p_rows({NUM_ROWS * DATA_WIDTH{1'b0}}),
                .i_x_old_n_rows({NUM_ROWS * DATA_WIDTH{1'b0}}),
                .i_tail_bound(13'd1),
                .i_block_weights(block_weights_clusters[(gi + 1) * BLOCK_WEIGHTS_WIDTH - 1 -: BLOCK_WEIGHTS_WIDTH]),
                .i_eta(eta_clusters[(gi + 1) * ACC_WIDTH - 1 -: ACC_WIDTH]),
                .o_valid_rows(valid_rows_clusters[(gi + 1) * NUM_ROWS - 1 -: NUM_ROWS]),
                .o_sum_p_rows(sum_p_clusters[(gi + 1) * NUM_ROWS * DATA_WIDTH - 1 -: NUM_ROWS * DATA_WIDTH]),
                .o_sum_n_rows(sum_n_clusters[(gi + 1) * NUM_ROWS * DATA_WIDTH - 1 -: NUM_ROWS * DATA_WIDTH]),
                .o_abs_upper_rows(abs_upper_unused),
                .o_block_bounds(block_bounds_clusters[(gi + 1) * NUM_BLOCKS * BOUND_WIDTH - 1 -: NUM_BLOCKS * BOUND_WIDTH]),
                .o_cluster_valid(cluster_valid[gi]),
                .o_cluster_certified(cluster_certified[gi]),
                .o_cluster_max_error(cluster_max_error[(gi + 1) * ACC_WIDTH - 1 -: ACC_WIDTH])
            );
        end
    endgenerate

    always #5 i_clk = ~i_clk;

    integer ci;
    integer seen_count;
    initial begin
        $readmemh("MSDF_iterative_solver/generated/rtl_vectors/blockdiag8/x0_p.memh", x0_p_mem);
        $readmemh("MSDF_iterative_solver/generated/rtl_vectors/blockdiag8/x1_p.memh", x1_p_mem);
        $readmemh("MSDF_iterative_solver/generated/rtl_vectors/blockdiag8/x2_p.memh", x2_p_mem);
        $readmemh("MSDF_iterative_solver/generated/rtl_vectors/blockdiag8/x3_p.memh", x3_p_mem);
        $readmemh("MSDF_iterative_solver/generated/rtl_vectors/blockdiag8/gold_sum_p_rows.memh", gold_sum_p_mem);
        $readmemh("MSDF_iterative_solver/generated/rtl_vectors/blockdiag8/gold_sum_n_rows.memh", gold_sum_n_mem);
        $readmemh("MSDF_iterative_solver/generated/rtl_vectors/blockdiag8/gold_block_bounds.memh", gold_block_bounds_mem);
        $readmemh("MSDF_iterative_solver/generated/rtl_vectors/blockdiag8/gold_max_error.memh", gold_max_error_mem);

        i_clk = 1'b0;
        i_rst = 1'b1;
        i_ena_rows = {NUM_ROWS{1'b0}};
        seen_count = 0;

        repeat (2) @(posedge i_clk);
        i_rst <= 1'b0;
        @(posedge i_clk);
        i_ena_rows <= {NUM_ROWS{1'b1}};
        @(posedge i_clk);
        i_ena_rows <= {NUM_ROWS{1'b0}};

        repeat (8) begin
            @(posedge i_clk);
            for (ci = 0; ci < NUM_CLUSTERS; ci = ci + 1) begin
                if (cluster_valid[ci]) begin
                    seen_count = seen_count + 1;
                    if (sum_p_clusters[(ci + 1) * NUM_ROWS * DATA_WIDTH - 1 -: NUM_ROWS * DATA_WIDTH]
                        !== gold_sum_p_mem[ci]) begin
                        $display("ERROR cluster %0d sum_p got=%h expected=%h",
                            ci,
                            sum_p_clusters[(ci + 1) * NUM_ROWS * DATA_WIDTH - 1 -: NUM_ROWS * DATA_WIDTH],
                            gold_sum_p_mem[ci]);
                        $fatal;
                    end
                    if (sum_n_clusters[(ci + 1) * NUM_ROWS * DATA_WIDTH - 1 -: NUM_ROWS * DATA_WIDTH]
                        !== gold_sum_n_mem[ci]) begin
                        $display("ERROR cluster %0d sum_n mismatch", ci);
                        $fatal;
                    end
                    if (block_bounds_clusters[(ci + 1) * NUM_BLOCKS * BOUND_WIDTH - 1 -: NUM_BLOCKS * BOUND_WIDTH]
                        !== gold_block_bounds_mem[ci]) begin
                        $display("ERROR cluster %0d block_bounds got=%h expected=%h",
                            ci,
                            block_bounds_clusters[(ci + 1) * NUM_BLOCKS * BOUND_WIDTH - 1 -: NUM_BLOCKS * BOUND_WIDTH],
                            gold_block_bounds_mem[ci]);
                        $fatal;
                    end
                    if (cluster_max_error[(ci + 1) * ACC_WIDTH - 1 -: ACC_WIDTH]
                        !== gold_max_error_mem[ci]) begin
                        $display("ERROR cluster %0d max_error got=%0d expected=%0d",
                            ci,
                            cluster_max_error[(ci + 1) * ACC_WIDTH - 1 -: ACC_WIDTH],
                            gold_max_error_mem[ci]);
                        $fatal;
                    end
                    if (cluster_certified[ci] !== 1'b0) begin
                        $display("ERROR cluster %0d certification mismatch", ci);
                        $fatal;
                    end
                end
            end
        end

        if (seen_count != NUM_CLUSTERS) begin
            $display("ERROR expected %0d cluster valids, got %0d", NUM_CLUSTERS, seen_count);
            $fatal;
        end

        $display("PASS tb_online_row_cluster_delta_cert_file");
        $finish;
    end
endmodule
