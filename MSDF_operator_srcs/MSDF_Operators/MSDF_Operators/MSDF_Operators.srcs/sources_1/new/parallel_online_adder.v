`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2025/06/25 19:21:04
// Design Name: 
// Module Name: parallel_online_adder
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


module parallel_online_adder #(
    parameter bit_width = 8
)
(
    input  [bit_width - 1 : 0] i_x_p,
    input  [bit_width - 1 : 0] i_x_n,
    input  [bit_width - 1 : 0] i_y_p,
    input  [bit_width - 1 : 0] i_y_n,
    input                      i_c_p,
    input                      i_c_n,
    output [bit_width - 1 : 0] o_z_p,
    output [bit_width - 1 : 0] o_z_n,
    output                     o_c_p,
    output                     o_c_n
    );

    wire [bit_width - 1 : 0] t_i_c_p_vec;
    wire [bit_width - 1 : 0] t_o_c_p_vec;
    wire [bit_width - 1 : 0] t_o_c_n_vec;
    
    assign o_c_p = t_o_c_p_vec[bit_width - 1];
    assign o_c_n = t_o_c_n_vec[bit_width - 1];
    
    assign o_z_n[bit_width - 1 : 1] = t_o_c_n_vec[bit_width - 2 : 0];
    assign o_z_n[0]                 = i_c_n;
    
    assign t_i_c_p_vec[bit_width - 1 : 1] = t_o_c_p_vec[bit_width - 2 : 0];
    assign t_i_c_p_vec[0]                 = i_c_p;
    
    genvar i;
    
    generate
        for (i = 0; i < bit_width; i = i + 1) begin
            parallel_online_adder_block POAB(
                .i_x_p (i_x_p[i]      ),
                .i_x_n (i_x_n[i]      ),
                .i_y_p (i_y_p[i]      ),
                .i_y_n (i_y_n[i]      ),
                .i_c_p (t_i_c_p_vec[i]),
                .o_c_p (t_o_c_p_vec[i]),
                .o_c_n (t_o_c_n_vec[i]),
                .o_z_p (o_z_p[i]      )
            );
        end
    endgenerate

endmodule
