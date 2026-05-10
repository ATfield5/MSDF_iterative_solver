`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2025/06/25 19:18:38
// Design Name: 
// Module Name: parallel_online_adder_block
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


module parallel_online_adder_block(
    input  i_x_p,
    input  i_x_n,
    input  i_y_p,
    input  i_y_n,
    input  i_c_p,
    output o_c_p,
    output o_c_n,
    output o_z_p
    );

    wire t_s  ;
    wire t_c_n;
    
    full_adder FA_0(
        .i_a (i_x_p ),
        .i_b (~i_x_n),
        .i_c (i_y_p ),
        .o_c (o_c_p ),
        .o_s (t_s   )
    );
    
    full_adder FA_1(
        .i_a (t_s   ),
        .i_b (~i_y_n),
        .i_c (i_c_p ),
        .o_c (t_c_n ),
        .o_s (o_z_p )
    );
    
    assign o_c_n = ~t_c_n;

endmodule
