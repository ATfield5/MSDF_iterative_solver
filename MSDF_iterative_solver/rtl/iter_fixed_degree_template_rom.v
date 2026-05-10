`timescale 1ns / 1ps

// First template packaging path: one packed payload word per cluster.
//
// The memory image is produced by `pack_fixed_degree_templates.py`.

module iter_fixed_degree_template_rom #(
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
    parameter integer payload_width = valid_width + src_width + 2 * coeff_terms_width + 2 * bias_vec_width,
    parameter template_mem_init = "MSDF_iterative_solver/generated/blockdiag8_fixed4_templates.memh"
) (
    output [num_clusters * payload_width - 1 : 0] o_template_words_clusters
);

    reg [payload_width - 1 : 0] r_template_words [0 : num_clusters - 1];
    integer ri;
    genvar gi;

    initial begin
        for (ri = 0; ri < num_clusters; ri = ri + 1) begin
            r_template_words[ri] = {payload_width{1'b0}};
        end
        $readmemh(template_mem_init, r_template_words);
    end

    generate
        for (gi = 0; gi < num_clusters; gi = gi + 1) begin : gen_rom_out
            assign o_template_words_clusters[(gi + 1) * payload_width - 1 -: payload_width] =
                r_template_words[gi];
        end
    endgenerate

endmodule
