`timescale 1ns / 1ps

// Conventional FPGA B2-style datapath array.
//
// Scope:
// - same cluster/row/degree shape as the online runtime experiments;
// - full-word signed fixed-point DSP-MAC row update;
// - same block-H certification datapath;
// - no runtime template/state loader yet.

module conv_jacobi_datapath_array_top #(
    parameter integer num_clusters = 8,
    parameter integer num_rows = 4,
    parameter integer degree = 4,
    parameter integer bit_width = 8,
    parameter integer data_width = bit_width + 3,
    parameter integer bias_width = bit_width + 2,
    parameter integer bound_width = bit_width + 5,
    parameter integer coeff_width = 8,
    parameter integer acc_width = 24,
    parameter integer mac_acc_width = 32,
    parameter integer block_size = 2,
    parameter integer num_blocks = (num_rows + block_size - 1) / block_size,
    parameter integer mac_pipeline = 0,
    parameter integer cert_operand_pipeline = 0
) (
    input                                                       i_clk,
    input                                                       i_rst,
    input                                                       i_valid,
    input      [num_clusters * num_rows * degree * data_width - 1 : 0] i_state_p_terms_clusters,
    input      [num_clusters * num_rows * degree * data_width - 1 : 0] i_state_n_terms_clusters,
    input      [num_clusters * num_rows * degree * bit_width - 1 : 0]  i_coeff_p_terms_clusters,
    input      [num_clusters * num_rows * degree * bit_width - 1 : 0]  i_coeff_n_terms_clusters,
    input      [num_clusters * num_rows * bias_width - 1 : 0]          i_bias_p_rows_clusters,
    input      [num_clusters * num_rows * bias_width - 1 : 0]          i_bias_n_rows_clusters,
    input      [num_clusters * num_rows * data_width - 1 : 0]          i_old_state_p_rows_clusters,
    input      [num_clusters * num_rows * data_width - 1 : 0]          i_old_state_n_rows_clusters,
    input      [num_clusters * bound_width - 1 : 0]                   i_tail_bound_clusters,
    input      [num_clusters * num_rows * num_blocks * coeff_width - 1 : 0] i_block_weights_clusters,
    input      [num_clusters * acc_width - 1 : 0]                     i_eta_clusters,
    output     [num_clusters - 1 : 0]                                 o_cluster_valid,
    output     [num_clusters - 1 : 0]                                 o_cluster_certified,
    output     [num_clusters * acc_width - 1 : 0]                     o_cluster_max_error,
    output     [num_clusters * num_rows * mac_acc_width - 1 : 0]      o_sum_rows_clusters,
    output     [num_clusters * num_rows * data_width - 1 : 0]         o_sum_p_rows_clusters,
    output     [num_clusters * num_rows * data_width - 1 : 0]         o_sum_n_rows_clusters
);

    genvar gi;
    generate
        for (gi = 0; gi < num_clusters; gi = gi + 1) begin : gen_clusters
            conv_row_cluster_delta_cert #(
                .num_rows(num_rows),
                .degree(degree),
                .bit_width(bit_width),
                .data_width(data_width),
                .bias_width(bias_width),
                .bound_width(bound_width),
                .coeff_width(coeff_width),
                .acc_width(acc_width),
                .mac_acc_width(mac_acc_width),
                .block_size(block_size),
                .num_blocks(num_blocks),
                .mac_pipeline(mac_pipeline),
                .cert_operand_pipeline(cert_operand_pipeline)
            ) cluster (
                .i_clk(i_clk),
                .i_rst(i_rst),
                .i_valid(i_valid),
                .i_state_p_terms_rows(i_state_p_terms_clusters[(gi + 1) * num_rows * degree * data_width - 1 -: num_rows * degree * data_width]),
                .i_state_n_terms_rows(i_state_n_terms_clusters[(gi + 1) * num_rows * degree * data_width - 1 -: num_rows * degree * data_width]),
                .i_coeff_p_terms_rows(i_coeff_p_terms_clusters[(gi + 1) * num_rows * degree * bit_width - 1 -: num_rows * degree * bit_width]),
                .i_coeff_n_terms_rows(i_coeff_n_terms_clusters[(gi + 1) * num_rows * degree * bit_width - 1 -: num_rows * degree * bit_width]),
                .i_bias_p_rows(i_bias_p_rows_clusters[(gi + 1) * num_rows * bias_width - 1 -: num_rows * bias_width]),
                .i_bias_n_rows(i_bias_n_rows_clusters[(gi + 1) * num_rows * bias_width - 1 -: num_rows * bias_width]),
                .i_old_state_p_rows(i_old_state_p_rows_clusters[(gi + 1) * num_rows * data_width - 1 -: num_rows * data_width]),
                .i_old_state_n_rows(i_old_state_n_rows_clusters[(gi + 1) * num_rows * data_width - 1 -: num_rows * data_width]),
                .i_tail_bound(i_tail_bound_clusters[(gi + 1) * bound_width - 1 -: bound_width]),
                .i_block_weights(i_block_weights_clusters[(gi + 1) * num_rows * num_blocks * coeff_width - 1 -: num_rows * num_blocks * coeff_width]),
                .i_eta(i_eta_clusters[(gi + 1) * acc_width - 1 -: acc_width]),
                .o_valid_rows(),
                .o_sum_rows(o_sum_rows_clusters[(gi + 1) * num_rows * mac_acc_width - 1 -: num_rows * mac_acc_width]),
                .o_sum_p_rows(o_sum_p_rows_clusters[(gi + 1) * num_rows * data_width - 1 -: num_rows * data_width]),
                .o_sum_n_rows(o_sum_n_rows_clusters[(gi + 1) * num_rows * data_width - 1 -: num_rows * data_width]),
                .o_abs_upper_rows(),
                .o_cluster_valid(o_cluster_valid[gi]),
                .o_cluster_certified(o_cluster_certified[gi]),
                .o_cluster_max_error(o_cluster_max_error[(gi + 1) * acc_width - 1 -: acc_width])
            );
        end
    endgenerate

endmodule
