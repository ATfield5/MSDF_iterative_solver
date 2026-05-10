`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2025/06/25 19:32:18
// Design Name: 
// Module Name: vector_append
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


module vector_append #(
    parameter bit_width = 8
)
(
    input  i_clk,
    input  i_rst,
    input  i_ena,

    input  i_x_p,
    input  i_x_n,
    input  i_y_p,
    input  i_y_n,

    output o_x_p,
    output o_x_n,
    output o_y_p,
    output o_y_n,

    output reg [bit_width - 1 : 0] o_vec_x_p,
    output reg [bit_width - 1 : 0] o_vec_x_n,
    output reg [bit_width - 1 : 0] o_vec_y_p,
    output reg [bit_width - 1 : 0] o_vec_y_n,

    output o_valid,
    output o_full
    );

    localparam idx_width = $clog2(bit_width);

    DFF #(
        .bit_width (2)
    )
    DFF_X(
        .i_clk  (i_clk),
        .i_rst  (i_rst),
        .i_ena  (i_ena),

        .i_data ({i_x_p, i_x_n}),
        .o_data ({o_x_p, o_x_n})
    );

    DFF #(
        .bit_width (2)
    )
    DFF_Y(
        .i_clk  (i_clk),
        .i_rst  (i_rst),
        .i_ena  (i_ena),

        .i_data ({i_y_p, i_y_n}),
        .o_data ({o_y_p, o_y_n})
    );
    
    reg r_ena_d1;

    assign o_valid = r_ena_d1;

    always @(posedge i_clk) begin
        if (i_rst) begin
            r_ena_d1 <= 1'b0;
        end
        else if (i_ena) begin
            r_ena_d1 <= 1'b1;
        end
        else begin
            r_ena_d1 <= 1'b0;
        end
    end

    reg [idx_width - 1 : 0] r_idx_x;

    always @(posedge i_clk) begin
        if (i_rst) begin
            r_idx_x <= bit_width - 1;
        end
        else if (r_ena_d1) begin
            if (r_idx_x == 0) begin
                r_idx_x <= r_idx_x;
            end
            else begin
                r_idx_x <= r_idx_x - 1;
            end
        end
        else begin
            r_idx_x <= r_idx_x;
        end
    end

    reg r_x_full;

    always @(posedge i_clk) begin
        if (i_rst) begin
            r_x_full <= 1'b0;
        end
        else if (r_ena_d1 && ~r_x_full) begin
            if (r_idx_x == 0) begin
                r_x_full <= 1'b1;
            end
            else begin
                r_x_full <= 1'b0;
            end
        end
        else begin
            r_x_full <= r_x_full;
        end
    end

    always @(posedge i_clk) begin
        if (i_rst) begin
            o_vec_x_p <= 0;
            o_vec_x_n <= 0;
        end
        else if (r_ena_d1 && ~r_x_full) begin
            o_vec_x_p[r_idx_x] <= o_x_p;
            o_vec_x_n[r_idx_x] <= o_x_n;
        end
        else begin
            o_vec_x_p <= o_vec_x_p;
            o_vec_x_n <= o_vec_x_n;
        end
    end

    reg [idx_width - 1 : 0] r_idx_y;

    always @(posedge i_clk) begin
        if (i_rst) begin
            r_idx_y <= bit_width - 1;
        end
        else if (i_ena) begin
            if (r_idx_y == 0) begin
                r_idx_y <= r_idx_y;
            end
            else begin
                r_idx_y <= r_idx_y - 1;
            end
        end
        else begin
            r_idx_y <= r_idx_y;
        end
    end

    reg r_y_full;

    always @(posedge i_clk) begin
        if (i_rst) begin
            r_y_full <= 1'b0;
        end
        else if (i_ena && ~r_y_full) begin
            if (r_idx_y == 0) begin
                r_y_full <= 1'b1;
            end
            else begin
                r_y_full <= 1'b0;
            end
        end
        else begin
            r_y_full <= r_y_full;
        end
    end

    always @(posedge i_clk) begin
        if (i_rst) begin
            o_vec_y_p <= 0;
            o_vec_y_n <= 0;
        end
        else if (i_ena && ~r_y_full) begin
            o_vec_y_p[r_idx_y] <= i_y_p;
            o_vec_y_n[r_idx_y] <= i_y_n;
        end
        else begin
            o_vec_y_p <= o_vec_y_p;
            o_vec_y_n <= o_vec_y_n;
        end
    end

    reg r_full;
    
    assign o_full = r_full;

    always @(posedge i_clk) begin
        if (i_rst) begin
            r_full <= 1'b0;
        end
        else if (r_x_full & r_y_full) begin
            r_full <= 1'b1;
        end
        else begin
            r_full <= r_full;
        end
    end

endmodule
