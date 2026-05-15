`timescale 1ns / 1ps

// P3-SP continuous feedback PageRank test with the original paper's
// L-infinity convergence condition.

module tb_iter_parallel_in_online_mma8_global_feedback_top;

`ifdef PARALLEL_IN_FEEDBACK_STAGES_VALUE
    localparam integer NUM_STAGES = `PARALLEL_IN_FEEDBACK_STAGES_VALUE;
`else
    localparam integer NUM_STAGES = 4;
`endif
`ifdef PARALLEL_IN_FEEDBACK_SUPERSTEPS_VALUE
    localparam integer TARGET_SUPERSTEPS = `PARALLEL_IN_FEEDBACK_SUPERSTEPS_VALUE;
`else
    localparam integer TARGET_SUPERSTEPS = 2;
`endif
`ifdef PARALLEL_IN_FEEDBACK_LINF_ETA_VALUE
    localparam integer LINF_ETA = `PARALLEL_IN_FEEDBACK_LINF_ETA_VALUE;
`else
    localparam integer LINF_ETA = 1;
`endif
`ifdef PARALLEL_IN_FEEDBACK_EXPECT_CONVERGED_VALUE
    localparam integer EXPECT_CONVERGED = `PARALLEL_IN_FEEDBACK_EXPECT_CONVERGED_VALUE;
`else
    localparam integer EXPECT_CONVERGED = 0;
`endif
`ifdef PARALLEL_IN_FAST2_VALUE
    localparam integer FAST2_CORE = `PARALLEL_IN_FAST2_VALUE;
`else
    localparam integer FAST2_CORE = 0;
`endif
`ifdef PARALLEL_IN_EST_SELECTOR_VALUE
    localparam integer EST_SELECTOR = `PARALLEL_IN_EST_SELECTOR_VALUE;
`else
    localparam integer EST_SELECTOR = 0;
`endif
`ifdef PARALLEL_IN_EST_FRAC_BITS_VALUE
    localparam integer EST_FRAC_BITS = `PARALLEL_IN_EST_FRAC_BITS_VALUE;
`else
    localparam integer EST_FRAC_BITS = 6;
`endif
`ifdef PARALLEL_IN_EST_GUARD_BITS_VALUE
    localparam integer EST_GUARD_BITS = `PARALLEL_IN_EST_GUARD_BITS_VALUE;
`else
    localparam integer EST_GUARD_BITS = 2;
`endif
`ifdef PARALLEL_IN_REDUNDANT_RESIDUAL_VALUE
    localparam integer REDUNDANT_RESIDUAL =
        `PARALLEL_IN_REDUNDANT_RESIDUAL_VALUE;
`else
    localparam integer REDUNDANT_RESIDUAL = 0;
`endif
`ifdef PARALLEL_IN_SPLIT_ESTIMATE_VALUE
    localparam integer SPLIT_ESTIMATE = `PARALLEL_IN_SPLIT_ESTIMATE_VALUE;
`else
    localparam integer SPLIT_ESTIMATE = 1;
`endif
`ifdef PARALLEL_IN_NONNEGATIVE_COEFF_VALUE
    localparam integer NONNEGATIVE_COEFF =
        `PARALLEL_IN_NONNEGATIVE_COEFF_VALUE;
`else
    localparam integer NONNEGATIVE_COEFF = 0;
`endif
`ifdef PARALLEL_IN_NONNEGATIVE_BIAS_VALUE
    localparam integer NONNEGATIVE_BIAS =
        `PARALLEL_IN_NONNEGATIVE_BIAS_VALUE;
`else
    localparam integer NONNEGATIVE_BIAS = 0;
`endif
`ifdef PARALLEL_IN_SOURCE_ONEHOT_VALUE
    localparam integer SOURCE_ONEHOT =
        `PARALLEL_IN_SOURCE_ONEHOT_VALUE;
`else
    localparam integer SOURCE_ONEHOT = 0;
`endif
`ifdef PARALLEL_IN_FEEDBACK_FIFO_DEPTH_VALUE
    localparam integer FEEDBACK_FIFO_DEPTH =
        `PARALLEL_IN_FEEDBACK_FIFO_DEPTH_VALUE;
`else
    localparam integer FEEDBACK_FIFO_DEPTH = 128;
`endif
`ifdef PARALLEL_IN_DEGREE_VALUE
    localparam integer DEGREE = `PARALLEL_IN_DEGREE_VALUE;
`else
    localparam integer DEGREE = 4;
`endif
`ifdef PARALLEL_IN_PHYSICAL_DEGREE_VALUE
    localparam integer PHYSICAL_DEGREE = `PARALLEL_IN_PHYSICAL_DEGREE_VALUE;
`else
    localparam integer PHYSICAL_DEGREE = 8;
`endif
    localparam integer NUM_CLUSTERS = 8;
    localparam integer ROWS_PER_CLUSTER = 4;
    localparam integer TOTAL_ROWS = NUM_CLUSTERS * ROWS_PER_CLUSTER;
    localparam integer BIT_WIDTH = 30;
    localparam integer DATA_WIDTH = 32;
    localparam integer BIAS_WIDTH = BIT_WIDTH + 2;
    localparam integer ACC_WIDTH = 64;
`ifdef PARALLEL_IN_CORE_ACC_WIDTH_VALUE
    localparam integer CORE_ACC_WIDTH = `PARALLEL_IN_CORE_ACC_WIDTH_VALUE;
`else
    localparam integer CORE_ACC_WIDTH = 33;
`endif
    localparam integer SRC_IDX_WIDTH = 5;
    localparam integer VALID_WIDTH = ROWS_PER_CLUSTER * DEGREE;
    localparam integer SRC_WIDTH = ROWS_PER_CLUSTER * DEGREE * SRC_IDX_WIDTH;
    localparam integer COEFF_TERMS_WIDTH = ROWS_PER_CLUSTER * DEGREE * BIT_WIDTH;
    localparam integer BIAS_VEC_WIDTH = ROWS_PER_CLUSTER * BIAS_WIDTH;
    localparam integer TEMPLATE_PAYLOAD_WIDTH =
        VALID_WIDTH + SRC_WIDTH + 2 * COEFF_TERMS_WIDTH + 2 * BIAS_VEC_WIDTH;
    localparam integer DIGIT_IDX_WIDTH = $clog2(DATA_WIDTH);
    localparam integer GOLD_ITERS = NUM_STAGES * TARGET_SUPERSTEPS;
    localparam integer VALUE_TOLERANCE = 0;
    localparam integer LINF_TOLERANCE = 0;

`include "iter_tb_signed_digit_reconstruct.vh"

    reg i_clk;
    reg i_rst;
    reg i_clear;
    reg i_start;
    reg i_valid_digit;
    reg [DIGIT_IDX_WIDTH - 1 : 0] i_digit_idx;
    reg [TEMPLATE_PAYLOAD_WIDTH - 1 : 0] template_mem [0 : NUM_CLUSTERS - 1];
    reg [NUM_CLUSTERS * TEMPLATE_PAYLOAD_WIDTH - 1 : 0] template_words_clusters;
    reg [ROWS_PER_CLUSTER * DATA_WIDTH - 1 : 0] gold_state_p_mem [0 : GOLD_ITERS * NUM_CLUSTERS - 1];
    reg [ROWS_PER_CLUSTER * DATA_WIDTH - 1 : 0] gold_state_n_mem [0 : GOLD_ITERS * NUM_CLUSTERS - 1];
    reg [ACC_WIDTH - 1 : 0] gold_linf_mem [0 : GOLD_ITERS - 1];

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
    wire [NUM_STAGES * 32 - 1 : 0] w_stage_linf_valid_count;
    wire [NUM_STAGES * ACC_WIDTH - 1 : 0] w_stage_linf_delta;
    wire [NUM_STAGES - 1 : 0] w_stage_linf_valid;
    wire [NUM_STAGES - 1 : 0] w_stage_done;
    wire [NUM_STAGES - 2 : 0] w_stage_started_before_prev_done;
    wire [31 : 0] w_superstep_count;
    wire [31 : 0] w_feedback_fifo_stall;
    wire [31 : 0] w_cert_late_cycles;
    wire [NUM_STAGES * 32 - 1 : 0] w_converged_stage_histogram;
    wire [31 : 0] w_speculative_kill_digits;
    wire w_converged;
    wire [$clog2(NUM_STAGES) - 1 : 0] w_converged_stage;

    reg [TOTAL_ROWS * DATA_WIDTH - 1 : 0] captured_p_rows;
    reg [TOTAL_ROWS * DATA_WIDTH - 1 : 0] captured_n_rows;
    reg [31 : 0] stage_linf_seen [0 : NUM_STAGES - 1];
    reg [31 : 0] first_valid_cycle [0 : NUM_STAGES - 1];
    integer capture_count;
    integer final_supersteps_seen;
    integer cycle_count;
    integer wait_count;
    integer ti;
    integer ci;
    integer ri;
    integer si;
    integer global_row;
    integer bit_sel;
    integer gold_idx;
    integer iter_idx;
    integer delta_value;
    integer abs_delta;
    reg [DATA_WIDTH - 1 : 0] dut_p_word;
    reg [DATA_WIDTH - 1 : 0] dut_n_word;
    reg [DATA_WIDTH - 1 : 0] gold_p_word;
    reg [DATA_WIDTH - 1 : 0] gold_n_word;
    reg signed [31 : 0] dut_value;
    reg signed [31 : 0] gold_value;
    reg [ACC_WIDTH - 1 : 0] dut_linf;
    reg [ACC_WIDTH - 1 : 0] gold_linf;
    wire [ACC_WIDTH - 1 : 0] w_linf_eta_value;

    assign w_linf_eta_value = {{(ACC_WIDTH - 32){1'b0}}, LINF_ETA[31:0]};

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

    iter_parallel_in_online_mma8_global_feedback_top #(
        .num_stages(NUM_STAGES),
        .num_rows(TOTAL_ROWS),
        .degree(DEGREE),
        .physical_degree(PHYSICAL_DEGREE),
        .bit_width(BIT_WIDTH),
        .data_width(DATA_WIDTH),
        .bias_width(BIAS_WIDTH),
        .online_delay(2),
        .acc_width(ACC_WIDTH),
        .core_acc_width(CORE_ACC_WIDTH),
        .fast2_core(FAST2_CORE),
        .estimate_selector(EST_SELECTOR),
        .estimate_frac_bits(EST_FRAC_BITS),
        .estimate_guard_bits(EST_GUARD_BITS),
        .split_estimate(SPLIT_ESTIMATE),
        .redundant_residual(REDUNDANT_RESIDUAL),
        .nonnegative_coeff(NONNEGATIVE_COEFF),
        .nonnegative_bias(NONNEGATIVE_BIAS),
        .source_onehot(SOURCE_ONEHOT),
        .src_idx_width(SRC_IDX_WIDTH),
        .feedback_fifo_depth(FEEDBACK_FIFO_DEPTH),
        .digit_idx_width(DIGIT_IDX_WIDTH)
    ) dut (
        .i_clk(i_clk),
        .i_rst(i_rst),
        .i_clear(i_clear),
        .i_start(i_start),
        .i_valid_digit(i_valid_digit),
        .i_digit_idx(i_digit_idx),
        .i_stage0_state_digit_p_rows({TOTAL_ROWS{1'b0}}),
        .i_stage0_state_digit_n_rows({TOTAL_ROWS{1'b0}}),
        .i_src_row_idx_rows(w_src_row_idx_clusters),
        .i_coeff_p_terms_rows(w_coeff_p_terms_clusters),
        .i_coeff_n_terms_rows(w_coeff_n_terms_clusters),
        .i_bias_p_rows(w_bias_vec_p_rows_clusters),
        .i_bias_n_rows(w_bias_vec_n_rows_clusters),
        .i_linf_eta(w_linf_eta_value),
        .i_stop_on_converged(EXPECT_CONVERGED != 0),
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
        .o_stage_linf_valid_count(w_stage_linf_valid_count),
        .o_stage_linf_delta(w_stage_linf_delta),
        .o_stage_linf_valid(w_stage_linf_valid),
        .o_stage_done(w_stage_done),
        .o_stage_started_before_prev_done(w_stage_started_before_prev_done),
        .o_superstep_count(w_superstep_count),
        .o_feedback_fifo_stall(w_feedback_fifo_stall),
        .o_cert_late_cycles(w_cert_late_cycles),
        .o_converged_stage_histogram(w_converged_stage_histogram),
        .o_speculative_kill_digits(w_speculative_kill_digits),
        .o_converged(w_converged),
        .o_converged_stage(w_converged_stage)
    );

    always @(posedge i_clk) begin
        if (i_rst || i_clear) begin
            capture_count <= 0;
            final_supersteps_seen <= 0;
            captured_p_rows <= {TOTAL_ROWS * DATA_WIDTH{1'b0}};
            captured_n_rows <= {TOTAL_ROWS * DATA_WIDTH{1'b0}};
        end else begin
            if (w_final_valid_rows[0]) begin
                bit_sel = DATA_WIDTH - 1 -
                    w_final_digit_idx_rows[DIGIT_IDX_WIDTH - 1 : 0];
                for (ri = 0; ri < TOTAL_ROWS; ri = ri + 1) begin
                    captured_p_rows[ri * DATA_WIDTH + bit_sel] <=
                        w_final_digit_p_rows[ri];
                    captured_n_rows[ri * DATA_WIDTH + bit_sel] <=
                        w_final_digit_n_rows[ri];
                end
                capture_count <= capture_count + 1;
            end
            if (w_final_done_rows[0]) begin
                final_supersteps_seen <= final_supersteps_seen + 1;
            end
        end
    end

    always @(posedge i_clk) begin
        if (i_rst || i_clear) begin
            cycle_count <= 0;
            for (si = 0; si < NUM_STAGES; si = si + 1) begin
                stage_linf_seen[si] <= 0;
                first_valid_cycle[si] <= 32'hffff_ffff;
            end
        end else begin
            cycle_count <= cycle_count + 1;
            for (si = 0; si < NUM_STAGES; si = si + 1) begin
                if (w_stage_valid_rows[si * TOTAL_ROWS] &&
                    first_valid_cycle[si] == 32'hffff_ffff) begin
                    first_valid_cycle[si] <= cycle_count;
                end
                if (w_stage_linf_valid[si]) begin
                    iter_idx = stage_linf_seen[si] * NUM_STAGES + si;
                    if (iter_idx < GOLD_ITERS) begin
                        dut_linf = w_stage_linf_delta[si * ACC_WIDTH +: ACC_WIDTH];
                        gold_linf = gold_linf_mem[iter_idx];
                        delta_value = dut_linf - gold_linf;
                        abs_delta = (delta_value < 0) ? -delta_value : delta_value;
                        if (abs_delta > LINF_TOLERANCE) begin
                            $display("ERROR Linf mismatch stage=%0d iter=%0d got=%0d expected=%0d",
                                si, iter_idx, dut_linf, gold_linf);
                            $fatal;
                        end
                    end
                    stage_linf_seen[si] <= stage_linf_seen[si] + 1;
                end
            end
        end
    end

    initial begin
`ifdef PARALLEL_IN_TEMPLATE_MEMH
        $readmemh(`PARALLEL_IN_TEMPLATE_MEMH,
            template_mem);
`else
        $readmemh("MSDF_iterative_solver/generated/rtl_vectors/pagerank32_global_parallel_in_fractional/templates.memh",
            template_mem);
`endif
`ifdef PARALLEL_IN_GOLD_STATE_P_MEMH
        $readmemh(`PARALLEL_IN_GOLD_STATE_P_MEMH,
            gold_state_p_mem);
`else
        $readmemh("MSDF_iterative_solver/generated/rtl_vectors/pagerank32_global_parallel_in_fractional/gold_state_p_iters.memh",
            gold_state_p_mem);
`endif
`ifdef PARALLEL_IN_GOLD_STATE_N_MEMH
        $readmemh(`PARALLEL_IN_GOLD_STATE_N_MEMH,
            gold_state_n_mem);
`else
        $readmemh("MSDF_iterative_solver/generated/rtl_vectors/pagerank32_global_parallel_in_fractional/gold_state_n_iters.memh",
            gold_state_n_mem);
`endif
`ifdef PARALLEL_IN_GOLD_LINF_MEMH
        $readmemh(`PARALLEL_IN_GOLD_LINF_MEMH,
            gold_linf_mem);
`else
        $readmemh("MSDF_iterative_solver/generated/rtl_vectors/pagerank32_global_parallel_in_fractional/gold_global_linf_delta.memh",
            gold_linf_mem);
`endif

        i_clk = 1'b0;
        i_rst = 1'b1;
        i_clear = 1'b0;
        i_start = 1'b0;
        i_valid_digit = 1'b0;
        i_digit_idx = {DIGIT_IDX_WIDTH{1'b0}};
        template_words_clusters = {NUM_CLUSTERS * TEMPLATE_PAYLOAD_WIDTH{1'b0}};
        capture_count = 0;
        final_supersteps_seen = 0;
        cycle_count = 0;

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
        if (EXPECT_CONVERGED != 0) begin
            while (!w_converged && wait_count < 4096) begin
                @(posedge i_clk);
                wait_count = wait_count + 1;
            end
        end else begin
            while ((final_supersteps_seen < TARGET_SUPERSTEPS) &&
                   wait_count < 4096) begin
                @(posedge i_clk);
                wait_count = wait_count + 1;
            end
        end
        repeat (4) @(posedge i_clk);
        #1;

        if (EXPECT_CONVERGED != 0) begin
            if (!w_converged) begin
                $display("ERROR expected Linf convergence but none was reported");
                $fatal;
            end
        end else if (final_supersteps_seen < TARGET_SUPERSTEPS) begin
            $display("ERROR feedback pipeline did not reach target supersteps got=%0d target=%0d",
                final_supersteps_seen, TARGET_SUPERSTEPS);
            $fatal;
        end

        if (EXPECT_CONVERGED == 0) begin
            gold_idx = (GOLD_ITERS - 1) * NUM_CLUSTERS;
            for (ci = 0; ci < NUM_CLUSTERS; ci = ci + 1) begin
                for (ri = 0; ri < ROWS_PER_CLUSTER; ri = ri + 1) begin
                    global_row = ci * ROWS_PER_CLUSTER + ri;
                    dut_p_word = captured_p_rows[global_row * DATA_WIDTH +: DATA_WIDTH];
                    dut_n_word = captured_n_rows[global_row * DATA_WIDTH +: DATA_WIDTH];
                    gold_p_word = gold_state_p_mem[gold_idx + ci][ri * DATA_WIDTH +: DATA_WIDTH];
                    gold_n_word = gold_state_n_mem[gold_idx + ci][ri * DATA_WIDTH +: DATA_WIDTH];
                    dut_value = iter_tb_signed_digit_value(dut_p_word, dut_n_word);
                    gold_value = iter_tb_signed_digit_value(gold_p_word, gold_n_word);
                    delta_value = dut_value - gold_value;
                    abs_delta = (delta_value < 0) ? -delta_value : delta_value;
                    if (abs_delta > VALUE_TOLERANCE) begin
                        $display("ERROR feedback state mismatch K=%0d supersteps=%0d row=%0d got=%0d expected=%0d p/n=%h/%h gold=%h/%h",
                            NUM_STAGES, TARGET_SUPERSTEPS, global_row,
                            dut_value, gold_value, dut_p_word, dut_n_word,
                            gold_p_word, gold_n_word);
                        $fatal;
                    end
                end
            end
        end

        if (w_stage_started_before_prev_done !== {(NUM_STAGES - 1){1'b1}}) begin
            $display("ERROR expected direct stage overlap flags=%b",
                w_stage_started_before_prev_done);
            $fatal;
        end

        $display("PASS tb_iter_parallel_in_online_mma8_global_feedback_top");
        $display("COUNTERS parallel_in_feedback K=%0d target_supersteps=%0d linf_eta=%0d fast2=%0d total=%0d final_supersteps=%0d capture=%0d first_valid0=%0d first_valid1=%0d first_gap01=%0d stage_counts=%h linf_counts=%h feedback_stall=%0d cert_late=%0d converged=%0d converged_stage=%0d hist=%h kill=%0d overlap=%b",
            NUM_STAGES,
            TARGET_SUPERSTEPS,
            LINF_ETA,
            FAST2_CORE,
            cycle_count,
            final_supersteps_seen,
            capture_count,
            first_valid_cycle[0],
            first_valid_cycle[1],
            first_valid_cycle[1] - first_valid_cycle[0],
            w_stage_valid_count,
            w_stage_linf_valid_count,
            w_feedback_fifo_stall,
            w_cert_late_cycles,
            w_converged,
            w_converged_stage,
            w_converged_stage_histogram,
            w_speculative_kill_digits,
            w_stage_started_before_prev_done);
        $finish;
    end

endmodule
