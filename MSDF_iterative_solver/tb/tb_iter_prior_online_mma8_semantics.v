`timescale 1ns / 1ps

// Characterization-only TB for the prior MSDF_MUL_ADD_8 word wrapper.
// It prints simple input/output points so the P2 baseline can align the
// original operator scaling before strict same-shell numerical checks are
// enabled.

module tb_iter_prior_online_mma8_semantics;
    localparam integer DEGREE = 4;
`ifdef PRIOR_SEM_BIT_WIDTH_VALUE
    localparam integer BIT_WIDTH = `PRIOR_SEM_BIT_WIDTH_VALUE;
`else
    localparam integer BIT_WIDTH = 11;
`endif
    localparam integer DATA_WIDTH = BIT_WIDTH;

    reg i_clk;
    reg i_rst;
    reg i_start;
    reg [DEGREE * BIT_WIDTH - 1 : 0] i_state_p_terms;
    reg [DEGREE * BIT_WIDTH - 1 : 0] i_state_n_terms;
    reg [DEGREE * BIT_WIDTH - 1 : 0] i_coeff_p_terms;
    reg [DEGREE * BIT_WIDTH - 1 : 0] i_coeff_n_terms;
    reg [BIT_WIDTH - 1 : 0] i_bias_p;
    reg [BIT_WIDTH - 1 : 0] i_bias_n;

    wire o_busy;
    wire o_valid;
    wire [DATA_WIDTH - 1 : 0] o_sum_p;
    wire [DATA_WIDTH - 1 : 0] o_sum_n;
    wire [$clog2(DATA_WIDTH + 1) - 1 : 0] o_captured_digits;

    integer wait_cycles;
    integer case_id;

    iter_prior_online_mma8_word_assembler #(
        .degree(DEGREE),
        .bit_width(BIT_WIDTH),
        .data_width(DATA_WIDTH),
`ifdef PRIOR_SEM_VALID_LATENCY
        .valid_latency(`PRIOR_SEM_VALID_LATENCY),
`else
        .valid_latency(4),
`endif
`ifdef PRIOR_SEM_FRACTIONAL_CAPTURE
        .capture_unit(0)
`else
        .capture_unit(1)
`endif
    ) dut (
        .i_clk(i_clk),
        .i_rst(i_rst),
        .i_start(i_start),
        .i_state_p_terms(i_state_p_terms),
        .i_state_n_terms(i_state_n_terms),
        .i_coeff_p_terms(i_coeff_p_terms),
        .i_coeff_n_terms(i_coeff_n_terms),
        .i_bias_p(i_bias_p),
        .i_bias_n(i_bias_n),
        .o_busy(o_busy),
        .o_valid(o_valid),
        .o_sum_p(o_sum_p),
        .o_sum_n(o_sum_n),
        .o_captured_digits(o_captured_digits)
    );

    always #5 i_clk = ~i_clk;

`ifdef PRIOR_SEM_TRACE
    always @(posedge i_clk) begin
        if (!i_rst && (dut.w_prior_int || dut.w_prior_unit || dut.w_prior_frac ||
            dut.w_capture_sample)) begin
            $display("TRACE feed=%0d cap=%0d int=%0d unit=%0d frac=%0d zp=%0d zn=%0d sample=%0d",
                dut.r_feed_idx,
                dut.r_capture_idx,
                dut.w_prior_int,
                dut.w_prior_unit,
                dut.w_prior_frac,
                dut.w_prior_z_p,
                dut.w_prior_z_n,
                dut.w_capture_sample);
        end
    end
`endif

    task run_case;
        input [31:0] label;
        input [BIT_WIDTH - 1 : 0] s0;
        input [BIT_WIDTH - 1 : 0] c0;
        input [BIT_WIDTH - 1 : 0] bias;
        begin
            i_state_p_terms = {DEGREE * BIT_WIDTH{1'b0}};
            i_state_n_terms = {DEGREE * BIT_WIDTH{1'b0}};
            i_coeff_p_terms = {DEGREE * BIT_WIDTH{1'b0}};
            i_coeff_n_terms = {DEGREE * BIT_WIDTH{1'b0}};
            i_bias_p = bias;
            i_bias_n = {BIT_WIDTH{1'b0}};
            i_state_p_terms[BIT_WIDTH - 1 : 0] = s0;
            i_coeff_p_terms[BIT_WIDTH - 1 : 0] = c0;

            @(negedge i_clk);
            i_start <= 1'b1;
            @(negedge i_clk);
            i_start <= 1'b0;

            wait_cycles = 0;
            while (!o_valid && wait_cycles < 160) begin
                @(posedge i_clk);
                wait_cycles = wait_cycles + 1;
            end
            if (!o_valid) begin
                $display("ERROR prior semantics timeout label=%0d captured=%0d busy=%0d",
                    label, o_captured_digits, o_busy);
                $fatal;
            end
            $display("SEM label=%0d state=%0d coeff=%0d bias=%0d out_p=%0d out_n=%0d out_signed=%0d cycles=%0d captured=%0d",
                label,
                s0,
                c0,
                bias,
                o_sum_p,
                o_sum_n,
                $signed({1'b0, o_sum_p}) - $signed({1'b0, o_sum_n}),
                wait_cycles,
                o_captured_digits);
            repeat (4) @(posedge i_clk);
        end
    endtask

    initial begin
        i_clk = 1'b0;
        i_rst = 1'b1;
        i_start = 1'b0;
        i_state_p_terms = {DEGREE * BIT_WIDTH{1'b0}};
        i_state_n_terms = {DEGREE * BIT_WIDTH{1'b0}};
        i_coeff_p_terms = {DEGREE * BIT_WIDTH{1'b0}};
        i_coeff_n_terms = {DEGREE * BIT_WIDTH{1'b0}};
        i_bias_p = {BIT_WIDTH{1'b0}};
        i_bias_n = {BIT_WIDTH{1'b0}};

        repeat (5) @(posedge i_clk);
        i_rst <= 1'b0;
        repeat (2) @(posedge i_clk);

        run_case(0, 11'd0, 11'd0, 11'd1);
        run_case(1, 11'd1, 11'd1, 11'd0);
        run_case(2, 11'd1, 11'd4, 11'd0);
        run_case(3, 11'd4, 11'd4, 11'd0);
        run_case(4, 11'd8, 11'd4, 11'd1);
        run_case(5, 11'd1024, 11'd1024, 11'd0);
        run_case(6, 11'd1024, 11'd512, 11'd0);
        run_case(7, 11'd512, 11'd512, 11'd0);
        run_case(8, 11'd2047, 11'd2047, 11'd0);
        if (BIT_WIDTH >= 14) begin
            run_case(9, 14'd0, 14'd0, 14'd38);
            run_case(10, 14'd4096, 14'd1741, 14'd0);
            run_case(11, 14'd38, 14'd1741, 14'd38);
        end

        $display("PASS tb_iter_prior_online_mma8_semantics");
        $finish;
    end
endmodule
