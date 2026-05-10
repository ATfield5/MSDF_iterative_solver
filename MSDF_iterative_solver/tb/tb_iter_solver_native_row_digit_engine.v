`timescale 1ns / 1ps

module tb_iter_solver_native_row_digit_engine;
    localparam integer BIT_WIDTH = 8;
    localparam integer DEGREE = 4;
    localparam integer DATA_WIDTH = BIT_WIDTH + 3;
    localparam integer BIAS_WIDTH = BIT_WIDTH + 2;
    localparam integer DIGIT_IDX_WIDTH = $clog2(DATA_WIDTH);

    reg i_clk;
    reg i_rst;
    reg i_start;
    reg i_valid_digit;
    reg [DIGIT_IDX_WIDTH-1:0] i_digit_idx;
    reg [DEGREE-1:0] i_state_digit_p_terms;
    reg [DEGREE-1:0] i_state_digit_n_terms;
    reg [DEGREE*BIT_WIDTH-1:0] i_coeff_p_terms;
    reg [DEGREE*BIT_WIDTH-1:0] i_coeff_n_terms;
    reg [BIAS_WIDTH-1:0] i_bias_p;
    reg [BIAS_WIDTH-1:0] i_bias_n;
    wire o_valid;
    wire o_x_new_digit_p;
    wire o_x_new_digit_n;
    wire [DATA_WIDTH-1:0] o_affine_p;
    wire [DATA_WIDTH-1:0] o_affine_n;

    integer di;
    integer cycle_count;
    integer valid_count;

    iter_solver_native_row_digit_engine #(
        .bit_width(BIT_WIDTH),
        .degree(DEGREE),
        .data_width(DATA_WIDTH),
        .bias_width(BIAS_WIDTH),
        .digit_idx_width(DIGIT_IDX_WIDTH)
    ) dut (
        .i_clk(i_clk),
        .i_rst(i_rst),
        .i_start(i_start),
        .i_valid_digit(i_valid_digit),
        .i_digit_idx(i_digit_idx),
        .i_state_digit_p_terms(i_state_digit_p_terms),
        .i_state_digit_n_terms(i_state_digit_n_terms),
        .i_coeff_p_terms(i_coeff_p_terms),
        .i_coeff_n_terms(i_coeff_n_terms),
        .i_bias_p(i_bias_p),
        .i_bias_n(i_bias_n),
        .o_valid(o_valid),
        .o_x_new_digit_p(o_x_new_digit_p),
        .o_x_new_digit_n(o_x_new_digit_n),
        .o_affine_p(o_affine_p),
        .o_affine_n(o_affine_n),
        .o_residual_p(),
        .o_residual_n()
    );

    always #5 i_clk = ~i_clk;

    initial begin
        i_clk = 1'b0;
        i_rst = 1'b1;
        i_start = 1'b0;
        i_valid_digit = 1'b0;
        i_digit_idx = {DIGIT_IDX_WIDTH{1'b0}};
        i_state_digit_p_terms = {DEGREE{1'b0}};
        i_state_digit_n_terms = {DEGREE{1'b0}};
        i_coeff_p_terms = {DEGREE*BIT_WIDTH{1'b0}};
        i_coeff_n_terms = {DEGREE*BIT_WIDTH{1'b0}};
        i_bias_p = {BIAS_WIDTH{1'b0}};
        i_bias_n = {BIAS_WIDTH{1'b0}};
        valid_count = 0;

        repeat (2) @(negedge i_clk);
        i_rst = 1'b0;

        for (di = 0; di < DATA_WIDTH; di = di + 1) begin
            i_start = (di == 0);
            i_valid_digit = 1'b1;
            i_digit_idx = di[DIGIT_IDX_WIDTH-1:0];
            @(negedge i_clk);
            if (o_valid) begin
                valid_count = valid_count + 1;
                if (o_x_new_digit_p || o_x_new_digit_n) begin
                    $display("ERROR solver-native zero row emitted non-zero digit p=%0d n=%0d",
                        o_x_new_digit_p, o_x_new_digit_n);
                    $fatal;
                end
            end
        end

        i_start = 1'b0;
        i_valid_digit = 1'b0;
        i_digit_idx = {DIGIT_IDX_WIDTH{1'b0}};

        for (cycle_count = 0; cycle_count < 6; cycle_count = cycle_count + 1) begin
            @(negedge i_clk);
            if (o_valid) begin
                valid_count = valid_count + 1;
                if (o_x_new_digit_p || o_x_new_digit_n) begin
                    $display("ERROR solver-native zero row emitted non-zero tail digit p=%0d n=%0d",
                        o_x_new_digit_p, o_x_new_digit_n);
                    $fatal;
                end
            end
        end

        if (valid_count !== DATA_WIDTH) begin
            $display("ERROR solver-native zero row valid_count=%0d expected=%0d", valid_count, DATA_WIDTH);
            $fatal;
        end

        $display("PASS tb_iter_solver_native_row_digit_engine");
        $finish;
    end
endmodule
