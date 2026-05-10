`timescale 1ns / 1ps

// First-step block-wise sensitivity certification engine.
// This module is word-parallel and functional-first. It is intended to validate
// the H-based certification rule before a more specialized online arithmetic
// implementation is introduced.

module block_h_cert_engine #(
    parameter integer num_rows = 4,
    parameter integer num_blocks = 4,
    parameter integer bound_width = 16,
    parameter integer coeff_width = 16,
    parameter integer acc_width = 40,
    parameter integer product_pipeline = 0,
    parameter integer operand_pipeline = 0,
    parameter integer compare_pipeline = 0
) (
    input                                             i_clk,
    input                                             i_rst,
    input                                             i_valid,
    input      [num_blocks * bound_width - 1 : 0]     i_block_bounds,
    input      [num_rows * num_blocks * coeff_width - 1 : 0] i_block_weights,
    input      [acc_width - 1 : 0]                    i_eta,
    output reg                                        o_valid,
    output reg                                        o_certified,
    output reg [acc_width - 1 : 0]                    o_max_error
);

    integer r;
    integer b;
    reg [acc_width - 1 : 0] row_sum_direct_comb;
    reg [acc_width - 1 : 0] row_sum_operand_comb;
    reg [acc_width - 1 : 0] row_sum_product_pipe_comb;
    reg [acc_width - 1 : 0] row_sum_max;
    reg [acc_width - 1 : 0] max_sum;
    reg [acc_width - 1 : 0] r_max_sum;
    reg [acc_width - 1 : 0] r_eta;
    reg [bound_width - 1 : 0] block_bound;
    reg [coeff_width - 1 : 0] block_weight;
    reg [num_rows * acc_width - 1 : 0] row_sums_comb;
    reg [num_rows * acc_width - 1 : 0] row_sums_from_products_comb;
    reg [num_rows * acc_width - 1 : 0] r_row_sums;
    reg [num_rows * num_blocks * acc_width - 1 : 0] product_terms_comb;
    reg [num_rows * num_blocks * acc_width - 1 : 0] product_terms_from_operands_comb;
    reg [num_rows * num_blocks * acc_width - 1 : 0] r_product_terms;
    reg [num_rows * num_blocks * bound_width - 1 : 0] operand_bound_terms_comb;
    reg [num_rows * num_blocks * coeff_width - 1 : 0] operand_weight_terms_comb;
    reg [num_rows * num_blocks * bound_width - 1 : 0] r_bound_terms;
    reg [num_rows * num_blocks * coeff_width - 1 : 0] r_weight_terms;
    reg [acc_width - 1 : 0] product_term;
    reg [acc_width - 1 : 0] operand_product_term;
    reg [acc_width - 1 : 0] product_sum_term;
    reg [num_rows * acc_width - 1 : 0] row_sums_from_operands_comb;
    reg [bound_width - 1 : 0] operand_block_bound;
    reg [coeff_width - 1 : 0] operand_block_weight;
    reg r_valid_operands;
    reg r_valid_products;
    reg r_valid_stage1;
    reg r_valid_compare;

    always @(*) begin
        row_sums_comb = {num_rows * acc_width{1'b0}};
        product_terms_comb = {num_rows * num_blocks * acc_width{1'b0}};
        operand_bound_terms_comb = {num_rows * num_blocks * bound_width{1'b0}};
        operand_weight_terms_comb = {num_rows * num_blocks * coeff_width{1'b0}};
        for (r = 0; r < num_rows; r = r + 1) begin
            row_sum_direct_comb = {acc_width{1'b0}};
            for (b = 0; b < num_blocks; b = b + 1) begin
                block_bound = i_block_bounds[(b + 1) * bound_width - 1 -: bound_width];
                block_weight = i_block_weights[((r * num_blocks + b) + 1) * coeff_width - 1 -: coeff_width];
                product_term = block_bound * block_weight;
                product_terms_comb[((r * num_blocks + b) + 1) * acc_width - 1 -: acc_width] = product_term;
                operand_bound_terms_comb[((r * num_blocks + b) + 1) * bound_width - 1 -: bound_width] = block_bound;
                operand_weight_terms_comb[((r * num_blocks + b) + 1) * coeff_width - 1 -: coeff_width] = block_weight;
                row_sum_direct_comb = row_sum_direct_comb + product_term;
            end
            row_sums_comb[(r + 1) * acc_width - 1 -: acc_width] = row_sum_direct_comb;
        end
    end

    always @(*) begin
        row_sums_from_operands_comb = {num_rows * acc_width{1'b0}};
        product_terms_from_operands_comb = {num_rows * num_blocks * acc_width{1'b0}};
        for (r = 0; r < num_rows; r = r + 1) begin
            row_sum_operand_comb = {acc_width{1'b0}};
            for (b = 0; b < num_blocks; b = b + 1) begin
                operand_block_bound = r_bound_terms[((r * num_blocks + b) + 1) * bound_width - 1 -: bound_width];
                operand_block_weight = r_weight_terms[((r * num_blocks + b) + 1) * coeff_width - 1 -: coeff_width];
                operand_product_term = operand_block_bound * operand_block_weight;
                product_terms_from_operands_comb[((r * num_blocks + b) + 1) * acc_width - 1 -: acc_width] = operand_product_term;
                row_sum_operand_comb = row_sum_operand_comb + operand_product_term;
            end
            row_sums_from_operands_comb[(r + 1) * acc_width - 1 -: acc_width] = row_sum_operand_comb;
        end
    end

    always @(*) begin
        row_sums_from_products_comb = {num_rows * acc_width{1'b0}};
        for (r = 0; r < num_rows; r = r + 1) begin
            row_sum_product_pipe_comb = {acc_width{1'b0}};
            for (b = 0; b < num_blocks; b = b + 1) begin
                product_sum_term = r_product_terms[((r * num_blocks + b) + 1) * acc_width - 1 -: acc_width];
                row_sum_product_pipe_comb = row_sum_product_pipe_comb + product_sum_term;
            end
            row_sums_from_products_comb[(r + 1) * acc_width - 1 -: acc_width] = row_sum_product_pipe_comb;
        end
    end

    always @(*) begin
        max_sum = {acc_width{1'b0}};
        for (r = 0; r < num_rows; r = r + 1) begin
            row_sum_max = r_row_sums[(r + 1) * acc_width - 1 -: acc_width];
            if (row_sum_max > max_sum) begin
                max_sum = row_sum_max;
            end
        end
    end

    always @(posedge i_clk) begin
        if (i_rst) begin
            r_row_sums <= {num_rows * acc_width{1'b0}};
            r_product_terms <= {num_rows * num_blocks * acc_width{1'b0}};
            r_bound_terms <= {num_rows * num_blocks * bound_width{1'b0}};
            r_weight_terms <= {num_rows * num_blocks * coeff_width{1'b0}};
            r_valid_operands <= 1'b0;
            r_valid_products <= 1'b0;
            r_valid_stage1 <= 1'b0;
            r_valid_compare <= 1'b0;
            r_max_sum <= {acc_width{1'b0}};
            r_eta <= {acc_width{1'b0}};
            o_valid <= 1'b0;
            o_certified <= 1'b0;
            o_max_error <= {acc_width{1'b0}};
        end else begin
            if (operand_pipeline != 0) begin
                r_bound_terms <= operand_bound_terms_comb;
                r_weight_terms <= operand_weight_terms_comb;
                r_valid_operands <= i_valid;
                if (product_pipeline != 0) begin
                    r_product_terms <= product_terms_from_operands_comb;
                    r_valid_products <= r_valid_operands;
                    r_row_sums <= row_sums_from_products_comb;
                    r_valid_stage1 <= r_valid_products;
                end else begin
                    r_product_terms <= {num_rows * num_blocks * acc_width{1'b0}};
                    r_valid_products <= 1'b0;
                    r_row_sums <= row_sums_from_operands_comb;
                    r_valid_stage1 <= r_valid_operands;
                end
            end else begin
                r_bound_terms <= {num_rows * num_blocks * bound_width{1'b0}};
                r_weight_terms <= {num_rows * num_blocks * coeff_width{1'b0}};
                r_valid_operands <= 1'b0;
                if (product_pipeline != 0) begin
                    r_product_terms <= product_terms_comb;
                    r_valid_products <= i_valid;
                    r_row_sums <= row_sums_from_products_comb;
                    r_valid_stage1 <= r_valid_products;
                end else begin
                    r_product_terms <= {num_rows * num_blocks * acc_width{1'b0}};
                    r_valid_products <= 1'b0;
                    r_row_sums <= row_sums_comb;
                    r_valid_stage1 <= i_valid;
                end
            end
            if (compare_pipeline != 0) begin
                r_max_sum <= max_sum;
                r_eta <= i_eta;
                r_valid_compare <= r_valid_stage1;
                o_valid <= r_valid_compare;
                o_max_error <= r_max_sum;
                o_certified <= r_valid_compare && (r_max_sum <= r_eta);
            end else begin
                r_max_sum <= {acc_width{1'b0}};
                r_eta <= {acc_width{1'b0}};
                r_valid_compare <= 1'b0;
                o_valid <= r_valid_stage1;
                o_max_error <= max_sum;
                o_certified <= r_valid_stage1 && (max_sum <= i_eta);
            end
        end
    end

endmodule
