`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2025/06/26 16:09:32
// Design Name: 
// Module Name: TB_MM
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


module TB_MM(

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

    reg r_rst;
    reg r_ena;
    
    reg r_x_p;
    reg r_x_n;
    reg r_y_p;
    reg r_y_n;

    wire o_z_p;
    wire o_z_n;
    
    wire o_int ;
    wire o_unit;
    wire o_frac;

    MSDF_MUL #(
        .bit_width (8)
    )
    MM(
        .i_clk  (i_clk ),
        .i_rst  (r_rst ),
        .i_ena  (r_ena ),

        .i_x_p  (r_x_p ),
        .i_x_n  (r_x_n ),
        .i_y_p  (r_y_p ),
        .i_y_n  (r_y_n ),

        .o_z_p  (o_z_p ),
        .o_z_n  (o_z_n ),
        
        .o_int  (o_int ),
        .o_unit (o_unit),
        .o_frac (o_frac)
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
            // end

            // 10 : begin
            //     r_x_p <= 1;
            //     r_x_n <= 0;
            //     r_y_p <= 0;
            //     r_y_n <= 1;
            // end

            8, 9, 10, 11, 12, 13, 14, 15 : begin
                r_x_p <= 1;
                r_x_n <= 0;
                r_y_p <= 1;
                r_y_n <= 0;
            end

            default : begin
                r_x_p <= 0;
                r_x_n <= 0;
                r_y_p <= 0;
                r_y_n <= 0;
            end
        endcase
    end

endmodule
