`timescale 1ns / 1ps

module tb_iter_digit_serial_full_row_update_delta_slice;
    localparam integer DEGREE = 4;
    localparam integer BIT_WIDTH = 8;
    localparam integer DATA_WIDTH = BIT_WIDTH + 3;
    localparam integer BIAS_WIDTH = BIT_WIDTH + 2;
    localparam integer BOUND_WIDTH = BIT_WIDTH + 5;
    localparam integer ACC_WIDTH = 32;
    localparam integer DIGIT_IDX_WIDTH = $clog2(DATA_WIDTH);

    reg i_clk;
    reg i_rst;
    reg i_start;
    reg i_valid_digit;
    reg i_last_digit;
    reg [DIGIT_IDX_WIDTH - 1 : 0] i_digit_idx;
    reg [DEGREE - 1 : 0] i_state_digit_p_terms;
    reg [DEGREE - 1 : 0] i_state_digit_n_terms;
    reg [DEGREE * BIT_WIDTH - 1 : 0] i_coeff_p_terms;
    reg [DEGREE * BIT_WIDTH - 1 : 0] i_coeff_n_terms;
    reg [BIAS_WIDTH - 1 : 0] i_bias_p;
    reg [BIAS_WIDTH - 1 : 0] i_bias_n;
    reg [DATA_WIDTH - 1 : 0] i_old_state_p;
    reg [DATA_WIDTH - 1 : 0] i_old_state_n;
    reg [BOUND_WIDTH - 1 : 0] i_tail_bound;
    wire o_busy;
    wire o_valid;
    wire signed [ACC_WIDTH - 1 : 0] o_sum;
    wire [DATA_WIDTH - 1 : 0] o_sum_p;
    wire [DATA_WIDTH - 1 : 0] o_sum_n;
    wire [BOUND_WIDTH - 1 : 0] o_abs_upper;

    iter_digit_serial_full_row_update_delta_slice #(
        .degree(DEGREE),
        .bit_width(BIT_WIDTH),
        .data_width(DATA_WIDTH),
        .bias_width(BIAS_WIDTH),
        .bound_width(BOUND_WIDTH),
        .acc_width(ACC_WIDTH)
    ) dut (
        .i_clk(i_clk),
        .i_rst(i_rst),
        .i_start(i_start),
        .i_valid_digit(i_valid_digit),
        .i_last_digit(i_last_digit),
        .i_digit_idx(i_digit_idx),
        .i_state_digit_p_terms(i_state_digit_p_terms),
        .i_state_digit_n_terms(i_state_digit_n_terms),
        .i_coeff_p_terms(i_coeff_p_terms),
        .i_coeff_n_terms(i_coeff_n_terms),
        .i_bias_p(i_bias_p),
        .i_bias_n(i_bias_n),
        .i_old_state_p(i_old_state_p),
        .i_old_state_n(i_old_state_n),
        .i_tail_bound(i_tail_bound),
        .o_busy(o_busy),
        .o_valid(o_valid),
        .o_sum(o_sum),
        .o_sum_p(o_sum_p),
        .o_sum_n(o_sum_n),
        .o_abs_upper(o_abs_upper)
    );

    always #5 i_clk = ~i_clk;

    function automatic signed [ACC_WIDTH - 1 : 0] sext_state;
        input signed [DATA_WIDTH : 0] value;
        begin
            sext_state = {{(ACC_WIDTH - DATA_WIDTH - 1){value[DATA_WIDTH]}}, value};
        end
    endfunction

    task automatic rail_from_sum;
        input signed [ACC_WIDTH - 1 : 0] sum_value;
        output [DATA_WIDTH - 1 : 0] rail_p;
        output [DATA_WIDTH - 1 : 0] rail_n;
        reg [ACC_WIDTH - 1 : 0] abs_sum;
        reg [ACC_WIDTH - 1 : 0] state_max;
        begin
            abs_sum = sum_value[ACC_WIDTH - 1] ? (~sum_value + 1'b1) : sum_value;
            state_max = {{(ACC_WIDTH - DATA_WIDTH){1'b0}}, {DATA_WIDTH{1'b1}}};
            if (sum_value[ACC_WIDTH - 1]) begin
                rail_p = {DATA_WIDTH{1'b0}};
                rail_n = (abs_sum > state_max) ? {DATA_WIDTH{1'b1}} : abs_sum[DATA_WIDTH - 1 : 0];
            end else begin
                rail_p = (abs_sum > state_max) ? {DATA_WIDTH{1'b1}} : abs_sum[DATA_WIDTH - 1 : 0];
                rail_n = {DATA_WIDTH{1'b0}};
            end
        end
    endtask

    task automatic abs_upper_from_sum;
        input signed [ACC_WIDTH - 1 : 0] sum_value;
        input [DATA_WIDTH - 1 : 0] old_p;
        input [DATA_WIDTH - 1 : 0] old_n;
        input [BOUND_WIDTH - 1 : 0] tail_bound;
        output [BOUND_WIDTH - 1 : 0] abs_upper;
        reg signed [DATA_WIDTH : 0] old_state;
        reg signed [ACC_WIDTH - 1 : 0] delta;
        reg [ACC_WIDTH - 1 : 0] abs_delta;
        begin
            old_state = $signed({1'b0, old_p}) - $signed({1'b0, old_n});
            delta = sum_value - sext_state(old_state);
            abs_delta = delta[ACC_WIDTH - 1] ? (~delta + 1'b1) : delta;
            if (abs_delta + tail_bound >= (1 << BOUND_WIDTH)) begin
                abs_upper = {BOUND_WIDTH{1'b1}};
            end else begin
                abs_upper = abs_delta[BOUND_WIDTH - 1 : 0] + tail_bound;
            end
        end
    endtask

    task automatic run_case;
        input [DEGREE * DATA_WIDTH - 1 : 0] state_p_terms;
        input [DEGREE * DATA_WIDTH - 1 : 0] state_n_terms;
        input [DEGREE * BIT_WIDTH - 1 : 0] coeff_p_terms;
        input [DEGREE * BIT_WIDTH - 1 : 0] coeff_n_terms;
        input [BIAS_WIDTH - 1 : 0] bias_p;
        input [BIAS_WIDTH - 1 : 0] bias_n;
        input [DATA_WIDTH - 1 : 0] old_p;
        input [DATA_WIDTH - 1 : 0] old_n;
        input [BOUND_WIDTH - 1 : 0] tail_bound;
        integer ti;
        integer di;
        integer bit_sel;
        integer wait_count;
        reg signed [DATA_WIDTH : 0] state_term;
        reg signed [BIT_WIDTH : 0] coeff_term;
        reg signed [BIAS_WIDTH : 0] bias_term;
        reg signed [ACC_WIDTH - 1 : 0] expected_sum;
        reg [DATA_WIDTH - 1 : 0] expected_p;
        reg [DATA_WIDTH - 1 : 0] expected_n;
        reg [BOUND_WIDTH - 1 : 0] expected_abs_upper;
        begin
            bias_term = $signed({1'b0, bias_p}) - $signed({1'b0, bias_n});
            expected_sum = {{(ACC_WIDTH - BIAS_WIDTH - 1){bias_term[BIAS_WIDTH]}}, bias_term};
            for (ti = 0; ti < DEGREE; ti = ti + 1) begin
                state_term =
                    $signed({1'b0, state_p_terms[ti * DATA_WIDTH +: DATA_WIDTH]}) -
                    $signed({1'b0, state_n_terms[ti * DATA_WIDTH +: DATA_WIDTH]});
                coeff_term =
                    $signed({1'b0, coeff_p_terms[ti * BIT_WIDTH +: BIT_WIDTH]}) -
                    $signed({1'b0, coeff_n_terms[ti * BIT_WIDTH +: BIT_WIDTH]});
                expected_sum = expected_sum + (state_term * coeff_term);
            end
            rail_from_sum(expected_sum, expected_p, expected_n);
            abs_upper_from_sum(expected_sum, old_p, old_n, tail_bound, expected_abs_upper);

            i_coeff_p_terms = coeff_p_terms;
            i_coeff_n_terms = coeff_n_terms;
            i_bias_p = bias_p;
            i_bias_n = bias_n;
            i_old_state_p = old_p;
            i_old_state_n = old_n;
            i_tail_bound = tail_bound;

            for (di = 0; di < DATA_WIDTH; di = di + 1) begin
                bit_sel = DATA_WIDTH - 1 - di;
                for (ti = 0; ti < DEGREE; ti = ti + 1) begin
                    i_state_digit_p_terms[ti] = state_p_terms[ti * DATA_WIDTH + bit_sel];
                    i_state_digit_n_terms[ti] = state_n_terms[ti * DATA_WIDTH + bit_sel];
                end
                i_digit_idx = di[DIGIT_IDX_WIDTH - 1 : 0];
                i_valid_digit = 1'b1;
                i_last_digit = (di == DATA_WIDTH - 1);
                i_start = (di == 0);
                @(negedge i_clk);
            end

            i_start = 1'b0;
            i_valid_digit = 1'b0;
            i_last_digit = 1'b0;
            i_state_digit_p_terms = {DEGREE{1'b0}};
            i_state_digit_n_terms = {DEGREE{1'b0}};
            wait_count = 0;
            while (!o_valid && wait_count < 4) begin
                @(negedge i_clk);
                wait_count = wait_count + 1;
            end
            #1;
            if (!o_valid ||
                o_sum !== expected_sum ||
                o_sum_p !== expected_p ||
                o_sum_n !== expected_n ||
                o_abs_upper !== expected_abs_upper) begin
                $display("ERROR full-digit row slice got valid=%0d sum=%0d p=%h n=%h abs=%0d expected sum=%0d p=%h n=%h abs=%0d",
                    o_valid,
                    o_sum,
                    o_sum_p,
                    o_sum_n,
                    o_abs_upper,
                    expected_sum,
                    expected_p,
                    expected_n,
                    expected_abs_upper);
                $fatal;
            end
            @(negedge i_clk);
        end
    endtask

    initial begin
        i_clk = 1'b0;
        i_rst = 1'b1;
        i_start = 1'b0;
        i_valid_digit = 1'b0;
        i_last_digit = 1'b0;
        i_digit_idx = {DIGIT_IDX_WIDTH{1'b0}};
        i_state_digit_p_terms = {DEGREE{1'b0}};
        i_state_digit_n_terms = {DEGREE{1'b0}};
        i_coeff_p_terms = {DEGREE * BIT_WIDTH{1'b0}};
        i_coeff_n_terms = {DEGREE * BIT_WIDTH{1'b0}};
        i_bias_p = {BIAS_WIDTH{1'b0}};
        i_bias_n = {BIAS_WIDTH{1'b0}};
        i_old_state_p = {DATA_WIDTH{1'b0}};
        i_old_state_n = {DATA_WIDTH{1'b0}};
        i_tail_bound = {{(BOUND_WIDTH - 1){1'b0}}, 1'b1};

        repeat (2) @(negedge i_clk);
        i_rst = 1'b0;

        run_case(
            {11'd3, 11'd0, 11'd7, 11'd12},
            {11'd0, 11'd4, 11'd0, 11'd1},
            {8'd2, 8'd0, 8'd7, 8'd9},
            {8'd0, 8'd3, 8'd0, 8'd0},
            10'd5,
            10'd1,
            11'd4,
            11'd0,
            13'd1
        );

        run_case(
            {11'd0, 11'd5, 11'd2, 11'd1},
            {11'd8, 11'd0, 11'd7, 11'd0},
            {8'd0, 8'd4, 8'd0, 8'd6},
            {8'd5, 8'd0, 8'd2, 8'd0},
            10'd0,
            10'd9,
            11'd0,
            11'd6,
            13'd3
        );

        run_case(
            {11'd300, 11'd128, 11'd17, 11'd0},
            {11'd0, 11'd1, 11'd0, 11'd64},
            {8'd12, 8'd3, 8'd1, 8'd0},
            {8'd0, 8'd0, 8'd4, 8'd2},
            10'd2,
            10'd0,
            11'd10,
            11'd0,
            13'd5
        );

        $display("PASS tb_iter_digit_serial_full_row_update_delta_slice");
        $finish;
    end
endmodule
