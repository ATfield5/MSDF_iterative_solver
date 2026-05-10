`timescale 1ns / 1ps

// Row-level equivalence checkpoint: compares the assembled solver-native
// signed-digit output stream against the full-digit bridge full-word result for
// non-zero rows.  The solver-native path has an online drain interval; the
// assembled trace must still match the full-word bridge value exactly.

module tb_iter_solver_native_row_digit_characterization;
    localparam integer DEGREE = 4;
    localparam integer BIT_WIDTH = 8;
    localparam integer DATA_WIDTH = BIT_WIDTH + 3;
    localparam integer BIAS_WIDTH = BIT_WIDTH + 2;
    localparam integer BOUND_WIDTH = BIT_WIDTH + 5;
    localparam integer ACC_WIDTH = 32;
    localparam integer DIGIT_IDX_WIDTH = $clog2(DATA_WIDTH);
    localparam integer EXTRA_DRAIN_DIGITS = 8;
    localparam integer TRACE_WIDTH = DATA_WIDTH + EXTRA_DRAIN_DIGITS;

    reg i_clk;
    reg i_rst;
    reg i_start;
    reg i_valid_digit;
    reg i_last_digit;
    reg [DIGIT_IDX_WIDTH-1:0] i_digit_idx;
    reg [DEGREE-1:0] i_state_digit_p_terms;
    reg [DEGREE-1:0] i_state_digit_n_terms;
    reg [DEGREE*BIT_WIDTH-1:0] i_coeff_p_terms;
    reg [DEGREE*BIT_WIDTH-1:0] i_coeff_n_terms;
    reg [BIAS_WIDTH-1:0] i_bias_p;
    reg [BIAS_WIDTH-1:0] i_bias_n;
    reg [DATA_WIDTH-1:0] i_old_state_p;
    reg [DATA_WIDTH-1:0] i_old_state_n;
    reg [BOUND_WIDTH-1:0] i_tail_bound;

    wire full_valid;
    wire signed [ACC_WIDTH-1:0] full_sum;
    wire [DATA_WIDTH-1:0] full_sum_p;
    wire [DATA_WIDTH-1:0] full_sum_n;

    wire native_valid;
    wire native_z_p;
    wire native_z_n;

    integer di;
    integer bit_sel;
    integer ti;
    integer wait_count;
    integer valid_count;
    integer mismatch_count;
    reg full_seen;
    reg signed [ACC_WIDTH-1:0] full_sum_seen;
    reg [DATA_WIDTH-1:0] full_sum_p_seen;
    reg [DATA_WIDTH-1:0] full_sum_n_seen;
    reg signed [ACC_WIDTH-1:0] native_sum;
    reg [TRACE_WIDTH-1:0] native_p_word;
    reg [TRACE_WIDTH-1:0] native_n_word;

    iter_digit_serial_full_row_update_delta_slice #(
        .degree(DEGREE),
        .bit_width(BIT_WIDTH),
        .data_width(DATA_WIDTH),
        .bias_width(BIAS_WIDTH),
        .bound_width(BOUND_WIDTH),
        .acc_width(ACC_WIDTH)
    ) full_ref (
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
        .o_busy(),
        .o_valid(full_valid),
        .o_sum(full_sum),
        .o_sum_p(full_sum_p),
        .o_sum_n(full_sum_n),
        .o_abs_upper(),
        .o_prefix_valid(),
        .o_prefix_abs_upper()
    );

    iter_solver_native_row_digit_engine #(
        .bit_width(BIT_WIDTH),
        .degree(DEGREE),
        .data_width(DATA_WIDTH),
        .bias_width(BIAS_WIDTH),
        .digit_idx_width(DIGIT_IDX_WIDTH)
    ) native_dut (
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
        .o_valid(native_valid),
        .o_x_new_digit_p(native_z_p),
        .o_x_new_digit_n(native_z_n),
        .o_affine_p(),
        .o_affine_n(),
        .o_residual_p(),
        .o_residual_n()
    );

    always #5 i_clk = ~i_clk;

    task automatic run_case;
        input integer case_id;
        input [DEGREE*DATA_WIDTH-1:0] state_p_terms;
        input [DEGREE*DATA_WIDTH-1:0] state_n_terms;
        input [DEGREE*BIT_WIDTH-1:0] coeff_p_terms;
        input [DEGREE*BIT_WIDTH-1:0] coeff_n_terms;
        input [BIAS_WIDTH-1:0] bias_p;
        input [BIAS_WIDTH-1:0] bias_n;
        begin
            i_coeff_p_terms = coeff_p_terms;
            i_coeff_n_terms = coeff_n_terms;
            i_bias_p = bias_p;
            i_bias_n = bias_n;
            i_old_state_p = {DATA_WIDTH{1'b0}};
            i_old_state_n = {DATA_WIDTH{1'b0}};
            i_tail_bound = {BOUND_WIDTH{1'b0}};
            native_sum = {ACC_WIDTH{1'b0}};
            native_p_word = {TRACE_WIDTH{1'b0}};
            native_n_word = {TRACE_WIDTH{1'b0}};
            valid_count = 0;
            full_seen = 1'b0;
            full_sum_seen = {ACC_WIDTH{1'b0}};
            full_sum_p_seen = {DATA_WIDTH{1'b0}};
            full_sum_n_seen = {DATA_WIDTH{1'b0}};

            for (di = 0; di < DATA_WIDTH; di = di + 1) begin
                bit_sel = DATA_WIDTH - 1 - di;
                for (ti = 0; ti < DEGREE; ti = ti + 1) begin
                    i_state_digit_p_terms[ti] = state_p_terms[ti*DATA_WIDTH + bit_sel];
                    i_state_digit_n_terms[ti] = state_n_terms[ti*DATA_WIDTH + bit_sel];
                end
                i_start = (di == 0);
                i_valid_digit = 1'b1;
                i_last_digit = (di == DATA_WIDTH - 1);
                i_digit_idx = di[DIGIT_IDX_WIDTH-1:0];
                @(negedge i_clk);
                if (full_valid && !full_seen) begin
                    full_seen = 1'b1;
                    full_sum_seen = full_sum;
                    full_sum_p_seen = full_sum_p;
                    full_sum_n_seen = full_sum_n;
                end
                if (native_valid && valid_count < TRACE_WIDTH) begin
                    native_sum = (native_sum <<< 1);
                    if (native_z_p && !native_z_n) begin
                        native_sum = native_sum + 1;
                        native_p_word[TRACE_WIDTH - valid_count - 1] = 1'b1;
                    end else if (!native_z_p && native_z_n) begin
                        native_sum = native_sum - 1;
                        native_n_word[TRACE_WIDTH - valid_count - 1] = 1'b1;
                    end
                    valid_count = valid_count + 1;
                end
            end

            i_start = 1'b0;
            i_valid_digit = 1'b1;
            i_last_digit = 1'b0;
            i_state_digit_p_terms = {DEGREE{1'b0}};
            i_state_digit_n_terms = {DEGREE{1'b0}};
            i_bias_p = {BIAS_WIDTH{1'b0}};
            i_bias_n = {BIAS_WIDTH{1'b0}};

            wait_count = 0;
            while ((!full_seen || valid_count < TRACE_WIDTH) && wait_count < 24) begin
                i_digit_idx = DATA_WIDTH - 1;
                @(negedge i_clk);
                if (full_valid && !full_seen) begin
                    full_seen = 1'b1;
                    full_sum_seen = full_sum;
                    full_sum_p_seen = full_sum_p;
                    full_sum_n_seen = full_sum_n;
                end
                if (native_valid && valid_count < TRACE_WIDTH) begin
                    native_sum = (native_sum <<< 1);
                    if (native_z_p && !native_z_n) begin
                        native_sum = native_sum + 1;
                        native_p_word[TRACE_WIDTH - valid_count - 1] = 1'b1;
                    end else if (!native_z_p && native_z_n) begin
                        native_sum = native_sum - 1;
                        native_n_word[TRACE_WIDTH - valid_count - 1] = 1'b1;
                    end
                    valid_count = valid_count + 1;
                end
                wait_count = wait_count + 1;
            end
            i_valid_digit = 1'b0;

            #1;
            if (!full_seen || valid_count !== TRACE_WIDTH) begin
                $display("CHAR_ERROR case=%0d full_valid=%0d native_valid_count=%0d",
                    case_id, full_seen, valid_count);
                $fatal;
            end

            if (native_sum !== full_sum_seen) begin
                mismatch_count = mismatch_count + 1;
            end
            $display("CHECK solver_native_row case=%0d full_sum=%0d native_trace_sum=%0d full_p=%h full_n=%h native_p=%h native_n=%h",
                case_id,
                full_sum_seen,
                native_sum,
                full_sum_p_seen,
                full_sum_n_seen,
                native_p_word,
                native_n_word);

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
        i_coeff_p_terms = {DEGREE*BIT_WIDTH{1'b0}};
        i_coeff_n_terms = {DEGREE*BIT_WIDTH{1'b0}};
        i_bias_p = {BIAS_WIDTH{1'b0}};
        i_bias_n = {BIAS_WIDTH{1'b0}};
        i_old_state_p = {DATA_WIDTH{1'b0}};
        i_old_state_n = {DATA_WIDTH{1'b0}};
        i_tail_bound = {BOUND_WIDTH{1'b0}};
        mismatch_count = 0;

        repeat (2) @(negedge i_clk);
        i_rst = 1'b0;

        run_case(
            0,
            {11'd3, 11'd0, 11'd7, 11'd12},
            {11'd0, 11'd4, 11'd0, 11'd1},
            {8'd2, 8'd0, 8'd7, 8'd9},
            {8'd0, 8'd3, 8'd0, 8'd0},
            10'd5,
            10'd1
        );

        run_case(
            1,
            {11'd0, 11'd5, 11'd2, 11'd1},
            {11'd8, 11'd0, 11'd7, 11'd0},
            {8'd0, 8'd4, 8'd0, 8'd6},
            {8'd5, 8'd0, 8'd2, 8'd0},
            10'd0,
            10'd9
        );

        if (mismatch_count != 0) begin
            $display("ERROR tb_iter_solver_native_row_digit_characterization mismatches=%0d", mismatch_count);
            $fatal;
        end

        $display("PASS tb_iter_solver_native_row_digit_characterization");
        $finish;
    end
endmodule
