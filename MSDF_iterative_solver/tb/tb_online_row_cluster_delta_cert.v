`timescale 1ns / 1ps

module tb_online_row_cluster_delta_cert;
    localparam integer NUM_ROWS = 4;
    localparam integer BIT_WIDTH = 8;
    localparam integer BOUND_WIDTH = BIT_WIDTH + 5;
    localparam integer BLOCK_SIZE = 2;
    localparam integer NUM_BLOCKS = (NUM_ROWS + BLOCK_SIZE - 1) / BLOCK_SIZE;
    localparam integer COEFF_WIDTH = 8;
    localparam integer ACC_WIDTH = 24;

    reg i_clk;
    reg i_rst;
    reg [NUM_ROWS-1:0] i_ena_rows;
    reg [NUM_ROWS-1:0] i_x0_p_rows, i_x0_n_rows;
    reg [NUM_ROWS-1:0] i_x1_p_rows, i_x1_n_rows;
    reg [NUM_ROWS-1:0] i_x2_p_rows, i_x2_n_rows;
    reg [NUM_ROWS-1:0] i_x3_p_rows, i_x3_n_rows;
    reg [NUM_ROWS*BIT_WIDTH-1:0] i_coeff0_vec_p_rows, i_coeff0_vec_n_rows;
    reg [NUM_ROWS*BIT_WIDTH-1:0] i_coeff1_vec_p_rows, i_coeff1_vec_n_rows;
    reg [NUM_ROWS*BIT_WIDTH-1:0] i_coeff2_vec_p_rows, i_coeff2_vec_n_rows;
    reg [NUM_ROWS*BIT_WIDTH-1:0] i_coeff3_vec_p_rows, i_coeff3_vec_n_rows;
    reg [NUM_ROWS*(BIT_WIDTH+2)-1:0] i_bias_vec_p_rows, i_bias_vec_n_rows;
    reg [NUM_ROWS*(BIT_WIDTH+3)-1:0] i_x_old_p_rows, i_x_old_n_rows;
    reg [BOUND_WIDTH-1:0] i_tail_bound;
    reg [NUM_ROWS*NUM_BLOCKS*COEFF_WIDTH-1:0] i_block_weights;
    reg [ACC_WIDTH-1:0] i_eta;
    wire [NUM_ROWS-1:0] o_valid_rows;
    wire [NUM_ROWS*(BIT_WIDTH+3)-1:0] o_sum_p_rows, o_sum_n_rows;
    wire [NUM_ROWS*BOUND_WIDTH-1:0] o_abs_upper_rows;
    wire [NUM_BLOCKS*BOUND_WIDTH-1:0] o_block_bounds;
    wire o_cluster_valid;
    wire o_cluster_certified;
    wire [ACC_WIDTH-1:0] o_cluster_max_error;
    integer seen_valid;

    online_row_cluster_delta_cert #(
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
        .i_ena_rows(i_ena_rows),
        .i_x0_p_rows(i_x0_p_rows), .i_x0_n_rows(i_x0_n_rows),
        .i_x1_p_rows(i_x1_p_rows), .i_x1_n_rows(i_x1_n_rows),
        .i_x2_p_rows(i_x2_p_rows), .i_x2_n_rows(i_x2_n_rows),
        .i_x3_p_rows(i_x3_p_rows), .i_x3_n_rows(i_x3_n_rows),
        .i_coeff0_vec_p_rows(i_coeff0_vec_p_rows), .i_coeff0_vec_n_rows(i_coeff0_vec_n_rows),
        .i_coeff1_vec_p_rows(i_coeff1_vec_p_rows), .i_coeff1_vec_n_rows(i_coeff1_vec_n_rows),
        .i_coeff2_vec_p_rows(i_coeff2_vec_p_rows), .i_coeff2_vec_n_rows(i_coeff2_vec_n_rows),
        .i_coeff3_vec_p_rows(i_coeff3_vec_p_rows), .i_coeff3_vec_n_rows(i_coeff3_vec_n_rows),
        .i_bias_vec_p_rows(i_bias_vec_p_rows), .i_bias_vec_n_rows(i_bias_vec_n_rows),
        .i_x_old_p_rows(i_x_old_p_rows), .i_x_old_n_rows(i_x_old_n_rows),
        .i_tail_bound(i_tail_bound),
        .i_block_weights(i_block_weights),
        .i_eta(i_eta),
        .o_valid_rows(o_valid_rows),
        .o_sum_p_rows(o_sum_p_rows), .o_sum_n_rows(o_sum_n_rows),
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
        i_ena_rows = 4'b0000;
        i_x0_p_rows = 4'b0000; i_x0_n_rows = 4'b0000;
        i_x1_p_rows = 4'b0000; i_x1_n_rows = 4'b0000;
        i_x2_p_rows = 4'b0000; i_x2_n_rows = 4'b0000;
        i_x3_p_rows = 4'b0000; i_x3_n_rows = 4'b0000;

        // Row0 -> sum 11 -> upper 12
        // Row1 -> sum 7  -> upper 8
        // Row2 -> sum 5  -> upper 6
        // Row3 -> sum 9  -> upper 10
        i_coeff0_vec_p_rows = {8'd2, 8'd2, 8'd2, 8'd5};
        i_coeff0_vec_n_rows = {32'd0};
        i_coeff1_vec_p_rows = {8'd4, 8'd2, 8'd2, 8'd3};
        i_coeff1_vec_n_rows = {32'd0};
        i_coeff2_vec_p_rows = {8'd0, 8'd0, 8'd0, 8'd0};
        i_coeff2_vec_n_rows = {32'd0};
        i_coeff3_vec_p_rows = {8'd2, 8'd0, 8'd0, 8'd2};
        i_coeff3_vec_n_rows = {32'd0};
        i_bias_vec_p_rows   = {10'd1, 10'd1, 10'd1, 10'd1};
        i_bias_vec_n_rows   = {40'd0};
        i_x_old_p_rows      = {44'd0};
        i_x_old_n_rows      = {44'd0};
        i_tail_bound        = 13'd1;

        // block maxima expected: [12, 10] for rows [0,1] and [2,3]
        // row0 weights [1,2] => 12 + 20 = 32
        // row1 weights [2,1] => 24 + 10 = 34
        // row2 weights [1,1] => 22
        // row3 weights [3,0] => 36
        i_block_weights = {
            8'd0, 8'd3,
            8'd1, 8'd1,
            8'd1, 8'd2,
            8'd2, 8'd1
        };
        i_eta = 24'd36;

        repeat (2) @(posedge i_clk);
        i_rst <= 1'b0;
        @(posedge i_clk);
        i_ena_rows  <= 4'b1111;
        i_x0_p_rows <= 4'b1111;
        i_x1_p_rows <= 4'b1111;
        i_x2_p_rows <= 4'b0000;
        i_x3_p_rows <= 4'b1001;

        @(posedge i_clk);
        i_ena_rows  <= 4'b0000;
        i_x0_p_rows <= 4'b0000;
        i_x1_p_rows <= 4'b0000;
        i_x2_p_rows <= 4'b0000;
        i_x3_p_rows <= 4'b0000;

        seen_valid = 0;
        repeat (8) begin
            @(posedge i_clk);
            if (o_cluster_valid) begin
                seen_valid = 1;
                if (o_block_bounds !== {13'd10, 13'd12} ||
                    !o_cluster_certified ||
                    o_cluster_max_error !== 24'd36) begin
                    $display("ERROR tb_online_row_cluster_delta_cert valid_rows=%b bounds=%h cert=%b max=%0d",
                        o_valid_rows, o_block_bounds, o_cluster_certified, o_cluster_max_error);
                    $fatal;
                end
                $display("PASS tb_online_row_cluster_delta_cert");
                $finish;
            end
        end

        if (!seen_valid) begin
            $display("ERROR tb_online_row_cluster_delta_cert no cluster valid");
            $fatal;
        end
    end
endmodule
