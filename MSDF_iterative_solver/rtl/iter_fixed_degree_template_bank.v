`timescale 1ns / 1ps

// Multi-cluster template bank.
//
// Reads a contiguous active window of NUM_CLUSTERS payload words from a larger
// template memory. This is the first step beyond the one-word-per-active-cluster
// ROM used by iter_dense_small_template_top.

module iter_fixed_degree_template_bank #(
    parameter integer num_total_clusters = 2,
    parameter integer num_clusters = 2,
    parameter integer payload_width = 236,
    parameter integer cluster_addr_width = (num_total_clusters <= 2) ? 1 : $clog2(num_total_clusters),
    parameter template_mem_init = "MSDF_iterative_solver/generated/blockdiag8_fixed4_templates.memh"
) (
    input      [cluster_addr_width - 1 : 0]               i_base_cluster_idx,
    output reg [num_clusters * payload_width - 1 : 0]     o_template_words_clusters
);

    reg [payload_width - 1 : 0] r_template_words [0 : num_total_clusters - 1];
    integer ri;
    integer mem_idx;

    initial begin
        for (ri = 0; ri < num_total_clusters; ri = ri + 1) begin
            r_template_words[ri] = {payload_width{1'b0}};
        end
        $readmemh(template_mem_init, r_template_words);
    end

    always @(*) begin
        o_template_words_clusters = {num_clusters * payload_width{1'b0}};
        for (ri = 0; ri < num_clusters; ri = ri + 1) begin
            mem_idx = i_base_cluster_idx + ri;
            if (mem_idx < num_total_clusters) begin
                o_template_words_clusters[(ri + 1) * payload_width - 1 -: payload_width] =
                    r_template_words[mem_idx];
            end
        end
    end

endmodule
