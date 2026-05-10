`timescale 1ns / 1ps

module tb_iter_dense_runtime_wavefront_superstep_smoke;
    localparam integer NUM_TOTAL_CLUSTERS = 1;
    localparam integer NUM_CLUSTERS = 1;
    localparam integer NUM_ROWS = 1;
    localparam integer DEGREE = 4;
    localparam integer BIT_WIDTH = 5;
    localparam integer DATA_WIDTH = BIT_WIDTH + 3;
    localparam integer BOUND_WIDTH = BIT_WIDTH + 5;
    localparam integer COEFF_WIDTH = 8;
    localparam integer ACC_WIDTH = 24;
    localparam integer BLOCK_SIZE = 1;
    localparam integer NUM_BLOCKS = 1;
    localparam integer SUPERSTEP_STAGES = 4;
    localparam integer SKIP_DIGITS = 4;
    localparam integer ROW_IDX_WIDTH = 1;
    localparam integer SRC_IDX_WIDTH = 1;
    localparam integer CLUSTER_ADDR_WIDTH = 1;
    localparam integer CLUSTER_SLOT_WIDTH = 1;
    localparam integer BIAS_WIDTH = BIT_WIDTH + 2;
    localparam integer DIGIT_IDX_WIDTH = $clog2(DATA_WIDTH);
    localparam integer VALID_WIDTH = NUM_ROWS * DEGREE;
    localparam integer SRC_WIDTH = NUM_ROWS * DEGREE * SRC_IDX_WIDTH;
    localparam integer COEFF_TERMS_WIDTH = NUM_ROWS * DEGREE * BIT_WIDTH;
    localparam integer BIAS_VEC_WIDTH = NUM_ROWS * BIAS_WIDTH;
    localparam integer TEMPLATE_PAYLOAD_WIDTH =
        VALID_WIDTH + SRC_WIDTH + 2 * COEFF_TERMS_WIDTH + 2 * BIAS_VEC_WIDTH;
    localparam integer BLOCK_WEIGHTS_WIDTH = NUM_ROWS * NUM_BLOCKS * COEFF_WIDTH;
    localparam integer CERT_PAYLOAD_WIDTH = BLOCK_WEIGHTS_WIDTH + ACC_WIDTH;

    reg i_clk;
    reg i_rst;
    reg i_cfg_template_we;
    reg i_cfg_cert_we;
    reg [CLUSTER_ADDR_WIDTH - 1 : 0] i_cfg_cluster_addr;
    reg [TEMPLATE_PAYLOAD_WIDTH - 1 : 0] i_cfg_template_word;
    reg [CERT_PAYLOAD_WIDTH - 1 : 0] i_cfg_cert_word;
    reg i_load_window;
    reg i_cfg_state_we;
    reg [CLUSTER_SLOT_WIDTH - 1 : 0] i_cfg_state_cluster_slot;
    reg i_cfg_state_bank_sel;
    reg [ROW_IDX_WIDTH - 1 : 0] i_cfg_state_row_idx;
    reg [DATA_WIDTH - 1 : 0] i_cfg_state_p;
    reg [DATA_WIDTH - 1 : 0] i_cfg_state_n;
    reg i_start_iter;
    reg i_commit_iter;
    reg [CLUSTER_ADDR_WIDTH - 1 : 0] i_base_cluster_idx;
    reg [NUM_CLUSTERS - 1 : 0] i_use_replay_clusters;
    reg [DIGIT_IDX_WIDTH - 1 : 0] i_replay_digit_idx;
    reg [NUM_CLUSTERS * NUM_ROWS - 1 : 0] i_issue_rows_clusters;
    reg [NUM_CLUSTERS * BOUND_WIDTH - 1 : 0] i_tail_bound_clusters;
    reg i_counter_clear;

    wire o_window_valid;
    wire o_iter_done;
    wire o_iter_converged;
    wire [NUM_CLUSTERS - 1 : 0] o_cluster_certified;
    wire [NUM_CLUSTERS * ACC_WIDTH - 1 : 0] o_cluster_max_error;
    wire [NUM_CLUSTERS * NUM_ROWS * DATA_WIDTH - 1 : 0] o_x_old_p_rows_clusters;
    wire [NUM_CLUSTERS * NUM_ROWS * DATA_WIDTH - 1 : 0] o_x_old_n_rows_clusters;

    reg ref_start;
    reg ref_valid_digit;
    reg [DIGIT_IDX_WIDTH - 1 : 0] ref_digit_idx;
    reg [NUM_ROWS - 1 : 0] ref_ext_x1_p_rows;
    reg [NUM_ROWS - 1 : 0] ref_ext_x1_n_rows;
    wire [NUM_ROWS - 1 : 0] ref_final_valid_rows;
    wire [NUM_ROWS * DIGIT_IDX_WIDTH - 1 : 0] ref_final_digit_idx_rows;
    wire [NUM_ROWS - 1 : 0] ref_final_digit_p_rows;
    wire [NUM_ROWS - 1 : 0] ref_final_digit_n_rows;
    wire ref_cluster_valid;
    wire [ACC_WIDTH - 1 : 0] ref_cluster_max_error;
    wire [SUPERSTEP_STAGES - 1 : 0] ref_stage_done;
    reg [DATA_WIDTH - 1 : 0] ref_final_p_word;
    reg [DATA_WIDTH - 1 : 0] ref_final_n_word;
    reg runtime_done_seen;
    reg runtime_converged_seen;
    reg ref_cluster_valid_seen;

    reg [VALID_WIDTH - 1 : 0] valid_mask;
    reg [SRC_WIDTH - 1 : 0] src_idx;
    reg [COEFF_TERMS_WIDTH - 1 : 0] coeff_p_terms;
    reg [COEFF_TERMS_WIDTH - 1 : 0] coeff_n_terms;
    reg [BIAS_VEC_WIDTH - 1 : 0] bias_p_rows;
    reg [BIAS_VEC_WIDTH - 1 : 0] bias_n_rows;
    reg [BLOCK_WEIGHTS_WIDTH - 1 : 0] block_weights;
    reg [DATA_WIDTH - 1 : 0] initial_state_p;
    reg [DATA_WIDTH - 1 : 0] initial_state_n;
    integer di;
    integer wait_count;
    integer bit_sel;

    iter_dense_small_runtime_top #(
        .num_total_clusters(NUM_TOTAL_CLUSTERS),
        .num_clusters(NUM_CLUSTERS),
        .num_rows(NUM_ROWS),
        .degree(DEGREE),
        .bit_width(BIT_WIDTH),
        .bound_width(BOUND_WIDTH),
        .coeff_width(COEFF_WIDTH),
        .acc_width(ACC_WIDTH),
        .block_size(BLOCK_SIZE),
        .num_blocks(NUM_BLOCKS),
        .data_width(DATA_WIDTH),
        .row_datapath_mode(4),
        .auto_full_digit(1),
        .auto_prefix_gating(0),
        .row_idx_width(ROW_IDX_WIDTH),
        .src_idx_width(SRC_IDX_WIDTH),
        .cluster_addr_width(CLUSTER_ADDR_WIDTH),
        .cluster_slot_width(CLUSTER_SLOT_WIDTH),
        .solver_native_skip_digits(SKIP_DIGITS),
        .solver_native_affine_guard_shift(3),
        .solver_native_sample_width(5),
        .wavefront_superstep_stages(SUPERSTEP_STAGES),
        .runtime_mem_style(1)
    ) dut (
        .i_clk(i_clk),
        .i_rst(i_rst),
        .i_cfg_template_we(i_cfg_template_we),
        .i_cfg_cert_we(i_cfg_cert_we),
        .i_cfg_cluster_addr(i_cfg_cluster_addr),
        .i_cfg_template_word(i_cfg_template_word),
        .i_cfg_cert_word(i_cfg_cert_word),
        .i_load_window(i_load_window),
        .i_cfg_state_we(i_cfg_state_we),
        .i_cfg_state_cluster_slot(i_cfg_state_cluster_slot),
        .i_cfg_state_bank_sel(i_cfg_state_bank_sel),
        .i_cfg_state_row_idx(i_cfg_state_row_idx),
        .i_cfg_state_p(i_cfg_state_p),
        .i_cfg_state_n(i_cfg_state_n),
        .i_start_iter(i_start_iter),
        .i_commit_iter(i_commit_iter),
        .i_base_cluster_idx(i_base_cluster_idx),
        .i_use_replay_clusters(i_use_replay_clusters),
        .i_replay_digit_idx(i_replay_digit_idx),
        .i_issue_rows_clusters(i_issue_rows_clusters),
        .i_x0_p_rows_clusters({NUM_CLUSTERS * NUM_ROWS{1'b0}}),
        .i_x0_n_rows_clusters({NUM_CLUSTERS * NUM_ROWS{1'b0}}),
        .i_x1_p_rows_clusters({NUM_CLUSTERS * NUM_ROWS{1'b0}}),
        .i_x1_n_rows_clusters({NUM_CLUSTERS * NUM_ROWS{1'b0}}),
        .i_x2_p_rows_clusters({NUM_CLUSTERS * NUM_ROWS{1'b0}}),
        .i_x2_n_rows_clusters({NUM_CLUSTERS * NUM_ROWS{1'b0}}),
        .i_x3_p_rows_clusters({NUM_CLUSTERS * NUM_ROWS{1'b0}}),
        .i_x3_n_rows_clusters({NUM_CLUSTERS * NUM_ROWS{1'b0}}),
        .i_tail_bound_clusters(i_tail_bound_clusters),
        .i_counter_clear(i_counter_clear),
        .o_window_valid(o_window_valid),
        .o_window_busy(),
        .o_total_cycles(),
        .o_issue_cycles(),
        .o_cert_wait_cycles(),
        .o_iter_count(),
        .o_converged_iter(),
        .o_cfg_template_write_count(),
        .o_cfg_cert_write_count(),
        .o_cfg_state_write_count(),
        .o_window_load_count(),
        .o_window_busy_cycles(),
        .o_window_ready_cycles(),
        .o_active_digit_cycles(),
        .o_gated_digit_cycles(),
        .o_cert_prefix_digit_sum(),
        .o_certified_block_count(),
        .o_template_words_clusters(),
        .o_cert_param_words_clusters(),
        .o_sched_row_active_clusters(),
        .o_read_bank_sel_clusters(),
        .o_drv_x0_p_rows_clusters(),
        .o_drv_x0_n_rows_clusters(),
        .o_drv_x1_p_rows_clusters(),
        .o_drv_x1_n_rows_clusters(),
        .o_drv_x2_p_rows_clusters(),
        .o_drv_x2_n_rows_clusters(),
        .o_drv_x3_p_rows_clusters(),
        .o_drv_x3_n_rows_clusters(),
        .o_cluster_valid(),
        .o_cluster_certified(o_cluster_certified),
        .o_cluster_max_error(o_cluster_max_error),
        .o_x_old_p_rows_clusters(o_x_old_p_rows_clusters),
        .o_x_old_n_rows_clusters(o_x_old_n_rows_clusters),
        .o_iter_done(o_iter_done),
        .o_iter_converged(o_iter_converged),
        .o_iter_continue(),
        .o_seen_mask(),
        .o_cert_mask()
    );

    iter_wavefront_superstep_cluster_state_top #(
        .superstep_stages(SUPERSTEP_STAGES),
        .num_rows(NUM_ROWS),
        .degree(DEGREE),
        .bit_width(BIT_WIDTH),
        .data_width(DATA_WIDTH),
        .bias_width(BIAS_WIDTH),
        .bound_width(BOUND_WIDTH),
        .coeff_width(COEFF_WIDTH),
        .acc_width(ACC_WIDTH),
        .block_size(BLOCK_SIZE),
        .num_blocks(NUM_BLOCKS),
        .skip_digits(SKIP_DIGITS),
        .row_idx_width(ROW_IDX_WIDTH),
        .affine_guard_shift(3)
    ) ref_model (
        .i_clk(i_clk),
        .i_rst(i_rst),
        .i_start(ref_start),
        .i_valid_digit(ref_valid_digit),
        .i_digit_idx(ref_digit_idx),
        .i_use_replay(1'b0),
        .i_clear_write_bank(1'b0),
        .i_commit_swap(1'b0),
        .i_load_state(1'b0),
        .i_load_bank_sel(1'b0),
        .i_load_row_idx({ROW_IDX_WIDTH{1'b0}}),
        .i_load_state_p({DATA_WIDTH{1'b0}}),
        .i_load_state_n({DATA_WIDTH{1'b0}}),
        .i_src_row_idx({NUM_ROWS * DEGREE * ROW_IDX_WIDTH{1'b0}}),
        .i_inter_stage_source_p_rows({SUPERSTEP_STAGES * NUM_ROWS{1'b0}}),
        .i_inter_stage_source_n_rows({SUPERSTEP_STAGES * NUM_ROWS{1'b0}}),
        .i_ext_x0_p_rows({NUM_ROWS{1'b0}}),
        .i_ext_x0_n_rows({NUM_ROWS{1'b0}}),
        .i_ext_x1_p_rows(ref_ext_x1_p_rows),
        .i_ext_x1_n_rows(ref_ext_x1_n_rows),
        .i_ext_x2_p_rows({NUM_ROWS{1'b0}}),
        .i_ext_x2_n_rows({NUM_ROWS{1'b0}}),
        .i_ext_x3_p_rows({NUM_ROWS{1'b0}}),
        .i_ext_x3_n_rows({NUM_ROWS{1'b0}}),
        .i_coeff_p_terms_rows(coeff_p_terms),
        .i_coeff_n_terms_rows(coeff_n_terms),
        .i_bias_p_rows(bias_p_rows),
        .i_bias_n_rows(bias_n_rows),
        .i_block_weights(block_weights),
        .i_eta(24'hffffff),
        .i_tail_bound({BOUND_WIDTH{1'b0}}),
        .o_replay_x0_p_rows(),
        .o_replay_x0_n_rows(),
        .o_replay_x1_p_rows(),
        .o_replay_x1_n_rows(),
        .o_replay_x2_p_rows(),
        .o_replay_x2_n_rows(),
        .o_replay_x3_p_rows(),
        .o_replay_x3_n_rows(),
        .o_final_valid_rows(ref_final_valid_rows),
        .o_final_digit_idx_rows(ref_final_digit_idx_rows),
        .o_final_digit_p_rows(ref_final_digit_p_rows),
        .o_final_digit_n_rows(ref_final_digit_n_rows),
        .o_read_state_p_rows(),
        .o_read_state_n_rows(),
        .o_cluster_valid(ref_cluster_valid),
        .o_cluster_certified(),
        .o_cluster_max_error(ref_cluster_max_error),
        .o_stage_commit_valid_rows(),
        .o_stage_commit_digit_idx_rows(),
        .o_stage_commit_digit_p_rows(),
        .o_stage_commit_digit_n_rows(),
        .o_stage_done(ref_stage_done)
    );

    always #5 i_clk = ~i_clk;

    task pack_template;
        begin
            valid_mask = {VALID_WIDTH{1'b0}};
            src_idx = {SRC_WIDTH{1'b0}};
            coeff_p_terms = {COEFF_TERMS_WIDTH{1'b0}};
            coeff_n_terms = {COEFF_TERMS_WIDTH{1'b0}};
            bias_p_rows = {BIAS_VEC_WIDTH{1'b0}};
            bias_n_rows = {BIAS_VEC_WIDTH{1'b0}};
            valid_mask[1] = 1'b1;
            coeff_p_terms[1 * BIT_WIDTH +: BIT_WIDTH] = 5'd1;
            i_cfg_template_word = {
                bias_n_rows,
                bias_p_rows,
                coeff_n_terms,
                coeff_p_terms,
                src_idx,
                valid_mask
            };
        end
    endtask

    always @(posedge i_clk) begin
        #1;
        if (i_rst || ref_start) begin
            ref_final_p_word = {DATA_WIDTH{1'b0}};
            ref_final_n_word = {DATA_WIDTH{1'b0}};
            runtime_done_seen = 1'b0;
            runtime_converged_seen = 1'b0;
            ref_cluster_valid_seen = 1'b0;
        end else if (ref_final_valid_rows[0]) begin
            bit_sel = DATA_WIDTH - 1 - ref_final_digit_idx_rows[DIGIT_IDX_WIDTH - 1 : 0];
            ref_final_p_word[bit_sel] = ref_final_digit_p_rows[0];
            ref_final_n_word[bit_sel] = ref_final_digit_n_rows[0];
        end
        if (!i_rst && !ref_start) begin
            if (o_iter_done) begin
                runtime_done_seen = 1'b1;
            end
            if (o_iter_converged) begin
                runtime_converged_seen = 1'b1;
            end
            if (ref_cluster_valid) begin
                ref_cluster_valid_seen = 1'b1;
            end
        end
    end

    initial begin
        i_clk = 1'b0;
        i_rst = 1'b1;
        i_cfg_template_we = 1'b0;
        i_cfg_cert_we = 1'b0;
        i_cfg_cluster_addr = {CLUSTER_ADDR_WIDTH{1'b0}};
        i_cfg_template_word = {TEMPLATE_PAYLOAD_WIDTH{1'b0}};
        i_cfg_cert_word = {CERT_PAYLOAD_WIDTH{1'b0}};
        i_load_window = 1'b0;
        i_cfg_state_we = 1'b0;
        i_cfg_state_cluster_slot = {CLUSTER_SLOT_WIDTH{1'b0}};
        i_cfg_state_bank_sel = 1'b0;
        i_cfg_state_row_idx = {ROW_IDX_WIDTH{1'b0}};
        i_cfg_state_p = {DATA_WIDTH{1'b0}};
        i_cfg_state_n = {DATA_WIDTH{1'b0}};
        i_start_iter = 1'b0;
        i_commit_iter = 1'b0;
        i_base_cluster_idx = {CLUSTER_ADDR_WIDTH{1'b0}};
        i_use_replay_clusters = {NUM_CLUSTERS{1'b1}};
        i_replay_digit_idx = {DIGIT_IDX_WIDTH{1'b0}};
        i_issue_rows_clusters = {NUM_CLUSTERS * NUM_ROWS{1'b0}};
        i_tail_bound_clusters = {NUM_CLUSTERS * BOUND_WIDTH{1'b0}};
        i_counter_clear = 1'b0;
        ref_start = 1'b0;
        ref_valid_digit = 1'b0;
        ref_digit_idx = {DIGIT_IDX_WIDTH{1'b0}};
        ref_ext_x1_p_rows = {NUM_ROWS{1'b0}};
        ref_ext_x1_n_rows = {NUM_ROWS{1'b0}};
        initial_state_p = 8'b01010010;
        initial_state_n = 8'b00000100;

        repeat (2) @(negedge i_clk);
        i_rst = 1'b0;

        pack_template();
        block_weights = 8'd1;
        i_cfg_cert_word = {24'hffffff, block_weights};
        @(negedge i_clk);
        i_cfg_template_we = 1'b1;
        i_cfg_cert_we = 1'b1;
        @(negedge i_clk);
        i_cfg_template_we = 1'b0;
        i_cfg_cert_we = 1'b0;

        @(negedge i_clk);
        i_load_window = 1'b1;
        @(negedge i_clk);
        i_load_window = 1'b0;
        wait_count = 0;
        while (!o_window_valid && wait_count < 16) begin
            @(posedge i_clk);
            wait_count = wait_count + 1;
        end

        @(negedge i_clk);
        i_cfg_state_we = 1'b1;
        i_cfg_state_p = initial_state_p;
        i_cfg_state_n = initial_state_n;
        @(negedge i_clk);
        i_cfg_state_we = 1'b0;
        i_cfg_state_p = {DATA_WIDTH{1'b0}};
        i_cfg_state_n = {DATA_WIDTH{1'b0}};

        @(negedge i_clk);
        i_start_iter = 1'b1;
        ref_start = 1'b1;
        for (di = 0; di < DATA_WIDTH; di = di + 1) begin
            i_replay_digit_idx = di[DIGIT_IDX_WIDTH - 1 : 0];
            i_issue_rows_clusters = {NUM_CLUSTERS * NUM_ROWS{1'b1}};
            ref_digit_idx = di[DIGIT_IDX_WIDTH - 1 : 0];
            ref_valid_digit = 1'b1;
            ref_ext_x1_p_rows = initial_state_p[DATA_WIDTH - 1 - di];
            ref_ext_x1_n_rows = initial_state_n[DATA_WIDTH - 1 - di];
            @(negedge i_clk);
            i_start_iter = 1'b0;
            ref_start = 1'b0;
        end
        i_issue_rows_clusters = {NUM_CLUSTERS * NUM_ROWS{1'b0}};
        ref_valid_digit = 1'b0;
        ref_ext_x1_p_rows = {NUM_ROWS{1'b0}};
        ref_ext_x1_n_rows = {NUM_ROWS{1'b0}};

        wait_count = 0;
        while ((!runtime_done_seen || !ref_cluster_valid_seen) && wait_count < 256) begin
            @(negedge i_clk);
            wait_count = wait_count + 1;
        end

        if (!runtime_done_seen || !runtime_converged_seen || !o_cluster_certified[0] ||
            !ref_cluster_valid_seen) begin
            $display("ERROR runtime wavefront done=%0d conv=%0d cert=%b max=%0d ref_valid=%0d",
                runtime_done_seen,
                runtime_converged_seen,
                o_cluster_certified,
                o_cluster_max_error[ACC_WIDTH - 1 : 0],
                ref_cluster_valid_seen);
            $fatal;
        end

        @(negedge i_clk);
        i_commit_iter = 1'b1;
        @(negedge i_clk);
        i_commit_iter = 1'b0;
        #1;

        if (o_x_old_p_rows_clusters[DATA_WIDTH - 1 : 0] !== ref_final_p_word ||
            o_x_old_n_rows_clusters[DATA_WIDTH - 1 : 0] !== ref_final_n_word) begin
            $display("ERROR runtime wavefront state=%h/%h ref=%h/%h",
                o_x_old_p_rows_clusters[DATA_WIDTH - 1 : 0],
                o_x_old_n_rows_clusters[DATA_WIDTH - 1 : 0],
                ref_final_p_word,
                ref_final_n_word);
            $fatal;
        end

        $display("PASS tb_iter_dense_runtime_wavefront_superstep_smoke max_error=%0d state=%h/%h",
            o_cluster_max_error[ACC_WIDTH - 1 : 0],
            o_x_old_p_rows_clusters[DATA_WIDTH - 1 : 0],
            o_x_old_n_rows_clusters[DATA_WIDTH - 1 : 0]);
        $finish;
    end
endmodule
