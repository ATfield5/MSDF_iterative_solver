`timescale 1ns / 1ps

module tb_iter_prior_online_mma8_row_cluster_delta_cert;
    localparam integer NUM_ROWS = 4;
    localparam integer DEGREE = 4;
    localparam integer BIT_WIDTH = 8;
    localparam integer DATA_WIDTH = 11;
    localparam integer BIAS_WIDTH = 10;
    localparam integer BOUND_WIDTH = 13;
    localparam integer COEFF_WIDTH = 8;
    localparam integer ACC_WIDTH = 24;
    localparam integer BLOCK_SIZE = 1;
    localparam integer NUM_BLOCKS = NUM_ROWS;

    reg i_clk;
    reg i_rst;
    reg i_start;
    reg [NUM_ROWS * DEGREE * DATA_WIDTH - 1 : 0] i_state_p_terms_rows;
    reg [NUM_ROWS * DEGREE * DATA_WIDTH - 1 : 0] i_state_n_terms_rows;
    reg [NUM_ROWS * DEGREE * BIT_WIDTH - 1 : 0] i_coeff_p_terms_rows;
    reg [NUM_ROWS * DEGREE * BIT_WIDTH - 1 : 0] i_coeff_n_terms_rows;
    reg [NUM_ROWS * BIAS_WIDTH - 1 : 0] i_bias_p_rows;
    reg [NUM_ROWS * BIAS_WIDTH - 1 : 0] i_bias_n_rows;
    reg [NUM_ROWS * DATA_WIDTH - 1 : 0] i_old_state_p_rows;
    reg [NUM_ROWS * DATA_WIDTH - 1 : 0] i_old_state_n_rows;
    reg [BOUND_WIDTH - 1 : 0] i_tail_bound;
    reg [NUM_ROWS * NUM_BLOCKS * COEFF_WIDTH - 1 : 0] i_block_weights;
    reg [ACC_WIDTH - 1 : 0] i_eta;

    wire [NUM_ROWS - 1 : 0] o_valid_rows;
    wire [NUM_ROWS * DATA_WIDTH - 1 : 0] o_sum_p_rows;
    wire [NUM_ROWS * DATA_WIDTH - 1 : 0] o_sum_n_rows;
    wire [NUM_ROWS * BOUND_WIDTH - 1 : 0] o_abs_upper_rows;
    wire [NUM_BLOCKS * BOUND_WIDTH - 1 : 0] o_block_bounds;
    wire o_cluster_valid;
    wire o_cluster_certified;
    wire [ACC_WIDTH - 1 : 0] o_cluster_max_error;

    integer idx;
    integer wait_cycles;

    iter_prior_online_mma8_row_cluster_delta_cert #(
        .num_rows(NUM_ROWS),
        .degree(DEGREE),
        .bit_width(BIT_WIDTH),
        .data_width(DATA_WIDTH),
        .bias_width(BIAS_WIDTH),
        .bound_width(BOUND_WIDTH),
        .coeff_width(COEFF_WIDTH),
        .acc_width(ACC_WIDTH),
        .block_size(BLOCK_SIZE),
        .num_blocks(NUM_BLOCKS)
    ) dut (
        .i_clk(i_clk),
        .i_rst(i_rst),
        .i_start(i_start),
        .i_state_p_terms_rows(i_state_p_terms_rows),
        .i_state_n_terms_rows(i_state_n_terms_rows),
        .i_coeff_p_terms_rows(i_coeff_p_terms_rows),
        .i_coeff_n_terms_rows(i_coeff_n_terms_rows),
        .i_bias_p_rows(i_bias_p_rows),
        .i_bias_n_rows(i_bias_n_rows),
        .i_old_state_p_rows(i_old_state_p_rows),
        .i_old_state_n_rows(i_old_state_n_rows),
        .i_tail_bound(i_tail_bound),
        .i_block_weights(i_block_weights),
        .i_eta(i_eta),
        .o_valid_rows(o_valid_rows),
        .o_sum_p_rows(o_sum_p_rows),
        .o_sum_n_rows(o_sum_n_rows),
        .o_abs_upper_rows(o_abs_upper_rows),
        .o_block_bounds(o_block_bounds),
        .o_cluster_valid(o_cluster_valid),
        .o_cluster_certified(o_cluster_certified),
        .o_cluster_max_error(o_cluster_max_error)
    );

    always #5 i_clk = ~i_clk;

    initial begin
        i_clk = 1'b0;
        i_rst = 1'b1;
        i_start = 1'b0;
        i_state_p_terms_rows = {NUM_ROWS * DEGREE * DATA_WIDTH{1'b0}};
        i_state_n_terms_rows = {NUM_ROWS * DEGREE * DATA_WIDTH{1'b0}};
        i_coeff_p_terms_rows = {NUM_ROWS * DEGREE * BIT_WIDTH{1'b0}};
        i_coeff_n_terms_rows = {NUM_ROWS * DEGREE * BIT_WIDTH{1'b0}};
        i_bias_p_rows = {NUM_ROWS * BIAS_WIDTH{1'b0}};
        i_bias_n_rows = {NUM_ROWS * BIAS_WIDTH{1'b0}};
        i_old_state_p_rows = {NUM_ROWS * DATA_WIDTH{1'b0}};
        i_old_state_n_rows = {NUM_ROWS * DATA_WIDTH{1'b0}};
        i_tail_bound = 13'd1;
        i_block_weights = {NUM_ROWS * NUM_BLOCKS{8'h01}};
        i_eta = 24'd4095;

        for (idx = 0; idx < NUM_ROWS * DEGREE; idx = idx + 1) begin
            i_state_p_terms_rows[idx * DATA_WIDTH +: DATA_WIDTH] = 11'h020 + idx[4:0];
            i_coeff_p_terms_rows[idx * BIT_WIDTH +: BIT_WIDTH] = 8'h04 + idx[3:0];
        end
        for (idx = 0; idx < NUM_ROWS; idx = idx + 1) begin
            i_bias_p_rows[idx * BIAS_WIDTH +: BIAS_WIDTH] = 10'h001;
        end

        repeat (4) @(posedge i_clk);
        i_rst <= 1'b0;
        @(negedge i_clk);
        i_start <= 1'b1;
        @(negedge i_clk);
        i_start <= 1'b0;

        wait_cycles = 0;
        while (!o_cluster_valid && wait_cycles < 160) begin
            @(posedge i_clk);
            wait_cycles = wait_cycles + 1;
        end
        if (!o_cluster_valid) begin
            $display("ERROR prior cluster timeout valid_rows=%b", o_valid_rows);
            $fatal;
        end
        if (o_cluster_max_error === {ACC_WIDTH{1'b0}}) begin
            $display("ERROR prior cluster zero max_error");
            $fatal;
        end

        $display("COUNTERS prior_mma8_cluster cycles=%0d max_error=%0d certified=%0d sum0p=%h sum0n=%h",
            wait_cycles,
            o_cluster_max_error,
            o_cluster_certified,
            o_sum_p_rows[DATA_WIDTH - 1 : 0],
            o_sum_n_rows[DATA_WIDTH - 1 : 0]);
        $display("PASS tb_iter_prior_online_mma8_row_cluster_delta_cert");
        $finish;
    end
endmodule
