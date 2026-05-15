`timescale 1ns / 1ps

// PageRank-specialized fractional online 4-term multiply-add core.
//
// This is a microarchitecture cleanup of the original paper's
// MSDF_MUL_ADD_8 operator for the current PageRank workload:
//   - PageRank rows use four valid source terms, so this core physically
//     implements four terms instead of keeping eight input slots.
//   - The external contract is fractional-only: the old int/unit/frac flags
//     are collapsed into o_frac_valid.
//   - The online residual recurrence and digit selection are preserved.

module iter_pagerank_online_mma4_frac_core #(
    parameter integer bit_width = 14
) (
    input                 i_clk,
    input                 i_rst,
    input                 i_ena,
    input      [3 : 0]    i_x_p,
    input      [3 : 0]    i_x_n,
    input      [3 : 0]    i_y_p,
    input      [3 : 0]    i_y_n,
    input                 i_a_p,
    input                 i_a_n,
    output                o_z_p,
    output                o_z_n,
    output                o_frac_valid
);

    wire [bit_width - 1 : 0] w_vec_x_p[3 : 0];
    wire [bit_width - 1 : 0] w_vec_x_n[3 : 0];
    wire [bit_width - 1 : 0] w_vec_y_p[3 : 0];
    wire [bit_width - 1 : 0] w_vec_y_n[3 : 0];
    wire [3 : 0] w_vec_valid;

    genvar i;
    generate
        for (i = 0; i < 4; i = i + 1) begin : gen_append_select
            append_and_select #(
                .bit_width(bit_width)
            ) aas_term (
                .i_clk(i_clk),
                .i_rst(i_rst),
                .i_ena(i_ena),
                .i_x_p(i_x_p[i]),
                .i_x_n(i_x_n[i]),
                .i_y_p(i_y_p[i]),
                .i_y_n(i_y_n[i]),
                .o_vec_x_p(w_vec_x_p[i]),
                .o_vec_x_n(w_vec_x_n[i]),
                .o_vec_y_p(w_vec_y_p[i]),
                .o_vec_y_n(w_vec_y_n[i]),
                .o_valid(w_vec_valid[i])
            );
        end
    endgenerate

    wire w_valid_reg0;
    wire w_valid_reg1;
    wire w_valid;

    DFF #(.bit_width(1)) dff_valid0 (
        .i_clk(i_clk), .i_rst(i_rst), .i_ena(1'b1),
        .i_data(w_vec_valid[0]), .o_data(w_valid_reg0)
    );

    DFF #(.bit_width(1)) dff_valid1 (
        .i_clk(i_clk), .i_rst(i_rst), .i_ena(1'b1),
        .i_data(w_valid_reg0), .o_data(w_valid_reg1)
    );

    assign w_valid = w_valid_reg1;

    wire [bit_width + 1 : 0] w_sum0_p[1 : 0];
    wire [bit_width + 1 : 0] w_sum0_n[1 : 0];

    parallel_online_adder_4_with_obuf #(.bit_width(bit_width)) sum0_pair0 (
        .i_clk(i_clk), .i_rst(i_rst), .i_ena(w_vec_valid[0]),
        .i_x0_p(w_vec_x_p[0]), .i_x0_n(w_vec_x_n[0]),
        .i_x1_p(w_vec_y_p[0]), .i_x1_n(w_vec_y_n[0]),
        .i_x2_p(w_vec_x_p[1]), .i_x2_n(w_vec_x_n[1]),
        .i_x3_p(w_vec_y_p[1]), .i_x3_n(w_vec_y_n[1]),
        .o_z_p(w_sum0_p[0]), .o_z_n(w_sum0_n[0])
    );

    parallel_online_adder_4_with_obuf #(.bit_width(bit_width)) sum0_pair1 (
        .i_clk(i_clk), .i_rst(i_rst), .i_ena(w_vec_valid[2]),
        .i_x0_p(w_vec_x_p[2]), .i_x0_n(w_vec_x_n[2]),
        .i_x1_p(w_vec_y_p[2]), .i_x1_n(w_vec_y_n[2]),
        .i_x2_p(w_vec_x_p[3]), .i_x2_n(w_vec_x_n[3]),
        .i_x3_p(w_vec_y_p[3]), .i_x3_n(w_vec_y_n[3]),
        .o_z_p(w_sum0_p[1]), .o_z_n(w_sum0_n[1])
    );

    wire [bit_width + 3 : 0] w_sum1_p;
    wire [bit_width + 3 : 0] w_sum1_n;

    parallel_online_adder_4_with_obuf #(.bit_width(bit_width + 2)) sum1 (
        .i_clk(i_clk), .i_rst(i_rst), .i_ena(w_valid_reg0),
        .i_x0_p(w_sum0_p[0]), .i_x0_n(w_sum0_n[0]),
        .i_x1_p(w_sum0_p[1]), .i_x1_n(w_sum0_n[1]),
        .i_x2_p({(bit_width + 2){1'b0}}), .i_x2_n({(bit_width + 2){1'b0}}),
        .i_x3_p({(bit_width + 2){1'b0}}), .i_x3_n({(bit_width + 2){1'b0}}),
        .o_z_p(w_sum1_p), .o_z_n(w_sum1_n)
    );

    wire [2 : 0] w_a_p_reg;
    wire [2 : 0] w_a_n_reg;

    DFF #(.bit_width(2)) dff_a0 (
        .i_clk(i_clk), .i_rst(i_rst), .i_ena(i_ena),
        .i_data({i_a_p, i_a_n}), .o_data({w_a_p_reg[0], w_a_n_reg[0]})
    );

    DFF #(.bit_width(2)) dff_a1 (
        .i_clk(i_clk), .i_rst(i_rst), .i_ena(w_vec_valid[0]),
        .i_data({w_a_p_reg[0], w_a_n_reg[0]}),
        .o_data({w_a_p_reg[1], w_a_n_reg[1]})
    );

    DFF #(.bit_width(2)) dff_a2 (
        .i_clk(i_clk), .i_rst(i_rst), .i_ena(w_valid_reg0),
        .i_data({w_a_p_reg[1], w_a_n_reg[1]}),
        .o_data({w_a_p_reg[2], w_a_n_reg[2]})
    );

    wire [bit_width + 4 : 0] w_sum_a_p;
    wire [bit_width + 4 : 0] w_sum_a_n;

    parallel_online_adder #(.bit_width(4)) sum_bias_msd (
        .i_x_p(w_sum1_p[bit_width + 3 : bit_width]),
        .i_x_n(w_sum1_n[bit_width + 3 : bit_width]),
        .i_y_p({3'b000, w_a_p_reg[2]}),
        .i_y_n({3'b000, w_a_n_reg[2]}),
        .i_c_p(1'b0), .i_c_n(1'b0),
        .o_z_p(w_sum_a_p[bit_width + 3 : bit_width]),
        .o_z_n(w_sum_a_n[bit_width + 3 : bit_width]),
        .o_c_p(w_sum_a_p[bit_width + 4]),
        .o_c_n(w_sum_a_n[bit_width + 4])
    );

    assign w_sum_a_p[bit_width - 1 : 0] = w_sum1_p[bit_width - 1 : 0];
    assign w_sum_a_n[bit_width - 1 : 0] = w_sum1_n[bit_width - 1 : 0];

    wire [bit_width + 6 : 0] w_vec_wj1_p;
    wire [bit_width + 6 : 0] w_vec_wj1_n;
    wire [bit_width + 6 : 0] w_vec_wj_p;
    wire [bit_width + 6 : 0] w_vec_wj_n;

    DFF #(.bit_width(bit_width + 7)) dff_w_p (
        .i_clk(i_clk), .i_rst(i_rst), .i_ena(w_valid_reg1),
        .i_data(w_vec_wj1_p), .o_data(w_vec_wj_p)
    );

    DFF #(.bit_width(bit_width + 7)) dff_w_n (
        .i_clk(i_clk), .i_rst(i_rst), .i_ena(w_valid_reg1),
        .i_data(w_vec_wj1_n), .o_data(w_vec_wj_n)
    );

    wire [bit_width + 7 : 0] w_vec_2wj_p;
    wire [bit_width + 7 : 0] w_vec_2wj_n;
    wire [bit_width + 7 : 0] w_vec_v_p;
    wire [bit_width + 7 : 0] w_vec_v_n;

    assign w_vec_2wj_p = {w_vec_wj_p, 1'b0};
    assign w_vec_2wj_n = {w_vec_wj_n, 1'b0};

    parallel_online_adder #(.bit_width(bit_width + 8)) residual_v (
        .i_x_p(w_vec_2wj_p), .i_x_n(w_vec_2wj_n),
        .i_y_p({3'b000, w_sum_a_p}), .i_y_n({3'b000, w_sum_a_n}),
        .i_c_p(1'b0), .i_c_n(1'b0),
        .o_z_p(w_vec_v_p), .o_z_n(w_vec_v_n)
    );

    wire w_z_p;
    wire w_z_n;

    output_and_update residual_update (
        .i_v_p_5msd(w_vec_v_p[bit_width + 7 : bit_width + 3]),
        .i_v_n_5msd(w_vec_v_n[bit_width + 7 : bit_width + 3]),
        .o_w_p_4msd(w_vec_wj1_p[bit_width + 6 : bit_width + 3]),
        .o_w_n_4msd(w_vec_wj1_n[bit_width + 6 : bit_width + 3]),
        .o_z_p(w_z_p), .o_z_n(w_z_n)
    );

    assign w_vec_wj1_p[bit_width + 2 : 0] = w_vec_v_p[bit_width + 2 : 0];
    assign w_vec_wj1_n[bit_width + 2 : 0] = w_vec_v_n[bit_width + 2 : 0];

    DFF #(.bit_width(2)) dff_z (
        .i_clk(i_clk), .i_rst(i_rst), .i_ena(w_valid),
        .i_data({w_z_p, w_z_n}), .o_data({o_z_p, o_z_n})
    );

    reg [2 : 0] r_skip_count;
    reg r_frac_valid;

    assign o_frac_valid = r_frac_valid;

    always @(posedge i_clk) begin
        if (i_rst) begin
            r_skip_count <= 3'd0;
            r_frac_valid <= 1'b0;
        end else begin
            r_frac_valid <= 1'b0;
            if (w_valid) begin
                if (r_skip_count < 3'd6) begin
                    r_skip_count <= r_skip_count + 1'b1;
                end else begin
                    r_frac_valid <= 1'b1;
                end
            end
        end
    end

endmodule
