`timescale 1ns / 1ps

// Row-cluster block-bound aggregation.
//
// Each row-local delta/cert slice produces a strict upper bound U_i on the
// prefix error magnitude for that row. For H-based block certification we need:
//
//   Delta_t = max_{i in block t} U_i
//
// This module performs that aggregation for a fixed row cluster and exposes a
// controller-ready valid signal when the entire row cluster is ready.

module block_bound_max_pool #(
    parameter integer num_rows = 4,
    parameter integer block_size = 2,
    parameter integer bound_width = 16,
    parameter integer num_blocks = (num_rows + block_size - 1) / block_size
) (
    input      [num_rows - 1 : 0]                i_valid_rows,
    input      [num_rows * bound_width - 1 : 0]  i_row_abs_upper,
    output reg                                   o_valid,
    output reg [num_blocks * bound_width - 1 : 0] o_block_bounds
);

    integer b;
    integer r;
    integer row_idx;
    reg [bound_width - 1 : 0] max_bound;
    reg [bound_width - 1 : 0] row_bound;

    always @(*) begin
        o_valid = &i_valid_rows;
        o_block_bounds = {(num_blocks * bound_width){1'b0}};

        for (b = 0; b < num_blocks; b = b + 1) begin
            max_bound = {bound_width{1'b0}};
            for (r = 0; r < block_size; r = r + 1) begin
                row_idx = b * block_size + r;
                if (row_idx < num_rows) begin
                    row_bound = i_row_abs_upper[(row_idx + 1) * bound_width - 1 -: bound_width];
                    if (row_bound > max_bound) begin
                        max_bound = row_bound;
                    end
                end
            end
            o_block_bounds[(b + 1) * bound_width - 1 -: bound_width] = max_bound;
        end
    end

endmodule
