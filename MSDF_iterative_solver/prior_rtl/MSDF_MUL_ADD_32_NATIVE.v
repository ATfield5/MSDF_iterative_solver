`timescale 1ns / 1ps

// Native 32-term integrated online multiply-add.
//
// This is the direct 32-input generalization of the original
// MSDF_MUL_ADD_8.v structure.  It does not instantiate four complete
// MSDF_MUL_ADD_8 operators.  Instead, it keeps the original operator-level
// integration:
//
//   32 append_and_select blocks
//   -> one balanced 64-vector parallel-online-adder tree
//   -> one bias injection
//   -> one residual/output_and_update loop
//
// The extra integer delay follows the original paper's serial/serial bound:
//
//   delta = ceil(log2((2n+1)/3)) + 3
//
// For n=32, delta=8, so o_unit is asserted on the eighth valid output digit
// and o_frac starts after that.

module MSDF_MUL_ADD_32_NATIVE #(
    parameter integer bit_width = 32
) (
    input                i_clk,
    input                i_rst,
    input                i_ena,
    input      [31 : 0]  i_x_p,
    input      [31 : 0]  i_x_n,
    input      [31 : 0]  i_y_p,
    input      [31 : 0]  i_y_n,
    input                i_a_p,
    input                i_a_n,
    output               o_z_p,
    output               o_z_n,
    output               o_int,
    output               o_unit,
    output               o_frac
);

    localparam integer NUM_TERMS = 32;
    localparam integer SUM_GROWTH = 6;
    localparam integer OUT_DELAY = 8;

    wire w_valid;
    reg [3 : 0] cnt_int;

    wire w_int;
    wire w_unit;
    wire w_frac;

    assign w_int = w_valid & (cnt_int < OUT_DELAY[3 : 0]);
    assign w_unit = w_valid & (cnt_int == (OUT_DELAY - 1));
    assign w_frac = w_valid & ~w_int;

    always @(posedge i_clk) begin
        if (i_rst) begin
            cnt_int <= 4'd0;
        end else if (w_int) begin
            cnt_int <= cnt_int + 1'b1;
        end
    end

    DFF #(
        .bit_width(3)
    ) DFF_FLAG (
        .i_clk(i_clk),
        .i_rst(i_rst),
        .i_ena(w_valid),
        .i_data({w_int, w_unit, w_frac}),
        .o_data({o_int, o_unit, o_frac})
    );

    wire [bit_width - 1 : 0] w_vec_x_p [0 : NUM_TERMS - 1];
    wire [bit_width - 1 : 0] w_vec_x_n [0 : NUM_TERMS - 1];
    wire [bit_width - 1 : 0] w_vec_y_p [0 : NUM_TERMS - 1];
    wire [bit_width - 1 : 0] w_vec_y_n [0 : NUM_TERMS - 1];
    wire [NUM_TERMS - 1 : 0] w_vec_valid;

    genvar gi;
    generate
        for (gi = 0; gi < NUM_TERMS; gi = gi + 1) begin : gen_append
            append_and_select #(
                .bit_width(bit_width)
            ) aas (
                .i_clk(i_clk),
                .i_rst(i_rst),
                .i_ena(i_ena),
                .i_x_p(i_x_p[gi]),
                .i_x_n(i_x_n[gi]),
                .i_y_p(i_y_p[gi]),
                .i_y_n(i_y_n[gi]),
                .o_vec_x_p(w_vec_x_p[gi]),
                .o_vec_x_n(w_vec_x_n[gi]),
                .o_vec_y_p(w_vec_y_p[gi]),
                .o_vec_y_n(w_vec_y_n[gi]),
                .o_valid(w_vec_valid[gi])
            );
        end
    endgenerate

    wire [2 : 0] w_valid_reg;
    assign w_valid = w_valid_reg[2];

    DFF #(.bit_width(1)) DFF_VLD0 (
        .i_clk(i_clk),
        .i_rst(i_rst),
        .i_ena(1'b1),
        .i_data(w_vec_valid[0]),
        .o_data(w_valid_reg[0])
    );

    DFF #(.bit_width(1)) DFF_VLD1 (
        .i_clk(i_clk),
        .i_rst(i_rst),
        .i_ena(1'b1),
        .i_data(w_valid_reg[0]),
        .o_data(w_valid_reg[1])
    );

    DFF #(.bit_width(1)) DFF_VLD2 (
        .i_clk(i_clk),
        .i_rst(i_rst),
        .i_ena(1'b1),
        .i_data(w_valid_reg[1]),
        .o_data(w_valid_reg[2])
    );

    wire [bit_width + 1 : 0] w_sum0_p [0 : 15];
    wire [bit_width + 1 : 0] w_sum0_n [0 : 15];
    wire [bit_width + 3 : 0] w_sum1_p [0 : 3];
    wire [bit_width + 3 : 0] w_sum1_n [0 : 3];
    wire [bit_width + 5 : 0] w_sum2_p;
    wire [bit_width + 5 : 0] w_sum2_n;

    genvar si;
    generate
        for (si = 0; si < 16; si = si + 1) begin : gen_sum0
            parallel_online_adder_4_with_obuf #(
                .bit_width(bit_width)
            ) sum0 (
                .i_clk(i_clk),
                .i_rst(i_rst),
                .i_ena(w_vec_valid[0]),
                .i_x0_p(w_vec_x_p[2 * si]),
                .i_x0_n(w_vec_x_n[2 * si]),
                .i_x1_p(w_vec_y_p[2 * si]),
                .i_x1_n(w_vec_y_n[2 * si]),
                .i_x2_p(w_vec_x_p[2 * si + 1]),
                .i_x2_n(w_vec_x_n[2 * si + 1]),
                .i_x3_p(w_vec_y_p[2 * si + 1]),
                .i_x3_n(w_vec_y_n[2 * si + 1]),
                .o_z_p(w_sum0_p[si]),
                .o_z_n(w_sum0_n[si])
            );
        end

        for (si = 0; si < 4; si = si + 1) begin : gen_sum1
            parallel_online_adder_4_with_obuf #(
                .bit_width(bit_width + 2)
            ) sum1 (
                .i_clk(i_clk),
                .i_rst(i_rst),
                .i_ena(w_valid_reg[0]),
                .i_x0_p(w_sum0_p[4 * si]),
                .i_x0_n(w_sum0_n[4 * si]),
                .i_x1_p(w_sum0_p[4 * si + 1]),
                .i_x1_n(w_sum0_n[4 * si + 1]),
                .i_x2_p(w_sum0_p[4 * si + 2]),
                .i_x2_n(w_sum0_n[4 * si + 2]),
                .i_x3_p(w_sum0_p[4 * si + 3]),
                .i_x3_n(w_sum0_n[4 * si + 3]),
                .o_z_p(w_sum1_p[si]),
                .o_z_n(w_sum1_n[si])
            );
        end
    endgenerate

    parallel_online_adder_4_with_obuf #(
        .bit_width(bit_width + 4)
    ) sum2 (
        .i_clk(i_clk),
        .i_rst(i_rst),
        .i_ena(w_valid_reg[1]),
        .i_x0_p(w_sum1_p[0]),
        .i_x0_n(w_sum1_n[0]),
        .i_x1_p(w_sum1_p[1]),
        .i_x1_n(w_sum1_n[1]),
        .i_x2_p(w_sum1_p[2]),
        .i_x2_n(w_sum1_n[2]),
        .i_x3_p(w_sum1_p[3]),
        .i_x3_n(w_sum1_n[3]),
        .o_z_p(w_sum2_p),
        .o_z_n(w_sum2_n)
    );

    wire w_a_p_reg [0 : 3];
    wire w_a_n_reg [0 : 3];

    DFF #(.bit_width(2)) DFF_A0 (
        .i_clk(i_clk),
        .i_rst(i_rst),
        .i_ena(i_ena),
        .i_data({i_a_p, i_a_n}),
        .o_data({w_a_p_reg[0], w_a_n_reg[0]})
    );

    DFF #(.bit_width(2)) DFF_A1 (
        .i_clk(i_clk),
        .i_rst(i_rst),
        .i_ena(w_vec_valid[0]),
        .i_data({w_a_p_reg[0], w_a_n_reg[0]}),
        .o_data({w_a_p_reg[1], w_a_n_reg[1]})
    );

    DFF #(.bit_width(2)) DFF_A2 (
        .i_clk(i_clk),
        .i_rst(i_rst),
        .i_ena(w_valid_reg[0]),
        .i_data({w_a_p_reg[1], w_a_n_reg[1]}),
        .o_data({w_a_p_reg[2], w_a_n_reg[2]})
    );

    DFF #(.bit_width(2)) DFF_A3 (
        .i_clk(i_clk),
        .i_rst(i_rst),
        .i_ena(w_valid_reg[1]),
        .i_data({w_a_p_reg[2], w_a_n_reg[2]}),
        .o_data({w_a_p_reg[3], w_a_n_reg[3]})
    );

    wire [bit_width + 6 : 0] w_sum_a_p;
    wire [bit_width + 6 : 0] w_sum_a_n;

    parallel_online_adder #(
        .bit_width(SUM_GROWTH)
    ) add_bias (
        .i_x_p(w_sum2_p[bit_width + SUM_GROWTH - 1 : bit_width]),
        .i_x_n(w_sum2_n[bit_width + SUM_GROWTH - 1 : bit_width]),
        .i_y_p({{(SUM_GROWTH - 1){1'b0}}, w_a_p_reg[3]}),
        .i_y_n({{(SUM_GROWTH - 1){1'b0}}, w_a_n_reg[3]}),
        .i_c_p(1'b0),
        .i_c_n(1'b0),
        .o_z_p(w_sum_a_p[bit_width + SUM_GROWTH - 1 : bit_width]),
        .o_z_n(w_sum_a_n[bit_width + SUM_GROWTH - 1 : bit_width]),
        .o_c_p(w_sum_a_p[bit_width + SUM_GROWTH]),
        .o_c_n(w_sum_a_n[bit_width + SUM_GROWTH])
    );

    assign w_sum_a_p[bit_width - 1 : 0] = w_sum2_p[bit_width - 1 : 0];
    assign w_sum_a_n[bit_width - 1 : 0] = w_sum2_n[bit_width - 1 : 0];

    wire [bit_width + SUM_GROWTH + 2 : 0] w_vec_wj1_p;
    wire [bit_width + SUM_GROWTH + 2 : 0] w_vec_wj1_n;
    wire [bit_width + SUM_GROWTH + 2 : 0] w_vec_wj_p;
    wire [bit_width + SUM_GROWTH + 2 : 0] w_vec_wj_n;

    DFF #(
        .bit_width(bit_width + SUM_GROWTH + 3)
    ) DFF_W_P (
        .i_clk(i_clk),
        .i_rst(i_rst),
        .i_ena(w_valid),
        .i_data(w_vec_wj1_p),
        .o_data(w_vec_wj_p)
    );

    DFF #(
        .bit_width(bit_width + SUM_GROWTH + 3)
    ) DFF_W_N (
        .i_clk(i_clk),
        .i_rst(i_rst),
        .i_ena(w_valid),
        .i_data(w_vec_wj1_n),
        .o_data(w_vec_wj_n)
    );

    wire [bit_width + SUM_GROWTH + 3 : 0] w_vec_2wj_p;
    wire [bit_width + SUM_GROWTH + 3 : 0] w_vec_2wj_n;
    wire [bit_width + SUM_GROWTH + 3 : 0] w_vec_v_p;
    wire [bit_width + SUM_GROWTH + 3 : 0] w_vec_v_n;

    assign w_vec_2wj_p = {w_vec_wj_p, 1'b0};
    assign w_vec_2wj_n = {w_vec_wj_n, 1'b0};

    parallel_online_adder #(
        .bit_width(bit_width + SUM_GROWTH + 4)
    ) add_v (
        .i_x_p(w_vec_2wj_p),
        .i_x_n(w_vec_2wj_n),
        .i_y_p({3'b000, w_sum_a_p}),
        .i_y_n({3'b000, w_sum_a_n}),
        .i_c_p(1'b0),
        .i_c_n(1'b0),
        .o_z_p(w_vec_v_p),
        .o_z_n(w_vec_v_n)
    );

    wire w_z_p;
    wire w_z_n;

    output_and_update oau (
        .i_v_p_5msd(w_vec_v_p[bit_width + SUM_GROWTH + 3 : bit_width + SUM_GROWTH - 1]),
        .i_v_n_5msd(w_vec_v_n[bit_width + SUM_GROWTH + 3 : bit_width + SUM_GROWTH - 1]),
        .o_w_p_4msd(w_vec_wj1_p[bit_width + SUM_GROWTH + 2 : bit_width + SUM_GROWTH - 1]),
        .o_w_n_4msd(w_vec_wj1_n[bit_width + SUM_GROWTH + 2 : bit_width + SUM_GROWTH - 1]),
        .o_z_p(w_z_p),
        .o_z_n(w_z_n)
    );

    assign w_vec_wj1_p[bit_width + SUM_GROWTH - 2 : 0] =
        w_vec_v_p[bit_width + SUM_GROWTH - 2 : 0];
    assign w_vec_wj1_n[bit_width + SUM_GROWTH - 2 : 0] =
        w_vec_v_n[bit_width + SUM_GROWTH - 2 : 0];

    DFF #(
        .bit_width(2)
    ) DFF_Z (
        .i_clk(i_clk),
        .i_rst(i_rst),
        .i_ena(w_valid),
        .i_data({w_z_p, w_z_n}),
        .o_data({o_z_p, o_z_n})
    );

endmodule
