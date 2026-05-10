`timescale 1ns / 1ps

// Solver-level digit-stream wrapper around the prior MSDF_MUL_ADD_8 operator.
//
// This is the first strict P3 candidate for the prior-compatible fractional
// PageRank fixture.  Unlike iter_prior_online_mma8_row_cluster_delta_cert, it
// does not assemble a full row word before state commit.  It captures the
// prior operator's unit/fraction output digits and writes them directly into
// the digit-stream ping-pong state bank; delta/certification is computed from
// the committed digit stream.

module iter_prior_online_mma8_digit_stream_cluster_delta_cert #(
    parameter integer num_rows = 4,
    parameter integer degree = 4,
    parameter integer bit_width = 8,
    parameter integer data_width = bit_width + 3,
    parameter integer bias_width = bit_width + 2,
    parameter integer capture_unit = 0,
    parameter integer bound_width = bit_width + 5,
    parameter integer coeff_width = 8,
    parameter integer acc_width = 24,
    parameter integer block_size = 1,
    parameter integer num_blocks = (num_rows + block_size - 1) / block_size,
    parameter integer row_idx_width = (num_rows <= 2) ? 1 : $clog2(num_rows),
    parameter integer feed_cycles = data_width + data_width + 8,
    parameter integer valid_latency = 4,
    parameter integer feed_idx_width = (feed_cycles <= 2) ? 1 : $clog2(feed_cycles + 1),
    parameter integer digit_idx_width = (data_width <= 2) ? 1 : $clog2(data_width),
    parameter integer cert_product_pipeline = 0,
    parameter integer cert_operand_pipeline = 0,
    parameter integer cert_compare_pipeline = 0
) (
    input                                                   i_clk,
    input                                                   i_rst,
    input                                                   i_start,
    input                                                   i_valid_digit,
    input      [num_rows - 1 : 0]                           i_ena_rows,
    input      [digit_idx_width - 1 : 0]                    i_digit_idx,
    input                                                   i_clear_write_bank,
    input                                                   i_commit_swap,

    input                                                   i_load_state,
    input                                                   i_load_bank_sel,
    input      [row_idx_width - 1 : 0]                      i_load_row_idx,
    input      [data_width - 1 : 0]                         i_load_state_p,
    input      [data_width - 1 : 0]                         i_load_state_n,

    input      [num_rows * degree * data_width - 1 : 0]     i_state_p_terms_rows,
    input      [num_rows * degree * data_width - 1 : 0]     i_state_n_terms_rows,
    input      [num_rows - 1 : 0]                           i_ext_x0_p_rows,
    input      [num_rows - 1 : 0]                           i_ext_x0_n_rows,
    input      [num_rows - 1 : 0]                           i_ext_x1_p_rows,
    input      [num_rows - 1 : 0]                           i_ext_x1_n_rows,
    input      [num_rows - 1 : 0]                           i_ext_x2_p_rows,
    input      [num_rows - 1 : 0]                           i_ext_x2_n_rows,
    input      [num_rows - 1 : 0]                           i_ext_x3_p_rows,
    input      [num_rows - 1 : 0]                           i_ext_x3_n_rows,
    input      [num_rows * degree * bit_width - 1 : 0]      i_coeff_p_terms_rows,
    input      [num_rows * degree * bit_width - 1 : 0]      i_coeff_n_terms_rows,
    input      [num_rows * bias_width - 1 : 0]              i_bias_p_rows,
    input      [num_rows * bias_width - 1 : 0]              i_bias_n_rows,
    input      [num_rows * num_blocks * coeff_width - 1 : 0] i_block_weights,
    input      [acc_width - 1 : 0]                          i_eta,
    input      [bound_width - 1 : 0]                        i_tail_bound,

    output     [num_rows - 1 : 0]                           o_write_done_rows,
    output     [num_rows * bound_width - 1 : 0]             o_abs_upper_rows,
    output     [num_blocks * bound_width - 1 : 0]           o_block_bounds,
    output                                                  o_cluster_valid,
    output                                                  o_cluster_certified,
    output     [acc_width - 1 : 0]                          o_cluster_max_error,
    output     [num_rows * data_width - 1 : 0]              o_read_state_p_rows,
    output     [num_rows * data_width - 1 : 0]              o_read_state_n_rows
);

    reg r_busy;
    reg r_prior_rst;
    reg [feed_idx_width - 1 : 0] r_feed_idx;
    reg [digit_idx_width - 1 : 0] r_capture_idx;
    reg [valid_latency : 0] r_feed_valid_pipe;
    reg [num_rows - 1 : 0] r_active_rows;

    wire w_operand_phase;
    wire w_feed_active;
    wire [digit_idx_width - 1 : 0] w_feed_digit_idx;
    wire w_capture_flag;
    wire w_capture_sample;
    wire w_capture_last;
    wire [num_rows - 1 : 0] w_prior_z_p_rows;
    wire [num_rows - 1 : 0] w_prior_z_n_rows;
    wire [num_rows - 1 : 0] w_prior_unit_rows;
    wire [num_rows - 1 : 0] w_prior_frac_rows;
    wire [num_rows - 1 : 0] w_write_valid_rows;
    wire [num_rows - 1 : 0] w_delta_valid_rows;
    wire [num_rows - 1 : 0] w_delta_final_rows;

    assign w_operand_phase = r_feed_idx < data_width;
    assign w_feed_active = r_busy && !r_prior_rst && (r_feed_idx < feed_cycles);
    assign w_feed_digit_idx = r_feed_idx[digit_idx_width - 1 : 0];
    assign w_capture_flag =
        ((capture_unit != 0) && w_prior_unit_rows[0]) || w_prior_frac_rows[0];
    assign w_capture_sample =
        r_feed_valid_pipe[valid_latency] && w_capture_flag &&
        (r_capture_idx < data_width);
    assign w_capture_last = w_capture_sample && (r_capture_idx == data_width - 1);
    assign w_write_valid_rows = {num_rows{w_capture_sample}} & r_active_rows;
    assign o_write_done_rows = {num_rows{w_capture_last}} & r_active_rows;

    always @(posedge i_clk) begin
        if (i_rst || i_clear_write_bank) begin
            r_busy <= 1'b0;
            r_prior_rst <= 1'b1;
            r_feed_idx <= {feed_idx_width{1'b0}};
            r_capture_idx <= {digit_idx_width{1'b0}};
            r_feed_valid_pipe <= {(valid_latency + 1){1'b0}};
            r_active_rows <= {num_rows{1'b0}};
        end else begin
            r_prior_rst <= 1'b0;
            r_feed_valid_pipe <= {r_feed_valid_pipe[valid_latency - 1 : 0], w_feed_active};

            if (i_start && !r_busy) begin
                r_busy <= 1'b1;
                // Match the word-assembler contract: reset the original
                // operator locally, then feed operands autonomously from the
                // full-word replay snapshot.
                r_prior_rst <= 1'b1;
                r_feed_idx <= {feed_idx_width{1'b0}};
                r_capture_idx <= {digit_idx_width{1'b0}};
                r_feed_valid_pipe <= {(valid_latency + 1){1'b0}};
                r_active_rows <= i_ena_rows;
            end else if (r_busy) begin
                if (w_feed_active) begin
                    r_feed_idx <= r_feed_idx + 1'b1;
                end
                if (w_capture_sample) begin
                    r_capture_idx <= r_capture_idx + 1'b1;
                end
                if (w_capture_last ||
                    ((r_feed_idx == feed_cycles) &&
                     (r_feed_valid_pipe == {(valid_latency + 1){1'b0}}))) begin
                    r_busy <= 1'b0;
                end
            end
        end
    end

    genvar ri;
    genvar ti;
    generate
        for (ri = 0; ri < num_rows; ri = ri + 1) begin : gen_rows
            wire [degree - 1 : 0] w_state_digit_p_terms;
            wire [degree - 1 : 0] w_state_digit_n_terms;
            wire [degree * data_width - 1 : 0] w_coeff_p_ext;
            wire [degree * data_width - 1 : 0] w_coeff_n_ext;
            wire [data_width - 1 : 0] w_bias_p_ext;
            wire [data_width - 1 : 0] w_bias_n_ext;
            wire w_bias_digit_p;
            wire w_bias_digit_n;
            wire [bound_width - 1 : 0] w_abs_upper;
            wire [bound_width : 0] w_abs_upper_with_tail;
            wire [data_width - 1 : 0] w_old_p_word;
            wire [data_width - 1 : 0] w_old_n_word;
            wire w_old_digit_p;
            wire w_old_digit_n;
            integer bit_sel;
            integer old_bit_sel;

            assign w_state_digit_p_terms[0] = w_operand_phase
                ? i_state_p_terms_rows[(ri * degree + 0) * data_width + bit_sel]
                : 1'b0;
            assign w_state_digit_n_terms[0] = w_operand_phase
                ? i_state_n_terms_rows[(ri * degree + 0) * data_width + bit_sel]
                : 1'b0;
            assign w_state_digit_p_terms[1] = w_operand_phase
                ? i_state_p_terms_rows[(ri * degree + 1) * data_width + bit_sel]
                : 1'b0;
            assign w_state_digit_n_terms[1] = w_operand_phase
                ? i_state_n_terms_rows[(ri * degree + 1) * data_width + bit_sel]
                : 1'b0;
            assign w_state_digit_p_terms[2] = w_operand_phase
                ? i_state_p_terms_rows[(ri * degree + 2) * data_width + bit_sel]
                : 1'b0;
            assign w_state_digit_n_terms[2] = w_operand_phase
                ? i_state_n_terms_rows[(ri * degree + 2) * data_width + bit_sel]
                : 1'b0;
            assign w_state_digit_p_terms[3] = w_operand_phase
                ? i_state_p_terms_rows[(ri * degree + 3) * data_width + bit_sel]
                : 1'b0;
            assign w_state_digit_n_terms[3] = w_operand_phase
                ? i_state_n_terms_rows[(ri * degree + 3) * data_width + bit_sel]
                : 1'b0;

            for (ti = 0; ti < degree; ti = ti + 1) begin : gen_coeff_ext
                assign w_coeff_p_ext[ti * data_width +: data_width] =
                    {{(data_width - bit_width){1'b0}},
                     i_coeff_p_terms_rows[(ri * degree + ti) * bit_width +: bit_width]};
                assign w_coeff_n_ext[ti * data_width +: data_width] =
                    {{(data_width - bit_width){1'b0}},
                     i_coeff_n_terms_rows[(ri * degree + ti) * bit_width +: bit_width]};
            end
            assign w_bias_p_ext =
                {{(data_width - bias_width){1'b0}},
                 i_bias_p_rows[ri * bias_width +: bias_width]};
            assign w_bias_n_ext =
                {{(data_width - bias_width){1'b0}},
                 i_bias_n_rows[ri * bias_width +: bias_width]};

            always @(*) begin
                bit_sel = data_width - 1 - w_feed_digit_idx;
            end
            assign w_bias_digit_p = (w_operand_phase && w_feed_active) ? w_bias_p_ext[bit_sel] : 1'b0;
            assign w_bias_digit_n = (w_operand_phase && w_feed_active) ? w_bias_n_ext[bit_sel] : 1'b0;

            iter_prior_online_mma8_row_kernel #(
                .degree(degree),
                .bit_width(data_width),
                .digit_idx_width(digit_idx_width)
            ) prior_row (
                .i_clk(i_clk),
                .i_rst(i_rst || r_prior_rst || i_clear_write_bank),
                .i_valid_digit(w_feed_active && r_active_rows[ri]),
                .i_digit_idx(w_feed_digit_idx),
                .i_state_digit_p_terms(w_state_digit_p_terms),
                .i_state_digit_n_terms(w_state_digit_n_terms),
                .i_coeff_p_terms(w_coeff_p_ext),
                .i_coeff_n_terms(w_coeff_n_ext),
                .i_bias_digit_p(w_bias_digit_p),
                .i_bias_digit_n(w_bias_digit_n),
                .o_z_p(w_prior_z_p_rows[ri]),
                .o_z_n(w_prior_z_n_rows[ri]),
                .o_int(),
                .o_unit(w_prior_unit_rows[ri]),
                .o_frac(w_prior_frac_rows[ri])
            );

            assign w_old_p_word = o_read_state_p_rows[(ri + 1) * data_width - 1 -: data_width];
            assign w_old_n_word = o_read_state_n_rows[(ri + 1) * data_width - 1 -: data_width];
            always @(*) begin
                old_bit_sel = data_width - 1 - r_capture_idx;
            end
            assign w_old_digit_p = w_old_p_word[old_bit_sel];
            assign w_old_digit_n = w_old_n_word[old_bit_sel];

            iter_digit_stream_delta_bound #(
                .data_width(data_width),
                .bound_width(bound_width),
                .acc_width(acc_width),
                .final_only(1),
                .digit_idx_width(digit_idx_width)
            ) delta_bound (
                .i_clk(i_clk),
                .i_rst(i_rst || i_clear_write_bank),
                .i_start(w_write_valid_rows[ri] &&
                         (r_capture_idx == {digit_idx_width{1'b0}})),
                .i_valid(w_write_valid_rows[ri]),
                .i_digit_idx(r_capture_idx),
                .i_new_digit_p(w_prior_z_p_rows[ri]),
                .i_new_digit_n(w_prior_z_n_rows[ri]),
                .i_old_digit_p(w_old_digit_p),
                .i_old_digit_n(w_old_digit_n),
                .o_valid(w_delta_valid_rows[ri]),
                .o_prefix_delta(),
                .o_abs_upper(w_abs_upper),
                .o_final(w_delta_final_rows[ri])
            );

            assign w_abs_upper_with_tail = {1'b0, w_abs_upper} + {1'b0, i_tail_bound};
            assign o_abs_upper_rows[(ri + 1) * bound_width - 1 -: bound_width] =
                w_abs_upper_with_tail[bound_width]
                    ? {bound_width{1'b1}}
                    : w_abs_upper_with_tail[bound_width - 1 : 0];
        end
    endgenerate

    iter_digit_stream_state_replay_top #(
        .num_rows(num_rows),
        .degree(degree),
        .data_width(data_width),
        .msb_first(1),
        .row_idx_width(row_idx_width),
        .digit_idx_width(digit_idx_width)
    ) state_replay (
        .i_clk(i_clk),
        .i_rst(i_rst),
        .i_commit_swap(i_commit_swap),
        .i_clear_write_bank(i_clear_write_bank),
        .i_load_state(i_load_state),
        .i_load_bank_sel(i_load_bank_sel),
        .i_load_row_idx(i_load_row_idx),
        .i_load_state_p(i_load_state_p),
        .i_load_state_n(i_load_state_n),
        .i_write_digit_valid_rows(w_write_valid_rows),
        .i_write_digit_idx(r_capture_idx),
        .i_write_digit_p_rows(w_prior_z_p_rows),
        .i_write_digit_n_rows(w_prior_z_n_rows),
        .i_replay_digit_idx(i_digit_idx),
        .i_src_row_idx({num_rows * degree * row_idx_width{1'b0}}),
        .o_read_bank_sel(),
        .o_read_state_p_rows(o_read_state_p_rows),
        .o_read_state_n_rows(o_read_state_n_rows),
        .o_x0_p_rows(),
        .o_x0_n_rows(),
        .o_x1_p_rows(),
        .o_x1_n_rows(),
        .o_x2_p_rows(),
        .o_x2_n_rows(),
        .o_x3_p_rows(),
        .o_x3_n_rows()
    );

    online_row_cluster_block_cert #(
        .num_rows(num_rows),
        .block_size(block_size),
        .bound_width(bound_width),
        .coeff_width(coeff_width),
        .acc_width(acc_width),
        .num_blocks(num_blocks),
        .cert_product_pipeline(cert_product_pipeline),
        .cert_operand_pipeline(cert_operand_pipeline),
        .cert_compare_pipeline(cert_compare_pipeline),
        .input_pipeline(0),
        .output_pipeline(0)
    ) cluster_cert (
        .i_clk(i_clk),
        .i_rst(i_rst),
        .i_valid_rows(w_delta_valid_rows & w_delta_final_rows),
        .i_row_abs_upper(o_abs_upper_rows),
        .i_block_weights(i_block_weights),
        .i_eta(i_eta),
        .o_valid(o_cluster_valid),
        .o_block_bounds(o_block_bounds),
        .o_certified(o_cluster_certified),
        .o_max_error(o_cluster_max_error)
    );

`ifdef PRIOR_DIGIT_STREAM_DEBUG
    always @(posedge i_clk) begin
        if (!i_rst && (w_feed_active || w_capture_sample || o_cluster_valid)) begin
            $display("PRIOR_DIGIT_STREAM_DEBUG busy=%0d feed=%0d feed_idx=%0d cap=%0d sample=%0d last=%0d unit0=%0d frac0=%0d z0=%0d/%0d valid=%b final=%b cluster_valid=%0d max=%0d",
                r_busy,
                w_feed_active,
                r_feed_idx,
                r_capture_idx,
                w_capture_sample,
                w_capture_last,
                w_prior_unit_rows[0],
                w_prior_frac_rows[0],
                w_prior_z_p_rows[0],
                w_prior_z_n_rows[0],
                w_delta_valid_rows,
                w_delta_final_rows,
                o_cluster_valid,
                o_cluster_max_error);
        end
    end
`endif

endmodule
