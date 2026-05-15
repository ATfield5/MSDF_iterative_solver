`timescale 1ns / 1ps

// Parallel-in / serial-state online affine MAC core.
//
// This is not a wrapper around the original MSDF_MUL_ADD_8.  It implements the
// P3-SP recurrence directly:
//   v[j] = 2w[j] + 2^-ONLINE_DELAY * (sum_s a_s*x_{s,j+1+d} + b_{j+1+d})
//   z[j+1] = sel(v[j])
//   w[j+1] = v[j] - z[j+1]
// Coefficients are external parallel fixed-point words; state and bias enter as
// MSB-first signed digits.

module iter_parallel_in_online_mma8_frac_core #(
    parameter integer physical_degree = 8,
    parameter integer bit_width = 30,
    parameter integer data_width = 32,
    parameter integer frac_bits = data_width - 1,
    parameter integer online_delay = 2,
    // Internal residual/contribution width.  This is not the external state
    // precision; the emitted state is still DATA_WIDTH signed digits.  For the
    // 32-digit PageRank32 parallel-in fixture, the proven minimum is 33 bits and
    // the default keeps three guard bits.
    parameter integer acc_width = 36,
    parameter integer feed_count_width = 8,
    parameter integer output_groups = 1,
    parameter integer nonnegative_coeff = 0,
    parameter integer nonnegative_bias = 0
) (
    input                                                   i_clk,
    input                                                   i_rst,
    input                                                   i_ena,
    input      [physical_degree - 1 : 0]                    i_x_p,
    input      [physical_degree - 1 : 0]                    i_x_n,
    input      [physical_degree * bit_width - 1 : 0]        i_coeff_p,
    input      [physical_degree * bit_width - 1 : 0]        i_coeff_n,
    input                                                   i_bias_p,
    input                                                   i_bias_n,
    (* max_fanout = 32 *) output reg                        o_z_p,
    (* max_fanout = 32 *) output reg                        o_z_n,
    output reg                                              o_valid,
    output reg [output_groups - 1 : 0]                      o_z_p_groups,
    output reg [output_groups - 1 : 0]                      o_z_n_groups
);

    localparam signed [acc_width - 1 : 0] SCALE = {{(acc_width - 1){1'b0}}, 1'b1} <<< frac_bits;
    localparam signed [acc_width - 1 : 0] HALF_SCALE = SCALE >>> 1;
    localparam [feed_count_width - 1 : 0] ONLINE_DELAY_VALUE = online_delay[feed_count_width - 1 : 0];

    reg signed [acc_width - 1 : 0] r_w;
    reg [feed_count_width - 1 : 0] r_feed_count;
    reg signed [acc_width - 1 : 0] r_u;
    reg [feed_count_width - 1 : 0] r_u_feed_count;
    reg r_u_valid;

    wire signed [acc_width - 1 : 0] w_term [0 : physical_degree - 1];
    wire signed [acc_width - 1 : 0] w_sum01;
    wire signed [acc_width - 1 : 0] w_sum23;
    wire signed [acc_width - 1 : 0] w_sum45;
    wire signed [acc_width - 1 : 0] w_sum67;
    wire signed [acc_width - 1 : 0] w_sum03;
    wire signed [acc_width - 1 : 0] w_sum47;
    wire signed [acc_width - 1 : 0] w_sum_terms;
    wire signed [acc_width - 1 : 0] w_bias_term;
    wire signed [acc_width - 1 : 0] w_contrib;
    reg signed [acc_width - 1 : 0] w_v;
    reg signed [acc_width - 1 : 0] w_z_scaled;
    reg w_z_p;
    reg w_z_n;

    genvar gi;
    generate
        for (gi = 0; gi < physical_degree; gi = gi + 1) begin : gen_terms
            wire signed [acc_width - 1 : 0] w_coeff;
            if (nonnegative_coeff != 0) begin : gen_nonnegative_coeff
                assign w_coeff =
                    $signed({1'b0, i_coeff_p[gi * bit_width +: bit_width]});
            end else begin : gen_signed_coeff
                assign w_coeff =
                    $signed({1'b0, i_coeff_p[gi * bit_width +: bit_width]}) -
                    $signed({1'b0, i_coeff_n[gi * bit_width +: bit_width]});
            end
            assign w_term[gi] =
                (i_x_p[gi] && !i_x_n[gi]) ? w_coeff :
                ((i_x_n[gi] && !i_x_p[gi]) ? -w_coeff : {acc_width{1'b0}});
        end
    endgenerate

    assign w_sum01 = w_term[0] + w_term[1];
    assign w_sum23 = w_term[2] + w_term[3];
    assign w_sum45 = w_term[4] + w_term[5];
    assign w_sum67 = w_term[6] + w_term[7];
    assign w_sum03 = w_sum01 + w_sum23;
    assign w_sum47 = w_sum45 + w_sum67;
    assign w_sum_terms = w_sum03 + w_sum47;
    assign w_bias_term =
        (nonnegative_bias != 0) ?
            (i_bias_p ? SCALE : {acc_width{1'b0}}) :
            ((i_bias_p && !i_bias_n) ? SCALE :
                ((i_bias_n && !i_bias_p) ? -SCALE : {acc_width{1'b0}}));
    assign w_contrib = w_sum_terms + w_bias_term;

    always @(*) begin
        w_v = (r_w <<< 1) + r_u;

        if (w_v >= HALF_SCALE) begin
            w_z_p = 1'b1;
            w_z_n = 1'b0;
            w_z_scaled = SCALE;
        end else if (w_v <= -HALF_SCALE) begin
            w_z_p = 1'b0;
            w_z_n = 1'b1;
            w_z_scaled = -SCALE;
        end else begin
            w_z_p = 1'b0;
            w_z_n = 1'b0;
            w_z_scaled = {acc_width{1'b0}};
        end
    end

    always @(posedge i_clk) begin
        if (i_rst) begin
            r_w <= {acc_width{1'b0}};
            r_feed_count <= {feed_count_width{1'b0}};
            r_u <= {acc_width{1'b0}};
            r_u_feed_count <= {feed_count_width{1'b0}};
            r_u_valid <= 1'b0;
            o_z_p <= 1'b0;
            o_z_n <= 1'b0;
            o_valid <= 1'b0;
            o_z_p_groups <= {output_groups{1'b0}};
            o_z_n_groups <= {output_groups{1'b0}};
        end else begin
            o_valid <= 1'b0;
            o_z_p_groups <= {output_groups{1'b0}};
            o_z_n_groups <= {output_groups{1'b0}};
            if (r_u_valid) begin
                if (r_u_feed_count < ONLINE_DELAY_VALUE) begin
                    r_w <= w_v;
                    o_z_p <= 1'b0;
                    o_z_n <= 1'b0;
                    o_valid <= 1'b0;
                    o_z_p_groups <= {output_groups{1'b0}};
                    o_z_n_groups <= {output_groups{1'b0}};
                end else begin
                    r_w <= w_v - w_z_scaled;
                    o_z_p <= w_z_p;
                    o_z_n <= w_z_n;
                    o_valid <= 1'b1;
                    o_z_p_groups <= {output_groups{w_z_p}};
                    o_z_n_groups <= {output_groups{w_z_n}};
                end
            end

            if (i_ena) begin
                r_u <= w_contrib >>> online_delay;
                r_u_feed_count <= r_feed_count;
                r_u_valid <= 1'b1;
                r_feed_count <= r_feed_count + 1'b1;
            end else begin
                r_u_valid <= 1'b0;
            end
        end
    end

endmodule
