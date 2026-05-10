`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2025/06/26 20:30:40
// Design Name: 
// Module Name: parallel_online_adder_4_with_obuf
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////


module parallel_online_adder_4_with_obuf #(
    parameter bit_width = 8
)
(
    input  i_clk,
    input  i_rst,
    input  i_ena,

    input  [bit_width - 1 : 0] i_x0_p,
    input  [bit_width - 1 : 0] i_x0_n,
    input  [bit_width - 1 : 0] i_x1_p,
    input  [bit_width - 1 : 0] i_x1_n,
    input  [bit_width - 1 : 0] i_x2_p,
    input  [bit_width - 1 : 0] i_x2_n,
    input  [bit_width - 1 : 0] i_x3_p,
    input  [bit_width - 1 : 0] i_x3_n,

    output [bit_width + 1 : 0] o_z_p,
    output [bit_width + 1 : 0] o_z_n
    );

    wire [bit_width + 1 : 0] w_sum_p;
    wire [bit_width + 1 : 0] w_sum_n;

    wire [bit_width + 1 : 0] w_sum_p_reg;
    wire [bit_width + 1 : 0] w_sum_n_reg;

    parallel_online_adder_4 #(
        .bit_width (bit_width)
    )
    POA4(
        .i_x0_p (i_x0_p),
        .i_x0_n (i_x0_n),
        .i_x1_p (i_x1_p),
        .i_x1_n (i_x1_n),
        .i_x2_p (i_x2_p),
        .i_x2_n (i_x2_n),
        .i_x3_p (i_x3_p),
        .i_x3_n (i_x3_n),

        .o_z_p  (w_sum_p),
        .o_z_n  (w_sum_n)
    );

    DFF #(
        .bit_width (bit_width + 2)
    )
    DFF_SUM_P(
        .i_clk  (i_clk),
        .i_rst  (i_rst),
        .i_ena  (i_ena),

        .i_data (w_sum_p    ),
        .o_data (w_sum_p_reg)
    );

    DFF #(
        .bit_width (bit_width + 2)
    )
    DFF_SUM_N(
        .i_clk  (i_clk),
        .i_rst  (i_rst),
        .i_ena  (i_ena),

        .i_data (w_sum_n    ),
        .o_data (w_sum_n_reg)
    );

    assign o_z_p = w_sum_p_reg;
    assign o_z_n = w_sum_n_reg;

endmodule
