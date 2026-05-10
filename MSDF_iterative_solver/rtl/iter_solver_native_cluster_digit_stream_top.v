`timescale 1ns / 1ps

// Solver-native digit-stream cluster shell.
//
// This is the reusable cluster boundary for ROW_DATAPATH_MODE=3.  It keeps the
// solver state in signed-digit rail form across iterations:
//
//   external/replayed source digits
//     -> solver-native row digit engines
//     -> fixed-width commit adapters
//     -> digit-stream ping-pong state bank
//     -> fixed-degree replay for the next iteration
//
// Certification is intentionally not included here.  This shell isolates the
// iteration-boundary contract before it is wired into the full runtime solver.

module iter_solver_native_cluster_digit_stream_top #(
    parameter integer num_rows = 4,
    parameter integer degree = 4,
    parameter integer bit_width = 8,
    parameter integer data_width = bit_width + 3,
    parameter integer bias_width = bit_width + 2,
    parameter integer skip_digits = 8,
    parameter integer affine_guard_shift = 3,
    parameter integer sample_width = 5,
    parameter integer row_idx_width = (num_rows <= 2) ? 1 : $clog2(num_rows),
    parameter integer digit_idx_width = (data_width <= 2) ? 1 : $clog2(data_width)
) (
    input                                                   i_clk,
    input                                                   i_rst,
    input                                                   i_start,
    input                                                   i_valid_digit,
    input      [num_rows - 1 : 0]                           i_ena_rows,
    input      [digit_idx_width - 1 : 0]                    i_digit_idx,
    input                                                   i_use_replay,
    input                                                   i_clear_write_bank,
    input                                                   i_commit_swap,

    input                                                   i_load_state,
    input                                                   i_load_bank_sel,
    input      [row_idx_width - 1 : 0]                      i_load_row_idx,
    input      [data_width - 1 : 0]                         i_load_state_p,
    input      [data_width - 1 : 0]                         i_load_state_n,

    input      [num_rows * degree * row_idx_width - 1 : 0]  i_src_row_idx,
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

    output     [num_rows - 1 : 0]                           o_replay_x0_p_rows,
    output     [num_rows - 1 : 0]                           o_replay_x0_n_rows,
    output     [num_rows - 1 : 0]                           o_replay_x1_p_rows,
    output     [num_rows - 1 : 0]                           o_replay_x1_n_rows,
    output     [num_rows - 1 : 0]                           o_replay_x2_p_rows,
    output     [num_rows - 1 : 0]                           o_replay_x2_n_rows,
    output     [num_rows - 1 : 0]                           o_replay_x3_p_rows,
    output     [num_rows - 1 : 0]                           o_replay_x3_n_rows,
    output     [num_rows - 1 : 0]                           o_row_valid,
    output     [num_rows - 1 : 0]                           o_row_digit_p,
    output     [num_rows - 1 : 0]                           o_row_digit_n,
    output     [num_rows - 1 : 0]                           o_write_valid_rows,
    output     [num_rows * digit_idx_width - 1 : 0]          o_write_digit_idx_rows,
    output     [num_rows - 1 : 0]                           o_write_digit_p_rows,
    output     [num_rows - 1 : 0]                           o_write_digit_n_rows,
    output     [num_rows - 1 : 0]                           o_write_done_rows,
    output     [num_rows * data_width - 1 : 0]              o_read_state_p_rows,
    output     [num_rows * data_width - 1 : 0]              o_read_state_n_rows
);

    wire [num_rows - 1 : 0] w_src_x0_p_rows;
    wire [num_rows - 1 : 0] w_src_x0_n_rows;
    wire [num_rows - 1 : 0] w_src_x1_p_rows;
    wire [num_rows - 1 : 0] w_src_x1_n_rows;
    wire [num_rows - 1 : 0] w_src_x2_p_rows;
    wire [num_rows - 1 : 0] w_src_x2_n_rows;
    wire [num_rows - 1 : 0] w_src_x3_p_rows;
    wire [num_rows - 1 : 0] w_src_x3_n_rows;
    wire [num_rows * degree - 1 : 0] w_state_digit_p_terms_rows;
    wire [num_rows * degree - 1 : 0] w_state_digit_n_terms_rows;
    wire [num_rows - 1 : 0] w_native_valid_rows;
    wire [num_rows - 1 : 0] w_native_digit_p_rows;
    wire [num_rows - 1 : 0] w_native_digit_n_rows;
    wire [num_rows - 1 : 0] w_adapter_write_valid_rows;
    wire [num_rows - 1 : 0] w_adapter_write_p_rows;
    wire [num_rows - 1 : 0] w_adapter_write_n_rows;
    wire [num_rows - 1 : 0] w_adapter_done_rows;
    wire [num_rows * digit_idx_width - 1 : 0] w_adapter_write_idx_rows;
    reg r_drain_active;
    reg [num_rows - 1 : 0] r_active_rows;
    reg [digit_idx_width - 1 : 0] r_drain_count;
    wire w_input_last_digit;
    wire w_engine_valid_digit;
    wire [num_rows - 1 : 0] w_engine_ena_rows;
    wire [digit_idx_width - 1 : 0] w_engine_digit_idx;
    wire w_drain_done;
    wire [num_rows * bias_width - 1 : 0] w_engine_bias_p_rows;
    wire [num_rows * bias_width - 1 : 0] w_engine_bias_n_rows;

    assign w_src_x0_p_rows = i_use_replay ? o_replay_x0_p_rows : i_ext_x0_p_rows;
    assign w_src_x0_n_rows = i_use_replay ? o_replay_x0_n_rows : i_ext_x0_n_rows;
    assign w_src_x1_p_rows = i_use_replay ? o_replay_x1_p_rows : i_ext_x1_p_rows;
    assign w_src_x1_n_rows = i_use_replay ? o_replay_x1_n_rows : i_ext_x1_n_rows;
    assign w_src_x2_p_rows = i_use_replay ? o_replay_x2_p_rows : i_ext_x2_p_rows;
    assign w_src_x2_n_rows = i_use_replay ? o_replay_x2_n_rows : i_ext_x2_n_rows;
    assign w_src_x3_p_rows = i_use_replay ? o_replay_x3_p_rows : i_ext_x3_p_rows;
    assign w_src_x3_n_rows = i_use_replay ? o_replay_x3_n_rows : i_ext_x3_n_rows;
    assign w_input_last_digit = i_valid_digit && (i_digit_idx == data_width - 1);
    assign w_engine_valid_digit = i_valid_digit || r_drain_active;
    assign w_engine_ena_rows = r_drain_active ? r_active_rows : i_ena_rows;
    assign w_engine_digit_idx = r_drain_active ? (data_width - 1) : i_digit_idx;
    assign w_drain_done = r_drain_active && (r_drain_count == skip_digits - 1);
    assign w_engine_bias_p_rows = r_drain_active ? {num_rows * bias_width{1'b0}} : i_bias_p_rows;
    assign w_engine_bias_n_rows = r_drain_active ? {num_rows * bias_width{1'b0}} : i_bias_n_rows;

    always @(posedge i_clk) begin
        if (i_rst || i_clear_write_bank) begin
            r_drain_active <= 1'b0;
            r_active_rows <= {num_rows{1'b0}};
            r_drain_count <= {digit_idx_width{1'b0}};
        end else begin
            if (i_valid_digit) begin
                r_active_rows <= i_ena_rows;
            end

            if (w_input_last_digit && (skip_digits != 0)) begin
                r_drain_active <= 1'b1;
                r_drain_count <= {digit_idx_width{1'b0}};
            end else if (r_drain_active) begin
                if (w_drain_done) begin
                    r_drain_active <= 1'b0;
                    r_drain_count <= {digit_idx_width{1'b0}};
                end else begin
                    r_drain_count <= r_drain_count + 1'b1;
                end
            end
        end
    end

    genvar ri;
    generate
        for (ri = 0; ri < num_rows; ri = ri + 1) begin : gen_pack_terms
            assign w_state_digit_p_terms_rows[ri * degree + 0] = w_src_x0_p_rows[ri];
            assign w_state_digit_n_terms_rows[ri * degree + 0] = w_src_x0_n_rows[ri];
            assign w_state_digit_p_terms_rows[ri * degree + 1] = w_src_x1_p_rows[ri];
            assign w_state_digit_n_terms_rows[ri * degree + 1] = w_src_x1_n_rows[ri];
            assign w_state_digit_p_terms_rows[ri * degree + 2] = w_src_x2_p_rows[ri];
            assign w_state_digit_n_terms_rows[ri * degree + 2] = w_src_x2_n_rows[ri];
            assign w_state_digit_p_terms_rows[ri * degree + 3] = w_src_x3_p_rows[ri];
            assign w_state_digit_n_terms_rows[ri * degree + 3] = w_src_x3_n_rows[ri];

            iter_solver_native_row_digit_engine #(
                .bit_width(bit_width),
                .degree(degree),
                .data_width(data_width),
                .bias_width(bias_width),
                .sample_width(sample_width),
                .affine_guard_shift(affine_guard_shift),
                .digit_idx_width(digit_idx_width)
            ) row_engine (
                .i_clk(i_clk),
                .i_rst(i_rst),
                .i_start(i_start && i_ena_rows[ri]),
                .i_valid_digit(w_engine_valid_digit && w_engine_ena_rows[ri]),
                .i_digit_idx(w_engine_digit_idx),
                .i_state_digit_p_terms(r_drain_active ? {degree{1'b0}} :
                    w_state_digit_p_terms_rows[ri * degree +: degree]),
                .i_state_digit_n_terms(r_drain_active ? {degree{1'b0}} :
                    w_state_digit_n_terms_rows[ri * degree +: degree]),
                .i_coeff_p_terms(i_coeff_p_terms_rows[ri * degree * bit_width +: degree * bit_width]),
                .i_coeff_n_terms(i_coeff_n_terms_rows[ri * degree * bit_width +: degree * bit_width]),
                .i_bias_p(w_engine_bias_p_rows[ri * bias_width +: bias_width]),
                .i_bias_n(w_engine_bias_n_rows[ri * bias_width +: bias_width]),
                .o_valid(w_native_valid_rows[ri]),
                .o_x_new_digit_p(w_native_digit_p_rows[ri]),
                .o_x_new_digit_n(w_native_digit_n_rows[ri]),
                .o_affine_p(),
                .o_affine_n(),
                .o_residual_p(),
                .o_residual_n()
            );

            iter_solver_native_commit_adapter #(
                .state_width(data_width),
                .skip_digits(skip_digits),
                .digit_idx_width(digit_idx_width)
            ) commit_adapter (
                .i_clk(i_clk),
                .i_rst(i_rst),
                .i_clear(i_clear_write_bank),
                .i_valid(w_native_valid_rows[ri]),
                .i_digit_p(w_native_digit_p_rows[ri]),
                .i_digit_n(w_native_digit_n_rows[ri]),
                .o_write_valid(w_adapter_write_valid_rows[ri]),
                .o_write_digit_idx(w_adapter_write_idx_rows[(ri + 1) * digit_idx_width - 1 -: digit_idx_width]),
                .o_write_digit_p(w_adapter_write_p_rows[ri]),
                .o_write_digit_n(w_adapter_write_n_rows[ri]),
                .o_done(w_adapter_done_rows[ri])
            );
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
        .i_write_digit_valid_rows(w_adapter_write_valid_rows),
        .i_write_digit_idx(w_adapter_write_idx_rows[digit_idx_width - 1 : 0]),
        .i_write_digit_p_rows(w_adapter_write_p_rows),
        .i_write_digit_n_rows(w_adapter_write_n_rows),
        .i_replay_digit_idx(i_digit_idx),
        .i_src_row_idx(i_src_row_idx),
        .o_read_bank_sel(),
        .o_read_state_p_rows(o_read_state_p_rows),
        .o_read_state_n_rows(o_read_state_n_rows),
        .o_x0_p_rows(o_replay_x0_p_rows),
        .o_x0_n_rows(o_replay_x0_n_rows),
        .o_x1_p_rows(o_replay_x1_p_rows),
        .o_x1_n_rows(o_replay_x1_n_rows),
        .o_x2_p_rows(o_replay_x2_p_rows),
        .o_x2_n_rows(o_replay_x2_n_rows),
        .o_x3_p_rows(o_replay_x3_p_rows),
        .o_x3_n_rows(o_replay_x3_n_rows)
    );

    assign o_row_valid = w_native_valid_rows;
    assign o_row_digit_p = w_native_digit_p_rows;
    assign o_row_digit_n = w_native_digit_n_rows;
    assign o_write_valid_rows = w_adapter_write_valid_rows;
    assign o_write_digit_idx_rows = w_adapter_write_idx_rows;
    assign o_write_digit_p_rows = w_adapter_write_p_rows;
    assign o_write_digit_n_rows = w_adapter_write_n_rows;
    assign o_write_done_rows = w_adapter_done_rows;

endmodule
