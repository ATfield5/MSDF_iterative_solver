`timescale 1ns / 1ps

// Residual/output-update loop for solver affine vectors.
//
// Input contract:
// - each valid cycle provides one rail-coded affine accumulated vector;
// - i_start marks the first valid vector of a new row/iteration output stream.
//
// Internal recurrence:
//   v_j     = 2 w_j + s_j
//   z_j     = select(v_j)
//   w_{j+1} = update(v_j, z_j)
//
// where s_j is the current affine accumulated vector from the row-update core.
// This is the missing loop that turns the row-update affine vector stream into
// the final solver state digit stream.

module iter_online_affine_digit_core #(
    parameter integer affine_width = 11,
    parameter integer sample_width = 5,
    parameter integer residual_width = affine_width + 2,
    parameter integer sample_offset = 0
) (
    input                                       i_clk,
    input                                       i_rst,
    input                                       i_start,
    input                                       i_valid,
    input      [affine_width - 1 : 0]          i_affine_p,
    input      [affine_width - 1 : 0]          i_affine_n,
    output reg                                  o_valid,
    output reg                                  o_z_p,
    output reg                                  o_z_n,
    output     [residual_width - 1 : 0]        o_residual_p,
    output     [residual_width - 1 : 0]        o_residual_n
);

    localparam integer v_width = residual_width + 1;
    localparam integer residual_high_width = sample_width - 1;
    localparam integer affine_pad_width = v_width - affine_width;
    localparam integer sample_msb = v_width - 1 - sample_offset;
    localparam integer residual_update_msb = sample_msb - 1;

    reg  [residual_width - 1 : 0] r_w_p;
    reg  [residual_width - 1 : 0] r_w_n;
    reg  [residual_width - 1 : 0] r_w_next_p;
    reg  [residual_width - 1 : 0] r_w_next_n;
    reg  r_z_p_next;
    reg  r_z_n_next;
    reg  r_valid_next;

    wire [residual_width - 1 : 0] w_curr_w_p;
    wire [residual_width - 1 : 0] w_curr_w_n;
    wire [v_width - 1 : 0] w_vec_2w_p;
    wire [v_width - 1 : 0] w_vec_2w_n;
    wire [v_width - 1 : 0] w_affine_ext_p;
    wire [v_width - 1 : 0] w_affine_ext_n;
    wire [v_width - 1 : 0] w_vec_v_p;
    wire [v_width - 1 : 0] w_vec_v_n;
    wire [residual_high_width - 1 : 0] w_w_msd_p;
    wire [residual_high_width - 1 : 0] w_w_msd_n;
    wire w_z_p;
    wire w_z_n;

    assign w_curr_w_p = i_start ? {residual_width{1'b0}} : r_w_p;
    assign w_curr_w_n = i_start ? {residual_width{1'b0}} : r_w_n;
    assign w_vec_2w_p = {w_curr_w_p, 1'b0};
    assign w_vec_2w_n = {w_curr_w_n, 1'b0};
    assign w_affine_ext_p = {{affine_pad_width{1'b0}}, i_affine_p};
    assign w_affine_ext_n = {{affine_pad_width{1'b0}}, i_affine_n};

    iter_parallel_online_adder #(
        .bit_width(v_width)
    ) add_v (
        .i_x_p(w_vec_2w_p),
        .i_x_n(w_vec_2w_n),
        .i_y_p(w_affine_ext_p),
        .i_y_n(w_affine_ext_n),
        .i_c_p(1'b0),
        .i_c_n(1'b0),
        .o_z_p(w_vec_v_p),
        .o_z_n(w_vec_v_n),
        .o_c_p(),
        .o_c_n()
    );

    iter_online_output_update #(
        .sample_width(sample_width)
    ) out_update (
        .i_v_p_msd(w_vec_v_p[sample_msb -: sample_width]),
        .i_v_n_msd(w_vec_v_n[sample_msb -: sample_width]),
        .o_w_p_msd(w_w_msd_p),
        .o_w_n_msd(w_w_msd_n),
        .o_z_p(w_z_p),
        .o_z_n(w_z_n)
    );

    always @(*) begin
        r_w_next_p = w_vec_v_p[residual_width - 1 : 0];
        r_w_next_n = w_vec_v_n[residual_width - 1 : 0];
        r_w_next_p[residual_update_msb -: residual_high_width] = w_w_msd_p;
        r_w_next_n[residual_update_msb -: residual_high_width] = w_w_msd_n;
        r_z_p_next = w_z_p;
        r_z_n_next = w_z_n;
        r_valid_next = i_valid;
    end

    always @(posedge i_clk) begin
        if (i_rst) begin
            r_w_p <= {residual_width{1'b0}};
            r_w_n <= {residual_width{1'b0}};
            o_valid <= 1'b0;
            o_z_p <= 1'b0;
            o_z_n <= 1'b0;
        end else begin
            if (i_valid) begin
                r_w_p <= r_w_next_p;
                r_w_n <= r_w_next_n;
            end
            o_valid <= r_valid_next;
            o_z_p <= r_z_p_next;
            o_z_n <= r_z_n_next;
        end
    end

    assign o_residual_p = r_w_p;
    assign o_residual_n = r_w_n;

endmodule
