`timescale 1ns / 1ps

// Combinational digit replay source for prefix-safe row lanes.
//
// The row lane requests one consumer row and one digit index.  This source
// returns the DEGREE signed-digit terms for that row/digit from a packed table.
//
// Table layout:
//   table[((row * DATA_WIDTH + digit_idx) * DEGREE) + term]
//
// This is intentionally a combinational checkpoint.  It matches the current
// row-lane contract, where source terms are consumed in the same cycle as the
// request.  A later memory-backed prefix FIFO/state-bank version should add a
// registered request and valid-aligned response.

module iter_prefix_safe_digit_replay_source #(
    parameter integer num_rows = 4,
    parameter integer degree = 4,
    parameter integer data_width = 11,
    parameter integer digit_idx_width = (data_width <= 2) ? 1 : $clog2(data_width),
    parameter integer row_id_width = (num_rows <= 2) ? 1 : $clog2(num_rows),
    parameter integer table_bits = num_rows * data_width * degree
) (
    input                                      i_req_valid,
    input      [row_id_width - 1 : 0]          i_req_row_id,
    input      [digit_idx_width - 1 : 0]       i_req_digit_idx,
    input      [table_bits - 1 : 0]            i_digit_p_table,
    input      [table_bits - 1 : 0]            i_digit_n_table,
    output                                     o_resp_valid,
    output     [degree - 1 : 0]                o_state_digit_p_terms,
    output     [degree - 1 : 0]                o_state_digit_n_terms
);

    wire [31 : 0] w_flat_base;

    assign w_flat_base =
        ((i_req_row_id * data_width) + i_req_digit_idx) * degree;
    assign o_resp_valid = i_req_valid;
    assign o_state_digit_p_terms =
        i_req_valid ? i_digit_p_table[w_flat_base +: degree] : {degree{1'b0}};
    assign o_state_digit_n_terms =
        i_req_valid ? i_digit_n_table[w_flat_base +: degree] : {degree{1'b0}};

endmodule
