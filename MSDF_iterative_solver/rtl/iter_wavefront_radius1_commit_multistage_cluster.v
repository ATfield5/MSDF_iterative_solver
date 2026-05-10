`timescale 1ns / 1ps

// K-stage radius-1 wavefront using committed state digits between stages.
//
// This is the runtime-compatible counterpart of
// iter_wavefront_radius1_multistage_cluster.  The next stage consumes only the
// fixed-width committed digit stream emitted after each row engine's online
// skip/drain boundary.

module iter_wavefront_radius1_commit_multistage_cluster #(
    parameter integer num_stages = 4,
    parameter integer num_rows = 3,
    parameter integer degree = 4,
    parameter integer bit_width = 5,
    parameter integer data_width = bit_width + 3,
    parameter integer bias_width = bit_width + 2,
    parameter integer skip_digits = 4,
    parameter integer sample_width = 5,
    parameter integer affine_guard_shift = 3,
    parameter integer residual_width = data_width + affine_guard_shift + 1,
    parameter integer row_idx_width = (num_rows <= 2) ? 1 : $clog2(num_rows),
    parameter integer source_rows = num_rows,
    parameter integer src_idx_width = row_idx_width,
    parameter integer digit_idx_width = (data_width <= 2) ? 1 : $clog2(data_width),
    parameter integer inter_stage_delay_cycles = 0,
    parameter integer inter_stage_source_mode = 0,
    parameter integer source_packet_width = digit_idx_width + 2 * num_rows
) (
    input                                               i_clk,
    input                                               i_rst,
    input                                               i_start,
    input                                               i_valid_digit,
    input      [digit_idx_width - 1 : 0]                i_digit_idx,
    input      [num_rows * degree - 1 : 0]              i_stage0_state_digit_p_terms_rows,
    input      [num_rows * degree - 1 : 0]              i_stage0_state_digit_n_terms_rows,
    input      [num_stages * num_rows * degree * bit_width - 1 : 0] i_coeff_p_terms_stages,
    input      [num_stages * num_rows * degree * bit_width - 1 : 0] i_coeff_n_terms_stages,
    input      [num_stages * num_rows * bias_width - 1 : 0] i_bias_p_stages,
    input      [num_stages * num_rows * bias_width - 1 : 0] i_bias_n_stages,
    input      [num_rows * degree * src_idx_width - 1 : 0]  i_stage_src_row_idx,
    input      [num_stages * source_rows - 1 : 0]           i_external_stage_source_p_rows,
    input      [num_stages * source_rows - 1 : 0]           i_external_stage_source_n_rows,
    output     [num_stages * num_rows - 1 : 0]          o_stage_commit_valid_rows,
    output     [num_stages * num_rows * digit_idx_width - 1 : 0] o_stage_commit_digit_idx_rows,
    output     [num_stages * num_rows - 1 : 0]          o_stage_commit_digit_p_rows,
    output     [num_stages * num_rows - 1 : 0]          o_stage_commit_digit_n_rows,
    output     [num_stages * num_rows - 1 : 0]          o_stage_commit_done_rows,
    output     [num_rows - 1 : 0]                       o_final_valid_rows,
    output     [num_rows * digit_idx_width - 1 : 0]     o_final_digit_idx_rows,
    output     [num_rows - 1 : 0]                       o_final_digit_p_rows,
    output     [num_rows - 1 : 0]                       o_final_digit_n_rows,
    output reg [num_stages * 32 - 1 : 0]                o_stage_valid_count,
    output reg [num_stages - 1 : 0]                     o_stage_done,
    output reg [num_stages - 2 : 0]                     o_stage_started_before_prev_done
);

    wire [num_stages - 1 : 0] w_stage_input_valid;
    wire [num_stages - 1 : 0] w_stage_start;
    wire [num_stages * digit_idx_width - 1 : 0] w_stage_input_digit_idx;
    wire [num_stages * source_rows - 1 : 0] w_stage_source_p_rows;
    wire [num_stages * source_rows - 1 : 0] w_stage_source_n_rows;
    wire [num_stages * num_rows * degree - 1 : 0] w_stage_state_p_terms;
    wire [num_stages * num_rows * degree - 1 : 0] w_stage_state_n_terms;

    integer si_seq;

    assign o_final_valid_rows =
        o_stage_commit_valid_rows[(num_stages - 1) * num_rows +: num_rows];
    assign o_final_digit_idx_rows =
        o_stage_commit_digit_idx_rows[(num_stages - 1) *
            num_rows * digit_idx_width +: num_rows * digit_idx_width];
    assign o_final_digit_p_rows =
        o_stage_commit_digit_p_rows[(num_stages - 1) * num_rows +: num_rows];
    assign o_final_digit_n_rows =
        o_stage_commit_digit_n_rows[(num_stages - 1) * num_rows +: num_rows];

    genvar si;
    genvar ri;
    genvar ti;
    generate
        for (si = 0; si < num_stages; si = si + 1) begin : gen_stage
            if (si == 0) begin : gen_stage0_source
                assign w_stage_input_valid[si] = i_valid_digit;
                assign w_stage_start[si] = i_start;
                assign w_stage_input_digit_idx[si * digit_idx_width +: digit_idx_width] =
                    i_digit_idx;
                for (ri = 0; ri < num_rows; ri = ri + 1) begin : gen_stage0_rows
                    assign w_stage_state_p_terms[(si * num_rows + ri) * degree +: degree] =
                        i_stage0_state_digit_p_terms_rows[ri * degree +: degree];
                    assign w_stage_state_n_terms[(si * num_rows + ri) * degree +: degree] =
                        i_stage0_state_digit_n_terms_rows[ri * degree +: degree];
                end
            end else begin : gen_committed_source
                wire [source_packet_width - 1 : 0] w_packet_in;
                wire [source_packet_width - 1 : 0] w_packet_out;

                assign w_packet_in = {
                    o_stage_commit_digit_idx_rows[(si - 1) * num_rows *
                        digit_idx_width +: digit_idx_width],
                    o_stage_commit_digit_p_rows[(si - 1) * num_rows +: num_rows],
                    o_stage_commit_digit_n_rows[(si - 1) * num_rows +: num_rows]
                };

                iter_wavefront_digit_delay_line #(
                    .data_width(source_packet_width),
                    .delay_cycles(inter_stage_delay_cycles)
                ) source_delay (
                    .i_clk(i_clk),
                    .i_rst(i_rst || i_start),
                    .i_valid(o_stage_commit_valid_rows[(si - 1) * num_rows + 0]),
                    .i_data(w_packet_in),
                    .o_valid(w_stage_input_valid[si]),
                    .o_data(w_packet_out)
                );

                assign w_stage_input_digit_idx[si * digit_idx_width +: digit_idx_width] =
                    w_packet_out[source_packet_width - 1 -: digit_idx_width];
                if (inter_stage_source_mode == 2) begin : gen_external_source_rows
                    assign w_stage_source_p_rows[si * source_rows +: source_rows] =
                        i_external_stage_source_p_rows[si * source_rows +: source_rows];
                    assign w_stage_source_n_rows[si * source_rows +: source_rows] =
                        i_external_stage_source_n_rows[si * source_rows +: source_rows];
                end else begin : gen_local_source_rows
                    assign w_stage_source_p_rows[si * source_rows +: source_rows] =
                        w_packet_out[2 * num_rows - 1 -: num_rows];
                    assign w_stage_source_n_rows[si * source_rows +: source_rows] =
                        w_packet_out[num_rows - 1 : 0];
                end
                assign w_stage_start[si] =
                    w_stage_input_valid[si] &&
                    (w_stage_input_digit_idx[si * digit_idx_width +: digit_idx_width] ==
                        {digit_idx_width{1'b0}});

                for (ri = 0; ri < num_rows; ri = ri + 1) begin : gen_wave_rows
                    for (ti = 0; ti < degree; ti = ti + 1) begin : gen_wave_terms
                        if (inter_stage_source_mode != 0) begin : gen_template_source
                            wire [src_idx_width - 1 : 0] w_src_row;

                            assign w_src_row = i_stage_src_row_idx[
                                (ri * degree + ti) * src_idx_width +: src_idx_width];
                            assign w_stage_state_p_terms[(si * num_rows + ri) * degree + ti] =
                                (w_src_row < source_rows)
                                    ? w_stage_source_p_rows[si * source_rows + w_src_row]
                                    : 1'b0;
                            assign w_stage_state_n_terms[(si * num_rows + ri) * degree + ti] =
                                (w_src_row < source_rows)
                                    ? w_stage_source_n_rows[si * source_rows + w_src_row]
                                    : 1'b0;
                        end else begin : gen_radius1_source
                            if (ti == 0) begin : gen_left_source
                                if (ri == 0) begin : gen_left_boundary
                                    assign w_stage_state_p_terms[(si * num_rows + ri) * degree + ti] = 1'b0;
                                    assign w_stage_state_n_terms[(si * num_rows + ri) * degree + ti] = 1'b0;
                                end else begin : gen_left_neighbor
                                    assign w_stage_state_p_terms[(si * num_rows + ri) * degree + ti] =
                                        w_stage_source_p_rows[si * num_rows + (ri - 1)];
                                    assign w_stage_state_n_terms[(si * num_rows + ri) * degree + ti] =
                                        w_stage_source_n_rows[si * num_rows + (ri - 1)];
                                end
                            end else if (ti == 1) begin : gen_self_source
                                assign w_stage_state_p_terms[(si * num_rows + ri) * degree + ti] =
                                    w_stage_source_p_rows[si * num_rows + ri];
                                assign w_stage_state_n_terms[(si * num_rows + ri) * degree + ti] =
                                    w_stage_source_n_rows[si * num_rows + ri];
                            end else if (ti == 2) begin : gen_right_source
                                if (ri == num_rows - 1) begin : gen_right_boundary
                                    assign w_stage_state_p_terms[(si * num_rows + ri) * degree + ti] = 1'b0;
                                    assign w_stage_state_n_terms[(si * num_rows + ri) * degree + ti] = 1'b0;
                                end else begin : gen_right_neighbor
                                    assign w_stage_state_p_terms[(si * num_rows + ri) * degree + ti] =
                                        w_stage_source_p_rows[si * num_rows + (ri + 1)];
                                    assign w_stage_state_n_terms[(si * num_rows + ri) * degree + ti] =
                                        w_stage_source_n_rows[si * num_rows + (ri + 1)];
                                end
                            end else begin : gen_zero_source
                                assign w_stage_state_p_terms[(si * num_rows + ri) * degree + ti] = 1'b0;
                                assign w_stage_state_n_terms[(si * num_rows + ri) * degree + ti] = 1'b0;
                            end
                        end
                    end
                end
            end

            iter_wavefront_commit_stage_cluster #(
                .num_rows(num_rows),
                .degree(degree),
                .bit_width(bit_width),
                .data_width(data_width),
                .bias_width(bias_width),
                .skip_digits(skip_digits),
                .sample_width(sample_width),
                .affine_guard_shift(affine_guard_shift),
                .residual_width(residual_width),
                .digit_idx_width(digit_idx_width)
            ) stage_cluster (
                .i_clk(i_clk),
                .i_rst(i_rst),
                .i_clear(i_start),
                .i_start(w_stage_start[si]),
                .i_valid_digit(w_stage_input_valid[si]),
                .i_digit_idx(w_stage_input_digit_idx[si * digit_idx_width +: digit_idx_width]),
                .i_state_digit_p_terms_rows(w_stage_state_p_terms[(si * num_rows) *
                    degree +: num_rows * degree]),
                .i_state_digit_n_terms_rows(w_stage_state_n_terms[(si * num_rows) *
                    degree +: num_rows * degree]),
                .i_coeff_p_terms_rows(i_coeff_p_terms_stages[(si * num_rows) *
                    degree * bit_width +: num_rows * degree * bit_width]),
                .i_coeff_n_terms_rows(i_coeff_n_terms_stages[(si * num_rows) *
                    degree * bit_width +: num_rows * degree * bit_width]),
                .i_bias_p_rows(i_bias_p_stages[si * num_rows *
                    bias_width +: num_rows * bias_width]),
                .i_bias_n_rows(i_bias_n_stages[si * num_rows *
                    bias_width +: num_rows * bias_width]),
                .o_raw_valid_rows(),
                .o_raw_digit_p_rows(),
                .o_raw_digit_n_rows(),
                .o_commit_valid_rows(o_stage_commit_valid_rows[si * num_rows +: num_rows]),
                .o_commit_digit_idx_rows(o_stage_commit_digit_idx_rows[si *
                    num_rows * digit_idx_width +: num_rows * digit_idx_width]),
                .o_commit_digit_p_rows(o_stage_commit_digit_p_rows[si * num_rows +: num_rows]),
                .o_commit_digit_n_rows(o_stage_commit_digit_n_rows[si * num_rows +: num_rows]),
                .o_commit_done_rows(o_stage_commit_done_rows[si * num_rows +: num_rows])
            );
        end
    endgenerate

    always @(posedge i_clk) begin
        if (i_rst || i_start) begin
            o_stage_valid_count <= {num_stages * 32{1'b0}};
            o_stage_done <= {num_stages{1'b0}};
            o_stage_started_before_prev_done <= {(num_stages - 1){1'b0}};
        end else begin
            for (si_seq = 0; si_seq < num_stages; si_seq = si_seq + 1) begin
                if (si_seq > 0 && w_stage_input_valid[si_seq] &&
                    !o_stage_done[si_seq - 1]) begin
                    o_stage_started_before_prev_done[si_seq - 1] <= 1'b1;
                end

                if (o_stage_commit_valid_rows[si_seq * num_rows + 0]) begin
                    if (!o_stage_done[si_seq]) begin
                        if (o_stage_valid_count[si_seq * 32 +: 32] == data_width - 1) begin
                            o_stage_done[si_seq] <= 1'b1;
                        end
                        o_stage_valid_count[si_seq * 32 +: 32] <=
                            o_stage_valid_count[si_seq * 32 +: 32] + 1'b1;
                    end
                end
            end
        end
    end

endmodule
