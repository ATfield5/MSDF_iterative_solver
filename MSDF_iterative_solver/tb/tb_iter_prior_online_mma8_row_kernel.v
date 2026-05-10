`timescale 1ns / 1ps

module tb_iter_prior_online_mma8_row_kernel;
    localparam integer DEGREE = 4;
    localparam integer BIT_WIDTH = 8;
    localparam integer DIGIT_IDX_WIDTH = 3;

    reg i_clk;
    reg i_rst;
    reg i_valid_digit;
    reg [DIGIT_IDX_WIDTH - 1 : 0] i_digit_idx;
    reg [DEGREE - 1 : 0] i_state_digit_p_terms;
    reg [DEGREE - 1 : 0] i_state_digit_n_terms;
    reg [DEGREE * BIT_WIDTH - 1 : 0] i_coeff_p_terms;
    reg [DEGREE * BIT_WIDTH - 1 : 0] i_coeff_n_terms;
    reg i_bias_digit_p;
    reg i_bias_digit_n;

    wire o_z_p;
    wire o_z_n;
    wire o_int;
    wire o_unit;
    wire o_frac;

    integer idx;
    integer out_count;
    integer unit_count;
    integer frac_count;
    reg [63 : 0] z_p_trace;
    reg [63 : 0] z_n_trace;

    iter_prior_online_mma8_row_kernel #(
        .degree(DEGREE),
        .bit_width(BIT_WIDTH)
    ) dut (
        .i_clk(i_clk),
        .i_rst(i_rst),
        .i_valid_digit(i_valid_digit),
        .i_digit_idx(i_digit_idx),
        .i_state_digit_p_terms(i_state_digit_p_terms),
        .i_state_digit_n_terms(i_state_digit_n_terms),
        .i_coeff_p_terms(i_coeff_p_terms),
        .i_coeff_n_terms(i_coeff_n_terms),
        .i_bias_digit_p(i_bias_digit_p),
        .i_bias_digit_n(i_bias_digit_n),
        .o_z_p(o_z_p),
        .o_z_n(o_z_n),
        .o_int(o_int),
        .o_unit(o_unit),
        .o_frac(o_frac)
    );

    always #5 i_clk = ~i_clk;

    task drive_digit;
        input integer digit_idx;
        begin
            @(negedge i_clk);
            i_valid_digit <= 1'b1;
            i_digit_idx <= digit_idx[DIGIT_IDX_WIDTH - 1 : 0];
            // Four positive source streams.  Coefficients are small positive
            // constants, so this smoke checks adapter wiring without requiring
            // a full PageRank assembler.
            i_state_digit_p_terms <= 4'b1111;
            i_state_digit_n_terms <= 4'b0000;
            i_bias_digit_p <= (digit_idx == 7);
            i_bias_digit_n <= 1'b0;
        end
    endtask

    always @(posedge i_clk) begin
        if (i_rst) begin
            out_count <= 0;
            unit_count <= 0;
            frac_count <= 0;
            z_p_trace <= 64'd0;
            z_n_trace <= 64'd0;
        end else if (o_int || o_unit || o_frac) begin
            z_p_trace[out_count] <= o_z_p;
            z_n_trace[out_count] <= o_z_n;
            out_count <= out_count + 1;
            unit_count <= unit_count + o_unit;
            frac_count <= frac_count + o_frac;
        end
    end

    initial begin
        i_clk = 1'b0;
        i_rst = 1'b1;
        i_valid_digit = 1'b0;
        i_digit_idx = 0;
        i_state_digit_p_terms = 0;
        i_state_digit_n_terms = 0;
        i_coeff_p_terms = {8'h04, 8'h08, 8'h10, 8'h20};
        i_coeff_n_terms = 0;
        i_bias_digit_p = 1'b0;
        i_bias_digit_n = 1'b0;

        repeat (4) @(posedge i_clk);
        i_rst <= 1'b0;

        for (idx = 0; idx < BIT_WIDTH; idx = idx + 1) begin
            drive_digit(idx);
        end
        @(negedge i_clk);
        i_valid_digit <= 1'b0;
        i_state_digit_p_terms <= 0;
        i_bias_digit_p <= 1'b0;

        repeat (80) @(posedge i_clk);
        if (out_count == 0 || unit_count == 0 || frac_count == 0) begin
            $display("ERROR prior adapter output out=%0d unit=%0d frac=%0d",
                out_count, unit_count, frac_count);
            $fatal;
        end

        $display("COUNTERS prior_mma8_row_kernel out=%0d unit=%0d frac=%0d z_p_trace=%h z_n_trace=%h",
            out_count, unit_count, frac_count, z_p_trace, z_n_trace);
        $display("PASS tb_iter_prior_online_mma8_row_kernel");
        $finish;
    end
endmodule
