`timescale 1ns / 1ps

module tb_iter_fixed_degree_row_scheduler;
    localparam integer NUM_ROWS = 4;
    localparam integer DEGREE = 4;
    localparam integer BIT_WIDTH = 8;
    localparam integer BIAS_WIDTH = BIT_WIDTH + 2;
    localparam integer ROW_IDX_WIDTH = 2;

    reg [NUM_ROWS * DEGREE - 1 : 0] i_term_valid_mask;
    reg [NUM_ROWS * DEGREE * ROW_IDX_WIDTH - 1 : 0] i_src_row_idx;
    reg [NUM_ROWS * DEGREE * BIT_WIDTH - 1 : 0] i_coeff_p_terms;
    reg [NUM_ROWS * DEGREE * BIT_WIDTH - 1 : 0] i_coeff_n_terms;
    reg [NUM_ROWS * BIAS_WIDTH - 1 : 0] i_bias_vec_p_rows;
    reg [NUM_ROWS * BIAS_WIDTH - 1 : 0] i_bias_vec_n_rows;

    wire [NUM_ROWS - 1 : 0] o_row_active_mask;
    wire [NUM_ROWS * DEGREE * ROW_IDX_WIDTH - 1 : 0] o_src_row_idx;
    wire [NUM_ROWS * BIT_WIDTH - 1 : 0] o_coeff0_vec_p_rows, o_coeff0_vec_n_rows;
    wire [NUM_ROWS * BIT_WIDTH - 1 : 0] o_coeff1_vec_p_rows, o_coeff1_vec_n_rows;
    wire [NUM_ROWS * BIT_WIDTH - 1 : 0] o_coeff2_vec_p_rows, o_coeff2_vec_n_rows;
    wire [NUM_ROWS * BIT_WIDTH - 1 : 0] o_coeff3_vec_p_rows, o_coeff3_vec_n_rows;
    wire [NUM_ROWS * BIAS_WIDTH - 1 : 0] o_bias_vec_p_rows, o_bias_vec_n_rows;

    iter_fixed_degree_row_scheduler #(
        .num_rows(NUM_ROWS),
        .degree(DEGREE),
        .bit_width(BIT_WIDTH),
        .bias_width(BIAS_WIDTH),
        .row_idx_width(ROW_IDX_WIDTH)
    ) dut (
        .i_term_valid_mask(i_term_valid_mask),
        .i_src_row_idx(i_src_row_idx),
        .i_coeff_p_terms(i_coeff_p_terms),
        .i_coeff_n_terms(i_coeff_n_terms),
        .i_bias_vec_p_rows(i_bias_vec_p_rows),
        .i_bias_vec_n_rows(i_bias_vec_n_rows),
        .o_row_active_mask(o_row_active_mask),
        .o_src_row_idx(o_src_row_idx),
        .o_coeff0_vec_p_rows(o_coeff0_vec_p_rows),
        .o_coeff0_vec_n_rows(o_coeff0_vec_n_rows),
        .o_coeff1_vec_p_rows(o_coeff1_vec_p_rows),
        .o_coeff1_vec_n_rows(o_coeff1_vec_n_rows),
        .o_coeff2_vec_p_rows(o_coeff2_vec_p_rows),
        .o_coeff2_vec_n_rows(o_coeff2_vec_n_rows),
        .o_coeff3_vec_p_rows(o_coeff3_vec_p_rows),
        .o_coeff3_vec_n_rows(o_coeff3_vec_n_rows),
        .o_bias_vec_p_rows(o_bias_vec_p_rows),
        .o_bias_vec_n_rows(o_bias_vec_n_rows)
    );

    initial begin
        // row0 valid terms: 0,1
        // row1 valid terms: 2
        // row2 valid terms: none
        // row3 valid terms: 0,3
        i_term_valid_mask = 16'b1001_0000_0100_0011;
        i_src_row_idx = {
            2'd3, 2'd2, 2'd1, 2'd0,
            2'd0, 2'd0, 2'd3, 2'd2,
            2'd0, 2'd0, 2'd0, 2'd0,
            2'd1, 2'd2, 2'd1, 2'd0
        };
        i_coeff_p_terms = {
            8'd44, 8'd43, 8'd42, 8'd41,
            8'd34, 8'd33, 8'd32, 8'd31,
            8'd24, 8'd23, 8'd22, 8'd21,
            8'd14, 8'd13, 8'd12, 8'd11
        };
        i_coeff_n_terms = 0;
        i_bias_vec_p_rows = {10'd4, 10'd3, 10'd2, 10'd1};
        i_bias_vec_n_rows = 0;

        #1;
        if (o_row_active_mask !== 4'b1011 ||
            o_coeff0_vec_p_rows !== {8'd41, 8'd0, 8'd0, 8'd11} ||
            o_coeff1_vec_p_rows !== {8'd0, 8'd0, 8'd0, 8'd12} ||
            o_coeff2_vec_p_rows !== {8'd0, 8'd0, 8'd23, 8'd0} ||
            o_coeff3_vec_p_rows !== {8'd44, 8'd0, 8'd0, 8'd0} ||
            o_bias_vec_p_rows !== i_bias_vec_p_rows) begin
            $display("ERROR tb_iter_fixed_degree_row_scheduler output mismatch");
            $fatal;
        end

        // Invalid terms must force src_row_idx to zero.
        if (o_src_row_idx[5:4] !== 2'd0 || o_src_row_idx[11:10] !== 2'd0) begin
            $display("ERROR tb_iter_fixed_degree_row_scheduler masked src idx mismatch");
            $fatal;
        end

        $display("PASS tb_iter_fixed_degree_row_scheduler");
        $finish;
    end
endmodule
