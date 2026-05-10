`timescale 1ns / 1ps

// Structured sparse / fixed-degree row scheduler.
//
// Input contract is row-major:
//   slot(row, term)
//
// For the current degree-4 row-update datapath, the scheduler emits:
// - row-active mask
// - masked source-row indices
// - term-major coefficient rail vectors:
//     coeff0(rows), coeff1(rows), coeff2(rows), coeff3(rows)
//
// Invalid term slots are zeroed and their source-row indices are forced to 0.

module iter_fixed_degree_row_scheduler #(
    parameter integer num_rows = 4,
    parameter integer degree = 4,
    parameter integer bit_width = 8,
    parameter integer bias_width = bit_width + 2,
    parameter integer row_idx_width = (num_rows <= 2) ? 1 : $clog2(num_rows)
) (
    input      [num_rows * degree - 1 : 0]                i_term_valid_mask,
    input      [num_rows * degree * row_idx_width - 1 : 0] i_src_row_idx,
    input      [num_rows * degree * bit_width - 1 : 0]    i_coeff_p_terms,
    input      [num_rows * degree * bit_width - 1 : 0]    i_coeff_n_terms,
    input      [num_rows * bias_width - 1 : 0]            i_bias_vec_p_rows,
    input      [num_rows * bias_width - 1 : 0]            i_bias_vec_n_rows,
    output reg [num_rows - 1 : 0]                         o_row_active_mask,
    output reg [num_rows * degree * row_idx_width - 1 : 0] o_src_row_idx,
    output reg [num_rows * bit_width - 1 : 0]             o_coeff0_vec_p_rows,
    output reg [num_rows * bit_width - 1 : 0]             o_coeff0_vec_n_rows,
    output reg [num_rows * bit_width - 1 : 0]             o_coeff1_vec_p_rows,
    output reg [num_rows * bit_width - 1 : 0]             o_coeff1_vec_n_rows,
    output reg [num_rows * bit_width - 1 : 0]             o_coeff2_vec_p_rows,
    output reg [num_rows * bit_width - 1 : 0]             o_coeff2_vec_n_rows,
    output reg [num_rows * bit_width - 1 : 0]             o_coeff3_vec_p_rows,
    output reg [num_rows * bit_width - 1 : 0]             o_coeff3_vec_n_rows,
    output     [num_rows * bias_width - 1 : 0]            o_bias_vec_p_rows,
    output     [num_rows * bias_width - 1 : 0]            o_bias_vec_n_rows
);

    integer row_idx;
    integer term_idx;
    reg term_valid;
    reg [row_idx_width - 1 : 0] src_idx;
    reg [bit_width - 1 : 0] coeff_p;
    reg [bit_width - 1 : 0] coeff_n;

    always @(*) begin
        o_row_active_mask = {num_rows{1'b0}};
        o_src_row_idx = {num_rows * degree * row_idx_width{1'b0}};
        o_coeff0_vec_p_rows = {num_rows * bit_width{1'b0}};
        o_coeff0_vec_n_rows = {num_rows * bit_width{1'b0}};
        o_coeff1_vec_p_rows = {num_rows * bit_width{1'b0}};
        o_coeff1_vec_n_rows = {num_rows * bit_width{1'b0}};
        o_coeff2_vec_p_rows = {num_rows * bit_width{1'b0}};
        o_coeff2_vec_n_rows = {num_rows * bit_width{1'b0}};
        o_coeff3_vec_p_rows = {num_rows * bit_width{1'b0}};
        o_coeff3_vec_n_rows = {num_rows * bit_width{1'b0}};

        for (row_idx = 0; row_idx < num_rows; row_idx = row_idx + 1) begin
            for (term_idx = 0; term_idx < degree; term_idx = term_idx + 1) begin
                term_valid = i_term_valid_mask[row_idx * degree + term_idx];
                src_idx = i_src_row_idx[((row_idx * degree + term_idx) + 1) * row_idx_width - 1 -: row_idx_width];
                coeff_p = i_coeff_p_terms[((row_idx * degree + term_idx) + 1) * bit_width - 1 -: bit_width];
                coeff_n = i_coeff_n_terms[((row_idx * degree + term_idx) + 1) * bit_width - 1 -: bit_width];

                if (term_valid) begin
                    o_row_active_mask[row_idx] = 1'b1;
                    o_src_row_idx[((row_idx * degree + term_idx) + 1) * row_idx_width - 1 -: row_idx_width] = src_idx;
                    case (term_idx)
                        0: begin
                            o_coeff0_vec_p_rows[(row_idx + 1) * bit_width - 1 -: bit_width] = coeff_p;
                            o_coeff0_vec_n_rows[(row_idx + 1) * bit_width - 1 -: bit_width] = coeff_n;
                        end
                        1: begin
                            o_coeff1_vec_p_rows[(row_idx + 1) * bit_width - 1 -: bit_width] = coeff_p;
                            o_coeff1_vec_n_rows[(row_idx + 1) * bit_width - 1 -: bit_width] = coeff_n;
                        end
                        2: begin
                            o_coeff2_vec_p_rows[(row_idx + 1) * bit_width - 1 -: bit_width] = coeff_p;
                            o_coeff2_vec_n_rows[(row_idx + 1) * bit_width - 1 -: bit_width] = coeff_n;
                        end
                        default: begin
                            o_coeff3_vec_p_rows[(row_idx + 1) * bit_width - 1 -: bit_width] = coeff_p;
                            o_coeff3_vec_n_rows[(row_idx + 1) * bit_width - 1 -: bit_width] = coeff_n;
                        end
                    endcase
                end
            end
        end
    end

    assign o_bias_vec_p_rows = i_bias_vec_p_rows;
    assign o_bias_vec_n_rows = i_bias_vec_n_rows;

endmodule
