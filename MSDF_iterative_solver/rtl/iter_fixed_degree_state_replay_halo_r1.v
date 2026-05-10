`timescale 1ns / 1ps

// Radius-1 halo replay scheduler.
//
// This is a specialization of iter_fixed_degree_state_replay for the banded
// Jacobi mainline where each cluster only reads previous/current/next cluster
// state rows.  The packed source index contract is unchanged:
//
//   0 .. NUM_ROWS-1              previous cluster rows
//   NUM_ROWS .. 2*NUM_ROWS-1     current cluster rows
//   2*NUM_ROWS .. 3*NUM_ROWS-1   next cluster rows
//
// Keeping this as a dedicated module avoids presenting synthesis with a flat
// all-source replay mux.  The datapath is still functionally identical to the
// generic halo replay for HALO_CLUSTER_RADIUS=1.

module iter_fixed_degree_state_replay_halo_r1 #(
    parameter integer num_rows = 4,
    parameter integer degree = 4,
    parameter integer data_width = 11,
    parameter integer msb_first = 1,
    parameter integer row_idx_width = (3 * num_rows <= 2) ? 1 : $clog2(3 * num_rows)
) (
    input      [num_rows * data_width - 1 : 0]          i_prev_state_p_rows,
    input      [num_rows * data_width - 1 : 0]          i_prev_state_n_rows,
    input      [num_rows * data_width - 1 : 0]          i_curr_state_p_rows,
    input      [num_rows * data_width - 1 : 0]          i_curr_state_n_rows,
    input      [num_rows * data_width - 1 : 0]          i_next_state_p_rows,
    input      [num_rows * data_width - 1 : 0]          i_next_state_n_rows,
    input      [$clog2(data_width) - 1 : 0]             i_digit_idx,
    input      [num_rows * degree * row_idx_width - 1 : 0] i_src_row_idx,
    output reg [num_rows - 1 : 0]                       o_x0_p_rows,
    output reg [num_rows - 1 : 0]                       o_x0_n_rows,
    output reg [num_rows - 1 : 0]                       o_x1_p_rows,
    output reg [num_rows - 1 : 0]                       o_x1_n_rows,
    output reg [num_rows - 1 : 0]                       o_x2_p_rows,
    output reg [num_rows - 1 : 0]                       o_x2_n_rows,
    output reg [num_rows - 1 : 0]                       o_x3_p_rows,
    output reg [num_rows - 1 : 0]                       o_x3_n_rows
);

    function automatic [0:0] get_row_bit;
        input [num_rows * data_width - 1 : 0] flat_vec;
        input integer row_idx;
        input integer bit_idx;
        begin
            if (row_idx < num_rows) begin
                get_row_bit = flat_vec[row_idx * data_width + bit_idx];
            end else begin
                get_row_bit = 1'b0;
            end
        end
    endfunction

    function automatic [0:0] select_halo_bit;
        input [num_rows * data_width - 1 : 0] prev_vec;
        input [num_rows * data_width - 1 : 0] curr_vec;
        input [num_rows * data_width - 1 : 0] next_vec;
        input integer src_idx;
        input integer bit_idx;
        integer local_row;
        begin
            local_row = src_idx % num_rows;
            if (src_idx < num_rows) begin
                select_halo_bit = get_row_bit(prev_vec, local_row, bit_idx);
            end else if (src_idx < (2 * num_rows)) begin
                select_halo_bit = get_row_bit(curr_vec, local_row, bit_idx);
            end else if (src_idx < (3 * num_rows)) begin
                select_halo_bit = get_row_bit(next_vec, local_row, bit_idx);
            end else begin
                select_halo_bit = 1'b0;
            end
        end
    endfunction

    integer dst_row;
    integer term_idx;
    integer src_row;
    integer bit_sel;
    reg digit_p;
    reg digit_n;

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
                digit_p = select_halo_bit(i_prev_state_p_rows, i_curr_state_p_rows, i_next_state_p_rows, src_row, bit_sel);
                digit_n = select_halo_bit(i_prev_state_n_rows, i_curr_state_n_rows, i_next_state_n_rows, src_row, bit_sel);
                case (term_idx)
                    0: begin
                        o_x0_p_rows[dst_row] = digit_p;
                        o_x0_n_rows[dst_row] = digit_n;
                    end
                    1: begin
                        o_x1_p_rows[dst_row] = digit_p;
                        o_x1_n_rows[dst_row] = digit_n;
                    end
                    2: begin
                        o_x2_p_rows[dst_row] = digit_p;
                        o_x2_n_rows[dst_row] = digit_n;
                    end
                    default: begin
                        o_x3_p_rows[dst_row] = digit_p;
                        o_x3_n_rows[dst_row] = digit_n;
                    end
                endcase
            end
        end
    end

endmodule

