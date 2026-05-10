`timescale 1ns / 1ps

// Runtime-level smoke test for ROW_DATAPATH_MODE=3.
//
// This validates that the runtime loader, template/cert banks, auto digit
// scheduler and iteration controller can drive the solver-native digit-stream
// cluster shell.  The state comparison is numerical because mode3 stores
// signed-digit rail traces, not full-word magnitude rails.

module tb_iter_dense_runtime_solver_native_mode3_smoke;
    localparam integer NUM_TOTAL_CLUSTERS = 2;
    localparam integer NUM_CLUSTERS = 1;
    localparam integer NUM_ROWS = 2;
    localparam integer DEGREE = 4;
    localparam integer BIT_WIDTH = 8;
    localparam integer DATA_WIDTH = BIT_WIDTH + 3;
    localparam integer BOUND_WIDTH = BIT_WIDTH + 5;
    localparam integer COEFF_WIDTH = 8;
    localparam integer ACC_WIDTH = 24;
    localparam integer BLOCK_SIZE = 2;
    localparam integer NUM_BLOCKS = 1;
    localparam integer ROW_IDX_WIDTH = 1;
    localparam integer SRC_IDX_WIDTH = 1;
    localparam integer CLUSTER_ADDR_WIDTH = 1;
    localparam integer CLUSTER_SLOT_WIDTH = 1;
    localparam integer BIAS_WIDTH = BIT_WIDTH + 2;
    localparam integer VALID_WIDTH = NUM_ROWS * DEGREE;
    localparam integer SRC_WIDTH = NUM_ROWS * DEGREE * SRC_IDX_WIDTH;
    localparam integer COEFF_TERMS_WIDTH = NUM_ROWS * DEGREE * BIT_WIDTH;
    localparam integer BIAS_VEC_WIDTH = NUM_ROWS * BIAS_WIDTH;
    localparam integer TEMPLATE_PAYLOAD_WIDTH =
        VALID_WIDTH + SRC_WIDTH + 2 * COEFF_TERMS_WIDTH + 2 * BIAS_VEC_WIDTH;
    localparam integer BLOCK_WEIGHTS_WIDTH = NUM_ROWS * NUM_BLOCKS * COEFF_WIDTH;
    localparam integer CERT_PAYLOAD_WIDTH = BLOCK_WEIGHTS_WIDTH + ACC_WIDTH;

`include "iter_tb_signed_digit_reconstruct.vh"

    reg i_clk;
    reg i_rst;
    reg i_cfg_template_we;
    reg i_cfg_cert_we;
    reg [CLUSTER_ADDR_WIDTH-1:0] i_cfg_cluster_addr;
    reg [TEMPLATE_PAYLOAD_WIDTH-1:0] i_cfg_template_word;
    reg [CERT_PAYLOAD_WIDTH-1:0] i_cfg_cert_word;
    reg i_load_window;
    reg i_cfg_state_we;
    reg [CLUSTER_SLOT_WIDTH-1:0] i_cfg_state_cluster_slot;
    reg i_cfg_state_bank_sel;
    reg [ROW_IDX_WIDTH-1:0] i_cfg_state_row_idx;
    reg [DATA_WIDTH-1:0] i_cfg_state_p;
    reg [DATA_WIDTH-1:0] i_cfg_state_n;
    reg i_start_iter;
    reg i_commit_iter;
    reg [CLUSTER_ADDR_WIDTH-1:0] i_base_cluster_idx;
    reg [NUM_CLUSTERS-1:0] i_use_replay_clusters;
    reg [$clog2(DATA_WIDTH)-1:0] i_replay_digit_idx;
    reg [NUM_CLUSTERS*NUM_ROWS-1:0] i_issue_rows_clusters;
    reg [NUM_CLUSTERS*BOUND_WIDTH-1:0] i_tail_bound_clusters;
    reg i_counter_clear;

    wire o_window_valid;
    wire o_window_busy;
    wire [31:0] o_issue_cycles;
    wire [31:0] o_iter_count;
    wire [31:0] o_active_digit_cycles;
    wire [NUM_CLUSTERS*NUM_ROWS-1:0] o_sched_row_active_clusters;
    wire [NUM_CLUSTERS-1:0] o_cluster_certified;
    wire [NUM_CLUSTERS*ACC_WIDTH-1:0] o_cluster_max_error;
    wire [NUM_CLUSTERS*NUM_ROWS*DATA_WIDTH-1:0] o_x_old_p_rows_clusters;
    wire [NUM_CLUSTERS*NUM_ROWS*DATA_WIDTH-1:0] o_x_old_n_rows_clusters;
    wire o_iter_done;
    wire o_iter_converged;
    wire o_iter_continue;
    wire [NUM_CLUSTERS-1:0] o_seen_mask;

    reg [VALID_WIDTH-1:0] valid_mask;
    reg [SRC_WIDTH-1:0] src_idx;
    reg [COEFF_TERMS_WIDTH-1:0] coeff_p_terms;
    reg [COEFF_TERMS_WIDTH-1:0] coeff_n_terms;
    reg [BIAS_VEC_WIDTH-1:0] bias_p_rows;
    reg [BIAS_VEC_WIDTH-1:0] bias_n_rows;
    reg [BLOCK_WEIGHTS_WIDTH-1:0] block_weights;
    integer wait_count;
    reg signed [31:0] state0_value;
    reg signed [31:0] state1_value;

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
        .row_datapath_mode(3),
        .auto_full_digit(1),
        .auto_prefix_gating(0),
        .row_idx_width(ROW_IDX_WIDTH),
        .src_idx_width(SRC_IDX_WIDTH),
        .cluster_addr_width(CLUSTER_ADDR_WIDTH),
        .cluster_slot_width(CLUSTER_SLOT_WIDTH),
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
        .i_x0_p_rows_clusters({NUM_CLUSTERS*NUM_ROWS{1'b0}}),
        .i_x0_n_rows_clusters({NUM_CLUSTERS*NUM_ROWS{1'b0}}),
        .i_x1_p_rows_clusters({NUM_CLUSTERS*NUM_ROWS{1'b0}}),
        .i_x1_n_rows_clusters({NUM_CLUSTERS*NUM_ROWS{1'b0}}),
        .i_x2_p_rows_clusters({NUM_CLUSTERS*NUM_ROWS{1'b0}}),
        .i_x2_n_rows_clusters({NUM_CLUSTERS*NUM_ROWS{1'b0}}),
        .i_x3_p_rows_clusters({NUM_CLUSTERS*NUM_ROWS{1'b0}}),
        .i_x3_n_rows_clusters({NUM_CLUSTERS*NUM_ROWS{1'b0}}),
        .i_tail_bound_clusters(i_tail_bound_clusters),
        .i_counter_clear(i_counter_clear),
        .o_window_valid(o_window_valid),
        .o_window_busy(o_window_busy),
        .o_total_cycles(),
        .o_issue_cycles(o_issue_cycles),
        .o_cert_wait_cycles(),
        .o_iter_count(o_iter_count),
        .o_converged_iter(),
        .o_cfg_template_write_count(),
        .o_cfg_cert_write_count(),
        .o_cfg_state_write_count(),
        .o_window_load_count(),
        .o_window_busy_cycles(),
        .o_window_ready_cycles(),
        .o_active_digit_cycles(o_active_digit_cycles),
        .o_gated_digit_cycles(),
        .o_cert_prefix_digit_sum(),
        .o_certified_block_count(),
        .o_template_words_clusters(),
        .o_cert_param_words_clusters(),
        .o_sched_row_active_clusters(o_sched_row_active_clusters),
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
        .o_iter_continue(o_iter_continue),
        .o_seen_mask(o_seen_mask),
        .o_cert_mask()
    );

    always #5 i_clk = ~i_clk;

    task automatic pack_template;
        begin
            valid_mask = {VALID_WIDTH{1'b0}};
            src_idx = {SRC_WIDTH{1'b0}};
            coeff_p_terms = {COEFF_TERMS_WIDTH{1'b0}};
            coeff_n_terms = {COEFF_TERMS_WIDTH{1'b0}};
            bias_p_rows = {BIAS_VEC_WIDTH{1'b0}};
            bias_n_rows = {BIAS_VEC_WIDTH{1'b0}};

            // row0 = row0 + 2
            valid_mask[0*DEGREE + 0] = 1'b1;
            src_idx[0*DEGREE + 0] = 1'b0;
            coeff_p_terms[(0*DEGREE + 0)*BIT_WIDTH +: BIT_WIDTH] = 8'd1;
            bias_p_rows[0*BIAS_WIDTH +: BIAS_WIDTH] = 10'd2;

            // row1 = -row1 - 1
            valid_mask[1*DEGREE + 0] = 1'b1;
            src_idx[1*DEGREE + 0] = 1'b1;
            coeff_n_terms[(1*DEGREE + 0)*BIT_WIDTH +: BIT_WIDTH] = 8'd1;
            bias_n_rows[1*BIAS_WIDTH +: BIAS_WIDTH] = 10'd1;

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

    task automatic pack_cert;
        begin
            block_weights = {BLOCK_WEIGHTS_WIDTH{1'b0}};
            block_weights[0*COEFF_WIDTH +: COEFF_WIDTH] = 8'd1;
            block_weights[1*COEFF_WIDTH +: COEFF_WIDTH] = 8'd1;
            i_cfg_cert_word = {24'd10, block_weights};
        end
    endtask

    task automatic cfg_load_state;
        input row_idx;
        input [DATA_WIDTH-1:0] state_p;
        input [DATA_WIDTH-1:0] state_n;
        begin
            @(negedge i_clk);
            i_cfg_state_we = 1'b1;
            i_cfg_state_cluster_slot = 1'b0;
            i_cfg_state_bank_sel = 1'b0;
            i_cfg_state_row_idx = row_idx;
            i_cfg_state_p = state_p;
            i_cfg_state_n = state_n;
            @(negedge i_clk);
            i_cfg_state_we = 1'b0;
            i_cfg_state_p = {DATA_WIDTH{1'b0}};
            i_cfg_state_n = {DATA_WIDTH{1'b0}};
        end
    endtask

    task automatic reconstruct_state;
        begin
            state0_value = iter_tb_signed_digit_value(
                o_x_old_p_rows_clusters[0*DATA_WIDTH +: DATA_WIDTH],
                o_x_old_n_rows_clusters[0*DATA_WIDTH +: DATA_WIDTH]);
            state1_value = iter_tb_signed_digit_value(
                o_x_old_p_rows_clusters[1*DATA_WIDTH +: DATA_WIDTH],
                o_x_old_n_rows_clusters[1*DATA_WIDTH +: DATA_WIDTH]);
        end
    endtask

    initial begin
        i_clk = 1'b0;
        i_rst = 1'b1;
        i_cfg_template_we = 1'b0;
        i_cfg_cert_we = 1'b0;
        i_cfg_cluster_addr = 1'b0;
        i_cfg_template_word = {TEMPLATE_PAYLOAD_WIDTH{1'b0}};
        i_cfg_cert_word = {CERT_PAYLOAD_WIDTH{1'b0}};
        i_load_window = 1'b0;
        i_cfg_state_we = 1'b0;
        i_cfg_state_cluster_slot = 1'b0;
        i_cfg_state_bank_sel = 1'b0;
        i_cfg_state_row_idx = 1'b0;
        i_cfg_state_p = {DATA_WIDTH{1'b0}};
        i_cfg_state_n = {DATA_WIDTH{1'b0}};
        i_start_iter = 1'b0;
        i_commit_iter = 1'b0;
        i_base_cluster_idx = 1'b0;
        i_use_replay_clusters = {NUM_CLUSTERS{1'b1}};
        i_replay_digit_idx = {($clog2(DATA_WIDTH)){1'b0}};
        i_issue_rows_clusters = {NUM_CLUSTERS*NUM_ROWS{1'b0}};
        i_tail_bound_clusters = {NUM_CLUSTERS*BOUND_WIDTH{1'b0}};
        i_counter_clear = 1'b0;

        repeat (2) @(negedge i_clk);
        i_rst = 1'b0;

        pack_template();
        pack_cert();
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
        if (!o_window_valid || o_window_busy) begin
            $display("ERROR mode3 window load failed");
            $fatal;
        end

        cfg_load_state(1'b0, 11'd5, 11'd0);
        cfg_load_state(1'b1, 11'd2, 11'd0);

        @(negedge i_clk);
        i_start_iter = 1'b1;
        @(negedge i_clk);
        i_start_iter = 1'b0;

        wait_count = 0;
        while (!o_iter_done && wait_count < 80) begin
            @(posedge i_clk);
            #1;
            wait_count = wait_count + 1;
        end

        if (!o_iter_done || o_seen_mask !== {NUM_CLUSTERS{1'b1}} ||
            !o_iter_converged || o_iter_continue ||
            !o_cluster_certified[0] || o_cluster_max_error[0 +: ACC_WIDTH] !== 24'd5) begin
            $display("ERROR mode3 iter done=%0d seen=%b conv=%0d cont=%0d cert=%b maxerr=%0d issue=%0d active=%0d sched=%b window=%0d busy=%0d",
                o_iter_done, o_seen_mask, o_iter_converged, o_iter_continue,
                o_cluster_certified, o_cluster_max_error[0 +: ACC_WIDTH],
                o_issue_cycles, o_active_digit_cycles, o_sched_row_active_clusters,
                o_window_valid, o_window_busy);
            $fatal;
        end

        @(negedge i_clk);
        i_commit_iter = 1'b1;
        @(negedge i_clk);
        i_commit_iter = 1'b0;
        #1;
        reconstruct_state();
        if (state0_value !== 32'sd7 || state1_value !== -32'sd3) begin
            $display("ERROR mode3 iter0 state0=%0d state1=%0d p=%h n=%h",
                state0_value,
                state1_value,
                o_x_old_p_rows_clusters,
                o_x_old_n_rows_clusters);
            $fatal;
        end

        @(negedge i_clk);
        i_start_iter = 1'b1;
        @(negedge i_clk);
        i_start_iter = 1'b0;

        wait_count = 0;
        while (!o_iter_done && wait_count < 80) begin
            @(posedge i_clk);
            #1;
            wait_count = wait_count + 1;
        end

        if (!o_iter_done || o_seen_mask !== {NUM_CLUSTERS{1'b1}} ||
            !o_iter_converged || o_iter_continue ||
            !o_cluster_certified[0] || o_cluster_max_error[0 +: ACC_WIDTH] !== 24'd5) begin
            $display("ERROR mode3 iter1 done=%0d seen=%b conv=%0d cont=%0d cert=%b maxerr=%0d issue=%0d active=%0d",
                o_iter_done, o_seen_mask, o_iter_converged, o_iter_continue,
                o_cluster_certified, o_cluster_max_error[0 +: ACC_WIDTH],
                o_issue_cycles, o_active_digit_cycles);
            $fatal;
        end

        @(negedge i_clk);
        i_commit_iter = 1'b1;
        @(negedge i_clk);
        i_commit_iter = 1'b0;
        #1;
        reconstruct_state();
        if (state0_value !== 32'sd9 || state1_value !== 32'sd2) begin
            $display("ERROR mode3 iter1 state0=%0d state1=%0d p=%h n=%h",
                state0_value,
                state1_value,
                o_x_old_p_rows_clusters,
                o_x_old_n_rows_clusters);
            $fatal;
        end

        if (o_issue_cycles !== 32'd22 || o_active_digit_cycles !== 32'd22 ||
            o_iter_count !== 32'd2) begin
            $display("ERROR mode3 counters issue=%0d active=%0d iter=%0d",
                o_issue_cycles, o_active_digit_cycles, o_iter_count);
            $fatal;
        end

        $display("PASS tb_iter_dense_runtime_solver_native_mode3_smoke final_state=(%0d,%0d) max_error=%0d",
            state0_value, state1_value, o_cluster_max_error[0 +: ACC_WIDTH]);
        $finish;
    end
endmodule
