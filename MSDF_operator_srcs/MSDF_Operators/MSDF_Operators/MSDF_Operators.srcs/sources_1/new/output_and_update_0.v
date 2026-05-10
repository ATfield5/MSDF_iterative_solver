`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2025/06/26 15:54:24
// Design Name: 
// Module Name: output_and_update_0
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


module output_and_update_0(
    input [3 : 0] i_v_p_4msd,
    input [3 : 0] i_v_n_4msd,

    output [2 : 0] o_w_p_3msd,
    output [2 : 0] o_w_n_3msd,

    output reg o_z_p,
    output reg o_z_n
    );

    wire [3 : 0] w_v_value ;
    wire [2 : 0] w_v_sample;

    assign w_v_value  = i_v_p_4msd - i_v_n_4msd;
    assign w_v_sample = w_v_value[3 : 1];

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

    reg [3 : 0] r_w_update;

    always @(*) begin
        case ({o_z_p, o_z_n})
            2'b10 : begin
                r_w_update[3 : 2] = w_v_value[3 : 2] - 1;
            end

            2'b01 : begin
                r_w_update[3 : 2] = w_v_value[3 : 2] + 1;
            end

            default : begin
                r_w_update[3 : 2] = w_v_value[3 : 2];
            end
        endcase

        r_w_update[1 : 0] = w_v_value[1 : 0];
    end

    wire w_w_sgn;

    assign w_w_sgn = r_w_update[3];

    reg [2 : 0] r_w_mag;

    always @(*) begin
        if (w_w_sgn) begin
            r_w_mag = ~r_w_update[2 : 0] + 1;
        end
        else begin
            r_w_mag = r_w_update[2 : 0];
        end
    end

    assign o_w_p_3msd = w_w_sgn ? 3'd0    : r_w_mag;
    assign o_w_n_3msd = w_w_sgn ? r_w_mag : 3'd0   ;

endmodule
