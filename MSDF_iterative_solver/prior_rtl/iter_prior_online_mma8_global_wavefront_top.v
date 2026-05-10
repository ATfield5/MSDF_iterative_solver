`timescale 1ns / 1ps

// Global-source K-stage PageRank wavefront built from the original
// MSDF_MUL_ADD_8 prior operator.
//
// This top is intentionally standalone.  It proves the strict prior-fractional
// stage-to-stage contract before the path is integrated into the full runtime
// loader/controller shell.

module iter_prior_online_mma8_global_wavefront_top #(
    parameter integer num_stages = 4,
    parameter integer num_rows = 32,
    parameter integer degree = 4,
    parameter integer bit_width = 11,
    parameter integer data_width = bit_width + 3,
    parameter integer bias_width = bit_width + 2,
    parameter integer src_idx_width = (num_rows <= 2) ? 1 : $clog2(num_rows),
    parameter integer capture_unit = 0,
    parameter integer digit_idx_width = (data_width <= 2) ? 1 : $clog2(data_width),
    parameter integer source_packet_width = digit_idx_width + 2 * num_rows
) (
    input                                                   i_clk,
    input                                                   i_rst,
    input                                                   i_clear,
    input                                                   i_start,
    input                                                   i_valid_digit,
    input      [digit_idx_width - 1 : 0]                    i_digit_idx,
    input      [num_rows * degree - 1 : 0]                  i_stage0_state_digit_p_terms_rows,
    input      [num_rows * degree - 1 : 0]                  i_stage0_state_digit_n_terms_rows,
    input      [num_rows * degree * src_idx_width - 1 : 0]  i_src_row_idx_rows,
    input      [num_rows * degree * bit_width - 1 : 0]      i_coeff_p_terms_rows,
    input      [num_rows * degree * bit_width - 1 : 0]      i_coeff_n_terms_rows,
    input      [num_rows * bias_width - 1 : 0]              i_bias_p_rows,
    input      [num_rows * bias_width - 1 : 0]              i_bias_n_rows,
    output     [num_rows - 1 : 0]                           o_final_valid_rows,
    output     [num_rows * digit_idx_width - 1 : 0]         o_final_digit_idx_rows,
    output     [num_rows - 1 : 0]                           o_final_digit_p_rows,
    output     [num_rows - 1 : 0]                           o_final_digit_n_rows,
    output     [num_rows - 1 : 0]                           o_final_done_rows,
    output     [num_stages * num_rows - 1 : 0]              o_stage_valid_rows,
    output     [num_stages * num_rows * digit_idx_width - 1 : 0] o_stage_digit_idx_rows,
    output     [num_stages * num_rows - 1 : 0]              o_stage_digit_p_rows,
    output     [num_stages * num_rows - 1 : 0]              o_stage_digit_n_rows,
    output     [num_stages * num_rows - 1 : 0]              o_stage_done_rows,
    output reg [num_stages * 32 - 1 : 0]                    o_stage_valid_count,
    output reg [num_stages - 1 : 0]                         o_stage_done,
    output reg [num_stages - 2 : 0]                         o_stage_started_before_prev_done
);

    wire [num_stages - 1 : 0] w_stage_input_valid;
    wire [num_stages - 1 : 0] w_stage_start;
    wire [num_stages * digit_idx_width - 1 : 0] w_stage_digit_idx;
    wire [num_stages * num_rows * degree - 1 : 0] w_stage_state_p_terms;
    wire [num_stages * num_rows * degree - 1 : 0] w_stage_state_n_terms;

    integer si_seq;

    assign o_final_valid_rows =
        o_stage_valid_rows[(num_stages - 1) * num_rows +: num_rows];
    assign o_final_digit_idx_rows =
        o_stage_digit_idx_rows[(num_stages - 1) *
            num_rows * digit_idx_width +: num_rows * digit_idx_width];
    assign o_final_digit_p_rows =
        o_stage_digit_p_rows[(num_stages - 1) * num_rows +: num_rows];
    assign o_final_digit_n_rows =
        o_stage_digit_n_rows[(num_stages - 1) * num_rows +: num_rows];
    assign o_final_done_rows =
        o_stage_done_rows[(num_stages - 1) * num_rows +: num_rows];

    genvar si;
    genvar ri;
    genvar ti;
    generate
        for (si = 0; si < num_stages; si = si + 1) begin : gen_stage
            if (si == 0) begin : gen_stage0_source
                assign w_stage_input_valid[si] = i_valid_digit;
                assign w_stage_start[si] = i_start;
                assign w_stage_digit_idx[si * digit_idx_width +: digit_idx_width] =
                    i_digit_idx;
                assign w_stage_state_p_terms[si * num_rows * degree +:
                    num_rows * degree] = i_stage0_state_digit_p_terms_rows;
                assign w_stage_state_n_terms[si * num_rows * degree +:
                    num_rows * degree] = i_stage0_state_digit_n_terms_rows;
            end else begin : gen_prev_stage_source
                assign w_stage_input_valid[si] =
                    o_stage_valid_rows[(si - 1) * num_rows + 0];
                assign w_stage_digit_idx[si * digit_idx_width +: digit_idx_width] =
                    o_stage_digit_idx_rows[(si - 1) * num_rows *
                        digit_idx_width +: digit_idx_width];
                assign w_stage_start[si] =
                    w_stage_input_valid[si] &&
                    (w_stage_digit_idx[si * digit_idx_width +: digit_idx_width] ==
                     {digit_idx_width{1'b0}});

                for (ri = 0; ri < num_rows; ri = ri + 1) begin : gen_rows
                    for (ti = 0; ti < degree; ti = ti + 1) begin : gen_terms
                        wire [src_idx_width - 1 : 0] w_src_row;

                        assign w_src_row = i_src_row_idx_rows[
                            (ri * degree + ti) * src_idx_width +: src_idx_width];
                        assign w_stage_state_p_terms[
                            (si * num_rows + ri) * degree + ti] =
                            (w_src_row < num_rows)
                                ? o_stage_digit_p_rows[(si - 1) * num_rows + w_src_row]
                                : 1'b0;
                        assign w_stage_state_n_terms[
                            (si * num_rows + ri) * degree + ti] =
                            (w_src_row < num_rows)
                                ? o_stage_digit_n_rows[(si - 1) * num_rows + w_src_row]
                                : 1'b0;
                    end
                end
            end

            iter_prior_online_mma8_stream_stage_cluster #(
                .num_rows(num_rows),
                .degree(degree),
                .bit_width(bit_width),
                .data_width(data_width),
                .bias_width(bias_width),
                .capture_unit(capture_unit),
                .digit_idx_width(digit_idx_width)
            ) stage_cluster (
                .i_clk(i_clk),
                .i_rst(i_rst),
                .i_clear(i_clear),
                .i_start(w_stage_start[si]),
                .i_valid_digit(w_stage_input_valid[si]),
                .i_digit_idx(w_stage_digit_idx[si * digit_idx_width +:
                    digit_idx_width]),
                .i_state_digit_p_terms_rows(w_stage_state_p_terms[
                    si * num_rows * degree +: num_rows * degree]),
                .i_state_digit_n_terms_rows(w_stage_state_n_terms[
                    si * num_rows * degree +: num_rows * degree]),
                .i_coeff_p_terms_rows(i_coeff_p_terms_rows),
                .i_coeff_n_terms_rows(i_coeff_n_terms_rows),
                .i_bias_p_rows(i_bias_p_rows),
                .i_bias_n_rows(i_bias_n_rows),
                .o_commit_valid_rows(o_stage_valid_rows[si * num_rows +: num_rows]),
                .o_commit_digit_idx_rows(o_stage_digit_idx_rows[si *
                    num_rows * digit_idx_width +: num_rows * digit_idx_width]),
                .o_commit_digit_p_rows(o_stage_digit_p_rows[si * num_rows +:
                    num_rows]),
                .o_commit_digit_n_rows(o_stage_digit_n_rows[si * num_rows +:
                    num_rows]),
                .o_commit_done_rows(o_stage_done_rows[si * num_rows +: num_rows]),
                .o_busy()
            );
        end
    endgenerate

    always @(posedge i_clk) begin
        if (i_rst || i_clear) begin
            o_stage_valid_count <= {num_stages * 32{1'b0}};
            o_stage_done <= {num_stages{1'b0}};
            o_stage_started_before_prev_done <= {(num_stages - 1){1'b0}};
        end else begin
            for (si_seq = 0; si_seq < num_stages; si_seq = si_seq + 1) begin
                if (si_seq > 0 &&
                    w_stage_input_valid[si_seq] &&
                    !o_stage_done[si_seq - 1]) begin
                    o_stage_started_before_prev_done[si_seq - 1] <= 1'b1;
                end

                if (o_stage_valid_rows[si_seq * num_rows + 0] &&
                    !o_stage_done[si_seq]) begin
                    if (o_stage_valid_count[si_seq * 32 +: 32] == data_width - 1) begin
                        o_stage_done[si_seq] <= 1'b1;
                    end
                    o_stage_valid_count[si_seq * 32 +: 32] <=
                        o_stage_valid_count[si_seq * 32 +: 32] + 1'b1;
                end
            end
        end
    end

endmodule
