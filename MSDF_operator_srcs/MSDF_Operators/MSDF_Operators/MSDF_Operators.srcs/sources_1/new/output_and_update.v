`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2025/06/25 19:48:41
// Design Name: 
// Module Name: output_and_update
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


module output_and_update(
    input [4 : 0] i_v_p_5msd,
    input [4 : 0] i_v_n_5msd,

    output [3 : 0] o_w_p_4msd,
    output [3 : 0] o_w_n_4msd,

    output reg o_z_p,
    output reg o_z_n
    );

    wire [4 : 0] w_v_value ;
    wire [2 : 0] w_v_sample;

    assign w_v_value  = i_v_p_5msd - i_v_n_5msd;
    assign w_v_sample = w_v_value[4 : 2];

    always @(*) begin
        case (w_v_sample)
            3'b011, 3'b010, 3'b001 : begin
                o_z_p = 1'b1;
                o_z_n = 1'b0;
            end

            3'b000, 3'b111 : begin
                o_z_p = 1'b0;
                o_z_n = 1'b0;
            end
            
            3'b110, 3'b101, 3'b100 : begin
                o_z_p = 1'b0;
                o_z_n = 1'b1;
            end
        endcase
    end

    reg [4 : 0] r_w_update;

    always @(*) begin
        case ({o_z_p, o_z_n})
            2'b10 : begin
                r_w_update[4 : 3] = w_v_value[4 : 3] - 1;
            end

            2'b01 : begin
                r_w_update[4 : 3] = w_v_value[4 : 3] + 1;
            end

            default : begin
                r_w_update[4 : 3] = w_v_value[4 : 3];
            end
        endcase

        r_w_update[2 : 0] = w_v_value[2 : 0];
    end

    wire w_w_sgn;

    assign w_w_sgn = r_w_update[4];

    reg [3 : 0] r_w_mag;

    always @(*) begin
        if (w_w_sgn) begin
            r_w_mag = ~r_w_update[3 : 0] + 1;
        end
        else begin
            r_w_mag = r_w_update[3 : 0];
        end
    end

    assign o_w_p_4msd = w_w_sgn ? 4'd0    : r_w_mag;
    assign o_w_n_4msd = w_w_sgn ? r_w_mag : 4'd0   ;

endmodule
