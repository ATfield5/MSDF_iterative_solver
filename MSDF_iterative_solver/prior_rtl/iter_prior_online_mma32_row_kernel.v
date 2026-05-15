`timescale 1ns / 1ps

// 32-term prior-compatible row kernel.
//
// The original paper RTL provides MSDF_MUL_ADD_8, which consumes eight
// serial/serial product terms plus one bias digit stream.  This wrapper builds
// a 32-term row update without changing that original operator:
//
//   chunk0 = sum(term  0.. 7) + bias
//   chunk1 = sum(term  8..15)
//   chunk2 = sum(term 16..23)
//   chunk3 = sum(term 24..31)
//   out    = chunk0 + chunk1 + chunk2 + chunk3
//
// The four chunk outputs are still MSB-first signed-digit streams, so they are
// merged by a tree of the original serial online adders rather than by a binary
// full-word accumulator.

module iter_prior_online_mma32_row_kernel #(
    parameter integer degree = 32,
    parameter integer bit_width = 8,
    parameter integer digit_idx_width = (bit_width <= 2) ? 1 : $clog2(bit_width)
) (
    input                                               i_clk,
    input                                               i_rst,
    input                                               i_valid_digit,
    input      [digit_idx_width - 1 : 0]                i_digit_idx,
    input      [degree - 1 : 0]                         i_state_digit_p_terms,
    input      [degree - 1 : 0]                         i_state_digit_n_terms,
    input      [degree * bit_width - 1 : 0]             i_coeff_p_terms,
    input      [degree * bit_width - 1 : 0]             i_coeff_n_terms,
    input                                               i_bias_digit_p,
    input                                               i_bias_digit_n,
    output                                              o_z_p,
    output                                              o_z_n,
    output                                              o_int,
    output                                              o_unit,
    output                                              o_frac
);

    localparam integer NUM_CHUNKS = 4;
    localparam integer CHUNK_TERMS = 8;

    wire [NUM_CHUNKS - 1 : 0] w_chunk_z_p;
    wire [NUM_CHUNKS - 1 : 0] w_chunk_z_n;
    wire [NUM_CHUNKS - 1 : 0] w_chunk_int;
    wire [NUM_CHUNKS - 1 : 0] w_chunk_unit;
    wire [NUM_CHUNKS - 1 : 0] w_chunk_frac;
    wire [NUM_CHUNKS - 1 : 0] w_chunk_valid;

    wire w_sum01_p;
    wire w_sum01_n;
    wire w_sum01_valid;
    wire w_sum01_dot;
    wire w_sum23_p;
    wire w_sum23_n;
    wire w_sum23_valid;
    wire w_sum23_dot;
    wire w_final_valid;
    wire w_final_dot;

    reg r_seen_unit;

    genvar cg;
    genvar tg;
    generate
        for (cg = 0; cg < NUM_CHUNKS; cg = cg + 1) begin : gen_chunks
            wire [CHUNK_TERMS - 1 : 0] w_x_p;
            wire [CHUNK_TERMS - 1 : 0] w_x_n;
            wire [CHUNK_TERMS - 1 : 0] w_y_p;
            wire [CHUNK_TERMS - 1 : 0] w_y_n;
            wire w_bias_p;
            wire w_bias_n;

            for (tg = 0; tg < CHUNK_TERMS; tg = tg + 1) begin : gen_terms
                localparam integer TERM_IDX = cg * CHUNK_TERMS + tg;
                if (TERM_IDX < degree) begin : gen_real_term
                    assign w_x_p[tg] = i_state_digit_p_terms[TERM_IDX];
                    assign w_x_n[tg] = i_state_digit_n_terms[TERM_IDX];
                    assign w_y_p[tg] = i_coeff_p_terms[
                        TERM_IDX * bit_width + (bit_width - 1 - i_digit_idx)];
                    assign w_y_n[tg] = i_coeff_n_terms[
                        TERM_IDX * bit_width + (bit_width - 1 - i_digit_idx)];
                end else begin : gen_zero_term
                    assign w_x_p[tg] = 1'b0;
                    assign w_x_n[tg] = 1'b0;
                    assign w_y_p[tg] = 1'b0;
                    assign w_y_n[tg] = 1'b0;
                end
            end

            assign w_bias_p = (cg == 0) ? i_bias_digit_p : 1'b0;
            assign w_bias_n = (cg == 0) ? i_bias_digit_n : 1'b0;

            MSDF_MUL_ADD_8 #(
                .bit_width(bit_width)
            ) prior_chunk (
                .i_clk(i_clk),
                .i_rst(i_rst),
                .i_ena(i_valid_digit),
                .i_x_p(w_x_p),
                .i_x_n(w_x_n),
                .i_y_p(w_y_p),
                .i_y_n(w_y_n),
                .i_a_p(w_bias_p),
                .i_a_n(w_bias_n),
                .o_z_p(w_chunk_z_p[cg]),
                .o_z_n(w_chunk_z_n[cg]),
                .o_int(w_chunk_int[cg]),
                .o_unit(w_chunk_unit[cg]),
                .o_frac(w_chunk_frac[cg])
            );

            assign w_chunk_valid[cg] =
                w_chunk_int[cg] || w_chunk_unit[cg] || w_chunk_frac[cg];
        end
    endgenerate

    MSDF_ADD add01 (
        .i_clk(i_clk),
        .i_rst(i_rst),
        .i_ena(w_chunk_valid[0] && w_chunk_valid[1]),
        .i_x_p(w_chunk_z_p[0]),
        .i_x_n(w_chunk_z_n[0]),
        .i_y_p(w_chunk_z_p[1]),
        .i_y_n(w_chunk_z_n[1]),
        .i_dot(w_chunk_unit[0]),
        .o_z_p(w_sum01_p),
        .o_z_n(w_sum01_n),
        .o_valid(w_sum01_valid),
        .o_dot(w_sum01_dot)
    );

    MSDF_ADD add23 (
        .i_clk(i_clk),
        .i_rst(i_rst),
        .i_ena(w_chunk_valid[2] && w_chunk_valid[3]),
        .i_x_p(w_chunk_z_p[2]),
        .i_x_n(w_chunk_z_n[2]),
        .i_y_p(w_chunk_z_p[3]),
        .i_y_n(w_chunk_z_n[3]),
        .i_dot(w_chunk_unit[2]),
        .o_z_p(w_sum23_p),
        .o_z_n(w_sum23_n),
        .o_valid(w_sum23_valid),
        .o_dot(w_sum23_dot)
    );

    MSDF_ADD add_final (
        .i_clk(i_clk),
        .i_rst(i_rst),
        .i_ena(w_sum01_valid && w_sum23_valid),
        .i_x_p(w_sum01_p),
        .i_x_n(w_sum01_n),
        .i_y_p(w_sum23_p),
        .i_y_n(w_sum23_n),
        .i_dot(w_sum01_dot),
        .o_z_p(o_z_p),
        .o_z_n(o_z_n),
        .o_valid(w_final_valid),
        .o_dot(w_final_dot)
    );

    assign o_unit = w_final_valid && w_final_dot;
    assign o_int = w_final_valid && !r_seen_unit && !w_final_dot;
    assign o_frac = w_final_valid && r_seen_unit && !w_final_dot;

    always @(posedge i_clk) begin
        if (i_rst) begin
            r_seen_unit <= 1'b0;
        end else if (w_final_valid && w_final_dot) begin
            r_seen_unit <= 1'b1;
        end
    end

endmodule
