`timescale 1ns / 1ps

module iter_full_adder(
    input  i_a,
    input  i_b,
    input  i_c,
    output o_c,
    output o_s
);

    assign {o_c, o_s} = i_a + i_b + i_c;

endmodule
