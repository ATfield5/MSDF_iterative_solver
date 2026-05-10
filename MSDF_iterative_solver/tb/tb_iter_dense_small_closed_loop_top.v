`timescale 1ns / 1ps

module tb_iter_dense_small_closed_loop_top;
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
    reg [NUM_CLUSTERS * NUM_ROWS * (BIT_WIDTH + 3) - 1 : 0] i_x_old_p_rows_clusters, i_x_old_n_rows_clusters;
    reg [NUM_CLUSTERS * BOUND_WIDTH - 1 : 0] i_tail_bound_clusters;
    reg [NUM_CLUSTERS * NUM_ROWS * NUM_BLOCKS * COEFF_WIDTH - 1 : 0] i_block_weights_clusters;
    reg [NUM_CLUSTERS * ACC_WIDTH - 1 : 0] i_eta_clusters;

    wire [NUM_CLUSTERS - 1 : 0] o_cluster_valid;
    wire [NUM_CLUSTERS - 1 : 0] o_cluster_certified;
    wire [NUM_CLUSTERS * ACC_WIDTH - 1 : 0] o_cluster_max_error;
    wire o_iter_done, o_iter_converged, o_iter_continue;
    wire [NUM_CLUSTERS - 1 : 0] o_seen_mask, o_cert_mask;

    iter_dense_small_closed_loop_top #(
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
        .i_x_old_p_rows_clusters(i_x_old_p_rows_clusters),
        .i_x_old_n_rows_clusters(i_x_old_n_rows_clusters),
        .i_tail_bound_clusters(i_tail_bound_clusters),
        .i_block_weights_clusters(i_block_weights_clusters),
        .i_eta_clusters(i_eta_clusters),
        .o_cluster_valid(o_cluster_valid),
        .o_cluster_certified(o_cluster_certified),
        .o_cluster_max_error(o_cluster_max_error),
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

    task launch_cluster0;
        begin
            @(posedge i_clk);
            i_ena_rows_clusters[NUM_ROWS-1:0] <= 4'b1111;
            i_x0_p_rows_clusters[NUM_ROWS-1:0] <= 4'b1111;
            i_x1_p_rows_clusters[NUM_ROWS-1:0] <= 4'b1111;
            i_x2_p_rows_clusters[NUM_ROWS-1:0] <= 4'b0000;
            i_x3_p_rows_clusters[NUM_ROWS-1:0] <= 4'b1001;
            @(posedge i_clk);
            i_ena_rows_clusters[NUM_ROWS-1:0] <= 4'b0000;
            i_x0_p_rows_clusters[NUM_ROWS-1:0] <= 4'b0000;
            i_x1_p_rows_clusters[NUM_ROWS-1:0] <= 4'b0000;
            i_x2_p_rows_clusters[NUM_ROWS-1:0] <= 4'b0000;
            i_x3_p_rows_clusters[NUM_ROWS-1:0] <= 4'b0000;
        end
    endtask

    task launch_cluster1;
        begin
            @(posedge i_clk);
            i_ena_rows_clusters[2 * NUM_ROWS - 1 -: NUM_ROWS] <= 4'b1111;
            i_x0_p_rows_clusters[2 * NUM_ROWS - 1 -: NUM_ROWS] <= 4'b1111;
            i_x1_p_rows_clusters[2 * NUM_ROWS - 1 -: NUM_ROWS] <= 4'b1111;
            i_x2_p_rows_clusters[2 * NUM_ROWS - 1 -: NUM_ROWS] <= 4'b0000;
            i_x3_p_rows_clusters[2 * NUM_ROWS - 1 -: NUM_ROWS] <= 4'b1001;
            @(posedge i_clk);
            i_ena_rows_clusters[2 * NUM_ROWS - 1 -: NUM_ROWS] <= 4'b0000;
            i_x0_p_rows_clusters[2 * NUM_ROWS - 1 -: NUM_ROWS] <= 4'b0000;
            i_x1_p_rows_clusters[2 * NUM_ROWS - 1 -: NUM_ROWS] <= 4'b0000;
            i_x2_p_rows_clusters[2 * NUM_ROWS - 1 -: NUM_ROWS] <= 4'b0000;
            i_x3_p_rows_clusters[2 * NUM_ROWS - 1 -: NUM_ROWS] <= 4'b0000;
        end
    endtask

    integer cycles_waited;
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
        i_x_old_p_rows_clusters = {NUM_CLUSTERS * NUM_ROWS * (BIT_WIDTH + 3){1'b0}};
        i_x_old_n_rows_clusters = {NUM_CLUSTERS * NUM_ROWS * (BIT_WIDTH + 3){1'b0}};
        i_tail_bound_clusters = {13'd1, 13'd1};

        // Both clusters see block bounds [12, 10].
        i_block_weights_clusters = {
            8'd0, 8'd3, 8'd1, 8'd1, 8'd1, 8'd2, 8'd2, 8'd1,
            8'd0, 8'd3, 8'd1, 8'd1, 8'd1, 8'd2, 8'd2, 8'd1
        };

        repeat (2) @(posedge i_clk);
        i_rst <= 1'b0;

        // Iteration 1: cluster0 certifies, cluster1 does not.
        i_eta_clusters <= {24'd20, 24'd36};
        pulse_start_iter();
        launch_cluster0();
        launch_cluster1();

        cycles_waited = 0;
        while (!o_iter_done && cycles_waited < 16) begin
            @(posedge i_clk);
            cycles_waited = cycles_waited + 1;
        end
        if (!o_iter_done ||
            o_iter_converged ||
            !o_iter_continue ||
            o_seen_mask !== 2'b11 ||
            o_cert_mask !== 2'b01) begin
            $display("ERROR iter1 done=%b conv=%b cont=%b seen=%b cert=%b",
                o_iter_done, o_iter_converged, o_iter_continue, o_seen_mask, o_cert_mask);
            $fatal;
        end

        @(posedge i_clk);
        if (o_iter_done || o_iter_converged || o_iter_continue) begin
            $display("ERROR iter1 pulse did not clear");
            $fatal;
        end

        // Iteration 2: both clusters certify.
        i_eta_clusters <= {24'd36, 24'd36};
        pulse_start_iter();
        launch_cluster1();
        launch_cluster0();

        cycles_waited = 0;
        while (!o_iter_done && cycles_waited < 16) begin
            @(posedge i_clk);
            cycles_waited = cycles_waited + 1;
        end
        if (!o_iter_done ||
            !o_iter_converged ||
            o_iter_continue ||
            o_seen_mask !== 2'b11 ||
            o_cert_mask !== 2'b11) begin
            $display("ERROR iter2 done=%b conv=%b cont=%b seen=%b cert=%b",
                o_iter_done, o_iter_converged, o_iter_continue, o_seen_mask, o_cert_mask);
            $fatal;
        end

        $display("PASS tb_iter_dense_small_closed_loop_top");
        $finish;
    end

endmodule
