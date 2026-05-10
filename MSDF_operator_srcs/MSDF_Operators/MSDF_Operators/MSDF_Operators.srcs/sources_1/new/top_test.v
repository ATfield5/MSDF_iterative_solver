`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2025/06/25 22:44:25
// Design Name: 
// Module Name: top_test
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


module top_test(
    input i_clk,
    input i_rst,

    output reg o_z_p,
    output reg o_z_n,

    output reg o_int ,
    output reg o_unit,
    output reg o_frac
    );

    reg r_rst;
    reg r_ena;
    
    reg r_x_p;
    reg r_x_n;
    reg r_y_p;
    reg r_y_n;

    reg r_a_p;
    reg r_a_n;

    wire w_z_p;
    wire w_z_n;
    
    wire w_int ;
    wire w_unit;
    wire w_frac;

    MSDF_MUL_ADD #(
        .bit_width (8)
    )
    MMA(
        .i_clk  (i_clk ),
        .i_rst  (r_rst ),
        .i_ena  (r_ena ),

        .i_x_p  (r_x_p ),
        .i_x_n  (r_x_n ),
        .i_y_p  (r_y_p ),
        .i_y_n  (r_y_n ),
        .i_a_p  (r_a_p ),
        .i_a_n  (r_a_n ),

        .o_z_p  (w_z_p ),
        .o_z_n  (w_z_n ),
        
        .o_int  (w_int ),
        .o_unit (w_unit),
        .o_frac (w_frac)
    );

    reg [5 : 0] cnt;

    always @(posedge i_clk) begin
        if (i_rst) begin
            cnt <= 0;
        end
        else begin
            cnt <= cnt + 1;
        end
    end

    always @(posedge i_clk) begin
        if (cnt < 8) begin
            r_rst <= 1;
            r_ena <= 0;
        end
        else if (cnt < 32) begin
            r_rst <= 0;
            r_ena <= 1;
        end
        else begin
            r_rst <= 1;
            r_ena <= 0;
        end
    end

    always @(posedge i_clk) begin
        case (cnt)
            // 8, 9 : begin
            //     r_x_p <= 1;
            //     r_x_n <= 0;
            //     r_y_p <= 0;
            //     r_y_n <= 1;

            //     r_a_p <= 0;
            //     r_a_n <= 1;
            // end

            // 10 : begin
            //     r_x_p <= 1;
            //     r_x_n <= 0;
            //     r_y_p <= 0;
            //     r_y_n <= 1;

            //     r_a_p <= 0;
            //     r_a_n <= 0;
            // end

            8, 9, 10, 11, 12, 13, 14, 15 : begin
                r_x_p <= 1;
                r_x_n <= 0;
                r_y_p <= 1;
                r_y_n <= 0;

                r_a_p <= 1;
                r_a_n <= 0;
            end

            default : begin
                r_x_p <= 0;
                r_x_n <= 0;
                r_y_p <= 0;
                r_y_n <= 0;

                r_a_p <= 0;
                r_a_n <= 0;
            end
        endcase
    end

    always @(posedge i_clk) begin
        if (i_rst) begin
            o_z_p <= 0;
            o_z_n <= 0;

            o_int  <= 0;
            o_unit <= 0;
            o_frac <= 0;
        end
        else begin
            o_z_p <= w_z_p;
            o_z_n <= w_z_n;

            o_int  <= w_int ;
            o_unit <= w_unit;
            o_frac <= w_frac;
        end
    end

endmodule
