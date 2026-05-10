`timescale 1ns / 1ps

// Phase-1 specialized row-update core:
// - replaces the generic variable-by-variable selector front-end
// - keeps the local online reduction fabric
// - emits an accumulated affine-update vector, not the final solver digit
//   stream. The residual/output-update loop remains the next integration step.

module online_affine_row_update_core #(
    parameter bit_width = 8
) (
    input                          i_clk,
    input                          i_rst,
    input                          i_ena,
    input                          i_x0_p,
    input                          i_x0_n,
    input                          i_x1_p,
    input                          i_x1_n,
    input                          i_x2_p,
    input                          i_x2_n,
    input                          i_x3_p,
    input                          i_x3_n,
    input      [bit_width - 1 : 0] i_coeff0_vec_p,
    input      [bit_width - 1 : 0] i_coeff0_vec_n,
    input      [bit_width - 1 : 0] i_coeff1_vec_p,
    input      [bit_width - 1 : 0] i_coeff1_vec_n,
    input      [bit_width - 1 : 0] i_coeff2_vec_p,
    input      [bit_width - 1 : 0] i_coeff2_vec_n,
    input      [bit_width - 1 : 0] i_coeff3_vec_p,
    input      [bit_width - 1 : 0] i_coeff3_vec_n,
    input      [bit_width + 1 : 0] i_bias_vec_p,
    input      [bit_width + 1 : 0] i_bias_vec_n,
    output                         o_valid,
    output     [bit_width + 2 : 0] o_sum_p,
    output     [bit_width + 2 : 0] o_sum_n
);

    wire [bit_width - 1 : 0] w_vec0_p;
    wire [bit_width - 1 : 0] w_vec0_n;
    wire [bit_width - 1 : 0] w_vec1_p;
    wire [bit_width - 1 : 0] w_vec1_n;
    wire [bit_width - 1 : 0] w_vec2_p;
    wire [bit_width - 1 : 0] w_vec2_n;
    wire [bit_width - 1 : 0] w_vec3_p;
    wire [bit_width - 1 : 0] w_vec3_n;

    wire [bit_width + 1 : 0] w_sum4_p;
    wire [bit_width + 1 : 0] w_sum4_n;
    wire [bit_width + 2 : 0] w_sum_bias_p;
    wire [bit_width + 2 : 0] w_sum_bias_n;
    wire [bit_width + 2 : 0] w_sum_bias_p_reg;
    wire [bit_width + 2 : 0] w_sum_bias_n_reg;

    reg  [1 : 0] r_valid_pipe;

    online_const_coeff_contrib #(.bit_width(bit_width)) contrib0 (
        .i_digit_p(i_x0_p), .i_digit_n(i_x0_n),
        .i_coeff_vec_p(i_coeff0_vec_p), .i_coeff_vec_n(i_coeff0_vec_n),
        .o_vec_p(w_vec0_p), .o_vec_n(w_vec0_n)
    );

    online_const_coeff_contrib #(.bit_width(bit_width)) contrib1 (
        .i_digit_p(i_x1_p), .i_digit_n(i_x1_n),
        .i_coeff_vec_p(i_coeff1_vec_p), .i_coeff_vec_n(i_coeff1_vec_n),
        .o_vec_p(w_vec1_p), .o_vec_n(w_vec1_n)
    );

    online_const_coeff_contrib #(.bit_width(bit_width)) contrib2 (
        .i_digit_p(i_x2_p), .i_digit_n(i_x2_n),
        .i_coeff_vec_p(i_coeff2_vec_p), .i_coeff_vec_n(i_coeff2_vec_n),
        .o_vec_p(w_vec2_p), .o_vec_n(w_vec2_n)
    );

    online_const_coeff_contrib #(.bit_width(bit_width)) contrib3 (
        .i_digit_p(i_x3_p), .i_digit_n(i_x3_n),
        .i_coeff_vec_p(i_coeff3_vec_p), .i_coeff_vec_n(i_coeff3_vec_n),
        .o_vec_p(w_vec3_p), .o_vec_n(w_vec3_n)
    );

    iter_parallel_online_adder_4_with_obuf #(.bit_width(bit_width)) sum4 (
        .i_clk(i_clk),
        .i_rst(i_rst),
        .i_ena(i_ena),
        .i_x0_p(w_vec0_p), .i_x0_n(w_vec0_n),
        .i_x1_p(w_vec1_p), .i_x1_n(w_vec1_n),
        .i_x2_p(w_vec2_p), .i_x2_n(w_vec2_n),
        .i_x3_p(w_vec3_p), .i_x3_n(w_vec3_n),
        .o_z_p(w_sum4_p), .o_z_n(w_sum4_n)
    );

    iter_parallel_online_adder #(.bit_width(bit_width + 2)) add_bias (
        .i_x_p(w_sum4_p),
        .i_x_n(w_sum4_n),
        .i_y_p(i_bias_vec_p),
        .i_y_n(i_bias_vec_n),
        .i_c_p(1'b0),
        .i_c_n(1'b0),
        .o_z_p(w_sum_bias_p[bit_width + 1 : 0]),
        .o_z_n(w_sum_bias_n[bit_width + 1 : 0]),
        .o_c_p(w_sum_bias_p[bit_width + 2]),
        .o_c_n(w_sum_bias_n[bit_width + 2])
    );

    iter_dff #(.bit_width(bit_width + 3)) dff_out_p (
        .i_clk(i_clk),
        .i_rst(i_rst),
        .i_ena(r_valid_pipe[0]),
        .i_data(w_sum_bias_p),
        .o_data(w_sum_bias_p_reg)
    );

    iter_dff #(.bit_width(bit_width + 3)) dff_out_n (
        .i_clk(i_clk),
        .i_rst(i_rst),
        .i_ena(r_valid_pipe[0]),
        .i_data(w_sum_bias_n),
        .o_data(w_sum_bias_n_reg)
    );

    always @(posedge i_clk) begin
        if (i_rst) begin
            r_valid_pipe <= 2'b00;
        end else begin
            r_valid_pipe[0] <= i_ena;
            r_valid_pipe[1] <= r_valid_pipe[0];
        end
    end

    assign o_valid = r_valid_pipe[1];
    assign o_sum_p = w_sum_bias_p_reg;
    assign o_sum_n = w_sum_bias_n_reg;

endmodule
