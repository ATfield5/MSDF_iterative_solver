`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2025/06/25 19:51:27
// Design Name: 
// Module Name: MSDF_MUL_ADD
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


module MSDF_MUL_ADD #(
    parameter bit_width = 128
)
(
    input i_clk,
    input i_rst,
    input i_ena,
    
    input i_x_p,
    input i_x_n,
    input i_y_p,
    input i_y_n,

    input i_a_p,
    input i_a_n,

    output o_z_p,
    output o_z_n,
    
    output o_int ,
    output o_unit,
    output o_frac
    );

    wire        w_valid;
    reg [1 : 0] cnt_int;

    wire w_int ;
    wire w_unit;
    wire w_frac;

    assign w_int  = w_valid & (cnt_int <  3);
    assign w_unit = w_valid & (cnt_int == 2);
    assign w_frac = w_valid & ~w_int        ;

    always @(posedge i_clk) begin
        if (i_rst) begin
            cnt_int <= 2'd0;
        end
        else if (w_int) begin
            cnt_int <= cnt_int + 1;
        end
        else begin
            cnt_int <= cnt_int;
        end
    end

    DFF #(
        .bit_width (3)
    )
    DFF_FLAG(
        .i_clk  (i_clk),
        .i_rst  (i_rst),

        .i_ena  (w_valid),

        .i_data ({w_int, w_unit, w_frac}),
        .o_data ({o_int, o_unit, o_frac})
    );

    wire [bit_width - 1 : 0] w_vec_x_p;
    wire [bit_width - 1 : 0] w_vec_x_n;
    wire [bit_width - 1 : 0] w_vec_y_p;
    wire [bit_width - 1 : 0] w_vec_y_n;

    append_and_select #(
        .bit_width (bit_width)
    )
    AAS(
        .i_clk     (i_clk    ),
        .i_rst     (i_rst    ),
        .i_ena     (i_ena    ),

        .i_x_p     (i_x_p    ),
        .i_x_n     (i_x_n    ),
        .i_y_p     (i_y_p    ),
        .i_y_n     (i_y_n    ),

        .o_vec_x_p (w_vec_x_p),
        .o_vec_x_n (w_vec_x_n),
        .o_vec_y_p (w_vec_y_p),
        .o_vec_y_n (w_vec_y_n),

        .o_valid   (w_valid  )
    );

    wire w_a_p_reg;
    wire w_a_n_reg;

    DFF #(
        .bit_width (2)
    )
    DFF_A(
        .i_clk  (i_clk),
        .i_rst  (i_rst),
        .i_ena  (i_ena),

        .i_data ({i_a_p    , i_a_n    }),
        .o_data ({w_a_p_reg, w_a_n_reg})
    );

    wire [bit_width + 1 : 0] w_sum_p;
    wire [bit_width + 1 : 0] w_sum_n;

    parallel_online_adder #(
        .bit_width (bit_width + 1)
    )
    POA_SUM(
        .i_x_p ({w_a_p_reg, w_vec_x_p}),
        .i_x_n ({w_a_n_reg, w_vec_x_n}),
        .i_y_p ({1'b0     , w_vec_y_p}),
        .i_y_n ({1'b0     , w_vec_y_n}),

        .i_c_p (1'b0),
        .i_c_n (1'b0),

        .o_z_p (w_sum_p[bit_width : 0]),
        .o_z_n (w_sum_n[bit_width : 0]),

        .o_c_p (w_sum_p[bit_width + 1]),
        .o_c_n (w_sum_n[bit_width + 1])
    );
    
    wire [bit_width + 3 : 0] w_vec_wj1_p;
    wire [bit_width + 3 : 0] w_vec_wj1_n;

    wire [bit_width + 3 : 0] w_vec_wj_p;
    wire [bit_width + 3 : 0] w_vec_wj_n;

    DFF #(
        .bit_width (bit_width + 4)
    )
    DFF_W_P(
        .i_clk  (i_clk),
        .i_rst  (i_rst),

        .i_ena  (w_valid),

        .i_data (w_vec_wj1_p),
        .o_data (w_vec_wj_p )
    );

    DFF #(
        .bit_width (bit_width + 4)
    )
    DFF_W_N(
        .i_clk  (i_clk),
        .i_rst  (i_rst),

        .i_ena  (w_valid),

        .i_data (w_vec_wj1_n),
        .o_data (w_vec_wj_n )
    );

    wire [bit_width + 4 : 0] w_vec_2wj_p;
    wire [bit_width + 4 : 0] w_vec_2wj_n;

    assign w_vec_2wj_p = {w_vec_wj_p, 1'b0};
    assign w_vec_2wj_n = {w_vec_wj_n, 1'b0};

    wire [bit_width + 4 : 0] w_vec_v_p;
    wire [bit_width + 4 : 0] w_vec_v_n;

    parallel_online_adder #(
        .bit_width (bit_width + 5)
    )
    POA_V(
        .i_x_p (w_vec_2wj_p),
        .i_x_n (w_vec_2wj_n),

        .i_y_p ({3'b000, w_sum_p}),
        .i_y_n ({3'b000, w_sum_n}),

        .i_c_p (1'b0),
        .i_c_n (1'b0),

        .o_z_p (w_vec_v_p),
        .o_z_n (w_vec_v_n)
    );

    wire w_z_p;
    wire w_z_n;

    output_and_update OAU(
        .i_v_p_5msd (w_vec_v_p[bit_width + 4 : bit_width]),
        .i_v_n_5msd (w_vec_v_n[bit_width + 4 : bit_width]),

        .o_w_p_4msd (w_vec_wj1_p[bit_width + 3 : bit_width]),
        .o_w_n_4msd (w_vec_wj1_n[bit_width + 3 : bit_width]),

        .o_z_p      (w_z_p),
        .o_z_n      (w_z_n)
    );

    assign w_vec_wj1_p[bit_width - 1 : 0] = w_vec_v_p[bit_width - 1 : 0];
    assign w_vec_wj1_n[bit_width - 1 : 0] = w_vec_v_n[bit_width - 1 : 0];

    DFF #(
        .bit_width (2)
    )
    DFF_Z(
        .i_clk  (i_clk),
        .i_rst  (i_rst),

        .i_ena  (w_valid),

        .i_data ({w_z_p, w_z_n}),
        .o_data ({o_z_p, o_z_n})
    );

endmodule
