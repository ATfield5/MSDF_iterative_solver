`timescale 1ns / 1ps

module tb_iter_dense_small_runtime_binary_io_top;
    localparam integer NUM_TOTAL_CLUSTERS = 2;
    localparam integer NUM_CLUSTERS = 2;
    localparam integer NUM_ROWS = 4;
    localparam integer DEGREE = 4;
    localparam integer BIT_WIDTH = 8;
    localparam integer BOUND_WIDTH = BIT_WIDTH + 5;
    localparam integer COEFF_WIDTH = 8;
    localparam integer ACC_WIDTH = 24;
    localparam integer BLOCK_SIZE = 2;
    localparam integer NUM_BLOCKS = (NUM_ROWS + BLOCK_SIZE - 1) / BLOCK_SIZE;
    localparam integer DATA_WIDTH = BIT_WIDTH + 3;
    localparam integer STATE_BIN_WIDTH = DATA_WIDTH + 1;
    localparam integer COEFF_BIN_WIDTH = BIT_WIDTH + 1;
    localparam integer BIAS_WIDTH = BIT_WIDTH + 2;
    localparam integer BIAS_BIN_WIDTH = BIAS_WIDTH + 1;
    localparam integer ROW_IDX_WIDTH = 2;
    localparam integer CLUSTER_ADDR_WIDTH = 1;
    localparam integer CLUSTER_SLOT_WIDTH = 1;
    localparam integer VALID_WIDTH = NUM_ROWS * DEGREE;
    localparam integer SRC_WIDTH = NUM_ROWS * DEGREE * ROW_IDX_WIDTH;
    localparam integer COEFF_BIN_TERMS_WIDTH = NUM_ROWS * DEGREE * COEFF_BIN_WIDTH;
    localparam integer BIAS_BIN_VEC_WIDTH = NUM_ROWS * BIAS_BIN_WIDTH;
    localparam integer BLOCK_WEIGHTS_WIDTH = NUM_ROWS * NUM_BLOCKS * COEFF_WIDTH;
    localparam integer CERT_PAYLOAD_WIDTH = BLOCK_WEIGHTS_WIDTH + ACC_WIDTH;

    reg i_clk;
    reg i_rst;
    reg i_cfg_template_we;
    reg i_cfg_cert_we;
    reg [CLUSTER_ADDR_WIDTH - 1 : 0] i_cfg_cluster_addr;
    reg [VALID_WIDTH - 1 : 0] i_cfg_valid_mask;
    reg [SRC_WIDTH - 1 : 0] i_cfg_src_row_idx;
    reg [COEFF_BIN_TERMS_WIDTH - 1 : 0] i_cfg_coeff_terms_bin;
    reg [BIAS_BIN_VEC_WIDTH - 1 : 0] i_cfg_bias_rows_bin;
    reg [CERT_PAYLOAD_WIDTH - 1 : 0] i_cfg_cert_word;
    reg i_load_window;
    reg i_cfg_state_we;
    reg [CLUSTER_SLOT_WIDTH - 1 : 0] i_cfg_state_cluster_slot;
    reg i_cfg_state_bank_sel;
    reg [ROW_IDX_WIDTH - 1 : 0] i_cfg_state_row_idx;
    reg signed [STATE_BIN_WIDTH - 1 : 0] i_cfg_state_bin;
    reg i_start_iter;
    reg i_commit_iter;
    reg [CLUSTER_ADDR_WIDTH - 1 : 0] i_base_cluster_idx;
    reg [NUM_CLUSTERS - 1 : 0] i_use_replay_clusters;
    reg [$clog2(DATA_WIDTH) - 1 : 0] i_replay_digit_idx;
    reg [NUM_CLUSTERS * NUM_ROWS - 1 : 0] i_issue_rows_clusters;
    reg [NUM_CLUSTERS * BOUND_WIDTH - 1 : 0] i_tail_bound_clusters;
    reg i_counter_clear;

    wire [NUM_CLUSTERS * NUM_ROWS * STATE_BIN_WIDTH - 1 : 0] o_x_old_bin_rows_clusters;
    wire o_window_valid;
    wire o_window_busy;

    iter_dense_small_runtime_binary_io_top #(
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
        .state_bin_width(STATE_BIN_WIDTH),
        .coeff_bin_width(COEFF_BIN_WIDTH),
        .bias_width(BIAS_WIDTH),
        .bias_bin_width(BIAS_BIN_WIDTH),
        .row_idx_width(ROW_IDX_WIDTH),
        .src_idx_width(ROW_IDX_WIDTH),
        .cluster_addr_width(CLUSTER_ADDR_WIDTH),
        .cluster_slot_width(CLUSTER_SLOT_WIDTH)
    ) dut (
        .i_clk(i_clk),
        .i_rst(i_rst),
        .i_cfg_template_we(i_cfg_template_we),
        .i_cfg_cert_we(i_cfg_cert_we),
        .i_cfg_cluster_addr(i_cfg_cluster_addr),
        .i_cfg_valid_mask(i_cfg_valid_mask),
        .i_cfg_src_row_idx(i_cfg_src_row_idx),
        .i_cfg_coeff_terms_bin(i_cfg_coeff_terms_bin),
        .i_cfg_bias_rows_bin(i_cfg_bias_rows_bin),
        .i_cfg_cert_word(i_cfg_cert_word),
        .i_load_window(i_load_window),
        .i_cfg_state_we(i_cfg_state_we),
        .i_cfg_state_cluster_slot(i_cfg_state_cluster_slot),
        .i_cfg_state_bank_sel(i_cfg_state_bank_sel),
        .i_cfg_state_row_idx(i_cfg_state_row_idx),
        .i_cfg_state_bin(i_cfg_state_bin),
        .i_start_iter(i_start_iter),
        .i_commit_iter(i_commit_iter),
        .i_base_cluster_idx(i_base_cluster_idx),
        .i_use_replay_clusters(i_use_replay_clusters),
        .i_replay_digit_idx(i_replay_digit_idx),
        .i_issue_rows_clusters(i_issue_rows_clusters),
        .i_tail_bound_clusters(i_tail_bound_clusters),
        .i_counter_clear(i_counter_clear),
        .o_window_valid(o_window_valid),
        .o_window_busy(o_window_busy),
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
        .o_x_old_bin_rows_clusters(o_x_old_bin_rows_clusters),
        .o_cluster_valid(),
        .o_cluster_certified(),
        .o_cluster_max_error(),
        .o_iter_done(),
        .o_iter_converged(),
        .o_iter_continue(),
        .o_seen_mask(),
        .o_cert_mask()
    );

    always #5 i_clk = ~i_clk;

    task set_coeff_bin;
        input integer term_idx;
        input signed [COEFF_BIN_WIDTH - 1 : 0] value;
        begin
            i_cfg_coeff_terms_bin[(term_idx + 1) * COEFF_BIN_WIDTH - 1 -: COEFF_BIN_WIDTH] = value;
        end
    endtask

    task set_bias_bin;
        input integer row_idx;
        input signed [BIAS_BIN_WIDTH - 1 : 0] value;
        begin
            i_cfg_bias_rows_bin[(row_idx + 1) * BIAS_BIN_WIDTH - 1 -: BIAS_BIN_WIDTH] = value;
        end
    endtask

    task load_state_bin;
        input integer cluster_slot;
        input integer row_idx;
        input signed [STATE_BIN_WIDTH - 1 : 0] value;
        begin
            @(negedge i_clk);
            i_cfg_state_cluster_slot <= cluster_slot[CLUSTER_SLOT_WIDTH - 1 : 0];
            i_cfg_state_bank_sel <= 1'b0;
            i_cfg_state_row_idx <= row_idx[ROW_IDX_WIDTH - 1 : 0];
            i_cfg_state_bin <= value;
            i_cfg_state_we <= 1'b1;
            @(negedge i_clk);
            i_cfg_state_we <= 1'b0;
            i_cfg_state_bin <= {STATE_BIN_WIDTH{1'b0}};
        end
    endtask

    task check_state_bin;
        input integer flat_row;
        input signed [STATE_BIN_WIDTH - 1 : 0] expected;
        reg signed [STATE_BIN_WIDTH - 1 : 0] got;
        begin
            got = o_x_old_bin_rows_clusters[(flat_row + 1) * STATE_BIN_WIDTH - 1 -: STATE_BIN_WIDTH];
            if (got !== expected) begin
                $display("ERROR binary state row=%0d got=%0d expected=%0d",
                    flat_row, got, expected);
                $fatal;
            end
        end
    endtask

    initial begin
        i_clk = 1'b0;
        i_rst = 1'b1;
        i_cfg_template_we = 1'b0;
        i_cfg_cert_we = 1'b0;
        i_cfg_cluster_addr = 0;
        i_cfg_valid_mask = {VALID_WIDTH{1'b0}};
        i_cfg_src_row_idx = {SRC_WIDTH{1'b0}};
        i_cfg_coeff_terms_bin = {COEFF_BIN_TERMS_WIDTH{1'b0}};
        i_cfg_bias_rows_bin = {BIAS_BIN_VEC_WIDTH{1'b0}};
        i_cfg_cert_word = {CERT_PAYLOAD_WIDTH{1'b0}};
        i_load_window = 1'b0;
        i_cfg_state_we = 1'b0;
        i_cfg_state_cluster_slot = 0;
        i_cfg_state_bank_sel = 1'b0;
        i_cfg_state_row_idx = 0;
        i_cfg_state_bin = 0;
        i_start_iter = 1'b0;
        i_commit_iter = 1'b0;
        i_base_cluster_idx = 0;
        i_use_replay_clusters = {NUM_CLUSTERS{1'b0}};
        i_replay_digit_idx = 0;
        i_issue_rows_clusters = {NUM_CLUSTERS * NUM_ROWS{1'b0}};
        i_tail_bound_clusters = {NUM_CLUSTERS{13'd1}};
        i_counter_clear = 1'b0;

        repeat (2) @(posedge i_clk);
        i_rst <= 1'b0;

        set_coeff_bin(0, 9'sd5);
        set_coeff_bin(1, -9'sd3);
        set_bias_bin(0, 11'sd7);
        set_bias_bin(1, -11'sd2);

        @(negedge i_clk);
        i_cfg_template_we <= 1'b1;
        i_cfg_cert_we <= 1'b1;
        @(negedge i_clk);
        i_cfg_template_we <= 1'b0;
        i_cfg_cert_we <= 1'b0;

        @(negedge i_clk);
        i_load_window <= 1'b1;
        @(negedge i_clk);
        i_load_window <= 1'b0;
        repeat (12) @(posedge i_clk);
        if (!o_window_valid || o_window_busy) begin
            $display("ERROR binary wrapper window did not become valid");
            $fatal;
        end

        load_state_bin(0, 0, 12'sd37);
        load_state_bin(0, 1, -12'sd23);
        load_state_bin(1, 0, 12'sd511);
        load_state_bin(1, 1, -12'sd512);

        @(posedge i_clk);
        #1;
        check_state_bin(0, 12'sd37);
        check_state_bin(1, -12'sd23);
        check_state_bin(4, 12'sd511);
        check_state_bin(5, -12'sd512);

        $display("PASS tb_iter_dense_small_runtime_binary_io_top");
        $finish;
    end
endmodule
