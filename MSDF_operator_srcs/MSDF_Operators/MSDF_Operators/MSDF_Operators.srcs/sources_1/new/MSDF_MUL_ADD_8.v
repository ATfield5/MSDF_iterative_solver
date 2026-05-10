`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2025/06/26 16:24:21
// Design Name: 
// Module Name: MSDF_MUL_ADD_8
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


module MSDF_MUL_ADD_8 #(
    parameter bit_width = 8
)
(
    input i_clk,
    input i_rst,
    input i_ena,
    
    input [7 : 0] i_x_p,
    input [7 : 0] i_x_n,
    input [7 : 0] i_y_p,
    input [7 : 0] i_y_n,

    input i_a_p,
    input i_a_n,

    output o_z_p,
    output o_z_n,

    output o_int ,
    output o_unit,
    output o_frac
    );

    wire        w_valid;
    reg [2 : 0] cnt_int;

    wire w_int ;
    wire w_unit;
    wire w_frac;

    assign w_int  = w_valid & (cnt_int <  6);
    assign w_unit = w_valid & (cnt_int == 5);
    assign w_frac = w_valid & ~w_int        ;

    always @(posedge i_clk) begin
        if (i_rst) begin
            cnt_int <= 3'd0;
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

    wire [bit_width - 1 : 0] w_vec_x_p[7 : 0];
    wire [bit_width - 1 : 0] w_vec_x_n[7 : 0];
    wire [bit_width - 1 : 0] w_vec_y_p[7 : 0];
    wire [bit_width - 1 : 0] w_vec_y_n[7 : 0];

    wire w_vec_valid[7 : 0];

    generate
        genvar i;
    
        for (i = 0; i < 8; i = i + 1) begin
            append_and_select #(
                .bit_width (bit_width)
            )
            AAS(
                .i_clk     (i_clk),
                .i_rst     (i_rst),
                .i_ena     (i_ena),

                .i_x_p     (i_x_p[i]),
                .i_x_n     (i_x_n[i]),
                .i_y_p     (i_y_p[i]),
                .i_y_n     (i_y_n[i]),

                .o_vec_x_p (w_vec_x_p[i]),
                .o_vec_x_n (w_vec_x_n[i]),
                .o_vec_y_p (w_vec_y_p[i]),
                .o_vec_y_n (w_vec_y_n[i]),

                .o_valid   (w_vec_valid[i])
            );
        end
    
    endgenerate

    wire w_valid_reg[1 : 0];

    assign w_valid = w_valid_reg[1];

    DFF #(
        .bit_width (1)
    )
    DFF_VLD0(
        .i_clk  (i_clk),
        .i_rst  (i_rst),
        .i_ena  (1'b1 ),

        .i_data (w_vec_valid[4]),
        .o_data (w_valid_reg[0])
    );

    DFF #(
        .bit_width (1)
    )
    DFF_VLD1(
        .i_clk  (i_clk),
        .i_rst  (i_rst),
        .i_ena  (1'b1 ),

        .i_data (w_valid_reg[0]),
        .o_data (w_valid_reg[1])
    );

    wire [bit_width + 1 : 0] w_sum0_p_reg[3 : 0];
    wire [bit_width + 1 : 0] w_sum0_n_reg[3 : 0];

    generate
        genvar j;
    
        for (j = 0; j < 4; j = j + 1) begin
            parallel_online_adder_4_with_obuf #(
                .bit_width (bit_width)
            )
            POA4WO_SUM0(
                .i_clk  (i_clk),
                .i_rst  (i_rst),

                .i_ena  (w_vec_valid[2 * j]),

                .i_x0_p (w_vec_x_p[2 * j]),
                .i_x0_n (w_vec_x_n[2 * j]),
                .i_x1_p (w_vec_y_p[2 * j]),
                .i_x1_n (w_vec_y_n[2 * j]),

                .i_x2_p (w_vec_x_p[2 * j + 1]),
                .i_x2_n (w_vec_x_n[2 * j + 1]),
                .i_x3_p (w_vec_y_p[2 * j + 1]),
                .i_x3_n (w_vec_y_n[2 * j + 1]),

                .o_z_p  (w_sum0_p_reg[j]),
                .o_z_n  (w_sum0_n_reg[j])
            );
        end
    
    endgenerate

    wire [bit_width + 3 : 0] w_sum1_p_reg;
    wire [bit_width + 3 : 0] w_sum1_n_reg;

    parallel_online_adder_4_with_obuf #(
        .bit_width (bit_width + 2)
    )
    POA4WO_SUM1(
        .i_clk  (i_clk),
        .i_rst  (i_rst),

        .i_ena  (w_valid_reg[0]),

        .i_x0_p (w_sum0_p_reg[0]),
        .i_x0_n (w_sum0_n_reg[0]),
        .i_x1_p (w_sum0_p_reg[1]),
        .i_x1_n (w_sum0_n_reg[1]),
        .i_x2_p (w_sum0_p_reg[2]),
        .i_x2_n (w_sum0_n_reg[2]),
        .i_x3_p (w_sum0_p_reg[3]),
        .i_x3_n (w_sum0_n_reg[3]),

        .o_z_p  (w_sum1_p_reg),
        .o_z_n  (w_sum1_n_reg)
    );

    wire w_a_p_reg[2 : 0];
    wire w_a_n_reg[2 : 0];

    DFF #(
        .bit_width (2)
    )
    DFF_A0(
        .i_clk  (i_clk),
        .i_rst  (i_rst),

        .i_ena  (i_ena),

        .i_data ({i_a_p       , i_a_n       }),
        .o_data ({w_a_p_reg[0], w_a_n_reg[0]})
    );

    DFF #(
        .bit_width (2)
    )
    DFF_A1(
        .i_clk  (i_clk),
        .i_rst  (i_rst),

        .i_ena  (w_vec_valid[0]),

        .i_data ({w_a_p_reg[0], w_a_n_reg[0]}),
        .o_data ({w_a_p_reg[1], w_a_n_reg[1]})
    );

    DFF #(
        .bit_width (2)
    )
    DFF_A2(
        .i_clk  (i_clk),
        .i_rst  (i_rst),

        .i_ena  (w_valid_reg[0]),

        .i_data ({w_a_p_reg[1], w_a_n_reg[1]}),
        .o_data ({w_a_p_reg[2], w_a_n_reg[2]})
    );

    wire [bit_width + 4 : 0] w_sum_a_p;
    wire [bit_width + 4 : 0] w_sum_a_n;

    parallel_online_adder #(
        .bit_width (4)
    )
    POA_SUM_A(
        .i_x_p (w_sum1_p_reg[bit_width + 3 : bit_width]),
        .i_x_n (w_sum1_n_reg[bit_width + 3 : bit_width]),

        .i_y_p ({3'b000, w_a_p_reg[2]}),
        .i_y_n ({3'b000, w_a_n_reg[2]}),

        .i_c_p (1'b0),
        .i_c_n (1'b0),

        .o_z_p (w_sum_a_p[bit_width + 3 : bit_width]),
        .o_z_n (w_sum_a_n[bit_width + 3 : bit_width]),

        .o_c_p (w_sum_a_p[bit_width + 4]),
        .o_c_n (w_sum_a_n[bit_width + 4])
    );

    assign w_sum_a_p[bit_width - 1 : 0] = w_sum1_p_reg[bit_width - 1 : 0];
    assign w_sum_a_n[bit_width - 1 : 0] = w_sum1_n_reg[bit_width - 1 : 0];

    wire [bit_width + 6 : 0] w_vec_wj1_p;
    wire [bit_width + 6 : 0] w_vec_wj1_n;

    wire [bit_width + 6 : 0] w_vec_wj_p;
    wire [bit_width + 6 : 0] w_vec_wj_n;

    DFF #(
        .bit_width (bit_width + 7)
    )
    DFF_W_P(
        .i_clk  (i_clk),
        .i_rst  (i_rst),

        .i_ena  (w_valid_reg[1]),

        .i_data (w_vec_wj1_p),
        .o_data (w_vec_wj_p )
    );

    DFF #(
        .bit_width (bit_width + 7)
    )
    DFF_W_N(
        .i_clk  (i_clk),
        .i_rst  (i_rst),

        .i_ena  (w_valid_reg[1]),

        .i_data (w_vec_wj1_n),
        .o_data (w_vec_wj_n )
    );

    wire [bit_width + 7 : 0] w_vec_2wj_p;
    wire [bit_width + 7 : 0] w_vec_2wj_n;

    assign w_vec_2wj_p = {w_vec_wj_p, 1'b0};
    assign w_vec_2wj_n = {w_vec_wj_n, 1'b0};

    wire [bit_width + 7 : 0] w_vec_v_p;
    wire [bit_width + 7 : 0] w_vec_v_n;

    parallel_online_adder #(
        .bit_width (bit_width + 8)
    )
    POA_V(
        .i_x_p (w_vec_2wj_p),
        .i_x_n (w_vec_2wj_n),

        .i_y_p ({3'b000, w_sum_a_p}),
        .i_y_n ({3'b000, w_sum_a_n}),

        .i_c_p (1'b0),
        .i_c_n (1'b0),

        .o_z_p (w_vec_v_p),
        .o_z_n (w_vec_v_n)
    );

    wire w_z_p;
    wire w_z_n;

    output_and_update OAU(
        .i_v_p_5msd (w_vec_v_p[bit_width + 7 : bit_width + 3]),
        .i_v_n_5msd (w_vec_v_n[bit_width + 7 : bit_width + 3]),

        .o_w_p_4msd (w_vec_wj1_p[bit_width + 6 : bit_width + 3]),
        .o_w_n_4msd (w_vec_wj1_n[bit_width + 6 : bit_width + 3]),

        .o_z_p      (w_z_p),
        .o_z_n      (w_z_n)
    );
    
    assign w_vec_wj1_p[bit_width + 2 : 0] = w_vec_v_p[bit_width + 2 : 0];
    assign w_vec_wj1_n[bit_width + 2 : 0] = w_vec_v_n[bit_width + 2 : 0];

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
