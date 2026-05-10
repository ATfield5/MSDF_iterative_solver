`timescale 1ns / 1ps

// Local digit-stream state commit + fixed-degree replay boundary.
//
// This is a small integration shell for the all-digit-stream solver path:
// digit-wise row outputs are written into the inactive ping-pong state bank,
// commit_swap promotes that bank, and the next iteration replays selected
// source digits directly from the committed state.
//
// It intentionally does not include row-update arithmetic or certification.
// Its purpose is to isolate the state/replay contract before replacing the
// full-digit row-update bridge.

module iter_digit_stream_state_replay_top #(
    parameter integer num_rows = 4,
    parameter integer degree = 4,
    parameter integer data_width = 11,
    parameter integer msb_first = 1,
    parameter integer row_idx_width = (num_rows <= 2) ? 1 : $clog2(num_rows),
    parameter integer digit_idx_width = (data_width <= 2) ? 1 : $clog2(data_width)
) (
    input                                                   i_clk,
    input                                                   i_rst,
    input                                                   i_commit_swap,
    input                                                   i_clear_write_bank,
    input                                                   i_load_state,
    input                                                   i_load_bank_sel,
    input      [row_idx_width - 1 : 0]                      i_load_row_idx,
    input      [data_width - 1 : 0]                         i_load_state_p,
    input      [data_width - 1 : 0]                         i_load_state_n,
    input      [num_rows - 1 : 0]                           i_write_digit_valid_rows,
    input      [digit_idx_width - 1 : 0]                    i_write_digit_idx,
    input      [num_rows - 1 : 0]                           i_write_digit_p_rows,
    input      [num_rows - 1 : 0]                           i_write_digit_n_rows,
    input      [digit_idx_width - 1 : 0]                    i_replay_digit_idx,
    input      [num_rows * degree * row_idx_width - 1 : 0]  i_src_row_idx,
    output                                                  o_read_bank_sel,
    output     [num_rows * data_width - 1 : 0]              o_read_state_p_rows,
    output     [num_rows * data_width - 1 : 0]              o_read_state_n_rows,
    output     [num_rows - 1 : 0]                           o_x0_p_rows,
    output     [num_rows - 1 : 0]                           o_x0_n_rows,
    output     [num_rows - 1 : 0]                           o_x1_p_rows,
    output     [num_rows - 1 : 0]                           o_x1_n_rows,
    output     [num_rows - 1 : 0]                           o_x2_p_rows,
    output     [num_rows - 1 : 0]                           o_x2_n_rows,
    output     [num_rows - 1 : 0]                           o_x3_p_rows,
    output     [num_rows - 1 : 0]                           o_x3_n_rows
);

    wire [num_rows * data_width - 1 : 0] w_read_state_p_rows;
    wire [num_rows * data_width - 1 : 0] w_read_state_n_rows;

    iter_digit_stream_state_ping_pong_bank #(
        .num_rows(num_rows),
        .data_width(data_width),
        .msb_first(msb_first),
        .row_idx_width(row_idx_width),
        .digit_idx_width(digit_idx_width)
    ) state_bank (
        .i_clk(i_clk),
        .i_rst(i_rst),
        .i_commit_swap(i_commit_swap),
        .i_clear_write_bank(i_clear_write_bank),
        .i_load_state(i_load_state),
        .i_load_bank_sel(i_load_bank_sel),
        .i_load_row_idx(i_load_row_idx),
        .i_load_state_p(i_load_state_p),
        .i_load_state_n(i_load_state_n),
        .i_write_digit_valid_rows(i_write_digit_valid_rows),
        .i_write_digit_idx(i_write_digit_idx),
        .i_write_digit_p_rows(i_write_digit_p_rows),
        .i_write_digit_n_rows(i_write_digit_n_rows),
        .o_read_bank_sel(o_read_bank_sel),
        .o_read_state_p_rows(w_read_state_p_rows),
        .o_read_state_n_rows(w_read_state_n_rows),
        .o_write_state_p_rows(),
        .o_write_state_n_rows()
    );

    iter_fixed_degree_state_replay #(
        .num_rows(num_rows),
        .source_rows(num_rows),
        .degree(degree),
        .data_width(data_width),
        .msb_first(msb_first),
        .row_idx_width(row_idx_width)
    ) replay (
        .i_state_p_rows(w_read_state_p_rows),
        .i_state_n_rows(w_read_state_n_rows),
        .i_digit_idx(i_replay_digit_idx),
        .i_src_row_idx(i_src_row_idx),
        .o_x0_p_rows(o_x0_p_rows),
        .o_x0_n_rows(o_x0_n_rows),
        .o_x1_p_rows(o_x1_p_rows),
        .o_x1_n_rows(o_x1_n_rows),
        .o_x2_p_rows(o_x2_p_rows),
        .o_x2_n_rows(o_x2_n_rows),
        .o_x3_p_rows(o_x3_p_rows),
        .o_x3_n_rows(o_x3_n_rows)
    );

    assign o_read_state_p_rows = w_read_state_p_rows;
    assign o_read_state_n_rows = w_read_state_n_rows;

endmodule
