`timescale 1ns / 1ps

// Continuous feedback PageRank wavefront built from the original
// MSDF_MUL_ADD_8 prior operator.
//
// Compared with iter_prior_online_mma8_global_wavefront_top, this module does
// not stop after one K-stage super-step.  Final-stage committed digits are
// buffered as a stream and can feed stage 0 again, creating:
//
//   x^(k) -> x^(k+K) -> x^(k+2K) ...
//
// The feedback path stores committed digit packets, not reconstructed full
// words.  Stage-wise L1 delta is computed from captured digit streams for
// convergence observation and speculative-stop control.

module iter_prior_online_mma8_global_feedback_top #(
    parameter integer num_stages = 4,
    parameter integer num_rows = 32,
    parameter integer degree = 4,
    parameter integer bit_width = 11,
    parameter integer data_width = bit_width + 3,
    parameter integer bias_width = bit_width + 2,
    parameter integer bound_width = 16,
    parameter integer acc_width = 24,
    parameter integer src_idx_width = (num_rows <= 2) ? 1 : $clog2(num_rows),
    parameter integer capture_unit = 0,
    parameter integer feedback_fifo_depth = 64,
    parameter integer digit_idx_width = (data_width <= 2) ? 1 : $clog2(data_width),
    parameter integer fifo_ptr_width = (feedback_fifo_depth <= 2) ? 1 : $clog2(feedback_fifo_depth),
    parameter integer fifo_count_width = (feedback_fifo_depth <= 2) ? 2 : $clog2(feedback_fifo_depth + 1),
    parameter integer converged_stage_width = (num_stages <= 2) ? 1 : $clog2(num_stages)
) (
    input                                                   i_clk,
    input                                                   i_rst,
    input                                                   i_clear,
    input                                                   i_start,
    input                                                   i_valid_digit,
    input      [digit_idx_width - 1 : 0]                    i_digit_idx,
    input      [num_rows - 1 : 0]                           i_stage0_state_digit_p_rows,
    input      [num_rows - 1 : 0]                           i_stage0_state_digit_n_rows,
    input      [num_rows * degree * src_idx_width - 1 : 0]  i_src_row_idx_rows,
    input      [num_rows * degree * bit_width - 1 : 0]      i_coeff_p_terms_rows,
    input      [num_rows * degree * bit_width - 1 : 0]      i_coeff_n_terms_rows,
    input      [num_rows * bias_width - 1 : 0]              i_bias_p_rows,
    input      [num_rows * bias_width - 1 : 0]              i_bias_n_rows,
    input      [acc_width - 1 : 0]                          i_l1_eta,
    input      [acc_width - 1 : 0]                          i_l1_tail_bound_per_row,
    input                                                   i_stop_on_converged,
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
    output reg [num_stages * 32 - 1 : 0]                    o_stage_l1_valid_count,
    output reg [num_stages * acc_width - 1 : 0]             o_stage_l1_delta,
    output reg [num_stages - 1 : 0]                         o_stage_l1_valid,
    output reg [num_stages - 1 : 0]                         o_stage_done,
    output reg [num_stages - 2 : 0]                         o_stage_started_before_prev_done,
    output reg [31 : 0]                                     o_superstep_count,
    output reg [31 : 0]                                     o_feedback_fifo_stall,
    output reg [31 : 0]                                     o_cert_late_cycles,
    output reg [num_stages * 32 - 1 : 0]                    o_converged_stage_histogram,
    output reg [31 : 0]                                     o_speculative_kill_digits,
    output reg                                              o_converged,
    output reg [converged_stage_width - 1 : 0]              o_converged_stage
);

    wire [num_stages - 1 : 0] w_stage_input_valid;
    wire [num_stages - 1 : 0] w_stage_start;
    wire [num_stages - 1 : 0] w_stage_busy;
    wire [num_stages * digit_idx_width - 1 : 0] w_stage_digit_idx;
    wire [num_stages * num_rows * degree - 1 : 0] w_stage_state_p_terms;
    wire [num_stages * num_rows * degree - 1 : 0] w_stage_state_n_terms;

    reg r_external_active;
    reg [digit_idx_width - 1 : 0] r_external_count;
    reg r_feedback_operand_active;
    reg [digit_idx_width - 1 : 0] r_feedback_count;
    reg r_stop_requested;

    reg [digit_idx_width - 1 : 0] r_fifo_idx [0 : feedback_fifo_depth - 1];
    reg [num_rows - 1 : 0] r_fifo_p [0 : feedback_fifo_depth - 1];
    reg [num_rows - 1 : 0] r_fifo_n [0 : feedback_fifo_depth - 1];
    reg [fifo_ptr_width - 1 : 0] r_fifo_wr_ptr;
    reg [fifo_ptr_width - 1 : 0] r_fifo_rd_ptr;
    reg [fifo_count_width - 1 : 0] r_fifo_count;

    reg [num_rows * data_width - 1 : 0] r_stage_old_p [0 : num_stages - 1];
    reg [num_rows * data_width - 1 : 0] r_stage_old_n [0 : num_stages - 1];
    reg [num_rows * data_width - 1 : 0] r_stage_new_p [0 : num_stages - 1];
    reg [num_rows * data_width - 1 : 0] r_stage_new_n [0 : num_stages - 1];
    reg [num_stages - 1 : 0] r_l1_pending;
    reg [num_stages - 1 : 0] r_stage_local_clear;

    wire w_final_valid;
    wire w_final_done;
    wire w_fifo_empty;
    wire w_fifo_full;
    wire [digit_idx_width - 1 : 0] w_fifo_head_idx;
    wire [num_rows - 1 : 0] w_fifo_head_p;
    wire [num_rows - 1 : 0] w_fifo_head_n;
    wire w_feedback_start;
    wire w_first_downstream_ready;
    wire w_feedback_dequeue;
    wire [num_rows - 1 : 0] w_stage0_source_p_rows;
    wire [num_rows - 1 : 0] w_stage0_source_n_rows;

    integer si_seq;
    integer ri_seq;
    integer bit_sel_seq;
    integer fifo_i;
    integer l1_sum;
    integer row_new_value;
    integer row_old_value;
    integer row_delta_value;
    integer tail_sum;

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

    assign w_final_valid = o_final_valid_rows[0];
    assign w_final_done = o_final_done_rows[0];
    assign w_fifo_empty = (r_fifo_count == {fifo_count_width{1'b0}});
    assign w_fifo_full = (r_fifo_count == feedback_fifo_depth[fifo_count_width - 1 : 0]);
    assign w_fifo_head_idx = r_fifo_idx[r_fifo_rd_ptr];
    assign w_fifo_head_p = r_fifo_p[r_fifo_rd_ptr];
    assign w_fifo_head_n = r_fifo_n[r_fifo_rd_ptr];
    assign w_first_downstream_ready = !w_stage_busy[1];
    assign w_feedback_start =
        !r_external_active &&
        !r_feedback_operand_active &&
        !w_stage_busy[0] &&
        w_first_downstream_ready &&
        !w_fifo_empty &&
        !r_stop_requested &&
        (w_fifo_head_idx == {digit_idx_width{1'b0}});
    assign w_feedback_dequeue =
        (r_feedback_operand_active || w_feedback_start) &&
        !w_fifo_empty &&
        !r_stop_requested;
    assign w_stage0_source_p_rows = r_feedback_operand_active || w_feedback_start
        ? w_fifo_head_p
        : i_stage0_state_digit_p_rows;
    assign w_stage0_source_n_rows = r_feedback_operand_active || w_feedback_start
        ? w_fifo_head_n
        : i_stage0_state_digit_n_rows;

    function integer rail_value;
        input [data_width - 1 : 0] p_word;
        input [data_width - 1 : 0] n_word;
        begin
            rail_value = p_word - n_word;
        end
    endfunction

    genvar si;
    genvar ri;
    genvar ti;
    generate
        for (si = 0; si < num_stages; si = si + 1) begin : gen_stage
            if (si == 0) begin : gen_stage0_source
                assign w_stage_input_valid[si] = r_feedback_operand_active ||
                    w_feedback_start ? w_feedback_dequeue : i_valid_digit;
                assign w_stage_start[si] = r_feedback_operand_active ||
                    w_feedback_start ? w_feedback_start : i_start;
                assign w_stage_digit_idx[si * digit_idx_width +: digit_idx_width] =
                    r_feedback_operand_active || w_feedback_start
                        ? w_fifo_head_idx
                        : i_digit_idx;

                for (ri = 0; ri < num_rows; ri = ri + 1) begin : gen_rows
                    for (ti = 0; ti < degree; ti = ti + 1) begin : gen_terms
                        wire [src_idx_width - 1 : 0] w_src_row;

                        assign w_src_row = i_src_row_idx_rows[
                            (ri * degree + ti) * src_idx_width +: src_idx_width];
                        assign w_stage_state_p_terms[
                            (si * num_rows + ri) * degree + ti] =
                            (w_src_row < num_rows)
                                ? w_stage0_source_p_rows[w_src_row]
                                : 1'b0;
                        assign w_stage_state_n_terms[
                            (si * num_rows + ri) * degree + ti] =
                            (w_src_row < num_rows)
                                ? w_stage0_source_n_rows[w_src_row]
                                : 1'b0;
                    end
                end
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
                .i_clear(i_clear || r_stage_local_clear[si]),
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
                .o_busy(w_stage_busy[si])
            );
        end
    endgenerate

    always @(posedge i_clk) begin
        if (i_rst || i_clear) begin
            r_external_active <= 1'b0;
            r_external_count <= {digit_idx_width{1'b0}};
            r_feedback_operand_active <= 1'b0;
            r_feedback_count <= {digit_idx_width{1'b0}};
            r_stop_requested <= 1'b0;
            r_fifo_wr_ptr <= {fifo_ptr_width{1'b0}};
            r_fifo_rd_ptr <= {fifo_ptr_width{1'b0}};
            r_fifo_count <= {fifo_count_width{1'b0}};
            o_stage_valid_count <= {num_stages * 32{1'b0}};
            o_stage_l1_valid_count <= {num_stages * 32{1'b0}};
            o_stage_l1_delta <= {num_stages * acc_width{1'b0}};
            o_stage_l1_valid <= {num_stages{1'b0}};
            o_stage_done <= {num_stages{1'b0}};
            o_stage_started_before_prev_done <= {(num_stages - 1){1'b0}};
            o_superstep_count <= 32'd0;
            o_feedback_fifo_stall <= 32'd0;
            o_cert_late_cycles <= 32'd0;
            o_converged_stage_histogram <= {num_stages * 32{1'b0}};
            o_speculative_kill_digits <= 32'd0;
            o_converged <= 1'b0;
            o_converged_stage <= {converged_stage_width{1'b0}};
            r_l1_pending <= {num_stages{1'b0}};
            r_stage_local_clear <= {num_stages{1'b0}};
            for (fifo_i = 0; fifo_i < feedback_fifo_depth; fifo_i = fifo_i + 1) begin
                r_fifo_idx[fifo_i] <= {digit_idx_width{1'b0}};
                r_fifo_p[fifo_i] <= {num_rows{1'b0}};
                r_fifo_n[fifo_i] <= {num_rows{1'b0}};
            end
            for (si_seq = 0; si_seq < num_stages; si_seq = si_seq + 1) begin
                r_stage_old_p[si_seq] <= {num_rows * data_width{1'b0}};
                r_stage_old_n[si_seq] <= {num_rows * data_width{1'b0}};
                r_stage_new_p[si_seq] <= {num_rows * data_width{1'b0}};
                r_stage_new_n[si_seq] <= {num_rows * data_width{1'b0}};
            end
        end else begin
            o_stage_l1_valid <= {num_stages{1'b0}};
            r_stage_local_clear <= {num_stages{1'b0}};

            if (i_start) begin
                r_external_active <= 1'b1;
                r_external_count <= {digit_idx_width{1'b0}};
            end

            if (i_valid_digit && (r_external_active || i_start)) begin
                if ((r_external_active ? r_external_count : {digit_idx_width{1'b0}}) ==
                    data_width - 1) begin
                    r_external_active <= 1'b0;
                    r_external_count <= {digit_idx_width{1'b0}};
                end else begin
                    r_external_count <= (r_external_active
                        ? r_external_count
                        : {digit_idx_width{1'b0}}) + 1'b1;
                end
            end

            if (w_feedback_start) begin
                r_feedback_operand_active <= 1'b1;
                r_feedback_count <= {digit_idx_width{1'b0}};
            end

            if (w_feedback_dequeue) begin
                if (r_feedback_count == data_width - 1) begin
                    r_feedback_operand_active <= 1'b0;
                    r_feedback_count <= {digit_idx_width{1'b0}};
                end else begin
                    r_feedback_count <= r_feedback_count + 1'b1;
                end
            end else if ((r_feedback_operand_active || w_feedback_start) &&
                         w_fifo_empty && !r_stop_requested) begin
                o_feedback_fifo_stall <= o_feedback_fifo_stall + 1'b1;
            end

            if (w_final_valid && !r_stop_requested) begin
                if (!w_fifo_full) begin
                    r_fifo_idx[r_fifo_wr_ptr] <=
                        o_final_digit_idx_rows[digit_idx_width - 1 : 0];
                    r_fifo_p[r_fifo_wr_ptr] <= o_final_digit_p_rows;
                    r_fifo_n[r_fifo_wr_ptr] <= o_final_digit_n_rows;
                    r_fifo_wr_ptr <= r_fifo_wr_ptr + 1'b1;
                end else begin
                    o_feedback_fifo_stall <= o_feedback_fifo_stall + 1'b1;
                end
            end else if (w_final_valid && r_stop_requested) begin
                o_speculative_kill_digits <= o_speculative_kill_digits + 1'b1;
            end

            if (w_feedback_dequeue) begin
                r_fifo_rd_ptr <= r_fifo_rd_ptr + 1'b1;
            end

            case ({(w_final_valid && !r_stop_requested && !w_fifo_full), w_feedback_dequeue})
                2'b10: r_fifo_count <= r_fifo_count + 1'b1;
                2'b01: r_fifo_count <= r_fifo_count - 1'b1;
                default: r_fifo_count <= r_fifo_count;
            endcase

            if (w_final_done) begin
                o_superstep_count <= o_superstep_count + 1'b1;
            end

            if (|r_l1_pending) begin
                o_cert_late_cycles <= o_cert_late_cycles + 1'b1;
            end

            for (si_seq = 0; si_seq < num_stages; si_seq = si_seq + 1) begin
                if (si_seq > 0 &&
                    w_stage_input_valid[si_seq] &&
                    !o_stage_done[si_seq - 1]) begin
                    o_stage_started_before_prev_done[si_seq - 1] <= 1'b1;
                end

                if (o_stage_valid_rows[si_seq * num_rows + 0]) begin
                    o_stage_valid_count[si_seq * 32 +: 32] <=
                        o_stage_valid_count[si_seq * 32 +: 32] + 1'b1;
                end

                if (o_stage_done_rows[si_seq * num_rows + 0]) begin
                    o_stage_done[si_seq] <= 1'b1;
                    r_l1_pending[si_seq] <= 1'b1;
                    r_stage_local_clear[si_seq] <= 1'b1;
                end
            end

            if (w_stage_input_valid[0]) begin
                bit_sel_seq = data_width - 1 -
                    w_stage_digit_idx[0 +: digit_idx_width];
                for (ri_seq = 0; ri_seq < num_rows; ri_seq = ri_seq + 1) begin
                    r_stage_old_p[0][ri_seq * data_width + bit_sel_seq] <=
                        w_stage0_source_p_rows[ri_seq];
                    r_stage_old_n[0][ri_seq * data_width + bit_sel_seq] <=
                        w_stage0_source_n_rows[ri_seq];
                end
            end

            for (si_seq = 1; si_seq < num_stages; si_seq = si_seq + 1) begin
                if (o_stage_valid_rows[(si_seq - 1) * num_rows + 0]) begin
                    bit_sel_seq = data_width - 1 -
                        o_stage_digit_idx_rows[(si_seq - 1) * num_rows *
                            digit_idx_width +: digit_idx_width];
                    for (ri_seq = 0; ri_seq < num_rows; ri_seq = ri_seq + 1) begin
                        r_stage_old_p[si_seq][ri_seq * data_width + bit_sel_seq] <=
                            o_stage_digit_p_rows[(si_seq - 1) * num_rows + ri_seq];
                        r_stage_old_n[si_seq][ri_seq * data_width + bit_sel_seq] <=
                            o_stage_digit_n_rows[(si_seq - 1) * num_rows + ri_seq];
                    end
                end
            end

            for (si_seq = 0; si_seq < num_stages; si_seq = si_seq + 1) begin
                if (o_stage_valid_rows[si_seq * num_rows + 0]) begin
                    bit_sel_seq = data_width - 1 -
                        o_stage_digit_idx_rows[si_seq * num_rows *
                            digit_idx_width +: digit_idx_width];
                    for (ri_seq = 0; ri_seq < num_rows; ri_seq = ri_seq + 1) begin
                        r_stage_new_p[si_seq][ri_seq * data_width + bit_sel_seq] <=
                            o_stage_digit_p_rows[si_seq * num_rows + ri_seq];
                        r_stage_new_n[si_seq][ri_seq * data_width + bit_sel_seq] <=
                            o_stage_digit_n_rows[si_seq * num_rows + ri_seq];
                    end
                end
            end

            for (si_seq = 0; si_seq < num_stages; si_seq = si_seq + 1) begin
                if (r_l1_pending[si_seq]) begin
                    l1_sum = 0;
                    for (ri_seq = 0; ri_seq < num_rows; ri_seq = ri_seq + 1) begin
                        row_new_value = rail_value(
                            r_stage_new_p[si_seq][ri_seq * data_width +: data_width],
                            r_stage_new_n[si_seq][ri_seq * data_width +: data_width]);
                        row_old_value = rail_value(
                            r_stage_old_p[si_seq][ri_seq * data_width +: data_width],
                            r_stage_old_n[si_seq][ri_seq * data_width +: data_width]);
                        row_delta_value = row_new_value - row_old_value;
                        if (row_delta_value < 0) begin
                            l1_sum = l1_sum - row_delta_value;
                        end else begin
                            l1_sum = l1_sum + row_delta_value;
                        end
                    end
                    tail_sum = i_l1_tail_bound_per_row * num_rows;
                    l1_sum = l1_sum + tail_sum;
                    o_stage_l1_delta[si_seq * acc_width +: acc_width] <=
                        l1_sum[acc_width - 1 : 0];
                    o_stage_l1_valid[si_seq] <= 1'b1;
                    o_stage_l1_valid_count[si_seq * 32 +: 32] <=
                        o_stage_l1_valid_count[si_seq * 32 +: 32] + 1'b1;
                    r_l1_pending[si_seq] <= 1'b0;

                    if (!o_converged && (l1_sum <= i_l1_eta)) begin
                        o_converged <= 1'b1;
                        o_converged_stage <= si_seq[converged_stage_width - 1 : 0];
                        o_converged_stage_histogram[si_seq * 32 +: 32] <=
                            o_converged_stage_histogram[si_seq * 32 +: 32] + 1'b1;
                        if (i_stop_on_converged) begin
                            r_stop_requested <= 1'b1;
                            o_speculative_kill_digits <=
                                o_speculative_kill_digits + r_fifo_count;
                            r_fifo_count <= {fifo_count_width{1'b0}};
                            r_fifo_rd_ptr <= r_fifo_wr_ptr;
                        end
                    end
                end
            end
        end
    end

endmodule
