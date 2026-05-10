`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2025/06/25 23:55:35
// Design Name: 
// Module Name: MSDF_ADD
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


module MSDF_ADD(
    input i_clk,
    input i_rst,
    input i_ena,

    input i_x_p,
    input i_x_n,
    input i_y_p,
    input i_y_n,

    input i_dot,

    output o_z_p,
    output o_z_n,

    output reg o_valid,
    output reg o_dot
    );

    wire xj3_p;
    wire xj3_n;
    wire yj3_p;
    wire yj3_n;

    assign xj3_p = i_x_p;
    assign xj3_n = i_x_n;
    assign yj3_p = i_y_p;
    assign yj3_n = i_y_n;

    wire t_sj3;

    reg t_sj2;
    reg yj2_n;

    wire zj1_n;
    wire zj2_p;

    reg zj1_p;

    reg zj_n;
    reg zj_p;

    assign o_z_n = zj_n;
    assign o_z_p = zj_p;

    serial_online_adder_block SOAB(
        .i_xj3_p (xj3_p),
        .i_xj3_n (xj3_n),
        .i_yj3_p (yj3_p),
        .i_yj2_n (yj2_n),
        .o_t_sj3 (t_sj3),
        .i_t_sj2 (t_sj2),
        .o_zj1_n (zj1_n),
        .o_zj2_p (zj2_p)
    );

    reg         dot_flg;
    reg [1 : 0] dot_cnt;

    always @(posedge i_clk) begin
        if (i_rst) begin
            o_valid <= 0;
        end
        else if (i_ena) begin
            o_valid <= 1;
        end
        else begin
            o_valid <= 0;
        end
    end

    always @(posedge i_clk) begin
        if (i_rst) begin
            t_sj2 <= 0;
            yj2_n <= 0;
        end
        else if (i_ena) begin
            t_sj2 <= t_sj3;
            yj2_n <= yj3_n;
        end
        else begin
            t_sj2 <= t_sj2;
            yj2_n <= yj2_n;
        end
    end

    always @(posedge i_clk) begin
        if (i_rst) begin
            zj1_p <= 0;
        end
        else if (i_ena) begin
            zj1_p <= zj2_p;
        end
        else begin
            zj1_p <= zj1_p;
        end
    end

    always @(posedge i_clk) begin
        if (i_rst) begin
            zj_n <= 0;
            zj_p <= 0;
        end
        else if (i_ena) begin
            zj_n <= zj1_n;
            zj_p <= zj1_p;
        end
        else begin
            zj_n <= zj_n;
            zj_p <= zj_p;
        end
    end

    always @(posedge i_clk) begin
        if (i_rst) begin
            o_dot   <= 0;
            dot_flg <= 0;
            dot_cnt <= 0;
        end
        else if (i_ena) begin
            if (dot_flg) begin
                if (dot_cnt == 2) begin
                    o_dot <= 0;
                end
                else if (dot_cnt == 1) begin
                    dot_cnt <= dot_cnt + 1;
                    o_dot   <= 1;
                end
                else begin
                    dot_cnt <= dot_cnt + 1;
                end
            end
            else begin
                if (i_dot) begin
                    dot_flg <= 1;
                end
                else begin
                    dot_flg <= 0;
                end
            end
        end
        else begin
            o_dot   <= 0;
            dot_flg <= dot_flg;
            dot_cnt <= dot_cnt;
        end
    end

endmodule
