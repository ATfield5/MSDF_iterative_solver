`timescale 1ns / 1ps

// Fixed-degree full-word state replay scheduler.
//
// The online solver replays one digit per source term each cycle. A conventional
// DSP-MAC baseline needs the same runtime state/source selection boundary, but
// it consumes the complete rail-coded state word for each source term.

module iter_fixed_degree_state_word_replay #(
    parameter integer num_rows = 4,
    parameter integer source_rows = num_rows,
    parameter integer degree = 4,
    parameter integer data_width = 11,
    parameter integer row_idx_width = (source_rows <= 2) ? 1 : $clog2(source_rows)
) (
    input      [source_rows * data_width - 1 : 0]           i_state_p_rows,
    input      [source_rows * data_width - 1 : 0]           i_state_n_rows,
    input      [num_rows * degree * row_idx_width - 1 : 0] i_src_row_idx,
    output reg [num_rows * degree * data_width - 1 : 0]    o_state_p_terms,
    output reg [num_rows * degree * data_width - 1 : 0]    o_state_n_terms
);

    function automatic [data_width - 1 : 0] get_flat_word;
        input [source_rows * data_width - 1 : 0] flat_vec;
        input integer row_idx;
        begin
            if (row_idx < source_rows) begin
                get_flat_word = flat_vec[(row_idx + 1) * data_width - 1 -: data_width];
            end else begin
                get_flat_word = {data_width{1'b0}};
            end
        end
    endfunction

    integer dst_row;
    integer term_idx;
    integer src_row;

    always @(*) begin
        o_state_p_terms = {num_rows * degree * data_width{1'b0}};
        o_state_n_terms = {num_rows * degree * data_width{1'b0}};

        for (term_idx = 0; term_idx < degree; term_idx = term_idx + 1) begin
            for (dst_row = 0; dst_row < num_rows; dst_row = dst_row + 1) begin
                src_row = i_src_row_idx[((dst_row * degree + term_idx) + 1) * row_idx_width - 1 -: row_idx_width];
                o_state_p_terms[((dst_row * degree + term_idx) + 1) * data_width - 1 -: data_width] =
                    get_flat_word(i_state_p_rows, src_row);
                o_state_n_terms[((dst_row * degree + term_idx) + 1) * data_width - 1 -: data_width] =
                    get_flat_word(i_state_n_rows, src_row);
            end
        end
    end

endmodule

