`timescale 1ns / 1ps

// Unpack one-word-per-cluster block-H certification parameter payloads.
//
// Payload layout, from LSB to MSB:
//   [block_weights][eta]

module iter_cert_param_unpack #(
    parameter integer num_clusters = 2,
    parameter integer num_rows = 4,
    parameter integer num_blocks = 2,
    parameter integer coeff_width = 8,
    parameter integer acc_width = 24,
    parameter integer block_weights_width = num_rows * num_blocks * coeff_width,
    parameter integer payload_width = block_weights_width + acc_width
) (
    input  [num_clusters * payload_width - 1 : 0]          i_cert_param_words_clusters,
    output [num_clusters * block_weights_width - 1 : 0]    o_block_weights_clusters,
    output [num_clusters * acc_width - 1 : 0]              o_eta_clusters
);

    genvar gi;
    generate
        for (gi = 0; gi < num_clusters; gi = gi + 1) begin : gen_unpack
            wire [payload_width - 1 : 0] w_payload;
            assign w_payload = i_cert_param_words_clusters[(gi + 1) * payload_width - 1 -: payload_width];
            assign o_block_weights_clusters[(gi + 1) * block_weights_width - 1 -: block_weights_width] =
                w_payload[block_weights_width - 1 : 0];
            assign o_eta_clusters[(gi + 1) * acc_width - 1 -: acc_width] =
                w_payload[payload_width - 1 -: acc_width];
        end
    endgenerate

endmodule
