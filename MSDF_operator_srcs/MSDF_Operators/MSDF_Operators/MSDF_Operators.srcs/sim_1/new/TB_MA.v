`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2025/06/26 00:29:37
// Design Name: 
// Module Name: TB_MA
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


module TB_MA(

    );

    reg i_clk;
    reg i_rst;
    reg i_ena;

    reg i_x_p;
    reg i_x_n;
    reg i_y_p;
    reg i_y_n;

    reg i_dot;

    wire o_z_p;
    wire o_z_n;

    wire o_valid;
    wire o_dot;

    MSDF_ADD u_MSDF_ADD(
        .i_clk   (i_clk  ),
        .i_rst   (i_rst  ),
        .i_ena   (i_ena  ),

        .i_x_p   (i_x_p  ),
        .i_x_n   (i_x_n  ),
        .i_y_p   (i_y_p  ),
        .i_y_n   (i_y_n  ),

        .i_dot   (i_dot  ),

        .o_z_p   (o_z_p  ),
        .o_z_n   (o_z_n  ),

        .o_valid (o_valid),
        .o_dot   (o_dot  )
    );

    initial i_clk = 0;
    always #10 i_clk = ~i_clk;

    initial begin
        i_rst = 1;

        #200
        i_rst = 0;
    end

    reg [4 : 0] cnt;

    always @(posedge i_clk) begin
        if (i_rst) begin
            cnt <= 0;
        end
        else begin
            cnt <= cnt + 1;
        end
    end

    always @(posedge i_clk) begin
        if (i_rst) begin
            i_ena <= 0;
        end
        else if ((cnt >= 8) && (cnt < 16 + 2)) begin
            i_ena <= 1;
        end
        else begin
            i_ena <= 0;
        end
    end

    always @(posedge i_clk) begin
        case (cnt)
            // 8, 9, 10, 11, 12, 13, 14, 15 : begin
            //     i_x_p <= 1;
            //     i_x_n <= 0;
            //     i_y_p <= 1;
            //     i_y_n <= 0;
            // end

            8 : begin
                i_x_p <= 1;
                i_x_n <= 0;
                i_y_p <= 1;
                i_y_n <= 0;
            end

            9 : begin
                i_x_p <= 0;
                i_x_n <= 0;
                i_y_p <= 1;
                i_y_n <= 0;
            end

            10 : begin
                i_x_p <= 0;
                i_x_n <= 0;
                i_y_p <= 0;
                i_y_n <= 1;
            end

            11 : begin
                i_x_p <= 1;
                i_x_n <= 0;
                i_y_p <= 1;
                i_y_n <= 0;
            end

            default : begin
                i_x_p <= 0;
                i_x_n <= 0;
                i_y_p <= 0;
                i_y_n <= 0;
            end
        endcase
    end

    always @(posedge i_clk) begin
        case (cnt)
            9 : begin
                i_dot <= 1;
            end

            default : begin
                i_dot <= 0;
            end
        endcase
    end

endmodule
