`timescale 1ns / 1ps

// Low-latency P3-SP online affine MAC core.
//
// This variant keeps the mathematical online delay but removes the extra
// contribution register used by the route-clean baseline.  The current input
// digit contribution enters the residual/select path in the same cycle:
//
//     v[j] = 2w[j] + 2^-delta * contribution[j]
//
// It is closer to the textbook online recurrence, but the critical path is
// longer because contribution accumulation, residual update, and digit
// selection are now in one cycle.

module iter_parallel_in_online_mma8_frac_core_fast2 #(
    parameter integer physical_degree = 8,
    parameter integer bit_width = 30,
    parameter integer data_width = 32,
    parameter integer frac_bits = data_width - 1,
    parameter integer online_delay = 2,
    parameter integer acc_width = 36,
    parameter integer feed_count_width = 8,
    parameter integer output_groups = 1,
    parameter integer estimate_selector = 0,
    parameter integer estimate_frac_bits = 6,
    parameter integer estimate_guard_bits = 2,
    parameter integer split_estimate = 1,
    parameter integer redundant_residual = 0,
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

    localparam signed [acc_width - 1 : 0] SCALE =
        {{(acc_width - 1){1'b0}}, 1'b1} <<< frac_bits;
    localparam signed [acc_width - 1 : 0] HALF_SCALE = SCALE >>> 1;
    localparam [feed_count_width - 1 : 0] ONLINE_DELAY_VALUE =
        online_delay[feed_count_width - 1 : 0];
    localparam integer EST_TOTAL_FRAC =
        estimate_frac_bits + estimate_guard_bits;
    localparam integer EST_LSB =
        (EST_TOTAL_FRAC >= frac_bits) ? 0 : (frac_bits - EST_TOTAL_FRAC);
    localparam integer EST_WIDTH = acc_width - EST_LSB;
    localparam integer EST_ACC_WIDTH = EST_WIDTH + 2;
    localparam integer EST_HALF_BIT =
        (frac_bits > EST_LSB) ? (frac_bits - EST_LSB - 1) : 0;
    localparam integer EST_U_LSB = EST_LSB + online_delay;
    localparam integer EST_BIAS_BIT =
        (EST_TOTAL_FRAC > online_delay) ? (EST_TOTAL_FRAC - online_delay) : 0;
    localparam integer max_physical_degree = 32;

    (* max_fanout = 8 *) reg signed [acc_width - 1 : 0] r_w;
    (* max_fanout = 8 *) reg signed [acc_width - 1 : 0] r_w_sum;
    (* max_fanout = 8 *) reg signed [acc_width - 1 : 0] r_w_carry;
    (* max_fanout = 8 *) reg signed [EST_ACC_WIDTH - 1 : 0] r_w_est_norm;
    reg [feed_count_width - 1 : 0] r_feed_count;

    wire signed [acc_width - 1 : 0] w_term [0 : max_physical_degree - 1];
    wire signed [EST_WIDTH - 1 : 0] w_term_est [0 : max_physical_degree - 1];
    (* keep = "true" *) wire signed [acc_width - 1 : 0] w_sum_l1 [0 : 15];
    (* keep = "true" *) wire signed [acc_width - 1 : 0] w_sum_l2 [0 : 7];
    (* keep = "true" *) wire signed [acc_width - 1 : 0] w_sum_l3 [0 : 3];
    (* keep = "true" *) wire signed [acc_width - 1 : 0] w_sum_l4 [0 : 1];
    (* keep = "true" *) wire signed [acc_width - 1 : 0] w_sum_terms;
    wire signed [acc_width - 1 : 0] w_bias_term;
    (* keep = "true" *) wire signed [acc_width - 1 : 0] w_contrib;
    wire signed [EST_WIDTH - 1 : 0] w_sum_l1_est [0 : 15];
    wire signed [EST_WIDTH - 1 : 0] w_sum_l2_est [0 : 7];
    wire signed [EST_WIDTH - 1 : 0] w_sum_l3_est [0 : 3];
    wire signed [EST_WIDTH - 1 : 0] w_sum_l4_est [0 : 1];
    wire signed [EST_WIDTH - 1 : 0] w_sum_terms_est;
    wire signed [EST_WIDTH - 1 : 0] w_bias_est;
    wire signed [EST_WIDTH - 1 : 0] w_u_est_split;
    wire signed [acc_width - 1 : 0] w_u_now;
    wire signed [acc_width - 1 : 0] w_v;
    wire signed [acc_width - 1 : 0] w_z_scaled;
    wire signed [acc_width - 1 : 0] w_neg_z_scaled;
    wire w_valid_now;
    wire w_z_p;
    wire w_z_n;
    wire [acc_width - frac_bits - 1 : 0] w_sel_high_bits;
    wire [frac_bits - 2 : 0] w_sel_low_bits;
    wire w_sel_high_nonzero;
    wire w_sel_high_all_one;
    wire w_sel_low_zero;
    wire signed [acc_width - 1 : 0] w_r_shift;
    wire signed [acc_width - 1 : 0] w_r_sum_shift;
    wire signed [acc_width - 1 : 0] w_r_carry_shift;
    wire signed [EST_WIDTH - 1 : 0] w_r_est;
    wire signed [EST_WIDTH - 1 : 0] w_r_sum_est;
    wire signed [EST_WIDTH - 1 : 0] w_r_carry_est;
    wire signed [EST_WIDTH - 1 : 0] w_u_est_exact;
    wire signed [EST_WIDTH - 1 : 0] w_u_est;
    wire signed [EST_ACC_WIDTH - 1 : 0] w_v_est;
    wire signed [EST_ACC_WIDTH - 1 : 0] w_v_est_norm;
    wire [EST_ACC_WIDTH - 1 : 0] w_est_half_scale;
    wire [EST_ACC_WIDTH - 1 : 0] w_est_one_scale;
    wire signed [EST_ACC_WIDTH - 1 : 0] w_est_pos_threshold;
    wire signed [EST_ACC_WIDTH - 1 : 0] w_est_neg_threshold;
    wire signed [EST_ACC_WIDTH - 1 : 0] w_est_z_scaled;
    wire w_est_z_p;
    wire w_est_z_n;
    wire signed [acc_width - 1 : 0] w_csa1_sum;
    wire signed [acc_width - 1 : 0] w_csa1_carry;
    wire signed [acc_width - 1 : 0] w_csa_next_sum;
    wire signed [acc_width - 1 : 0] w_csa_next_carry;

    genvar gi;
    generate
        for (gi = 0; gi < max_physical_degree; gi = gi + 1) begin : gen_terms
            wire signed [acc_width - 1 : 0] w_coeff;
            wire signed [EST_WIDTH - 1 : 0] w_coeff_est;

            if (gi < physical_degree) begin : gen_real_term
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

                if (EST_U_LSB < bit_width) begin : gen_coeff_est_slice
                    localparam integer EST_COEFF_BITS = bit_width - EST_U_LSB;
                    wire signed [EST_WIDTH - 1 : 0] w_coeff_p_est;
                    wire signed [EST_WIDTH - 1 : 0] w_coeff_n_est;

                    assign w_coeff_p_est =
                        $signed({1'b0,
                            i_coeff_p[gi * bit_width + EST_U_LSB +:
                                EST_COEFF_BITS]});
                    assign w_coeff_n_est =
                        $signed({1'b0,
                            i_coeff_n[gi * bit_width + EST_U_LSB +:
                                EST_COEFF_BITS]});
                    if (nonnegative_coeff != 0) begin : gen_nonnegative_coeff_est
                        assign w_coeff_est = w_coeff_p_est;
                    end else begin : gen_signed_coeff_est
                        assign w_coeff_est = w_coeff_p_est - w_coeff_n_est;
                    end
                end else begin : gen_coeff_est_zero
                    assign w_coeff_est = {EST_WIDTH{1'b0}};
                end

                assign w_term_est[gi] =
                    (i_x_p[gi] && !i_x_n[gi]) ? w_coeff_est :
                    ((i_x_n[gi] && !i_x_p[gi]) ? -w_coeff_est :
                        {EST_WIDTH{1'b0}});
            end else begin : gen_coeff_est_zero
                assign w_coeff = {acc_width{1'b0}};
                assign w_coeff_est = {EST_WIDTH{1'b0}};
                assign w_term[gi] = {acc_width{1'b0}};
                assign w_term_est[gi] = {EST_WIDTH{1'b0}};
            end
        end

        for (gi = 0; gi < 16; gi = gi + 1) begin : gen_sum_l1
            assign w_sum_l1[gi] =
                w_term[2 * gi] + w_term[2 * gi + 1];
            assign w_sum_l1_est[gi] =
                w_term_est[2 * gi] + w_term_est[2 * gi + 1];
        end
        for (gi = 0; gi < 8; gi = gi + 1) begin : gen_sum_l2
            assign w_sum_l2[gi] =
                w_sum_l1[2 * gi] + w_sum_l1[2 * gi + 1];
            assign w_sum_l2_est[gi] =
                w_sum_l1_est[2 * gi] + w_sum_l1_est[2 * gi + 1];
        end
        for (gi = 0; gi < 4; gi = gi + 1) begin : gen_sum_l3
            assign w_sum_l3[gi] =
                w_sum_l2[2 * gi] + w_sum_l2[2 * gi + 1];
            assign w_sum_l3_est[gi] =
                w_sum_l2_est[2 * gi] + w_sum_l2_est[2 * gi + 1];
        end
        for (gi = 0; gi < 2; gi = gi + 1) begin : gen_sum_l4
            assign w_sum_l4[gi] =
                w_sum_l3[2 * gi] + w_sum_l3[2 * gi + 1];
            assign w_sum_l4_est[gi] =
                w_sum_l3_est[2 * gi] + w_sum_l3_est[2 * gi + 1];
        end
    endgenerate

    assign w_sum_terms = w_sum_l4[0] + w_sum_l4[1];
    assign w_bias_term =
        (nonnegative_bias != 0) ?
            (i_bias_p ? SCALE : {acc_width{1'b0}}) :
            ((i_bias_p && !i_bias_n) ? SCALE :
                ((i_bias_n && !i_bias_p) ? -SCALE : {acc_width{1'b0}}));
    assign w_contrib = w_sum_terms + w_bias_term;

    assign w_sum_terms_est = w_sum_l4_est[0] + w_sum_l4_est[1];
    assign w_bias_est =
        (nonnegative_bias != 0) ?
            (i_bias_p ?
                ($signed({{(EST_WIDTH - 1){1'b0}}, 1'b1}) << EST_BIAS_BIT) :
                {EST_WIDTH{1'b0}}) :
            ((i_bias_p && !i_bias_n) ?
                ($signed({{(EST_WIDTH - 1){1'b0}}, 1'b1}) << EST_BIAS_BIT) :
                ((i_bias_n && !i_bias_p) ?
                    -($signed({{(EST_WIDTH - 1){1'b0}}, 1'b1}) << EST_BIAS_BIT) :
                    {EST_WIDTH{1'b0}}));
    assign w_u_est_split = w_sum_terms_est + w_bias_est;
    assign w_u_now = w_contrib >>> online_delay;
    assign w_v = (r_w <<< 1) + w_u_now;
    assign w_valid_now = i_ena && (r_feed_count >= ONLINE_DELAY_VALUE);

    // The selector thresholds are powers of two: +/-S/2, where
    // S=2^frac_bits.  A full signed comparator is unnecessary here and maps to
    // a long carry path.  This exact threshold decoder preserves the original
    // >= +S/2 and <= -S/2 rules while only inspecting the sign, the bits above
    // the half-scale boundary, and the exact negative-boundary low-zero case.
    assign w_sel_high_bits = w_v[acc_width - 2 -: (acc_width - frac_bits)];
    assign w_sel_low_bits = w_v[frac_bits - 2 : 0];
    assign w_sel_high_nonzero = |w_sel_high_bits;
    assign w_sel_high_all_one = &w_sel_high_bits;
    assign w_sel_low_zero = ~(|w_sel_low_bits);
    assign w_r_shift = r_w <<< 1;
    assign w_r_sum_shift = r_w_sum <<< 1;
    assign w_r_carry_shift = r_w_carry <<< 1;
    assign w_r_est = w_r_shift[acc_width - 1 : EST_LSB];
    assign w_r_sum_est = w_r_sum_shift[acc_width - 1 : EST_LSB];
    assign w_r_carry_est = w_r_carry_shift[acc_width - 1 : EST_LSB];
    assign w_u_est_exact = w_u_now[acc_width - 1 : EST_LSB];
    assign w_u_est =
        ((estimate_selector != 0) && (split_estimate != 0)) ?
            w_u_est_split : w_u_est_exact;
    // Carry-save residual rails are not individually sign-normalized.  In
    // redundant mode the selector therefore uses this small canonical
    // residual estimate instead of sign-extending the sum/carry rails.
    assign w_v_est_norm =
        (r_w_est_norm <<< 1) +
        {{(EST_ACC_WIDTH - EST_WIDTH){w_u_est[EST_WIDTH - 1]}}, w_u_est};
    assign w_v_est =
        (redundant_residual != 0) ?
            w_v_est_norm :
            ({{(EST_ACC_WIDTH - EST_WIDTH){w_r_est[EST_WIDTH - 1]}},
                w_r_est} +
             {{(EST_ACC_WIDTH - EST_WIDTH){w_u_est[EST_WIDTH - 1]}},
                w_u_est});
    assign w_est_half_scale = {{(EST_ACC_WIDTH - 1){1'b0}}, 1'b1} << EST_HALF_BIT;
    assign w_est_one_scale = w_est_half_scale << 1;
    assign w_est_pos_threshold = $signed(w_est_half_scale);
    assign w_est_neg_threshold = -$signed(w_est_half_scale);
    assign w_est_z_scaled =
        w_est_z_p ? $signed(w_est_one_scale) :
        (w_est_z_n ? -$signed(w_est_one_scale) :
            {EST_ACC_WIDTH{1'b0}});
    assign w_est_z_p = (w_v_est >= w_est_pos_threshold);
    assign w_est_z_n = (w_v_est <= w_est_neg_threshold);

    assign w_z_p = ((estimate_selector != 0) || (redundant_residual != 0)) ?
        w_est_z_p :
        (!w_v[acc_width - 1] && w_sel_high_nonzero);
    assign w_z_n = ((estimate_selector != 0) || (redundant_residual != 0)) ?
        w_est_z_n :
        (w_v[acc_width - 1] && ((!w_sel_high_all_one) || w_sel_low_zero));
    assign w_z_scaled = w_z_p ? SCALE : (w_z_n ? -SCALE : {acc_width{1'b0}});
    assign w_neg_z_scaled =
        w_z_p ? -SCALE : (w_z_n ? SCALE : {acc_width{1'b0}});

    // Carry-save residual update for the experimental redundant mode:
    //   w_next = 2*S + 2*C + u - z
    // without a final carry-propagate adder in the feedback path.
    assign w_csa1_sum = w_r_sum_shift ^ w_r_carry_shift ^ w_u_now;
    assign w_csa1_carry =
        ((w_r_sum_shift & w_r_carry_shift) |
         (w_r_sum_shift & w_u_now) |
         (w_r_carry_shift & w_u_now)) <<< 1;
    assign w_csa_next_sum = w_csa1_sum ^ w_csa1_carry ^ w_neg_z_scaled;
    assign w_csa_next_carry =
        ((w_csa1_sum & w_csa1_carry) |
         (w_csa1_sum & w_neg_z_scaled) |
         (w_csa1_carry & w_neg_z_scaled)) <<< 1;

    always @(posedge i_clk) begin
        if (i_rst) begin
            r_w <= {acc_width{1'b0}};
            r_w_sum <= {acc_width{1'b0}};
            r_w_carry <= {acc_width{1'b0}};
            r_w_est_norm <= {EST_ACC_WIDTH{1'b0}};
            r_feed_count <= {feed_count_width{1'b0}};
            o_z_p <= 1'b0;
            o_z_n <= 1'b0;
            o_valid <= 1'b0;
            o_z_p_groups <= {output_groups{1'b0}};
            o_z_n_groups <= {output_groups{1'b0}};
        end else begin
            o_valid <= 1'b0;
            if (i_ena) begin
                if (redundant_residual != 0) begin
                    r_w_sum <= w_valid_now ? w_csa_next_sum : w_csa1_sum;
                    r_w_carry <= w_valid_now ? w_csa_next_carry : w_csa1_carry;
                    r_w_est_norm <= w_valid_now ?
                        (w_v_est_norm - w_est_z_scaled) : w_v_est_norm;
                    r_w <= {acc_width{1'b0}};
                end else begin
                    r_w <= w_valid_now ? (w_v - w_z_scaled) : w_v;
                    r_w_sum <= {acc_width{1'b0}};
                    r_w_carry <= {acc_width{1'b0}};
                    r_w_est_norm <= {EST_ACC_WIDTH{1'b0}};
                end
                r_feed_count <= r_feed_count + 1'b1;
                // Keep digit data independent of valid/control.  Downstream
                // logic samples these rails only when o_valid is asserted, so
                // invalid cycles do not need to force the rails to zero.
                o_z_p <= w_z_p;
                o_z_n <= w_z_n;
                o_valid <= w_valid_now;
                o_z_p_groups <= {output_groups{w_z_p}};
                o_z_n_groups <= {output_groups{w_z_n}};
            end
        end
    end

endmodule
