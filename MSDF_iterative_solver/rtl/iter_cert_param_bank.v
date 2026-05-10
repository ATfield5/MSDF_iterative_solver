`timescale 1ns / 1ps

// Multi-cluster certification parameter bank.

module iter_cert_param_bank #(
    parameter integer num_total_clusters = 2,
    parameter integer num_clusters = 2,
    parameter integer payload_width = 88,
    parameter integer cluster_addr_width = (num_total_clusters <= 2) ? 1 : $clog2(num_total_clusters),
    parameter cert_param_mem_init = "MSDF_iterative_solver/generated/blockdiag8_cert_params.memh"
) (
    input      [cluster_addr_width - 1 : 0]                i_base_cluster_idx,
    output reg [num_clusters * payload_width - 1 : 0]      o_cert_param_words_clusters
);

    reg [payload_width - 1 : 0] r_cert_param_words [0 : num_total_clusters - 1];
    integer ri;
    integer mem_idx;

    initial begin
        for (ri = 0; ri < num_total_clusters; ri = ri + 1) begin
            r_cert_param_words[ri] = {payload_width{1'b0}};
        end
        $readmemh(cert_param_mem_init, r_cert_param_words);
    end

    always @(*) begin
        o_cert_param_words_clusters = {num_clusters * payload_width{1'b0}};
        for (ri = 0; ri < num_clusters; ri = ri + 1) begin
            mem_idx = i_base_cluster_idx + ri;
            if (mem_idx < num_total_clusters) begin
                o_cert_param_words_clusters[(ri + 1) * payload_width - 1 -: payload_width] =
                    r_cert_param_words[mem_idx];
            end
        end
    end

endmodule
