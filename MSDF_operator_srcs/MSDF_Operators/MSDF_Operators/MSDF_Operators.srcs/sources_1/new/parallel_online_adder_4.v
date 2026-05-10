`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2025/06/26 16:46:57
// Design Name: 
// Module Name: parallel_online_adder_4
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


module parallel_online_adder_4 #(
    parameter bit_width = 8
)
(
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

    wire [bit_width - 1 : 0] t0_0_p;
    wire [bit_width - 1 : 0] t0_0_n;
    wire                     c0_0_p;
    wire                     c0_0_n;

    wire [bit_width - 1 : 0] t0_1_p;
    wire [bit_width - 1 : 0] t0_1_n;
    wire                     c0_1_p;
    wire                     c0_1_n;

    parallel_online_adder #(
        .bit_width (bit_width)
    )
    POA_0_0(
        .i_x_p (i_x0_p),
        .i_x_n (i_x0_n),
        .i_y_p (i_x1_p),
        .i_y_n (i_x1_n),
        .i_c_p (1'b0  ),
        .i_c_n (1'b0  ),
        .o_z_p (t0_0_p),
        .o_z_n (t0_0_n),
        .o_c_p (c0_0_p),
        .o_c_n (c0_0_n)
    );

    parallel_online_adder #(
        .bit_width (bit_width)
    )
    POA_0_1(
        .i_x_p (i_x2_p),
        .i_x_n (i_x2_n),
        .i_y_p (i_x3_p),
        .i_y_n (i_x3_n),
        .i_c_p (1'b0  ),
        .i_c_n (1'b0  ),
        .o_z_p (t0_1_p),
        .o_z_n (t0_1_n),
        .o_c_p (c0_1_p),
        .o_c_n (c0_1_n)
    );

    wire [bit_width : 0] t1_0_p;
    wire [bit_width : 0] t1_0_n;
    
    wire [bit_width : 0] t1_1_p;
    wire [bit_width : 0] t1_1_n;

    assign t1_0_p = {c0_0_p, t0_0_p};
    assign t1_0_n = {c0_0_n, t0_0_n};

    assign t1_1_p = {c0_1_p, t0_1_p};
    assign t1_1_n = {c0_1_n, t0_1_n};

    parallel_online_adder #(
        .bit_width (bit_width + 1)
    )
    POA_1(
        .i_x_p (t1_0_p),
        .i_x_n (t1_0_n),
        .i_y_p (t1_1_p),
        .i_y_n (t1_1_n),
        .i_c_p (1'b0  ),
        .i_c_n (1'b0  ),

        .o_z_p (o_z_p[bit_width : 0]),
        .o_z_n (o_z_n[bit_width : 0]),
        .o_c_p (o_z_p[bit_width + 1]),
        .o_c_n (o_z_n[bit_width + 1])
    );

endmodule
