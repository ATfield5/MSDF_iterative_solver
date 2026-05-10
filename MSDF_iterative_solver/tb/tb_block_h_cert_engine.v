`timescale 1ns / 1ps

module tb_block_h_cert_engine;
    localparam integer NUM_ROWS = 2;
    localparam integer NUM_BLOCKS = 2;
    localparam integer BOUND_WIDTH = 8;
    localparam integer COEFF_WIDTH = 8;
    localparam integer ACC_WIDTH = 24;

    reg  i_clk;
    reg  i_rst;
    reg  i_valid;
    reg  [NUM_BLOCKS*BOUND_WIDTH-1:0] i_block_bounds;
    reg  [NUM_ROWS*NUM_BLOCKS*COEFF_WIDTH-1:0] i_block_weights;
    reg  [ACC_WIDTH-1:0] i_eta;
    wire o_valid;
    wire o_certified;
    wire [ACC_WIDTH-1:0] o_max_error;

    block_h_cert_engine #(
        .num_rows(NUM_ROWS),
        .num_blocks(NUM_BLOCKS),
        .bound_width(BOUND_WIDTH),
        .coeff_width(COEFF_WIDTH),
        .acc_width(ACC_WIDTH)
    ) dut (
        .i_clk(i_clk),
        .i_rst(i_rst),
        .i_valid(i_valid),
        .i_block_bounds(i_block_bounds),
        .i_block_weights(i_block_weights),
        .i_eta(i_eta),
        .o_valid(o_valid),
        .o_certified(o_certified),
        .o_max_error(o_max_error)
    );

    always #5 i_clk = ~i_clk;

    initial begin
        i_clk = 1'b0;
        i_rst = 1'b1;
        i_valid = 1'b0;
        // bounds: [3, 5]
        i_block_bounds = {8'd5, 8'd3};
        // row0: [2,1] => 3*2 + 5*1 = 11
        // row1: [1,4] => 3*1 + 5*4 = 23
        i_block_weights = {8'd4, 8'd1, 8'd1, 8'd2};

        i_eta = 24'd23;
        repeat (2) @(posedge i_clk);
        i_rst <= 1'b0;
        @(posedge i_clk);
        i_valid <= 1'b1;
        @(posedge i_clk);
        i_valid <= 1'b0;
        repeat (2) @(posedge i_clk);
        if (!o_valid || !o_certified || o_max_error !== 24'd23) begin
            $display("ERROR tb_block_h_cert_engine case1 valid=%b cert=%b max=%0d", o_valid, o_certified, o_max_error);
            $fatal;
        end

        i_eta = 24'd22;
        @(posedge i_clk);
        i_valid <= 1'b1;
        @(posedge i_clk);
        i_valid <= 1'b0;
        repeat (2) @(posedge i_clk);
        if (!o_valid || o_certified || o_max_error !== 24'd23) begin
            $display("ERROR tb_block_h_cert_engine case2 valid=%b cert=%b max=%0d", o_valid, o_certified, o_max_error);
            $fatal;
        end

        $display("PASS tb_block_h_cert_engine");
        $finish;
    end
endmodule
