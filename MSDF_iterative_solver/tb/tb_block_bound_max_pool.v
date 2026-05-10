`timescale 1ns / 1ps

module tb_block_bound_max_pool;
    localparam integer NUM_ROWS = 4;
    localparam integer BLOCK_SIZE = 2;
    localparam integer BOUND_WIDTH = 8;
    localparam integer NUM_BLOCKS = (NUM_ROWS + BLOCK_SIZE - 1) / BLOCK_SIZE;

    reg  [NUM_ROWS - 1 : 0] i_valid_rows;
    reg  [NUM_ROWS * BOUND_WIDTH - 1 : 0] i_row_abs_upper;
    wire o_valid;
    wire [NUM_BLOCKS * BOUND_WIDTH - 1 : 0] o_block_bounds;

    block_bound_max_pool #(
        .num_rows(NUM_ROWS),
        .block_size(BLOCK_SIZE),
        .bound_width(BOUND_WIDTH),
        .num_blocks(NUM_BLOCKS)
    ) dut (
        .i_valid_rows(i_valid_rows),
        .i_row_abs_upper(i_row_abs_upper),
        .o_valid(o_valid),
        .o_block_bounds(o_block_bounds)
    );

    initial begin
        // row bounds: [7, 3, 5, 11]
        i_row_abs_upper = {8'd11, 8'd5, 8'd3, 8'd7};
        i_valid_rows = 4'b1111;
        #1;
        if (!o_valid || o_block_bounds !== {8'd11, 8'd7}) begin
            $display("ERROR tb_block_bound_max_pool case1 valid=%b bounds=%h", o_valid, o_block_bounds);
            $fatal;
        end

        i_valid_rows = 4'b1011;
        #1;
        if (o_valid) begin
            $display("ERROR tb_block_bound_max_pool case2 valid should be 0");
            $fatal;
        end

        $display("PASS tb_block_bound_max_pool");
        $finish;
    end
endmodule
