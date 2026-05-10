`timescale 1ns / 1ps

module tb_online_const_coeff_contrib;
    localparam integer BIT_WIDTH = 8;

    reg  i_digit_p;
    reg  i_digit_n;
    reg  [BIT_WIDTH-1:0] i_coeff_vec_p;
    reg  [BIT_WIDTH-1:0] i_coeff_vec_n;
    wire [BIT_WIDTH-1:0] o_vec_p;
    wire [BIT_WIDTH-1:0] o_vec_n;

    online_const_coeff_contrib #(.bit_width(BIT_WIDTH)) dut (
        .i_digit_p(i_digit_p),
        .i_digit_n(i_digit_n),
        .i_coeff_vec_p(i_coeff_vec_p),
        .i_coeff_vec_n(i_coeff_vec_n),
        .o_vec_p(o_vec_p),
        .o_vec_n(o_vec_n)
    );

    task check_vec;
        input [1:0] digit;
        input [BIT_WIDTH-1:0] exp_p;
        input [BIT_WIDTH-1:0] exp_n;
        begin
            {i_digit_p, i_digit_n} = digit;
            #1;
            if (o_vec_p !== exp_p || o_vec_n !== exp_n) begin
                $display("ERROR tb_online_const_coeff_contrib digit=%b got p=%b n=%b exp p=%b n=%b",
                         digit, o_vec_p, o_vec_n, exp_p, exp_n);
                $fatal;
            end
        end
    endtask

    initial begin
        i_coeff_vec_p = 8'b01011010;
        i_coeff_vec_n = 8'b00000101;

        check_vec(2'b10, i_coeff_vec_p, i_coeff_vec_n);
        check_vec(2'b01, ~i_coeff_vec_p, ~i_coeff_vec_n);
        check_vec(2'b00, 8'b0, 8'b0);
        check_vec(2'b11, 8'b0, 8'b0);

        $display("PASS tb_online_const_coeff_contrib");
        $finish;
    end
endmodule
