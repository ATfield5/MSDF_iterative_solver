`timescale 1ns / 1ps

// Unpack one-word-per-cluster template payloads into scheduler buses.
//
// Payload layout, from LSB to MSB:
//   [valid_mask][src_row_idx][coeff_p_terms][coeff_n_terms][bias_p_rows][bias_n_rows]

module iter_fixed_degree_template_unpack #(
    parameter integer num_clusters = 2,
    parameter integer num_rows = 4,
    parameter integer degree = 4,
    parameter integer bit_width = 8,
    parameter integer bias_width = bit_width + 2,
    parameter integer row_idx_width = (num_rows <= 2) ? 1 : $clog2(num_rows),
    parameter integer valid_width = num_rows * degree,
    parameter integer src_width = num_rows * degree * row_idx_width,
    parameter integer coeff_terms_width = num_rows * degree * bit_width,
    parameter integer bias_vec_width = num_rows * bias_width,
    parameter integer payload_width = valid_width + src_width + 2 * coeff_terms_width + 2 * bias_vec_width
) (
    input  [num_clusters * payload_width - 1 : 0]             i_template_words_clusters,
    output [num_clusters * valid_width - 1 : 0]               o_term_valid_mask_clusters,
    output [num_clusters * src_width - 1 : 0]                 o_src_row_idx_clusters,
    output [num_clusters * coeff_terms_width - 1 : 0]         o_coeff_p_terms_clusters,
    output [num_clusters * coeff_terms_width - 1 : 0]         o_coeff_n_terms_clusters,
    output [num_clusters * bias_vec_width - 1 : 0]            o_bias_vec_p_rows_clusters,
    output [num_clusters * bias_vec_width - 1 : 0]            o_bias_vec_n_rows_clusters
);

    localparam integer off_valid = 0;
    localparam integer off_src = off_valid + valid_width;
    localparam integer off_coeff_p = off_src + src_width;
    localparam integer off_coeff_n = off_coeff_p + coeff_terms_width;
    localparam integer off_bias_p = off_coeff_n + coeff_terms_width;
    localparam integer off_bias_n = off_bias_p + bias_vec_width;

    genvar gi;
    generate
        for (gi = 0; gi < num_clusters; gi = gi + 1) begin : gen_unpack
            wire [payload_width - 1 : 0] w_payload;
            assign w_payload = i_template_words_clusters[(gi + 1) * payload_width - 1 -: payload_width];

            assign o_term_valid_mask_clusters[(gi + 1) * valid_width - 1 -: valid_width] =
                w_payload[off_valid + valid_width - 1 -: valid_width];
            assign o_src_row_idx_clusters[(gi + 1) * src_width - 1 -: src_width] =
                w_payload[off_src + src_width - 1 -: src_width];
            assign o_coeff_p_terms_clusters[(gi + 1) * coeff_terms_width - 1 -: coeff_terms_width] =
                w_payload[off_coeff_p + coeff_terms_width - 1 -: coeff_terms_width];
            assign o_coeff_n_terms_clusters[(gi + 1) * coeff_terms_width - 1 -: coeff_terms_width] =
                w_payload[off_coeff_n + coeff_terms_width - 1 -: coeff_terms_width];
            assign o_bias_vec_p_rows_clusters[(gi + 1) * bias_vec_width - 1 -: bias_vec_width] =
                w_payload[off_bias_p + bias_vec_width - 1 -: bias_vec_width];
            assign o_bias_vec_n_rows_clusters[(gi + 1) * bias_vec_width - 1 -: bias_vec_width] =
                w_payload[off_bias_n + bias_vec_width - 1 -: bias_vec_width];
        end
    endgenerate

endmodule
