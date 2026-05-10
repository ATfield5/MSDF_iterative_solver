`timescale 1ns / 1ps

module tb_iter_signed_rail_codec;
    localparam integer RAIL_WIDTH = 11;
    localparam integer BIN_WIDTH = RAIL_WIDTH + 1;

    reg signed [BIN_WIDTH - 1 : 0] i_value;
    wire [RAIL_WIDTH - 1 : 0] value_p;
    wire [RAIL_WIDTH - 1 : 0] value_n;
    wire signed [BIN_WIDTH - 1 : 0] roundtrip_value;

    iter_signed_to_rail #(
        .in_width(BIN_WIDTH),
        .rail_width(RAIL_WIDTH)
    ) to_rail (
        .i_value(i_value),
        .o_value_p(value_p),
        .o_value_n(value_n)
    );

    iter_rail_to_signed #(
        .rail_width(RAIL_WIDTH),
        .out_width(BIN_WIDTH)
    ) to_signed (
        .i_value_p(value_p),
        .i_value_n(value_n),
        .o_value(roundtrip_value)
    );

    task check_value;
        input signed [BIN_WIDTH - 1 : 0] value;
        begin
            i_value = value;
            #1;
            if (roundtrip_value !== value) begin
                $display("ERROR codec value=%0d p=%0d n=%0d roundtrip=%0d",
                    value, value_p, value_n, roundtrip_value);
                $fatal;
            end
        end
    endtask

    initial begin
        check_value(12'sd0);
        check_value(12'sd1);
        check_value(-12'sd1);
        check_value(12'sd37);
        check_value(-12'sd37);
        check_value(12'sd1023);
        check_value(-12'sd1023);
        $display("PASS tb_iter_signed_rail_codec");
        $finish;
    end
endmodule
