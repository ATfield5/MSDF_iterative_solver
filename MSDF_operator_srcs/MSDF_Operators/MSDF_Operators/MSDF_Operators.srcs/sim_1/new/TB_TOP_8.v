`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2025/06/26 19:58:24
// Design Name: 
// Module Name: TB_TOP_8
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


module TB_TOP_8(

    );

    reg i_clk;

    initial i_clk = 0;
    always #10 i_clk = ~i_clk;

    reg i_rst;

    initial begin
        i_rst = 1;

        #500
        i_rst = 0;
    end

    wire o_z_p;
    wire o_z_n;
    
    wire o_int ;
    wire o_unit;
    wire o_frac;

    top_test_8 u_top_test_8(
        .i_clk  (i_clk  ),
        .i_rst  (i_rst  ),
        .o_z_p  (o_z_p  ),
        .o_z_n  (o_z_n  ),
        .o_int  (o_int  ),
        .o_unit (o_unit ),
        .o_frac (o_frac )
    );

endmodule
