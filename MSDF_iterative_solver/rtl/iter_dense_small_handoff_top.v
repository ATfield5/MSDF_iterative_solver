`timescale 1ns / 1ps

// Dense small top with internal x_old handoff.
//
// Compared with iter_dense_small_closed_loop_top, this version removes the
// external x_old input and feeds row-update outputs back into the next
// iteration's delta/certification path through explicit row-state buffers.
//
// Scope:
// - closes the first real state-transfer boundary
// - keeps x-driving digits external
// - does not yet replay x^(k+1) as an online source stream for the next row
//   update stage

module iter_dense_small_handoff_top #(
    parameter integer num_clusters = 2,
    parameter integer num_rows = 4,
    parameter integer bit_width = 8,
    parameter integer bound_width = bit_width + 5,
    parameter integer coeff_width = 16,
    parameter integer acc_width = 40,
    parameter integer block_size = 2,
    parameter integer num_blocks = (num_rows + block_size - 1) / block_size
) (
    input                                               i_clk,
    input                                               i_rst,
    input                                               i_start_iter,
    input      [num_clusters * num_rows - 1 : 0]        i_ena_rows_clusters,
    input      [num_clusters * num_rows - 1 : 0]        i_x0_p_rows_clusters,
    input      [num_clusters * num_rows - 1 : 0]        i_x0_n_rows_clusters,
    input      [num_clusters * num_rows - 1 : 0]        i_x1_p_rows_clusters,
    input      [num_clusters * num_rows - 1 : 0]        i_x1_n_rows_clusters,
    input      [num_clusters * num_rows - 1 : 0]        i_x2_p_rows_clusters,
    input      [num_clusters * num_rows - 1 : 0]        i_x2_n_rows_clusters,
    input      [num_clusters * num_rows - 1 : 0]        i_x3_p_rows_clusters,
    input      [num_clusters * num_rows - 1 : 0]        i_x3_n_rows_clusters,
    input      [num_clusters * num_rows * bit_width - 1 : 0] i_coeff0_vec_p_rows_clusters,
    input      [num_clusters * num_rows * bit_width - 1 : 0] i_coeff0_vec_n_rows_clusters,
    input      [num_clusters * num_rows * bit_width - 1 : 0] i_coeff1_vec_p_rows_clusters,
    input      [num_clusters * num_rows * bit_width - 1 : 0] i_coeff1_vec_n_rows_clusters,
    input      [num_clusters * num_rows * bit_width - 1 : 0] i_coeff2_vec_p_rows_clusters,
    input      [num_clusters * num_rows * bit_width - 1 : 0] i_coeff2_vec_n_rows_clusters,
    input      [num_clusters * num_rows * bit_width - 1 : 0] i_coeff3_vec_p_rows_clusters,
    input      [num_clusters * num_rows * bit_width - 1 : 0] i_coeff3_vec_n_rows_clusters,
    input      [num_clusters * num_rows * (bit_width + 2) - 1 : 0] i_bias_vec_p_rows_clusters,
    input      [num_clusters * num_rows * (bit_width + 2) - 1 : 0] i_bias_vec_n_rows_clusters,
    input      [num_clusters * bound_width - 1 : 0]     i_tail_bound_clusters,
    input      [num_clusters * num_rows * num_blocks * coeff_width - 1 : 0] i_block_weights_clusters,
    input      [num_clusters * acc_width - 1 : 0]       i_eta_clusters,
    output     [num_clusters - 1 : 0]                   o_cluster_valid,
    output     [num_clusters - 1 : 0]                   o_cluster_certified,
    output     [num_clusters * acc_width - 1 : 0]       o_cluster_max_error,
    output     [num_clusters * num_rows * (bit_width + 3) - 1 : 0] o_x_old_p_rows_clusters,
    output     [num_clusters * num_rows * (bit_width + 3) - 1 : 0] o_x_old_n_rows_clusters,
    output                                              o_iter_done,
    output                                              o_iter_converged,
    output                                              o_iter_continue,
    output     [num_clusters - 1 : 0]                   o_seen_mask,
    output     [num_clusters - 1 : 0]                   o_cert_mask
);

    wire [num_clusters - 1 : 0] w_cluster_valid;
    wire [num_clusters - 1 : 0] w_cluster_certified;
    wire [num_clusters * acc_width - 1 : 0] w_cluster_max_error;
    wire [num_clusters * num_rows - 1 : 0] w_valid_rows_clusters;
    wire [num_clusters * num_rows * (bit_width + 3) - 1 : 0] w_sum_p_rows_clusters;
    wire [num_clusters * num_rows * (bit_width + 3) - 1 : 0] w_sum_n_rows_clusters;
    wire [num_clusters * num_rows * (bit_width + 3) - 1 : 0] w_x_old_p_rows_clusters;
    wire [num_clusters * num_rows * (bit_width + 3) - 1 : 0] w_x_old_n_rows_clusters;
    reg  [num_clusters - 1 : 0] r_cluster_certified;
    reg  [num_clusters * acc_width - 1 : 0] r_cluster_max_error;
    integer ri;

    genvar gi;
    generate
        for (gi = 0; gi < num_clusters; gi = gi + 1) begin : gen_clusters
            wire [num_rows * bound_width - 1 : 0] w_abs_upper_rows_unused;
            wire [num_blocks * bound_width - 1 : 0] w_block_bounds_unused;

            online_row_cluster_delta_cert #(
                .num_rows(num_rows),
                .bit_width(bit_width),
                .bound_width(bound_width),
                .coeff_width(coeff_width),
                .acc_width(acc_width),
                .block_size(block_size),
                .num_blocks(num_blocks)
            ) cluster_datapath (
                .i_clk(i_clk),
                .i_rst(i_rst),
                .i_ena_rows(i_ena_rows_clusters[(gi + 1) * num_rows - 1 -: num_rows]),
                .i_x0_p_rows(i_x0_p_rows_clusters[(gi + 1) * num_rows - 1 -: num_rows]),
                .i_x0_n_rows(i_x0_n_rows_clusters[(gi + 1) * num_rows - 1 -: num_rows]),
                .i_x1_p_rows(i_x1_p_rows_clusters[(gi + 1) * num_rows - 1 -: num_rows]),
                .i_x1_n_rows(i_x1_n_rows_clusters[(gi + 1) * num_rows - 1 -: num_rows]),
                .i_x2_p_rows(i_x2_p_rows_clusters[(gi + 1) * num_rows - 1 -: num_rows]),
                .i_x2_n_rows(i_x2_n_rows_clusters[(gi + 1) * num_rows - 1 -: num_rows]),
                .i_x3_p_rows(i_x3_p_rows_clusters[(gi + 1) * num_rows - 1 -: num_rows]),
                .i_x3_n_rows(i_x3_n_rows_clusters[(gi + 1) * num_rows - 1 -: num_rows]),
                .i_coeff0_vec_p_rows(i_coeff0_vec_p_rows_clusters[(gi + 1) * num_rows * bit_width - 1 -: num_rows * bit_width]),
                .i_coeff0_vec_n_rows(i_coeff0_vec_n_rows_clusters[(gi + 1) * num_rows * bit_width - 1 -: num_rows * bit_width]),
                .i_coeff1_vec_p_rows(i_coeff1_vec_p_rows_clusters[(gi + 1) * num_rows * bit_width - 1 -: num_rows * bit_width]),
                .i_coeff1_vec_n_rows(i_coeff1_vec_n_rows_clusters[(gi + 1) * num_rows * bit_width - 1 -: num_rows * bit_width]),
                .i_coeff2_vec_p_rows(i_coeff2_vec_p_rows_clusters[(gi + 1) * num_rows * bit_width - 1 -: num_rows * bit_width]),
                .i_coeff2_vec_n_rows(i_coeff2_vec_n_rows_clusters[(gi + 1) * num_rows * bit_width - 1 -: num_rows * bit_width]),
                .i_coeff3_vec_p_rows(i_coeff3_vec_p_rows_clusters[(gi + 1) * num_rows * bit_width - 1 -: num_rows * bit_width]),
                .i_coeff3_vec_n_rows(i_coeff3_vec_n_rows_clusters[(gi + 1) * num_rows * bit_width - 1 -: num_rows * bit_width]),
                .i_bias_vec_p_rows(i_bias_vec_p_rows_clusters[(gi + 1) * num_rows * (bit_width + 2) - 1 -: num_rows * (bit_width + 2)]),
                .i_bias_vec_n_rows(i_bias_vec_n_rows_clusters[(gi + 1) * num_rows * (bit_width + 2) - 1 -: num_rows * (bit_width + 2)]),
                .i_x_old_p_rows(w_x_old_p_rows_clusters[(gi + 1) * num_rows * (bit_width + 3) - 1 -: num_rows * (bit_width + 3)]),
                .i_x_old_n_rows(w_x_old_n_rows_clusters[(gi + 1) * num_rows * (bit_width + 3) - 1 -: num_rows * (bit_width + 3)]),
                .i_tail_bound(i_tail_bound_clusters[(gi + 1) * bound_width - 1 -: bound_width]),
                .i_block_weights(i_block_weights_clusters[(gi + 1) * num_rows * num_blocks * coeff_width - 1 -: num_rows * num_blocks * coeff_width]),
                .i_eta(i_eta_clusters[(gi + 1) * acc_width - 1 -: acc_width]),
                .o_valid_rows(w_valid_rows_clusters[(gi + 1) * num_rows - 1 -: num_rows]),
                .o_sum_p_rows(w_sum_p_rows_clusters[(gi + 1) * num_rows * (bit_width + 3) - 1 -: num_rows * (bit_width + 3)]),
                .o_sum_n_rows(w_sum_n_rows_clusters[(gi + 1) * num_rows * (bit_width + 3) - 1 -: num_rows * (bit_width + 3)]),
                .o_abs_upper_rows(w_abs_upper_rows_unused),
                .o_block_bounds(w_block_bounds_unused),
                .o_cluster_valid(w_cluster_valid[gi]),
                .o_cluster_certified(w_cluster_certified[gi]),
                .o_cluster_max_error(w_cluster_max_error[(gi + 1) * acc_width - 1 -: acc_width])
            );

            iter_row_state_handoff_buffer #(
                .num_rows(num_rows),
                .data_width(bit_width + 3)
            ) state_handoff (
                .i_clk(i_clk),
                .i_rst(i_rst),
                .i_clear(1'b0),
                .i_valid_rows(w_valid_rows_clusters[(gi + 1) * num_rows - 1 -: num_rows]),
                .i_state_p_rows(w_sum_p_rows_clusters[(gi + 1) * num_rows * (bit_width + 3) - 1 -: num_rows * (bit_width + 3)]),
                .i_state_n_rows(w_sum_n_rows_clusters[(gi + 1) * num_rows * (bit_width + 3) - 1 -: num_rows * (bit_width + 3)]),
                .o_state_p_rows(w_x_old_p_rows_clusters[(gi + 1) * num_rows * (bit_width + 3) - 1 -: num_rows * (bit_width + 3)]),
                .o_state_n_rows(w_x_old_n_rows_clusters[(gi + 1) * num_rows * (bit_width + 3) - 1 -: num_rows * (bit_width + 3)])
            );
        end
    endgenerate

    iter_cluster_cert_controller #(
        .num_clusters(num_clusters)
    ) iter_controller (
        .i_clk(i_clk),
        .i_rst(i_rst),
        .i_start_iter(i_start_iter),
        .i_cluster_valid(w_cluster_valid),
        .i_cluster_certified(w_cluster_certified),
        .o_iter_done(o_iter_done),
        .o_iter_converged(o_iter_converged),
        .o_iter_continue(o_iter_continue),
        .o_seen_mask(o_seen_mask),
        .o_cert_mask(o_cert_mask)
    );

    assign o_cluster_valid = w_cluster_valid;
    assign o_cluster_certified = r_cluster_certified;
    assign o_cluster_max_error = r_cluster_max_error;
    assign o_x_old_p_rows_clusters = w_x_old_p_rows_clusters;
    assign o_x_old_n_rows_clusters = w_x_old_n_rows_clusters;

    always @(posedge i_clk) begin
        if (i_rst || i_start_iter) begin
            r_cluster_certified <= {num_clusters{1'b0}};
            r_cluster_max_error <= {num_clusters * acc_width{1'b0}};
        end else begin
            for (ri = 0; ri < num_clusters; ri = ri + 1) begin
                if (w_cluster_valid[ri]) begin
                    r_cluster_certified[ri] <= w_cluster_certified[ri];
                    r_cluster_max_error[(ri + 1) * acc_width - 1 -: acc_width]
                        <= w_cluster_max_error[(ri + 1) * acc_width - 1 -: acc_width];
                end
            end
        end
    end

endmodule
