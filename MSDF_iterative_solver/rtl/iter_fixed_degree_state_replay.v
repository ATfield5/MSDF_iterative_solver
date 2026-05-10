`timescale 1ns / 1ps

// Fixed-degree state replay scheduler.
//
// This module replays stored rail-coded row states as the next iteration's
// per-term source digits for a fixed-degree row-update engine.
//
// Contract:
// - state is stored as row-parallel rail-coded words;
// - each destination row has DEGREE source-row indices;
// - one digit index selects one replay slice across all rows and all terms;
// - the default replay order is MSB-first.

module iter_fixed_degree_state_replay #(
    parameter integer num_rows = 4,
    parameter integer source_rows = num_rows,
    parameter integer degree = 4,
    parameter integer data_width = 11,
    parameter integer msb_first = 1,
    parameter integer row_idx_width = (source_rows <= 2) ? 1 : $clog2(source_rows)
) (
    input      [source_rows * data_width - 1 : 0]           i_state_p_rows,
    input      [source_rows * data_width - 1 : 0]           i_state_n_rows,
    input      [$clog2(data_width) - 1 : 0]                 i_digit_idx,
    input      [num_rows * degree * row_idx_width - 1 : 0] i_src_row_idx,
    output reg [num_rows - 1 : 0]                           o_x0_p_rows,
    output reg [num_rows - 1 : 0]                           o_x0_n_rows,
    output reg [num_rows - 1 : 0]                           o_x1_p_rows,
    output reg [num_rows - 1 : 0]                           o_x1_n_rows,
    output reg [num_rows - 1 : 0]                           o_x2_p_rows,
    output reg [num_rows - 1 : 0]                           o_x2_n_rows,
    output reg [num_rows - 1 : 0]                           o_x3_p_rows,
    output reg [num_rows - 1 : 0]                           o_x3_n_rows
);

    function automatic [0:0] get_flat_bit;
        input [source_rows * data_width - 1 : 0] flat_vec;
        input integer row_idx;
        input integer bit_idx;
        begin
            if (row_idx < source_rows) begin
                get_flat_bit = flat_vec[row_idx * data_width + bit_idx];
            end else begin
                get_flat_bit = 1'b0;
            end
        end
    endfunction

    integer dst_row;
    integer term_idx;
    integer src_row;
    integer bit_sel;

    always @(*) begin
        bit_sel = msb_first ? (data_width - 1 - i_digit_idx) : i_digit_idx;

        o_x0_p_rows = {num_rows{1'b0}};
        o_x0_n_rows = {num_rows{1'b0}};
        o_x1_p_rows = {num_rows{1'b0}};
        o_x1_n_rows = {num_rows{1'b0}};
        o_x2_p_rows = {num_rows{1'b0}};
        o_x2_n_rows = {num_rows{1'b0}};
        o_x3_p_rows = {num_rows{1'b0}};
        o_x3_n_rows = {num_rows{1'b0}};

        for (term_idx = 0; term_idx < degree; term_idx = term_idx + 1) begin
            for (dst_row = 0; dst_row < num_rows; dst_row = dst_row + 1) begin
                src_row = i_src_row_idx[((dst_row * degree + term_idx) + 1) * row_idx_width - 1 -: row_idx_width];
                case (term_idx)
                    0: begin
                        o_x0_p_rows[dst_row] = get_flat_bit(i_state_p_rows, src_row, bit_sel);
                        o_x0_n_rows[dst_row] = get_flat_bit(i_state_n_rows, src_row, bit_sel);
                    end
                    1: begin
                        o_x1_p_rows[dst_row] = get_flat_bit(i_state_p_rows, src_row, bit_sel);
                        o_x1_n_rows[dst_row] = get_flat_bit(i_state_n_rows, src_row, bit_sel);
                    end
                    2: begin
                        o_x2_p_rows[dst_row] = get_flat_bit(i_state_p_rows, src_row, bit_sel);
                        o_x2_n_rows[dst_row] = get_flat_bit(i_state_n_rows, src_row, bit_sel);
                    end
                    default: begin
                        o_x3_p_rows[dst_row] = get_flat_bit(i_state_p_rows, src_row, bit_sel);
                        o_x3_n_rows[dst_row] = get_flat_bit(i_state_n_rows, src_row, bit_sel);
                    end
                endcase
            end
        end
    end

endmodule
