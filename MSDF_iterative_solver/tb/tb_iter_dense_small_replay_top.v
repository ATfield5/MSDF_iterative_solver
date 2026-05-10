`timescale 1ns / 1ps

module tb_iter_dense_small_replay_top;
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

    wire [NUM_CLUSTERS * NUM_ROWS - 1 : 0] o_drv_x0_p_rows_clusters, o_drv_x0_n_rows_clusters;
    wire [NUM_CLUSTERS * NUM_ROWS - 1 : 0] o_drv_x1_p_rows_clusters, o_drv_x1_n_rows_clusters;
    wire [NUM_CLUSTERS * NUM_ROWS - 1 : 0] o_drv_x2_p_rows_clusters, o_drv_x2_n_rows_clusters;
    wire [NUM_CLUSTERS * NUM_ROWS - 1 : 0] o_drv_x3_p_rows_clusters, o_drv_x3_n_rows_clusters;
    wire [NUM_CLUSTERS - 1 : 0] o_cluster_valid, o_cluster_certified;
    wire [NUM_CLUSTERS * ACC_WIDTH - 1 : 0] o_cluster_max_error;
    wire [NUM_CLUSTERS * NUM_ROWS * DATA_WIDTH - 1 : 0] o_x_old_p_rows_clusters, o_x_old_n_rows_clusters;
    wire o_iter_done, o_iter_converged, o_iter_continue;
    wire [NUM_CLUSTERS - 1 : 0] o_seen_mask, o_cert_mask;

    iter_dense_small_replay_top #(
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

    function automatic [0:0] get_state_bit;
        input [NUM_CLUSTERS * NUM_ROWS * DATA_WIDTH - 1 : 0] flat_vec;
        input integer cluster_idx;
        input integer row_idx;
        input integer bit_idx;
        integer base;
        begin
            base = cluster_idx * NUM_ROWS * DATA_WIDTH + row_idx * DATA_WIDTH + bit_idx;
            get_state_bit = flat_vec[base];
        end
    endfunction

    integer cycles_waited;
    integer cluster_idx;
    integer dst_row;
    integer term_idx;
    integer src_row;
    integer bit_sel;
    reg expected_bit;
    initial begin
        i_clk = 1'b0;
        i_rst = 1'b1;
        i_start_iter = 1'b0;
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

        // Bootstrap one iteration using external digits to populate handoff state.
        pulse_start_iter();
        launch_both_clusters_same_pattern();
        cycles_waited = 0;
        while (!o_iter_done && cycles_waited < 16) begin
            @(posedge i_clk);
            cycles_waited = cycles_waited + 1;
        end
        if (!o_iter_done) begin
            $display("ERROR bootstrap iteration did not finish");
            $fatal;
        end

        // Switch to replay mode and verify that driven x bits exactly match the
        // stored state plus source-row mapping for a chosen digit slice.
        i_use_replay_clusters = 2'b11;
        i_replay_digit_idx = 3;
        #1;
        bit_sel = DATA_WIDTH - 1 - i_replay_digit_idx;
        for (cluster_idx = 0; cluster_idx < NUM_CLUSTERS; cluster_idx = cluster_idx + 1) begin
            for (dst_row = 0; dst_row < NUM_ROWS; dst_row = dst_row + 1) begin
                for (term_idx = 0; term_idx < DEGREE; term_idx = term_idx + 1) begin
                    src_row = i_src_row_idx_clusters[((cluster_idx * NUM_ROWS * DEGREE) + (dst_row * DEGREE + term_idx) + 1) * ROW_IDX_WIDTH - 1 -: ROW_IDX_WIDTH];
                    expected_bit = get_state_bit(o_x_old_p_rows_clusters, cluster_idx, src_row, bit_sel);
                    case (term_idx)
                        0: if (o_drv_x0_p_rows_clusters[cluster_idx * NUM_ROWS + dst_row] !== expected_bit) begin
                            $display("ERROR replay x0_p mismatch c=%0d row=%0d term=%0d", cluster_idx, dst_row, term_idx);
                            $fatal;
                        end
                        1: if (o_drv_x1_p_rows_clusters[cluster_idx * NUM_ROWS + dst_row] !== expected_bit) begin
                            $display("ERROR replay x1_p mismatch c=%0d row=%0d term=%0d", cluster_idx, dst_row, term_idx);
                            $fatal;
                        end
                        2: if (o_drv_x2_p_rows_clusters[cluster_idx * NUM_ROWS + dst_row] !== expected_bit) begin
                            $display("ERROR replay x2_p mismatch c=%0d row=%0d term=%0d", cluster_idx, dst_row, term_idx);
                            $fatal;
                        end
                        3: if (o_drv_x3_p_rows_clusters[cluster_idx * NUM_ROWS + dst_row] !== expected_bit) begin
                            $display("ERROR replay x3_p mismatch c=%0d row=%0d term=%0d", cluster_idx, dst_row, term_idx);
                            $fatal;
                        end
                    endcase

                    expected_bit = get_state_bit(o_x_old_n_rows_clusters, cluster_idx, src_row, bit_sel);
                    case (term_idx)
                        0: if (o_drv_x0_n_rows_clusters[cluster_idx * NUM_ROWS + dst_row] !== expected_bit) begin
                            $display("ERROR replay x0_n mismatch c=%0d row=%0d term=%0d", cluster_idx, dst_row, term_idx);
                            $fatal;
                        end
                        1: if (o_drv_x1_n_rows_clusters[cluster_idx * NUM_ROWS + dst_row] !== expected_bit) begin
                            $display("ERROR replay x1_n mismatch c=%0d row=%0d term=%0d", cluster_idx, dst_row, term_idx);
                            $fatal;
                        end
                        2: if (o_drv_x2_n_rows_clusters[cluster_idx * NUM_ROWS + dst_row] !== expected_bit) begin
                            $display("ERROR replay x2_n mismatch c=%0d row=%0d term=%0d", cluster_idx, dst_row, term_idx);
                            $fatal;
                        end
                        3: if (o_drv_x3_n_rows_clusters[cluster_idx * NUM_ROWS + dst_row] !== expected_bit) begin
                            $display("ERROR replay x3_n mismatch c=%0d row=%0d term=%0d", cluster_idx, dst_row, term_idx);
                            $fatal;
                        end
                    endcase
                end
            end
        end

        // Fire one replay-driven iteration just to prove the integrated path
        // still completes a full controller loop.
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
            $display("ERROR replay-driven iteration did not complete");
            $fatal;
        end

        $display("PASS tb_iter_dense_small_replay_top");
        $finish;
    end
endmodule
