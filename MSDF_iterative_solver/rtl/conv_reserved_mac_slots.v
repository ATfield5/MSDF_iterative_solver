`timescale 1ns / 1ps

// Reserved DSP-MAC slots for fairness experiments.
//
// Some same-scope comparisons need the conventional baseline to reserve the
// same physical input-slot width as a prior online operator, even when the
// current sparse fixture has fewer live terms.  If padded terms are tied to
// compile-time zero, synthesis correctly removes those multipliers.  This
// module keeps the extra multiplier slots as real registered DSP work, but its
// products are not consumed by the mathematical row update.

(* keep_hierarchy = "yes" *)
module conv_reserved_mac_slots #(
    parameter integer num_rows = 4,
    parameter integer live_degree = 4,
    parameter integer reserved_degree = 4,
    parameter integer data_width = 14,
    parameter integer bit_width = 11,
    parameter integer acc_width = 32
) (
    input                                               i_clk,
    input                                               i_rst,
    input                                               i_valid,
    input      [num_rows * live_degree * data_width - 1 : 0] i_state_p_terms_rows,
    input      [num_rows * live_degree * data_width - 1 : 0] i_state_n_terms_rows,
    input      [num_rows * live_degree * bit_width - 1 : 0]  i_coeff_p_terms_rows,
    input      [num_rows * live_degree * bit_width - 1 : 0]  i_coeff_n_terms_rows,
    output     [num_rows * reserved_degree * acc_width - 1 : 0] o_product_rows
);

    genvar ri;
    genvar di;
    generate
        for (ri = 0; ri < num_rows; ri = ri + 1) begin : gen_rows
            for (di = 0; di < reserved_degree; di = di + 1) begin : gen_slots
                localparam integer live_term = di % live_degree;

                wire signed [data_width : 0] w_state_term;
                wire signed [bit_width : 0] w_coeff_term;
                (* use_dsp = "yes" *) wire signed [acc_width - 1 : 0] w_product;
                (* keep = "true", dont_touch = "true" *)
                reg signed [acc_width - 1 : 0] r_product;

                assign w_state_term =
                    $signed({1'b0, i_state_p_terms_rows[
                        ((ri * live_degree + live_term) + 1) * data_width - 1 -:
                        data_width]}) -
                    $signed({1'b0, i_state_n_terms_rows[
                        ((ri * live_degree + live_term) + 1) * data_width - 1 -:
                        data_width]});
                assign w_coeff_term =
                    $signed({1'b0, i_coeff_p_terms_rows[
                        ((ri * live_degree + live_term) + 1) * bit_width - 1 -:
                        bit_width]}) -
                    $signed({1'b0, i_coeff_n_terms_rows[
                        ((ri * live_degree + live_term) + 1) * bit_width - 1 -:
                        bit_width]});
                assign w_product = w_state_term * w_coeff_term;

                always @(posedge i_clk) begin
                    if (i_rst) begin
                        r_product <= {acc_width{1'b0}};
                    end else if (i_valid) begin
                        r_product <= w_product;
                    end
                end

                assign o_product_rows[
                    ((ri * reserved_degree + di) + 1) * acc_width - 1 -:
                    acc_width] = r_product;
            end
        end
    endgenerate

endmodule
