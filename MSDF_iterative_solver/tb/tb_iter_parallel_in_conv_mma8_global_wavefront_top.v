`timescale 1ns / 1ps

// Standalone P4-SP conventional full-word K-stage PageRank wavefront test.

module tb_iter_parallel_in_conv_mma8_global_wavefront_top;

`ifdef PARALLEL_IN_WAVEFRONT_STAGES_VALUE
    localparam integer NUM_STAGES = `PARALLEL_IN_WAVEFRONT_STAGES_VALUE;
`else
    localparam integer NUM_STAGES = 4;
`endif
    localparam integer NUM_CLUSTERS = 8;
    localparam integer ROWS_PER_CLUSTER = 4;
    localparam integer TOTAL_ROWS = NUM_CLUSTERS * ROWS_PER_CLUSTER;
    localparam integer DEGREE = 4;
    localparam integer PHYSICAL_DEGREE = 8;
    localparam integer BIT_WIDTH = 30;
    localparam integer DATA_WIDTH = 32;
    localparam integer BIAS_WIDTH = 32;
    localparam integer BOUND_WIDTH = 16;
    localparam integer SRC_IDX_WIDTH = 5;
    localparam integer ACC_WIDTH = 40;
    localparam integer PRODUCT_WIDTH = 66;
    localparam integer PRODUCT_SHIFT = DATA_WIDTH;
    localparam integer VALID_WIDTH = ROWS_PER_CLUSTER * DEGREE;
    localparam integer SRC_WIDTH = ROWS_PER_CLUSTER * DEGREE * SRC_IDX_WIDTH;
    localparam integer COEFF_TERMS_WIDTH = ROWS_PER_CLUSTER * DEGREE * BIT_WIDTH;
    localparam integer BIAS_VEC_WIDTH = ROWS_PER_CLUSTER * BIAS_WIDTH;
    localparam integer TEMPLATE_PAYLOAD_WIDTH =
        VALID_WIDTH + SRC_WIDTH + 2 * COEFF_TERMS_WIDTH + 2 * BIAS_VEC_WIDTH;
    localparam integer VALUE_TOLERANCE = 0;

`include "iter_tb_signed_digit_reconstruct.vh"

    reg i_clk;
    reg i_rst;
    reg i_clear;
    reg i_start;
    reg [TEMPLATE_PAYLOAD_WIDTH - 1 : 0] template_mem [0 : NUM_CLUSTERS - 1];
    reg [NUM_CLUSTERS * TEMPLATE_PAYLOAD_WIDTH - 1 : 0] template_words_clusters;
    reg [ROWS_PER_CLUSTER * DATA_WIDTH - 1 : 0] gold_state_p_mem [0 : NUM_STAGES * NUM_CLUSTERS - 1];
    reg [ROWS_PER_CLUSTER * DATA_WIDTH - 1 : 0] gold_state_n_mem [0 : NUM_STAGES * NUM_CLUSTERS - 1];

    wire [NUM_CLUSTERS * VALID_WIDTH - 1 : 0] w_term_valid_mask_clusters;
    wire [NUM_CLUSTERS * SRC_WIDTH - 1 : 0] w_src_row_idx_clusters;
    wire [NUM_CLUSTERS * COEFF_TERMS_WIDTH - 1 : 0] w_coeff_p_terms_clusters;
    wire [NUM_CLUSTERS * COEFF_TERMS_WIDTH - 1 : 0] w_coeff_n_terms_clusters;
    wire [NUM_CLUSTERS * BIAS_VEC_WIDTH - 1 : 0] w_bias_vec_p_rows_clusters;
    wire [NUM_CLUSTERS * BIAS_VEC_WIDTH - 1 : 0] w_bias_vec_n_rows_clusters;
    wire w_final_valid;
    wire [TOTAL_ROWS * DATA_WIDTH - 1 : 0] w_final_state_p_rows;
    wire [TOTAL_ROWS * DATA_WIDTH - 1 : 0] w_final_state_n_rows;
    wire [NUM_STAGES * 32 - 1 : 0] w_stage_valid_count;
    wire [NUM_STAGES - 1 : 0] w_stage_done;

    integer cycle_count;
    integer wait_count;
    integer ci;
    integer ri;
    integer global_row;
    integer gold_idx;
    reg [DATA_WIDTH - 1 : 0] dut_p_word;
    reg [DATA_WIDTH - 1 : 0] dut_n_word;
    reg [DATA_WIDTH - 1 : 0] gold_p_word;
    reg [DATA_WIDTH - 1 : 0] gold_n_word;

    always #5 i_clk = ~i_clk;

    iter_fixed_degree_template_unpack #(
        .num_clusters(NUM_CLUSTERS),
        .num_rows(ROWS_PER_CLUSTER),
        .degree(DEGREE),
        .bit_width(BIT_WIDTH),
        .bias_width(BIAS_WIDTH),
        .row_idx_width(SRC_IDX_WIDTH),
        .valid_width(VALID_WIDTH),
        .src_width(SRC_WIDTH),
        .coeff_terms_width(COEFF_TERMS_WIDTH),
        .bias_vec_width(BIAS_VEC_WIDTH),
        .payload_width(TEMPLATE_PAYLOAD_WIDTH)
    ) unpack_templates (
        .i_template_words_clusters(template_words_clusters),
        .o_term_valid_mask_clusters(w_term_valid_mask_clusters),
        .o_src_row_idx_clusters(w_src_row_idx_clusters),
        .o_coeff_p_terms_clusters(w_coeff_p_terms_clusters),
        .o_coeff_n_terms_clusters(w_coeff_n_terms_clusters),
        .o_bias_vec_p_rows_clusters(w_bias_vec_p_rows_clusters),
        .o_bias_vec_n_rows_clusters(w_bias_vec_n_rows_clusters)
    );

    iter_parallel_in_conv_mma8_global_wavefront_top #(
        .num_stages(NUM_STAGES),
        .num_rows(TOTAL_ROWS),
        .degree(DEGREE),
        .physical_degree(PHYSICAL_DEGREE),
        .bit_width(BIT_WIDTH),
        .data_width(DATA_WIDTH),
        .bias_width(BIAS_WIDTH),
        .bound_width(BOUND_WIDTH),
        .acc_width(ACC_WIDTH),
        .product_width(PRODUCT_WIDTH),
        .product_shift(PRODUCT_SHIFT),
        .round_pipeline(1),
        .src_idx_width(SRC_IDX_WIDTH)
    ) dut (
        .i_clk(i_clk),
        .i_rst(i_rst),
        .i_clear(i_clear),
        .i_start(i_start),
        .i_src_row_idx_rows(w_src_row_idx_clusters),
        .i_coeff_p_terms_rows(w_coeff_p_terms_clusters),
        .i_coeff_n_terms_rows(w_coeff_n_terms_clusters),
        .i_bias_p_rows(w_bias_vec_p_rows_clusters),
        .i_bias_n_rows(w_bias_vec_n_rows_clusters),
        .o_final_valid(w_final_valid),
        .o_final_state_p_rows(w_final_state_p_rows),
        .o_final_state_n_rows(w_final_state_n_rows),
        .o_stage_valid_count(w_stage_valid_count),
        .o_stage_done(w_stage_done)
    );

    always @(posedge i_clk) begin
        if (i_rst || i_clear) begin
            cycle_count <= 0;
        end else begin
            cycle_count <= cycle_count + 1;
        end
    end

    initial begin
        $readmemh("MSDF_iterative_solver/generated/rtl_vectors/pagerank32_global_parallel_in_fractional/templates.memh", template_mem);
        $readmemh("MSDF_iterative_solver/generated/rtl_vectors/pagerank32_global_parallel_in_fractional/conv_gold_state_p_iters.memh", gold_state_p_mem);
        $readmemh("MSDF_iterative_solver/generated/rtl_vectors/pagerank32_global_parallel_in_fractional/conv_gold_state_n_iters.memh", gold_state_n_mem);

        i_clk = 1'b0;
        i_rst = 1'b1;
        i_clear = 1'b0;
        i_start = 1'b0;
        template_words_clusters = {NUM_CLUSTERS * TEMPLATE_PAYLOAD_WIDTH{1'b0}};

        for (ci = 0; ci < NUM_CLUSTERS; ci = ci + 1) begin
            template_words_clusters[ci * TEMPLATE_PAYLOAD_WIDTH +: TEMPLATE_PAYLOAD_WIDTH] = template_mem[ci];
        end

        repeat (4) @(posedge i_clk);
        i_rst <= 1'b0;
        @(posedge i_clk);

        i_start <= 1'b1;
        @(posedge i_clk);
        i_start <= 1'b0;

        wait_count = 0;
        while (!w_final_valid && wait_count < 256) begin
            @(posedge i_clk);
            wait_count = wait_count + 1;
        end
        @(posedge i_clk);
        #1;

        if (!w_stage_done[NUM_STAGES - 1]) begin
            $display("ERROR conventional wavefront did not complete done=%b counts=%h",
                w_stage_done, w_stage_valid_count);
            $fatal;
        end

        for (ci = 0; ci < NUM_CLUSTERS; ci = ci + 1) begin
            gold_idx = (NUM_STAGES - 1) * NUM_CLUSTERS + ci;
            for (ri = 0; ri < ROWS_PER_CLUSTER; ri = ri + 1) begin
                global_row = ci * ROWS_PER_CLUSTER + ri;
                dut_p_word = w_final_state_p_rows[global_row * DATA_WIDTH +: DATA_WIDTH];
                dut_n_word = w_final_state_n_rows[global_row * DATA_WIDTH +: DATA_WIDTH];
                gold_p_word = gold_state_p_mem[gold_idx][ri * DATA_WIDTH +: DATA_WIDTH];
                gold_n_word = gold_state_n_mem[gold_idx][ri * DATA_WIDTH +: DATA_WIDTH];
                if ((dut_p_word !== gold_p_word) || (dut_n_word !== gold_n_word)) begin
                    $display("ERROR conventional state mismatch K=%0d row=%0d p/n=%h/%h gold=%h/%h",
                        NUM_STAGES, global_row,
                        dut_p_word, dut_n_word, gold_p_word, gold_n_word);
                    $fatal;
                end
            end
        end

        $display("PASS tb_iter_parallel_in_conv_mma8_global_wavefront_top");
        $display("COUNTERS parallel_in_conv_wavefront K=%0d product_shift=%0d total=%0d stage_counts=%h",
            NUM_STAGES, PRODUCT_SHIFT, cycle_count, w_stage_valid_count);
        $finish;
    end

endmodule
