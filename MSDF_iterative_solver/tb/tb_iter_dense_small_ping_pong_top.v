`timescale 1ns / 1ps

module tb_iter_dense_small_ping_pong_top;
    localparam integer NUM_CLUSTERS = 2;
    localparam integer NUM_ROWS = 4;
    localparam integer DEGREE = 4;
    localparam integer BIT_WIDTH = 8;
    localparam integer BOUND_WIDTH = BIT_WIDTH + 5;
    localparam integer BLOCK_SIZE = 2;
    localparam integer NUM_BLOCKS = (NUM_ROWS + BLOCK_SIZE - 1) / BLOCK_SIZE;
    localparam integer COEFF_WIDTH = 8;
    localparam integer ACC_WIDTH = 24;
    localparam integer DATA_WIDTH = BIT_WIDTH + 3;
    localparam integer ROW_IDX_WIDTH = 2;

    reg i_clk;
    reg i_rst;
    reg i_start_iter;
    reg i_commit_iter;
    reg [NUM_CLUSTERS - 1 : 0] i_use_replay_clusters;
    reg [$clog2(DATA_WIDTH) - 1 : 0] i_replay_digit_idx;
    reg [NUM_CLUSTERS * NUM_ROWS * DEGREE * ROW_IDX_WIDTH - 1 : 0] i_src_row_idx_clusters;
    reg [NUM_CLUSTERS * NUM_ROWS - 1 : 0] i_ena_rows_clusters;
    reg [NUM_CLUSTERS * NUM_ROWS - 1 : 0] i_x0_p_rows_clusters, i_x0_n_rows_clusters;
    reg [NUM_CLUSTERS * NUM_ROWS - 1 : 0] i_x1_p_rows_clusters, i_x1_n_rows_clusters;
    reg [NUM_CLUSTERS * NUM_ROWS - 1 : 0] i_x2_p_rows_clusters, i_x2_n_rows_clusters;
    reg [NUM_CLUSTERS * NUM_ROWS - 1 : 0] i_x3_p_rows_clusters, i_x3_n_rows_clusters;
    reg [NUM_CLUSTERS * NUM_ROWS * BIT_WIDTH - 1 : 0] i_coeff0_vec_p_rows_clusters, i_coeff0_vec_n_rows_clusters;
    reg [NUM_CLUSTERS * NUM_ROWS * BIT_WIDTH - 1 : 0] i_coeff1_vec_p_rows_clusters, i_coeff1_vec_n_rows_clusters;
    reg [NUM_CLUSTERS * NUM_ROWS * BIT_WIDTH - 1 : 0] i_coeff2_vec_p_rows_clusters, i_coeff2_vec_n_rows_clusters;
    reg [NUM_CLUSTERS * NUM_ROWS * BIT_WIDTH - 1 : 0] i_coeff3_vec_p_rows_clusters, i_coeff3_vec_n_rows_clusters;
    reg [NUM_CLUSTERS * NUM_ROWS * (BIT_WIDTH + 2) - 1 : 0] i_bias_vec_p_rows_clusters, i_bias_vec_n_rows_clusters;
    reg [NUM_CLUSTERS * BOUND_WIDTH - 1 : 0] i_tail_bound_clusters;
    reg [NUM_CLUSTERS * NUM_ROWS * NUM_BLOCKS * COEFF_WIDTH - 1 : 0] i_block_weights_clusters;
    reg [NUM_CLUSTERS * ACC_WIDTH - 1 : 0] i_eta_clusters;

    wire [NUM_CLUSTERS - 1 : 0] o_read_bank_sel_clusters;
    wire [NUM_CLUSTERS * NUM_ROWS - 1 : 0] o_drv_x0_p_rows_clusters, o_drv_x0_n_rows_clusters;
    wire [NUM_CLUSTERS * NUM_ROWS - 1 : 0] o_drv_x1_p_rows_clusters, o_drv_x1_n_rows_clusters;
    wire [NUM_CLUSTERS * NUM_ROWS - 1 : 0] o_drv_x2_p_rows_clusters, o_drv_x2_n_rows_clusters;
    wire [NUM_CLUSTERS * NUM_ROWS - 1 : 0] o_drv_x3_p_rows_clusters, o_drv_x3_n_rows_clusters;
    wire [NUM_CLUSTERS - 1 : 0] o_cluster_valid, o_cluster_certified;
    wire [NUM_CLUSTERS * ACC_WIDTH - 1 : 0] o_cluster_max_error;
    wire [NUM_CLUSTERS * NUM_ROWS * DATA_WIDTH - 1 : 0] o_x_old_p_rows_clusters, o_x_old_n_rows_clusters;
    wire o_iter_done, o_iter_converged, o_iter_continue;
    wire [NUM_CLUSTERS - 1 : 0] o_seen_mask, o_cert_mask;

    iter_dense_small_ping_pong_top #(
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
        .row_idx_width(ROW_IDX_WIDTH)
    ) dut (
        .i_clk(i_clk),
        .i_rst(i_rst),
        .i_start_iter(i_start_iter),
        .i_commit_iter(i_commit_iter),
        .i_use_replay_clusters(i_use_replay_clusters),
        .i_replay_digit_idx(i_replay_digit_idx),
        .i_src_row_idx_clusters(i_src_row_idx_clusters),
        .i_ena_rows_clusters(i_ena_rows_clusters),
        .i_x0_p_rows_clusters(i_x0_p_rows_clusters),
        .i_x0_n_rows_clusters(i_x0_n_rows_clusters),
        .i_x1_p_rows_clusters(i_x1_p_rows_clusters),
        .i_x1_n_rows_clusters(i_x1_n_rows_clusters),
        .i_x2_p_rows_clusters(i_x2_p_rows_clusters),
        .i_x2_n_rows_clusters(i_x2_n_rows_clusters),
        .i_x3_p_rows_clusters(i_x3_p_rows_clusters),
        .i_x3_n_rows_clusters(i_x3_n_rows_clusters),
        .i_coeff0_vec_p_rows_clusters(i_coeff0_vec_p_rows_clusters),
        .i_coeff0_vec_n_rows_clusters(i_coeff0_vec_n_rows_clusters),
        .i_coeff1_vec_p_rows_clusters(i_coeff1_vec_p_rows_clusters),
        .i_coeff1_vec_n_rows_clusters(i_coeff1_vec_n_rows_clusters),
        .i_coeff2_vec_p_rows_clusters(i_coeff2_vec_p_rows_clusters),
        .i_coeff2_vec_n_rows_clusters(i_coeff2_vec_n_rows_clusters),
        .i_coeff3_vec_p_rows_clusters(i_coeff3_vec_p_rows_clusters),
        .i_coeff3_vec_n_rows_clusters(i_coeff3_vec_n_rows_clusters),
        .i_bias_vec_p_rows_clusters(i_bias_vec_p_rows_clusters),
        .i_bias_vec_n_rows_clusters(i_bias_vec_n_rows_clusters),
        .i_tail_bound_clusters(i_tail_bound_clusters),
        .i_block_weights_clusters(i_block_weights_clusters),
        .i_eta_clusters(i_eta_clusters),
        .o_read_bank_sel_clusters(o_read_bank_sel_clusters),
        .o_drv_x0_p_rows_clusters(o_drv_x0_p_rows_clusters),
        .o_drv_x0_n_rows_clusters(o_drv_x0_n_rows_clusters),
        .o_drv_x1_p_rows_clusters(o_drv_x1_p_rows_clusters),
        .o_drv_x1_n_rows_clusters(o_drv_x1_n_rows_clusters),
        .o_drv_x2_p_rows_clusters(o_drv_x2_p_rows_clusters),
        .o_drv_x2_n_rows_clusters(o_drv_x2_n_rows_clusters),
        .o_drv_x3_p_rows_clusters(o_drv_x3_p_rows_clusters),
        .o_drv_x3_n_rows_clusters(o_drv_x3_n_rows_clusters),
        .o_cluster_valid(o_cluster_valid),
        .o_cluster_certified(o_cluster_certified),
        .o_cluster_max_error(o_cluster_max_error),
        .o_x_old_p_rows_clusters(o_x_old_p_rows_clusters),
        .o_x_old_n_rows_clusters(o_x_old_n_rows_clusters),
        .o_iter_done(o_iter_done),
        .o_iter_converged(o_iter_converged),
        .o_iter_continue(o_iter_continue),
        .o_seen_mask(o_seen_mask),
        .o_cert_mask(o_cert_mask)
    );

    always #5 i_clk = ~i_clk;

    task pulse_start_iter;
        begin
            @(negedge i_clk);
            i_start_iter <= 1'b1;
            @(negedge i_clk);
            i_start_iter <= 1'b0;
        end
    endtask

    task pulse_commit_iter;
        begin
            @(negedge i_clk);
            i_commit_iter <= 1'b1;
            @(negedge i_clk);
            i_commit_iter <= 1'b0;
        end
    endtask

    task launch_both_clusters_same_pattern;
        begin
            @(posedge i_clk);
            i_ena_rows_clusters <= 8'b1111_1111;
            i_x0_p_rows_clusters <= 8'b1111_1111;
            i_x1_p_rows_clusters <= 8'b1111_1111;
            i_x2_p_rows_clusters <= 8'b0000_0000;
            i_x3_p_rows_clusters <= 8'b1001_1001;
            @(posedge i_clk);
            i_ena_rows_clusters <= 8'b0000_0000;
            i_x0_p_rows_clusters <= 8'b0000_0000;
            i_x1_p_rows_clusters <= 8'b0000_0000;
            i_x2_p_rows_clusters <= 8'b0000_0000;
            i_x3_p_rows_clusters <= 8'b0000_0000;
        end
    endtask

    integer cycles_waited;
    initial begin
        i_clk = 1'b0;
        i_rst = 1'b1;
        i_start_iter = 1'b0;
        i_commit_iter = 1'b0;
        i_use_replay_clusters = 2'b00;
        i_replay_digit_idx = 0;
        i_src_row_idx_clusters = {
            2'd1, 2'd0, 2'd3, 2'd2,
            2'd1, 2'd1, 2'd1, 2'd1,
            2'd0, 2'd1, 2'd2, 2'd3,
            2'd3, 2'd2, 2'd1, 2'd0,
            2'd1, 2'd0, 2'd3, 2'd2,
            2'd1, 2'd1, 2'd1, 2'd1,
            2'd0, 2'd1, 2'd2, 2'd3,
            2'd3, 2'd2, 2'd1, 2'd0
        };
        i_ena_rows_clusters = 0;
        i_x0_p_rows_clusters = 0; i_x0_n_rows_clusters = 0;
        i_x1_p_rows_clusters = 0; i_x1_n_rows_clusters = 0;
        i_x2_p_rows_clusters = 0; i_x2_n_rows_clusters = 0;
        i_x3_p_rows_clusters = 0; i_x3_n_rows_clusters = 0;
        i_coeff0_vec_p_rows_clusters = {
            8'd2, 8'd2, 8'd2, 8'd5,
            8'd2, 8'd2, 8'd2, 8'd5
        };
        i_coeff0_vec_n_rows_clusters = 0;
        i_coeff1_vec_p_rows_clusters = {
            8'd4, 8'd2, 8'd2, 8'd3,
            8'd4, 8'd2, 8'd2, 8'd3
        };
        i_coeff1_vec_n_rows_clusters = 0;
        i_coeff2_vec_p_rows_clusters = 0;
        i_coeff2_vec_n_rows_clusters = 0;
        i_coeff3_vec_p_rows_clusters = {
            8'd2, 8'd0, 8'd0, 8'd2,
            8'd2, 8'd0, 8'd0, 8'd2
        };
        i_coeff3_vec_n_rows_clusters = 0;
        i_bias_vec_p_rows_clusters = {
            10'd1, 10'd1, 10'd1, 10'd1,
            10'd1, 10'd1, 10'd1, 10'd1
        };
        i_bias_vec_n_rows_clusters = 0;
        i_tail_bound_clusters = {13'd1, 13'd1};
        i_block_weights_clusters = {
            8'd0, 8'd3, 8'd1, 8'd1, 8'd1, 8'd2, 8'd2, 8'd1,
            8'd0, 8'd3, 8'd1, 8'd1, 8'd1, 8'd2, 8'd2, 8'd1
        };
        i_eta_clusters = {24'd3, 24'd3};

        repeat (2) @(posedge i_clk);
        i_rst <= 1'b0;

        // Iteration 1 writes into bank1 while bank0 is the read bank.
        pulse_start_iter();
        launch_both_clusters_same_pattern();
        cycles_waited = 0;
        while (!o_iter_done && cycles_waited < 16) begin
            @(posedge i_clk);
            cycles_waited = cycles_waited + 1;
        end
        if (!o_iter_done || o_read_bank_sel_clusters !== 2'b00) begin
            $display("ERROR pingpong iter1 completion or bank sel mismatch");
            $fatal;
        end

        // Commit: newly written bank becomes the active read bank.
        pulse_commit_iter();
        #1;
        if (o_read_bank_sel_clusters !== 2'b11) begin
            $display("ERROR pingpong bank did not flip after commit1");
            $fatal;
        end

        // Replay-integrated second iteration.
        i_use_replay_clusters = 2'b11;
        i_replay_digit_idx = 3;
        pulse_start_iter();
        @(posedge i_clk);
        i_ena_rows_clusters <= 8'b1111_1111;
        @(posedge i_clk);
        i_ena_rows_clusters <= 8'b0000_0000;
        cycles_waited = 0;
        while (!o_iter_done && cycles_waited < 16) begin
            @(posedge i_clk);
            cycles_waited = cycles_waited + 1;
        end
        if (!o_iter_done || o_seen_mask !== 2'b11) begin
            $display("ERROR pingpong replay iteration did not finish");
            $fatal;
        end

        // Commit again: write bank flips back to bank0 as next read source.
        pulse_commit_iter();
        #1;
        if (o_read_bank_sel_clusters !== 2'b00) begin
            $display("ERROR pingpong bank did not flip after commit2");
            $fatal;
        end

        $display("PASS tb_iter_dense_small_ping_pong_top");
        $finish;
    end
endmodule
