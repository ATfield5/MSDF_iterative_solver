`timescale 1ns / 1ps

module iter_dff #(
    parameter bit_width = 8
) (
    input                          i_clk,
    input                          i_rst,
    input                          i_ena,
    input      [bit_width - 1 : 0] i_data,
    output reg [bit_width - 1 : 0] o_data
);

    always @(posedge i_clk) begin
        if (i_rst) begin
            o_data <= {bit_width{1'b0}};
        end else if (i_ena) begin
            o_data <= i_data;
        end
    end

endmodule
