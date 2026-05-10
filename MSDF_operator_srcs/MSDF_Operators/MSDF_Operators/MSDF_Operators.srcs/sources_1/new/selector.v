`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2025/06/25 19:26:50
// Design Name: 
// Module Name: selector
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


module selector #(
    parameter bit_width = 8
)
(
    input                          i_ena   ,
    input      [            1 : 0] i_sel   ,
    input      [bit_width - 1 : 0] i_data_p,
    input      [bit_width - 1 : 0] i_data_n,
    output reg [bit_width - 1 : 0] o_data_p,
    output reg [bit_width - 1 : 0] o_data_n
    );

    always @(*) begin
        if (i_ena) begin
            case (i_sel)
                2'b10: begin
                    o_data_p = i_data_p;
                    o_data_n = i_data_n;
                end
                2'b01: begin
                    o_data_p = ~i_data_p;
                    o_data_n = ~i_data_n;
                end
                2'b00, 2'b11: begin
                    o_data_p = 0;
                    o_data_n = 0;
                end
            endcase
        end
        else begin
            o_data_p = 0;
            o_data_n = 0;
        end
    end

endmodule
