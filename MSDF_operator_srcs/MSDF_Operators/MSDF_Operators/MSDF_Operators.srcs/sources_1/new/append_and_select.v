`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2025/06/25 19:46:19
// Design Name: 
// Module Name: append_and_select
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


module append_and_select #(
    parameter bit_width = 8
)
(
    input  i_clk,
    input  i_rst,
    input  i_ena,

    input  i_x_p,
    input  i_x_n,
    input  i_y_p,
    input  i_y_n,

    output [bit_width - 1 : 0] o_vec_x_p,
    output [bit_width - 1 : 0] o_vec_x_n,
    output [bit_width - 1 : 0] o_vec_y_p,
    output [bit_width - 1 : 0] o_vec_y_n,

    output o_valid
    );

    wire w_x_p;
    wire w_x_n;
    wire w_y_p;
    wire w_y_n;

    wire [bit_width - 1 : 0] w_vec_x_p;
    wire [bit_width - 1 : 0] w_vec_x_n;
    wire [bit_width - 1 : 0] w_vec_y_p;
    wire [bit_width - 1 : 0] w_vec_y_n;

    wire w_full;

    vector_append #(
        .bit_width (bit_width)
    )
    VA(
        .i_clk     (i_clk),
        .i_rst     (i_rst),
        .i_ena     (i_ena),

        .i_x_p     (i_x_p),
        .i_x_n     (i_x_n),
        .i_y_p     (i_y_p),
        .i_y_n     (i_y_n),

        .o_x_p     (w_x_p),
        .o_x_n     (w_x_n),
        .o_y_p     (w_y_p),
        .o_y_n     (w_y_n),

        .o_vec_x_p (w_vec_x_p),
        .o_vec_x_n (w_vec_x_n),
        .o_vec_y_p (w_vec_y_p),
        .o_vec_y_n (w_vec_y_n),

        .o_valid   (o_valid),
        .o_full    (w_full )
    );

    wire w_sel_ena;

    assign w_sel_ena = o_valid;

    selector #(
        .bit_width (bit_width)
    )
    SEL_X(
        .i_ena    (w_sel_ena     ),
        .i_sel    ({w_y_p, w_y_n}),
        .i_data_p (w_vec_x_p     ),
        .i_data_n (w_vec_x_n     ),
        .o_data_p (o_vec_x_p     ),
        .o_data_n (o_vec_x_n     )
    );

    selector #(
        .bit_width (bit_width)
    )
    SEL_Y(
        .i_ena    (w_sel_ena     ),
        .i_sel    ({w_x_p, w_x_n}),
        .i_data_p (w_vec_y_p     ),
        .i_data_n (w_vec_y_n     ),
        .o_data_p (o_vec_y_p     ),
        .o_data_n (o_vec_y_n     )
    );

endmodule
