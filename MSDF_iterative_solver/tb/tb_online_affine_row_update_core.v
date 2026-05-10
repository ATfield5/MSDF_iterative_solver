`timescale 1ns / 1ps

module tb_online_affine_row_update_core;
    localparam integer BIT_WIDTH = 8;

    reg i_clk;
    reg i_rst;
    reg i_ena;
    reg i_x0_p, i_x0_n;
    reg i_x1_p, i_x1_n;
    reg i_x2_p, i_x2_n;
    reg i_x3_p, i_x3_n;
    reg [BIT_WIDTH-1:0] i_coeff0_vec_p, i_coeff0_vec_n;
    reg [BIT_WIDTH-1:0] i_coeff1_vec_p, i_coeff1_vec_n;
    reg [BIT_WIDTH-1:0] i_coeff2_vec_p, i_coeff2_vec_n;
    reg [BIT_WIDTH-1:0] i_coeff3_vec_p, i_coeff3_vec_n;
    reg [BIT_WIDTH+1:0] i_bias_vec_p, i_bias_vec_n;
    wire o_valid;
    wire [BIT_WIDTH+2:0] o_sum_p;
    wire [BIT_WIDTH+2:0] o_sum_n;
    integer seen_valid;

    online_affine_row_update_core #(.bit_width(BIT_WIDTH)) dut (
        .i_clk(i_clk), .i_rst(i_rst), .i_ena(i_ena),
        .i_x0_p(i_x0_p), .i_x0_n(i_x0_n),
        .i_x1_p(i_x1_p), .i_x1_n(i_x1_n),
        .i_x2_p(i_x2_p), .i_x2_n(i_x2_n),
        .i_x3_p(i_x3_p), .i_x3_n(i_x3_n),
        .i_coeff0_vec_p(i_coeff0_vec_p), .i_coeff0_vec_n(i_coeff0_vec_n),
        .i_coeff1_vec_p(i_coeff1_vec_p), .i_coeff1_vec_n(i_coeff1_vec_n),
        .i_coeff2_vec_p(i_coeff2_vec_p), .i_coeff2_vec_n(i_coeff2_vec_n),
        .i_coeff3_vec_p(i_coeff3_vec_p), .i_coeff3_vec_n(i_coeff3_vec_n),
        .i_bias_vec_p(i_bias_vec_p), .i_bias_vec_n(i_bias_vec_n),
        .o_valid(o_valid), .o_sum_p(o_sum_p), .o_sum_n(o_sum_n)
    );

    always #5 i_clk = ~i_clk;

    initial begin
        i_clk = 1'b0;
        i_rst = 1'b1;
        i_ena = 1'b0;
        i_x0_p = 0; i_x0_n = 0;
        i_x1_p = 0; i_x1_n = 0;
        i_x2_p = 0; i_x2_n = 0;
        i_x3_p = 0; i_x3_n = 0;
        i_coeff0_vec_p = 8'b00000101; i_coeff0_vec_n = 8'b0;
        i_coeff1_vec_p = 8'b00000011; i_coeff1_vec_n = 8'b0;
        i_coeff2_vec_p = 8'b00000001; i_coeff2_vec_n = 8'b0;
        i_coeff3_vec_p = 8'b00000010; i_coeff3_vec_n = 8'b0;
        i_bias_vec_p   = 10'b0000000001; i_bias_vec_n = 10'b0;

        repeat (2) @(posedge i_clk);
        i_rst <= 1'b0;
        @(posedge i_clk);
        i_ena  <= 1'b1;
        i_x0_p <= 1'b1; i_x0_n <= 1'b0;
        i_x1_p <= 1'b1; i_x1_n <= 1'b0;
        i_x2_p <= 1'b0; i_x2_n <= 1'b0;
        i_x3_p <= 1'b1; i_x3_n <= 1'b0;

        @(posedge i_clk);
        i_ena <= 1'b0;
        i_x0_p <= 1'b0; i_x0_n <= 1'b0;
        i_x1_p <= 1'b0; i_x1_n <= 1'b0;
        i_x2_p <= 1'b0; i_x2_n <= 1'b0;
        i_x3_p <= 1'b0; i_x3_n <= 1'b0;

        seen_valid = 0;
        repeat (6) begin
            @(posedge i_clk);
            if (o_valid) begin
                seen_valid = 1;
                if ((^o_sum_p === 1'bx) || (^o_sum_n === 1'bx)) begin
                    $display("ERROR tb_online_affine_row_update_core unknown output");
                    $fatal;
                end
                $display("PASS tb_online_affine_row_update_core o_sum_p=%b o_sum_n=%b", o_sum_p, o_sum_n);
                $finish;
            end
        end

        if (!seen_valid) begin
            $display("ERROR tb_online_affine_row_update_core no valid output");
            $fatal;
        end
    end
endmodule
