`timescale 1ns / 1ps

module tb_iter_streamed_bias_source;
    localparam integer BIAS_WIDTH = 4;
    localparam integer STREAM_WIDTH = 6;
    localparam integer DIGIT_IDX_WIDTH = $clog2(STREAM_WIDTH);

    reg i_valid;
    reg [DIGIT_IDX_WIDTH-1:0] i_digit_idx;
    reg [BIAS_WIDTH-1:0] i_bias_p;
    reg [BIAS_WIDTH-1:0] i_bias_n;
    wire o_valid;
    wire o_bias_digit_p;
    wire o_bias_digit_n;

    iter_streamed_bias_source #(
        .bias_width(BIAS_WIDTH),
        .stream_width(STREAM_WIDTH),
        .msb_first(1),
        .digit_idx_width(DIGIT_IDX_WIDTH)
    ) dut (
        .i_valid(i_valid),
        .i_digit_idx(i_digit_idx),
        .i_bias_p(i_bias_p),
        .i_bias_n(i_bias_n),
        .o_valid(o_valid),
        .o_bias_digit_p(o_bias_digit_p),
        .o_bias_digit_n(o_bias_digit_n)
    );

    task automatic check_digit;
        input integer idx;
        input expected_p;
        input expected_n;
        begin
            i_valid = 1'b1;
            i_digit_idx = idx[DIGIT_IDX_WIDTH-1:0];
            #1;
            if (!o_valid || o_bias_digit_p !== expected_p || o_bias_digit_n !== expected_n) begin
                $display("ERROR bias digit idx=%0d got valid=%0d p=%0d n=%0d expected p=%0d n=%0d",
                    idx, o_valid, o_bias_digit_p, o_bias_digit_n, expected_p, expected_n);
                $fatal;
            end
        end
    endtask

    initial begin
        i_valid = 1'b0;
        i_digit_idx = {DIGIT_IDX_WIDTH{1'b0}};
        i_bias_p = 4'b1010;
        i_bias_n = 4'b0101;
        #1;
        if (o_valid || o_bias_digit_p || o_bias_digit_n) begin
            $display("ERROR bias source should be idle when invalid");
            $fatal;
        end

        check_digit(0, 1'b0, 1'b0);
        check_digit(1, 1'b0, 1'b0);
        check_digit(2, 1'b1, 1'b0);
        check_digit(3, 1'b0, 1'b1);
        check_digit(4, 1'b1, 1'b0);
        check_digit(5, 1'b0, 1'b1);

        $display("PASS tb_iter_streamed_bias_source");
        $finish;
    end
endmodule
