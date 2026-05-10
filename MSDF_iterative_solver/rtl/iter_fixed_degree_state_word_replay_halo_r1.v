`timescale 1ns / 1ps

// Radius-1 halo full-word replay scheduler.
//
// This mirrors iter_fixed_degree_state_replay_halo_r1, but returns the full
// rail-coded source words for the conventional full-word datapath.  It keeps
// the conventional baseline on the same halo source contract as the online
// datapath without retaining the flat generic replay tree.

module iter_fixed_degree_state_word_replay_halo_r1 #(
    parameter integer num_rows = 4,
    parameter integer degree = 4,
    parameter integer data_width = 11,
    parameter integer row_idx_width = (3 * num_rows <= 2) ? 1 : $clog2(3 * num_rows)
) (
    input      [num_rows * data_width - 1 : 0]          i_prev_state_p_rows,
    input      [num_rows * data_width - 1 : 0]          i_prev_state_n_rows,
    input      [num_rows * data_width - 1 : 0]          i_curr_state_p_rows,
    input      [num_rows * data_width - 1 : 0]          i_curr_state_n_rows,
    input      [num_rows * data_width - 1 : 0]          i_next_state_p_rows,
    input      [num_rows * data_width - 1 : 0]          i_next_state_n_rows,
    input      [num_rows * degree * row_idx_width - 1 : 0] i_src_row_idx,
    output reg [num_rows * degree * data_width - 1 : 0] o_state_p_terms,
    output reg [num_rows * degree * data_width - 1 : 0] o_state_n_terms
);

    function automatic [data_width - 1 : 0] get_row_word;
        input [num_rows * data_width - 1 : 0] flat_vec;
        input integer row_idx;
        begin
            if (row_idx < num_rows) begin
                get_row_word = flat_vec[row_idx * data_width +: data_width];
            end else begin
                get_row_word = {data_width{1'b0}};
            end
        end
    endfunction

    function automatic [data_width - 1 : 0] select_halo_word;
        input [num_rows * data_width - 1 : 0] prev_vec;
        input [num_rows * data_width - 1 : 0] curr_vec;
        input [num_rows * data_width - 1 : 0] next_vec;
        input integer src_idx;
        integer local_row;
        begin
            local_row = src_idx % num_rows;
            if (src_idx < num_rows) begin
                select_halo_word = get_row_word(prev_vec, local_row);
            end else if (src_idx < (2 * num_rows)) begin
                select_halo_word = get_row_word(curr_vec, local_row);
            end else if (src_idx < (3 * num_rows)) begin
                select_halo_word = get_row_word(next_vec, local_row);
            end else begin
                select_halo_word = {data_width{1'b0}};
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
                    select_halo_word(i_prev_state_p_rows, i_curr_state_p_rows, i_next_state_p_rows, src_row);
                o_state_n_terms[((dst_row * degree + term_idx) + 1) * data_width - 1 -: data_width] =
                    select_halo_word(i_prev_state_n_rows, i_curr_state_n_rows, i_next_state_n_rows, src_row);
            end
        end
    end

endmodule

