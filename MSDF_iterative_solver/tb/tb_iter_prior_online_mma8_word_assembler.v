`timescale 1ns / 1ps

module tb_iter_prior_online_mma8_word_assembler;
    localparam integer DEGREE = 4;
    localparam integer BIT_WIDTH = 8;
    localparam integer DATA_WIDTH = 11;

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

    iter_prior_online_mma8_word_assembler #(
        .degree(DEGREE),
        .bit_width(BIT_WIDTH),
        .data_width(DATA_WIDTH)
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

    initial begin
        i_clk = 1'b0;
        i_rst = 1'b1;
        i_start = 1'b0;
        i_state_p_terms = {8'h20, 8'h10, 8'h08, 8'h04};
        i_state_n_terms = 0;
        i_coeff_p_terms = {8'h04, 8'h08, 8'h10, 8'h20};
        i_coeff_n_terms = 0;
        i_bias_p = 8'h01;
        i_bias_n = 8'h00;

        repeat (4) @(posedge i_clk);
        i_rst <= 1'b0;
        @(negedge i_clk);
        i_start <= 1'b1;
        @(negedge i_clk);
        i_start <= 1'b0;

        wait_cycles = 0;
        while (!o_valid && wait_cycles < 128) begin
            @(posedge i_clk);
            wait_cycles = wait_cycles + 1;
        end
        if (!o_valid) begin
            $display("ERROR prior word assembler timeout captured=%0d busy=%0d",
                o_captured_digits, o_busy);
            $fatal;
        end
        if (o_captured_digits != DATA_WIDTH) begin
            $display("ERROR prior word assembler captured=%0d expected=%0d",
                o_captured_digits, DATA_WIDTH);
            $fatal;
        end
        if (o_sum_p === {DATA_WIDTH{1'b0}} && o_sum_n === {DATA_WIDTH{1'b0}}) begin
            $display("ERROR prior word assembler zero output");
            $fatal;
        end

        $display("COUNTERS prior_mma8_word_assembler cycles=%0d captured=%0d sum_p=%h sum_n=%h",
            wait_cycles, o_captured_digits, o_sum_p, o_sum_n);
        $display("PASS tb_iter_prior_online_mma8_word_assembler");
        $finish;
    end
endmodule
