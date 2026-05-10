`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2025/06/25 19:25:26
// Design Name: 
// Module Name: DFF
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


module DFF #(
    parameter bit_width = 8
)
(
    input                          i_clk ,
    input                          i_rst ,
    input                          i_ena ,
    input      [bit_width - 1 : 0] i_data,
    output reg [bit_width - 1 : 0] o_data
    );

    always @(posedge i_clk) begin
        if(i_rst) begin
            o_data <= 0;
        end
        else if (i_ena) begin
            o_data <= i_data;
        end
        else begin
            o_data <= o_data;
        end
    end

endmodule
