`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2025/06/25 23:44:20
// Design Name: 
// Module Name: serial_online_adder_block
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


module serial_online_adder_block(
    input  i_xj3_p,
    input  i_xj3_n,
    input  i_yj3_p,
    input  i_yj2_n,

    output o_t_sj3,
    input  i_t_sj2,

    output o_zj1_n,
    output o_zj2_p
    );

    wire t_cj2;
    wire t_cj1;
    wire t_sj3;
    
    full_adder FA_0(
    .i_a(i_xj3_p),
    .i_b(~i_xj3_n),
    .i_c(i_yj3_p),
    .o_c(t_cj2),
    .o_s(t_sj3)
    );

    assign o_t_sj3 = ~t_sj3;
    
    full_adder FA_1(
    .i_a(~i_t_sj2),
    .i_b(~i_yj2_n),
    .i_c(t_cj2),
    .o_c(t_cj1),
    .o_s(o_zj2_p)
    );
    
    assign o_zj1_n = ~t_cj1;

endmodule
