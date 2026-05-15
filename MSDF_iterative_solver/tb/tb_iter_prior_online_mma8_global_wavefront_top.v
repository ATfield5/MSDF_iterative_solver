`timescale 1ns / 1ps

// Strict prior-fractional K-stage PageRank wavefront.
//
// This test does not use the runtime shell.  It isolates the architectural
// question: can committed output digits from the original MSDF_MUL_ADD_8
// operator feed the next PageRank iteration stage directly, without
// full-word assembly between stages?

module tb_iter_prior_online_mma8_global_wavefront_top;

`ifdef PRIOR_WAVEFRONT_STAGES_VALUE
    localparam integer NUM_STAGES = `PRIOR_WAVEFRONT_STAGES_VALUE;
`else
    localparam integer NUM_STAGES = 4;
`endif
    localparam integer NUM_CLUSTERS = 8;
    localparam integer ROWS_PER_CLUSTER = 4;
    localparam integer TOTAL_ROWS = NUM_CLUSTERS * ROWS_PER_CLUSTER;
`ifdef PRIOR_WAVEFRONT_DEGREE_VALUE
    localparam integer DEGREE = `PRIOR_WAVEFRONT_DEGREE_VALUE;
`else
    localparam integer DEGREE = 4;
`endif
`ifdef PRIOR_WAVEFRONT_BIT_WIDTH_VALUE
    localparam integer BIT_WIDTH = `PRIOR_WAVEFRONT_BIT_WIDTH_VALUE;
`else
    localparam integer BIT_WIDTH = 11;
`endif
    localparam integer DATA_WIDTH = BIT_WIDTH + 3;
    localparam integer BIAS_WIDTH = BIT_WIDTH + 2;
    localparam integer SRC_IDX_WIDTH = 5;
    localparam integer VALID_WIDTH = ROWS_PER_CLUSTER * DEGREE;
    localparam integer SRC_WIDTH = ROWS_PER_CLUSTER * DEGREE * SRC_IDX_WIDTH;
    localparam integer COEFF_TERMS_WIDTH = ROWS_PER_CLUSTER * DEGREE * BIT_WIDTH;
    localparam integer BIAS_VEC_WIDTH = ROWS_PER_CLUSTER * BIAS_WIDTH;
    localparam integer TEMPLATE_PAYLOAD_WIDTH =
        VALID_WIDTH + SRC_WIDTH + 2 * COEFF_TERMS_WIDTH + 2 * BIAS_VEC_WIDTH;
    localparam integer DIGIT_IDX_WIDTH = $clog2(DATA_WIDTH);
`ifdef PRIOR_WAVEFRONT_TOLERANCE_VALUE
    localparam integer PRIOR_TOLERANCE = `PRIOR_WAVEFRONT_TOLERANCE_VALUE;
`else
    localparam integer PRIOR_TOLERANCE = 4;
`endif

`include "iter_tb_signed_digit_reconstruct.vh"

    reg i_clk;
    reg i_rst;
    reg i_clear;
    reg i_start;
    reg i_valid_digit;
    reg [DIGIT_IDX_WIDTH - 1 : 0] i_digit_idx;
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
    wire [TOTAL_ROWS - 1 : 0] w_final_valid_rows;
    wire [TOTAL_ROWS * DIGIT_IDX_WIDTH - 1 : 0] w_final_digit_idx_rows;
    wire [TOTAL_ROWS - 1 : 0] w_final_digit_p_rows;
    wire [TOTAL_ROWS - 1 : 0] w_final_digit_n_rows;
    wire [TOTAL_ROWS - 1 : 0] w_final_done_rows;
    wire [NUM_STAGES * TOTAL_ROWS - 1 : 0] w_stage_valid_rows;
    wire [NUM_STAGES * TOTAL_ROWS * DIGIT_IDX_WIDTH - 1 : 0] w_stage_digit_idx_rows;
    wire [NUM_STAGES * TOTAL_ROWS - 1 : 0] w_stage_digit_p_rows;
    wire [NUM_STAGES * TOTAL_ROWS - 1 : 0] w_stage_digit_n_rows;
    wire [NUM_STAGES * TOTAL_ROWS - 1 : 0] w_stage_done_rows;
    wire [NUM_STAGES * 32 - 1 : 0] w_stage_valid_count;
    wire [NUM_STAGES - 1 : 0] w_stage_done;
    wire [NUM_STAGES - 2 : 0] w_stage_started_before_prev_done;

    reg [TOTAL_ROWS * DATA_WIDTH - 1 : 0] captured_p_rows;
    reg [TOTAL_ROWS * DATA_WIDTH - 1 : 0] captured_n_rows;
    integer capture_count;
    integer cycle_count;
    integer wait_count;
    integer ti;
    integer ci;
    integer ri;
    integer global_row;
    integer bit_sel;
    integer gold_idx;
    integer delta_value;
    integer abs_delta;
    reg [DATA_WIDTH - 1 : 0] dut_p_word;
    reg [DATA_WIDTH - 1 : 0] dut_n_word;
    reg [DATA_WIDTH - 1 : 0] gold_p_word;
    reg [DATA_WIDTH - 1 : 0] gold_n_word;
    reg signed [31 : 0] dut_value;
    reg signed [31 : 0] gold_value;

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

    iter_prior_online_mma8_global_wavefront_top #(
        .num_stages(NUM_STAGES),
        .num_rows(TOTAL_ROWS),
        .degree(DEGREE),
        .bit_width(BIT_WIDTH),
        .data_width(DATA_WIDTH),
        .bias_width(BIAS_WIDTH),
        .src_idx_width(SRC_IDX_WIDTH),
        .capture_unit(0),
        .digit_idx_width(DIGIT_IDX_WIDTH)
    ) dut (
        .i_clk(i_clk),
        .i_rst(i_rst),
        .i_clear(i_clear),
        .i_start(i_start),
        .i_valid_digit(i_valid_digit),
        .i_digit_idx(i_digit_idx),
        .i_stage0_state_digit_p_terms_rows({TOTAL_ROWS * DEGREE{1'b0}}),
        .i_stage0_state_digit_n_terms_rows({TOTAL_ROWS * DEGREE{1'b0}}),
        .i_src_row_idx_rows(w_src_row_idx_clusters),
        .i_coeff_p_terms_rows(w_coeff_p_terms_clusters),
        .i_coeff_n_terms_rows(w_coeff_n_terms_clusters),
        .i_bias_p_rows(w_bias_vec_p_rows_clusters),
        .i_bias_n_rows(w_bias_vec_n_rows_clusters),
        .o_final_valid_rows(w_final_valid_rows),
        .o_final_digit_idx_rows(w_final_digit_idx_rows),
        .o_final_digit_p_rows(w_final_digit_p_rows),
        .o_final_digit_n_rows(w_final_digit_n_rows),
        .o_final_done_rows(w_final_done_rows),
        .o_stage_valid_rows(w_stage_valid_rows),
        .o_stage_digit_idx_rows(w_stage_digit_idx_rows),
        .o_stage_digit_p_rows(w_stage_digit_p_rows),
        .o_stage_digit_n_rows(w_stage_digit_n_rows),
        .o_stage_done_rows(w_stage_done_rows),
        .o_stage_valid_count(w_stage_valid_count),
        .o_stage_done(w_stage_done),
        .o_stage_started_before_prev_done(w_stage_started_before_prev_done)
    );

    always @(posedge i_clk) begin
        if (i_rst || i_clear) begin
            capture_count <= 0;
            captured_p_rows <= {TOTAL_ROWS * DATA_WIDTH{1'b0}};
            captured_n_rows <= {TOTAL_ROWS * DATA_WIDTH{1'b0}};
        end else if (w_final_valid_rows[0] && (capture_count < DATA_WIDTH)) begin
            bit_sel = DATA_WIDTH - 1 - w_final_digit_idx_rows[DIGIT_IDX_WIDTH - 1 : 0];
            for (ri = 0; ri < TOTAL_ROWS; ri = ri + 1) begin
                captured_p_rows[ri * DATA_WIDTH + bit_sel] <= w_final_digit_p_rows[ri];
                captured_n_rows[ri * DATA_WIDTH + bit_sel] <= w_final_digit_n_rows[ri];
            end
            capture_count <= capture_count + 1;
        end
    end

    always @(posedge i_clk) begin
        if (i_rst || i_clear) begin
            cycle_count <= 0;
        end else begin
            cycle_count <= cycle_count + 1;
        end
    end

    initial begin
`ifdef PRIOR_WAVEFRONT_TEMPLATE_MEMH
        $readmemh(`PRIOR_WAVEFRONT_TEMPLATE_MEMH,
            template_mem);
`else
        $readmemh("MSDF_iterative_solver/generated/rtl_vectors/pagerank32_global_prior_fractional/templates.memh",
            template_mem);
`endif
`ifdef PRIOR_WAVEFRONT_GOLD_STATE_P_MEMH
        $readmemh(`PRIOR_WAVEFRONT_GOLD_STATE_P_MEMH,
            gold_state_p_mem);
`else
        $readmemh("MSDF_iterative_solver/generated/rtl_vectors/pagerank32_global_prior_fractional/gold_state_p_iters.memh",
            gold_state_p_mem);
`endif
`ifdef PRIOR_WAVEFRONT_GOLD_STATE_N_MEMH
        $readmemh(`PRIOR_WAVEFRONT_GOLD_STATE_N_MEMH,
            gold_state_n_mem);
`else
        $readmemh("MSDF_iterative_solver/generated/rtl_vectors/pagerank32_global_prior_fractional/gold_state_n_iters.memh",
            gold_state_n_mem);
`endif

        i_clk = 1'b0;
        i_rst = 1'b1;
        i_clear = 1'b0;
        i_start = 1'b0;
        i_valid_digit = 1'b0;
        i_digit_idx = {DIGIT_IDX_WIDTH{1'b0}};
        template_words_clusters = {NUM_CLUSTERS * TEMPLATE_PAYLOAD_WIDTH{1'b0}};

        for (ci = 0; ci < NUM_CLUSTERS; ci = ci + 1) begin
            template_words_clusters[ci * TEMPLATE_PAYLOAD_WIDTH +:
                TEMPLATE_PAYLOAD_WIDTH] = template_mem[ci];
        end

        repeat (4) @(posedge i_clk);
        i_rst <= 1'b0;
        @(posedge i_clk);

        for (ti = 0; ti < DATA_WIDTH; ti = ti + 1) begin
            i_start <= (ti == 0);
            i_valid_digit <= 1'b1;
            i_digit_idx <= ti[DIGIT_IDX_WIDTH - 1 : 0];
            @(posedge i_clk);
        end
        i_start <= 1'b0;
        i_valid_digit <= 1'b0;
        i_digit_idx <= {DIGIT_IDX_WIDTH{1'b0}};

        wait_count = 0;
        while (!w_final_done_rows[0] && wait_count < 512) begin
            @(posedge i_clk);
            wait_count = wait_count + 1;
        end
        @(posedge i_clk);
        #1;

        if (!w_stage_done[NUM_STAGES - 1] || capture_count !== DATA_WIDTH) begin
            $display("ERROR prior wavefront did not complete done=%b capture=%0d counts=%h",
                w_stage_done, capture_count, w_stage_valid_count);
            $fatal;
        end

        if (w_stage_started_before_prev_done !== {(NUM_STAGES - 1){1'b1}}) begin
            $display("ERROR expected direct stage overlap flags=%b",
                w_stage_started_before_prev_done);
            $fatal;
        end

        for (ci = 0; ci < NUM_CLUSTERS; ci = ci + 1) begin
            gold_idx = (NUM_STAGES - 1) * NUM_CLUSTERS + ci;
            for (ri = 0; ri < ROWS_PER_CLUSTER; ri = ri + 1) begin
                global_row = ci * ROWS_PER_CLUSTER + ri;
                dut_p_word =
                    captured_p_rows[global_row * DATA_WIDTH +: DATA_WIDTH];
                dut_n_word =
                    captured_n_rows[global_row * DATA_WIDTH +: DATA_WIDTH];
                gold_p_word =
                    gold_state_p_mem[gold_idx][ri * DATA_WIDTH +: DATA_WIDTH];
                gold_n_word =
                    gold_state_n_mem[gold_idx][ri * DATA_WIDTH +: DATA_WIDTH];
                dut_value = iter_tb_signed_digit_value(dut_p_word, dut_n_word);
                gold_value = iter_tb_magnitude_rail_value(gold_p_word, gold_n_word);
                delta_value = dut_value - gold_value;
                abs_delta = (delta_value < 0) ? -delta_value : delta_value;
                if (abs_delta > PRIOR_TOLERANCE) begin
                    $display("ERROR prior wavefront state mismatch K=%0d row=%0d got=%0d expected=%0d p/n=%h/%h gold=%h/%h",
                        NUM_STAGES,
                        global_row,
                        dut_value,
                        gold_value,
                        dut_p_word,
                        dut_n_word,
                        gold_p_word,
                        gold_n_word);
                    $fatal;
                end
            end
        end

        $display("PASS tb_iter_prior_online_mma8_global_wavefront_top");
        $display("COUNTERS prior_wavefront K=%0d total=%0d capture=%0d stage_counts=%h overlap=%b",
            NUM_STAGES,
            cycle_count,
            capture_count,
            w_stage_valid_count,
            w_stage_started_before_prev_done);
        $finish;
    end

endmodule
