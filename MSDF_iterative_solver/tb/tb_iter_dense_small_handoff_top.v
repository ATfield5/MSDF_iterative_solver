`timescale 1ns / 1ps

module tb_iter_dense_small_handoff_top;
    localparam integer NUM_CLUSTERS = 2;
    localparam integer NUM_ROWS = 4;
    localparam integer BIT_WIDTH = 8;
    localparam integer BOUND_WIDTH = BIT_WIDTH + 5;
    localparam integer BLOCK_SIZE = 2;
    localparam integer NUM_BLOCKS = (NUM_ROWS + BLOCK_SIZE - 1) / BLOCK_SIZE;
    localparam integer COEFF_WIDTH = 8;
    localparam integer ACC_WIDTH = 24;

    reg i_clk;
    reg i_rst;
    reg i_start_iter;
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

    wire [NUM_CLUSTERS - 1 : 0] o_cluster_valid;
    wire [NUM_CLUSTERS - 1 : 0] o_cluster_certified;
    wire [NUM_CLUSTERS * ACC_WIDTH - 1 : 0] o_cluster_max_error;
    wire [NUM_CLUSTERS * NUM_ROWS * (BIT_WIDTH + 3) - 1 : 0] o_x_old_p_rows_clusters;
    wire [NUM_CLUSTERS * NUM_ROWS * (BIT_WIDTH + 3) - 1 : 0] o_x_old_n_rows_clusters;
    wire o_iter_done, o_iter_converged, o_iter_continue;
    wire [NUM_CLUSTERS - 1 : 0] o_seen_mask, o_cert_mask;

    iter_dense_small_handoff_top #(
        .num_clusters(NUM_CLUSTERS),
        .num_rows(NUM_ROWS),
        .bit_width(BIT_WIDTH),
        .bound_width(BOUND_WIDTH),
        .coeff_width(COEFF_WIDTH),
        .acc_width(ACC_WIDTH),
        .block_size(BLOCK_SIZE),
        .num_blocks(NUM_BLOCKS)
    ) dut (
        .i_clk(i_clk),
        .i_rst(i_rst),
        .i_start_iter(i_start_iter),
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

    integer cycles_waited;
    reg [NUM_CLUSTERS * NUM_ROWS * (BIT_WIDTH + 3) - 1 : 0] saved_xold_p_rows;
    reg [NUM_CLUSTERS * NUM_ROWS * (BIT_WIDTH + 3) - 1 : 0] saved_xold_n_rows;
    initial begin
        i_clk = 1'b0;
        i_rst = 1'b1;
        i_start_iter = 1'b0;
        i_ena_rows_clusters = {NUM_CLUSTERS * NUM_ROWS{1'b0}};
        i_x0_p_rows_clusters = {NUM_CLUSTERS * NUM_ROWS{1'b0}};
        i_x0_n_rows_clusters = {NUM_CLUSTERS * NUM_ROWS{1'b0}};
        i_x1_p_rows_clusters = {NUM_CLUSTERS * NUM_ROWS{1'b0}};
        i_x1_n_rows_clusters = {NUM_CLUSTERS * NUM_ROWS{1'b0}};
        i_x2_p_rows_clusters = {NUM_CLUSTERS * NUM_ROWS{1'b0}};
        i_x2_n_rows_clusters = {NUM_CLUSTERS * NUM_ROWS{1'b0}};
        i_x3_p_rows_clusters = {NUM_CLUSTERS * NUM_ROWS{1'b0}};
        i_x3_n_rows_clusters = {NUM_CLUSTERS * NUM_ROWS{1'b0}};

        i_coeff0_vec_p_rows_clusters = {
            8'd2, 8'd2, 8'd2, 8'd5,
            8'd2, 8'd2, 8'd2, 8'd5
        };
        i_coeff0_vec_n_rows_clusters = {NUM_CLUSTERS * NUM_ROWS * BIT_WIDTH{1'b0}};
        i_coeff1_vec_p_rows_clusters = {
            8'd4, 8'd2, 8'd2, 8'd3,
            8'd4, 8'd2, 8'd2, 8'd3
        };
        i_coeff1_vec_n_rows_clusters = {NUM_CLUSTERS * NUM_ROWS * BIT_WIDTH{1'b0}};
        i_coeff2_vec_p_rows_clusters = {NUM_CLUSTERS * NUM_ROWS * BIT_WIDTH{1'b0}};
        i_coeff2_vec_n_rows_clusters = {NUM_CLUSTERS * NUM_ROWS * BIT_WIDTH{1'b0}};
        i_coeff3_vec_p_rows_clusters = {
            8'd2, 8'd0, 8'd0, 8'd2,
            8'd2, 8'd0, 8'd0, 8'd2
        };
        i_coeff3_vec_n_rows_clusters = {NUM_CLUSTERS * NUM_ROWS * BIT_WIDTH{1'b0}};
        i_bias_vec_p_rows_clusters = {
            10'd1, 10'd1, 10'd1, 10'd1,
            10'd1, 10'd1, 10'd1, 10'd1
        };
        i_bias_vec_n_rows_clusters = {NUM_CLUSTERS * NUM_ROWS * (BIT_WIDTH + 2){1'b0}};
        i_tail_bound_clusters = {13'd1, 13'd1};
        i_block_weights_clusters = {
            8'd0, 8'd3, 8'd1, 8'd1, 8'd1, 8'd2, 8'd2, 8'd1,
            8'd0, 8'd3, 8'd1, 8'd1, 8'd1, 8'd2, 8'd2, 8'd1
        };

        repeat (2) @(posedge i_clk);
        i_rst <= 1'b0;

        // Iteration 1: internal x_old is zero, so max error should be large.
        i_eta_clusters <= {24'd3, 24'd3};
        pulse_start_iter();
        launch_both_clusters_same_pattern();

        cycles_waited = 0;
        while (!o_iter_done && cycles_waited < 16) begin
            @(posedge i_clk);
            cycles_waited = cycles_waited + 1;
        end
        if (!o_iter_done || o_iter_converged || !o_iter_continue ||
            o_cert_mask !== 2'b00 ||
            o_cluster_max_error[ACC_WIDTH-1:0] !== 24'd36 ||
            o_cluster_max_error[2*ACC_WIDTH-1:ACC_WIDTH] !== 24'd36) begin
            $display("ERROR iter1 done=%b conv=%b cont=%b cert=%b max0=%0d max1=%0d",
                o_iter_done, o_iter_converged, o_iter_continue, o_cert_mask,
                o_cluster_max_error[ACC_WIDTH-1:0],
                o_cluster_max_error[2*ACC_WIDTH-1:ACC_WIDTH]);
            $fatal;
        end

        // Handoff state is rail-coded. Check that it is no longer zero and keep
        // an exact copy to verify stable replay into the next iteration.
        if (o_x_old_p_rows_clusters === {NUM_CLUSTERS * NUM_ROWS * (BIT_WIDTH + 3){1'b0}} &&
            o_x_old_n_rows_clusters === {NUM_CLUSTERS * NUM_ROWS * (BIT_WIDTH + 3){1'b0}}) begin
            $display("ERROR handoff state stayed zero");
            $fatal;
        end
        saved_xold_p_rows = o_x_old_p_rows_clusters;
        saved_xold_n_rows = o_x_old_n_rows_clusters;

        // Iteration 2: same affine output, but x_old is now fed back internally.
        // With tail_bound=1 and the chosen H weights, max error should drop to 3.
        pulse_start_iter();
        launch_both_clusters_same_pattern();

        cycles_waited = 0;
        while (!o_iter_done && cycles_waited < 16) begin
            @(posedge i_clk);
            cycles_waited = cycles_waited + 1;
        end
        if (o_x_old_p_rows_clusters !== saved_xold_p_rows ||
            o_x_old_n_rows_clusters !== saved_xold_n_rows) begin
            $display("ERROR handoff state changed unexpectedly between iterations");
            $fatal;
        end
        if (!o_iter_done || !o_iter_converged || o_iter_continue ||
            o_cert_mask !== 2'b11 ||
            o_cluster_max_error[ACC_WIDTH-1:0] !== 24'd3 ||
            o_cluster_max_error[2*ACC_WIDTH-1:ACC_WIDTH] !== 24'd3) begin
            $display("ERROR iter2 done=%b conv=%b cont=%b cert=%b max0=%0d max1=%0d",
                o_iter_done, o_iter_converged, o_iter_continue, o_cert_mask,
                o_cluster_max_error[ACC_WIDTH-1:0],
                o_cluster_max_error[2*ACC_WIDTH-1:ACC_WIDTH]);
            $fatal;
        end

        $display("PASS tb_iter_dense_small_handoff_top");
        $finish;
    end

endmodule
