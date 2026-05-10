`timescale 1ns / 1ps

module tb_conv_jacobi_datapath_array_top;
    localparam integer NUM_CLUSTERS = 2;
    localparam integer NUM_ROWS = 4;
    localparam integer DEGREE = 4;
    localparam integer BIT_WIDTH = 8;
    localparam integer DATA_WIDTH = BIT_WIDTH + 3;
    localparam integer BIAS_WIDTH = BIT_WIDTH + 2;
    localparam integer BOUND_WIDTH = BIT_WIDTH + 5;
    localparam integer COEFF_WIDTH = 8;
    localparam integer ACC_WIDTH = 24;
    localparam integer MAC_ACC_WIDTH = 32;
    localparam integer BLOCK_SIZE = 2;
    localparam integer NUM_BLOCKS = 2;

    reg i_clk;
    reg i_rst;
    reg i_valid;
    reg [NUM_CLUSTERS * NUM_ROWS * DEGREE * DATA_WIDTH - 1 : 0] i_state_p_terms_clusters;
    reg [NUM_CLUSTERS * NUM_ROWS * DEGREE * DATA_WIDTH - 1 : 0] i_state_n_terms_clusters;
    reg [NUM_CLUSTERS * NUM_ROWS * DEGREE * BIT_WIDTH - 1 : 0] i_coeff_p_terms_clusters;
    reg [NUM_CLUSTERS * NUM_ROWS * DEGREE * BIT_WIDTH - 1 : 0] i_coeff_n_terms_clusters;
    reg [NUM_CLUSTERS * NUM_ROWS * BIAS_WIDTH - 1 : 0] i_bias_p_rows_clusters;
    reg [NUM_CLUSTERS * NUM_ROWS * BIAS_WIDTH - 1 : 0] i_bias_n_rows_clusters;
    reg [NUM_CLUSTERS * NUM_ROWS * DATA_WIDTH - 1 : 0] i_old_state_p_rows_clusters;
    reg [NUM_CLUSTERS * NUM_ROWS * DATA_WIDTH - 1 : 0] i_old_state_n_rows_clusters;
    reg [NUM_CLUSTERS * BOUND_WIDTH - 1 : 0] i_tail_bound_clusters;
    reg [NUM_CLUSTERS * NUM_ROWS * NUM_BLOCKS * COEFF_WIDTH - 1 : 0] i_block_weights_clusters;
    reg [NUM_CLUSTERS * ACC_WIDTH - 1 : 0] i_eta_clusters;
    wire [NUM_CLUSTERS - 1 : 0] o_cluster_valid;
    wire [NUM_CLUSTERS - 1 : 0] o_cluster_certified;
    wire [NUM_CLUSTERS * ACC_WIDTH - 1 : 0] o_cluster_max_error;
    wire [NUM_CLUSTERS * NUM_ROWS * MAC_ACC_WIDTH - 1 : 0] o_sum_rows_clusters;

    integer ci;
    integer ri;
    integer ti;
    integer flat_term;

    conv_jacobi_datapath_array_top #(
        .num_clusters(NUM_CLUSTERS),
        .num_rows(NUM_ROWS),
        .degree(DEGREE),
        .bit_width(BIT_WIDTH),
        .data_width(DATA_WIDTH),
        .bias_width(BIAS_WIDTH),
        .bound_width(BOUND_WIDTH),
        .coeff_width(COEFF_WIDTH),
        .acc_width(ACC_WIDTH),
        .mac_acc_width(MAC_ACC_WIDTH),
        .block_size(BLOCK_SIZE),
        .num_blocks(NUM_BLOCKS)
    ) dut (
        .i_clk(i_clk),
        .i_rst(i_rst),
        .i_valid(i_valid),
        .i_state_p_terms_clusters(i_state_p_terms_clusters),
        .i_state_n_terms_clusters(i_state_n_terms_clusters),
        .i_coeff_p_terms_clusters(i_coeff_p_terms_clusters),
        .i_coeff_n_terms_clusters(i_coeff_n_terms_clusters),
        .i_bias_p_rows_clusters(i_bias_p_rows_clusters),
        .i_bias_n_rows_clusters(i_bias_n_rows_clusters),
        .i_old_state_p_rows_clusters(i_old_state_p_rows_clusters),
        .i_old_state_n_rows_clusters(i_old_state_n_rows_clusters),
        .i_tail_bound_clusters(i_tail_bound_clusters),
        .i_block_weights_clusters(i_block_weights_clusters),
        .i_eta_clusters(i_eta_clusters),
        .o_cluster_valid(o_cluster_valid),
        .o_cluster_certified(o_cluster_certified),
        .o_cluster_max_error(o_cluster_max_error),
        .o_sum_rows_clusters(o_sum_rows_clusters)
    );

    always #5 i_clk = ~i_clk;

    initial begin
        i_clk = 1'b0;
        i_rst = 1'b1;
        i_valid = 1'b0;
        i_state_p_terms_clusters = 0;
        i_state_n_terms_clusters = 0;
        i_coeff_p_terms_clusters = 0;
        i_coeff_n_terms_clusters = 0;
        i_bias_p_rows_clusters = 0;
        i_bias_n_rows_clusters = 0;
        i_old_state_p_rows_clusters = 0;
        i_old_state_n_rows_clusters = 0;
        i_tail_bound_clusters = {NUM_CLUSTERS{13'd1}};
        i_block_weights_clusters = 0;
        i_eta_clusters = {NUM_CLUSTERS{24'd4095}};

        for (ci = 0; ci < NUM_CLUSTERS; ci = ci + 1) begin
            for (ri = 0; ri < NUM_ROWS; ri = ri + 1) begin
                i_bias_p_rows_clusters[(ci * NUM_ROWS + ri) * BIAS_WIDTH +: BIAS_WIDTH] = 10'd3;
                i_old_state_p_rows_clusters[(ci * NUM_ROWS + ri) * DATA_WIDTH +: DATA_WIDTH] = 11'd1;
                for (ti = 0; ti < DEGREE; ti = ti + 1) begin
                    flat_term = ((ci * NUM_ROWS + ri) * DEGREE + ti);
                    i_state_p_terms_clusters[flat_term * DATA_WIDTH +: DATA_WIDTH] = 11'd2;
                    i_coeff_p_terms_clusters[flat_term * BIT_WIDTH +: BIT_WIDTH] = 8'd4;
                end
                i_block_weights_clusters[(ci * NUM_ROWS * NUM_BLOCKS + ri * NUM_BLOCKS) * COEFF_WIDTH +: COEFF_WIDTH] = 8'd1;
                i_block_weights_clusters[(ci * NUM_ROWS * NUM_BLOCKS + ri * NUM_BLOCKS + 1) * COEFF_WIDTH +: COEFF_WIDTH] = 8'd1;
            end
        end

        repeat (3) @(posedge i_clk);
        i_rst <= 1'b0;
        @(posedge i_clk);
        i_valid <= 1'b1;
        @(posedge i_clk);
        i_valid <= 1'b0;

        repeat (5) @(posedge i_clk);
        if (o_cluster_valid !== {NUM_CLUSTERS{1'b1}}) begin
            $display("ERROR conv cluster_valid=%b", o_cluster_valid);
            $fatal;
        end
        if (o_cluster_max_error === {NUM_CLUSTERS * ACC_WIDTH{1'bx}}) begin
            $display("ERROR conv max_error unknown");
            $fatal;
        end

        $display("PASS tb_conv_jacobi_datapath_array_top");
        $finish;
    end
endmodule
