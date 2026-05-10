`timescale 1ns / 1ps

module tb_online_row_cluster_block_cert;
    localparam integer NUM_ROWS = 4;
    localparam integer BLOCK_SIZE = 2;
    localparam integer NUM_BLOCKS = (NUM_ROWS + BLOCK_SIZE - 1) / BLOCK_SIZE;
    localparam integer BOUND_WIDTH = 8;
    localparam integer COEFF_WIDTH = 8;
    localparam integer ACC_WIDTH = 24;

    reg  i_clk;
    reg  i_rst;
    reg  [NUM_ROWS - 1 : 0] i_valid_rows;
    reg  [NUM_ROWS * BOUND_WIDTH - 1 : 0] i_row_abs_upper;
    reg  [NUM_ROWS * NUM_BLOCKS * COEFF_WIDTH - 1 : 0] i_block_weights;
    reg  [ACC_WIDTH - 1 : 0] i_eta;
    wire o_valid;
    wire [NUM_BLOCKS * BOUND_WIDTH - 1 : 0] o_block_bounds;
    wire o_certified;
    wire [ACC_WIDTH - 1 : 0] o_max_error;

    online_row_cluster_block_cert #(
        .num_rows(NUM_ROWS),
        .block_size(BLOCK_SIZE),
        .bound_width(BOUND_WIDTH),
        .coeff_width(COEFF_WIDTH),
        .acc_width(ACC_WIDTH),
        .num_blocks(NUM_BLOCKS)
    ) dut (
        .i_clk(i_clk),
        .i_rst(i_rst),
        .i_valid_rows(i_valid_rows),
        .i_row_abs_upper(i_row_abs_upper),
        .i_block_weights(i_block_weights),
        .i_eta(i_eta),
        .o_valid(o_valid),
        .o_block_bounds(o_block_bounds),
        .o_certified(o_certified),
        .o_max_error(o_max_error)
    );

    always #5 i_clk = ~i_clk;

    task wait_case;
        input expected_certified;
        input [ACC_WIDTH - 1 : 0] expected_max_error;
        integer wi;
        reg seen_valid;
        begin
            seen_valid = 1'b0;
            for (wi = 0; wi < 8; wi = wi + 1) begin
                @(posedge i_clk);
                if (o_valid) begin
                    seen_valid = 1'b1;
                    if (o_certified !== expected_certified ||
                        o_block_bounds !== {8'd11, 8'd7} ||
                        o_max_error !== expected_max_error) begin
                        $display("ERROR tb_online_row_cluster_block_cert valid=%b cert=%b bounds=%h max=%0d",
                            o_valid, o_certified, o_block_bounds, o_max_error);
                        $fatal;
                    end
                    wi = 8;
                end
            end
            if (!seen_valid) begin
                $display("ERROR tb_online_row_cluster_block_cert no valid");
                $fatal;
            end
        end
    endtask

    initial begin
        i_clk = 1'b0;
        i_rst = 1'b1;
        i_valid_rows = 4'b0000;
        // row upper bounds: [7, 3, 5, 11]
        // block maxima for BLOCK_SIZE=2 => [7, 11]
        i_row_abs_upper = {8'd11, 8'd5, 8'd3, 8'd7};

        // weights packed row-major:
        // row0: [1,2] => 7*1 + 11*2 = 29
        // row1: [2,1] => 7*2 + 11*1 = 25
        // row2: [1,1] => 18
        // row3: [3,0] => 21
        i_block_weights = {
            8'd0, 8'd3,
            8'd1, 8'd1,
            8'd1, 8'd2,
            8'd2, 8'd1
        };

        i_eta = 24'd29;
        repeat (2) @(posedge i_clk);
        i_rst <= 1'b0;
        @(posedge i_clk);
        i_valid_rows <= 4'b1111;
        @(posedge i_clk);
        i_valid_rows <= 4'b0000;
        wait_case(1'b1, 24'd29);

        i_eta = 24'd28;
        @(posedge i_clk);
        i_valid_rows <= 4'b1111;
        @(posedge i_clk);
        i_valid_rows <= 4'b0000;
        wait_case(1'b0, 24'd29);

        $display("PASS tb_online_row_cluster_block_cert");
        $finish;
    end
endmodule
