`timescale 1ns / 1ps

// P4-SP standalone conventional full-word PageRank wavefront.
//
// This top uses the same global-source template fixture as P3-SP, but each
// stage materializes a complete row word before the next stage starts.  It is
// intentionally kept separate from the runtime shell so the operator-level
// latency difference can be measured without configuration/state preload noise.

module iter_parallel_in_conv_mma8_global_wavefront_top #(
    parameter integer num_stages = 4,
    parameter integer num_rows = 32,
    parameter integer degree = 4,
    parameter integer physical_degree = 8,
    parameter integer bit_width = 30,
    parameter integer data_width = 32,
    parameter integer bias_width = 32,
    parameter integer bound_width = 16,
    parameter integer acc_width = 40,
    parameter integer product_width = data_width + bit_width + 4,
    parameter integer product_shift = data_width,
    parameter integer round_pipeline = 1,
    parameter integer src_idx_width = (num_rows <= 2) ? 1 : $clog2(num_rows)
) (
    input                                                   i_clk,
    input                                                   i_rst,
    input                                                   i_clear,
    input                                                   i_start,
    input      [num_rows * degree * src_idx_width - 1 : 0]  i_src_row_idx_rows,
    input      [num_rows * degree * bit_width - 1 : 0]      i_coeff_p_terms_rows,
    input      [num_rows * degree * bit_width - 1 : 0]      i_coeff_n_terms_rows,
    input      [num_rows * bias_width - 1 : 0]              i_bias_p_rows,
    input      [num_rows * bias_width - 1 : 0]              i_bias_n_rows,
    output                                                  o_final_valid,
    output     [num_rows * data_width - 1 : 0]              o_final_state_p_rows,
    output     [num_rows * data_width - 1 : 0]              o_final_state_n_rows,
    output reg [num_stages * 32 - 1 : 0]                    o_stage_valid_count,
    output reg [num_stages - 1 : 0]                         o_stage_done
);

    wire [num_stages - 1 : 0] w_stage_valid_in;
    wire [num_stages - 1 : 0] w_stage_valid_out;
    wire [num_stages * num_rows - 1 : 0] w_row_valid_stage;
    wire [num_stages * num_rows * data_width - 1 : 0] w_stage_state_p_rows;
    wire [num_stages * num_rows * data_width - 1 : 0] w_stage_state_n_rows;
    wire [num_stages * num_rows * physical_degree * data_width - 1 : 0] w_state_p_terms_stage;
    wire [num_stages * num_rows * physical_degree * data_width - 1 : 0] w_state_n_terms_stage;
    wire [num_stages * num_rows * physical_degree * bit_width - 1 : 0] w_coeff_p_terms_stage;
    wire [num_stages * num_rows * physical_degree * bit_width - 1 : 0] w_coeff_n_terms_stage;

    integer si_seq;

    assign o_final_valid = w_stage_valid_out[num_stages - 1];
    assign o_final_state_p_rows =
        w_stage_state_p_rows[(num_stages - 1) * num_rows * data_width +:
        num_rows * data_width];
    assign o_final_state_n_rows =
        w_stage_state_n_rows[(num_stages - 1) * num_rows * data_width +:
        num_rows * data_width];

    genvar si;
    genvar ri;
    genvar ti;
    generate
        for (si = 0; si < num_stages; si = si + 1) begin : gen_stage
            if (si == 0) begin : gen_stage0_valid
                assign w_stage_valid_in[si] = i_start;
            end else begin : gen_stage_valid
                assign w_stage_valid_in[si] = w_stage_valid_out[si - 1];
            end

            for (ri = 0; ri < num_rows; ri = ri + 1) begin : gen_rows
                wire [physical_degree * data_width - 1 : 0] w_state_p_terms;
                wire [physical_degree * data_width - 1 : 0] w_state_n_terms;
                wire [physical_degree * bit_width - 1 : 0] w_coeff_p_terms;
                wire [physical_degree * bit_width - 1 : 0] w_coeff_n_terms;
                wire [data_width - 1 : 0] w_unused_old_p;
                wire [data_width - 1 : 0] w_unused_old_n;
                wire [bound_width - 1 : 0] w_unused_abs_upper;
                wire signed [acc_width - 1 : 0] w_unused_sum;
                wire w_row_valid;

                assign w_unused_old_p = {data_width{1'b0}};
                assign w_unused_old_n = {data_width{1'b0}};

                for (ti = 0; ti < physical_degree; ti = ti + 1) begin : gen_terms
                    if (ti < degree) begin : gen_live_term
                        wire [src_idx_width - 1 : 0] w_src_row;
                        assign w_src_row =
                            i_src_row_idx_rows[(ri * degree + ti) * src_idx_width +:
                            src_idx_width];

                        if (si == 0) begin : gen_zero_source
                            assign w_state_p_terms[ti * data_width +: data_width] =
                                {data_width{1'b0}};
                            assign w_state_n_terms[ti * data_width +: data_width] =
                                {data_width{1'b0}};
                        end else begin : gen_prev_source
                            assign w_state_p_terms[ti * data_width +: data_width] =
                                (w_src_row < num_rows)
                                    ? w_stage_state_p_rows[
                                        ((si - 1) * num_rows + w_src_row) *
                                        data_width +: data_width]
                                    : {data_width{1'b0}};
                            assign w_state_n_terms[ti * data_width +: data_width] =
                                (w_src_row < num_rows)
                                    ? w_stage_state_n_rows[
                                        ((si - 1) * num_rows + w_src_row) *
                                        data_width +: data_width]
                                    : {data_width{1'b0}};
                        end

                        assign w_coeff_p_terms[ti * bit_width +: bit_width] =
                            i_coeff_p_terms_rows[(ri * degree + ti) * bit_width +:
                            bit_width];
                        assign w_coeff_n_terms[ti * bit_width +: bit_width] =
                            i_coeff_n_terms_rows[(ri * degree + ti) * bit_width +:
                            bit_width];
                    end else begin : gen_reserved_zero_term
                        assign w_state_p_terms[ti * data_width +: data_width] =
                            {data_width{1'b0}};
                        assign w_state_n_terms[ti * data_width +: data_width] =
                            {data_width{1'b0}};
                        assign w_coeff_p_terms[ti * bit_width +: bit_width] =
                            {bit_width{1'b0}};
                        assign w_coeff_n_terms[ti * bit_width +: bit_width] =
                            {bit_width{1'b0}};
                    end
                end

                assign w_state_p_terms_stage[
                    (si * num_rows + ri) * physical_degree * data_width +:
                    physical_degree * data_width] = w_state_p_terms;
                assign w_state_n_terms_stage[
                    (si * num_rows + ri) * physical_degree * data_width +:
                    physical_degree * data_width] = w_state_n_terms;
                assign w_coeff_p_terms_stage[
                    (si * num_rows + ri) * physical_degree * bit_width +:
                    physical_degree * bit_width] = w_coeff_p_terms;
                assign w_coeff_n_terms_stage[
                    (si * num_rows + ri) * physical_degree * bit_width +:
                    physical_degree * bit_width] = w_coeff_n_terms;

                conv_signed_row_update_delta_slice_pipe #(
                    .degree(physical_degree),
                    .bit_width(bit_width),
                    .data_width(data_width),
                    .bias_width(bias_width),
                    .bound_width(bound_width),
                    .acc_width(acc_width),
                    .product_width(product_width),
                    .product_shift(product_shift),
                    .round_pipeline(round_pipeline)
                ) row_update (
                    .i_clk(i_clk),
                    .i_rst(i_rst || i_clear),
                    .i_valid(w_stage_valid_in[si]),
                    .i_state_p_terms(w_state_p_terms),
                    .i_state_n_terms(w_state_n_terms),
                    .i_coeff_p_terms(w_coeff_p_terms),
                    .i_coeff_n_terms(w_coeff_n_terms),
                    .i_bias_p(i_bias_p_rows[ri * bias_width +: bias_width]),
                    .i_bias_n(i_bias_n_rows[ri * bias_width +: bias_width]),
                    .i_old_state_p(w_unused_old_p),
                    .i_old_state_n(w_unused_old_n),
                    .i_tail_bound({bound_width{1'b0}}),
                    .o_valid(w_row_valid),
                    .o_sum(w_unused_sum),
                    .o_sum_p(w_stage_state_p_rows[
                        (si * num_rows + ri) * data_width +: data_width]),
                    .o_sum_n(w_stage_state_n_rows[
                        (si * num_rows + ri) * data_width +: data_width]),
                    .o_abs_upper(w_unused_abs_upper)
                );

                assign w_row_valid_stage[si * num_rows + ri] = w_row_valid;
            end

            assign w_stage_valid_out[si] = w_row_valid_stage[si * num_rows];
        end
    endgenerate

    always @(posedge i_clk) begin
        if (i_rst || i_clear) begin
            o_stage_valid_count <= {num_stages * 32{1'b0}};
            o_stage_done <= {num_stages{1'b0}};
        end else begin
            for (si_seq = 0; si_seq < num_stages; si_seq = si_seq + 1) begin
                if (w_stage_valid_out[si_seq]) begin
                    o_stage_done[si_seq] <= 1'b1;
                    o_stage_valid_count[si_seq * 32 +: 32] <=
                        o_stage_valid_count[si_seq * 32 +: 32] + 1'b1;
                end
            end
        end
    end

endmodule
