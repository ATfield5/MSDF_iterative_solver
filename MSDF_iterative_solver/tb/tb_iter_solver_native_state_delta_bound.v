`timescale 1ns / 1ps

// Solver-native state replay -> inline delta bound checkpoint.
//
// This test reuses the fixed-width signed-digit state commit path, replays the
// committed state, and feeds the replayed digits plus an old-state digit stream
// into iter_digit_stream_delta_bound.  The final delta must match
// full_bridge_sum - old_state without reconstructing the new state in hardware.

module tb_iter_solver_native_state_delta_bound;
    localparam integer NUM_ROWS = 1;
    localparam integer DEGREE = 4;
    localparam integer BIT_WIDTH = 8;
    localparam integer DATA_WIDTH = BIT_WIDTH + 3;
    localparam integer BIAS_WIDTH = BIT_WIDTH + 2;
    localparam integer BOUND_WIDTH = BIT_WIDTH + 5;
    localparam integer ACC_WIDTH = 32;
    localparam integer DIGIT_IDX_WIDTH = $clog2(DATA_WIDTH);
    localparam integer SKIP_DIGITS = 8;

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

    wire full_valid;
    wire signed [ACC_WIDTH-1:0] full_sum;
    wire native_valid;
    wire native_z_p;
    wire native_z_n;
    wire adapter_write_valid;
    wire [DIGIT_IDX_WIDTH-1:0] adapter_write_idx;
    wire adapter_write_p;
    wire adapter_write_n;
    wire adapter_done;

    reg i_commit_swap;
    reg i_clear_write_bank;
    reg [DIGIT_IDX_WIDTH-1:0] replay_digit_idx;
    wire replay_x0_p;
    wire replay_x0_n;
    wire delta_valid;
    wire signed [ACC_WIDTH-1:0] delta_prefix;
    wire [BOUND_WIDTH-1:0] delta_abs_upper;
    wire delta_final;

    reg [DATA_WIDTH-1:0] state0_p_word;
    reg [DATA_WIDTH-1:0] state0_n_word;
    reg [DATA_WIDTH-1:0] state1_p_word;
    reg [DATA_WIDTH-1:0] state2_n_word;
    reg [DATA_WIDTH-1:0] state3_p_word;
    reg [DATA_WIDTH-1:0] old_state_p_word;
    reg [DATA_WIDTH-1:0] old_state_n_word;
    integer di;
    integer bit_sel;
    integer wait_count;
    reg full_seen;
    reg signed [ACC_WIDTH-1:0] full_sum_seen;
    reg signed [ACC_WIDTH-1:0] expected_delta;
    reg delta_seen;
    reg signed [ACC_WIDTH-1:0] delta_seen_value;

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
        .i_old_state_p(old_state_p_word),
        .i_old_state_n(old_state_n_word),
        .i_tail_bound({BOUND_WIDTH{1'b0}}),
        .o_busy(),
        .o_valid(full_valid),
        .o_sum(full_sum),
        .o_sum_p(),
        .o_sum_n(),
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
    ) native_engine (
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

    iter_solver_native_commit_adapter #(
        .state_width(DATA_WIDTH),
        .skip_digits(SKIP_DIGITS),
        .digit_idx_width(DIGIT_IDX_WIDTH)
    ) commit_adapter (
        .i_clk(i_clk),
        .i_rst(i_rst),
        .i_clear(i_clear_write_bank),
        .i_valid(native_valid),
        .i_digit_p(native_z_p),
        .i_digit_n(native_z_n),
        .o_write_valid(adapter_write_valid),
        .o_write_digit_idx(adapter_write_idx),
        .o_write_digit_p(adapter_write_p),
        .o_write_digit_n(adapter_write_n),
        .o_done(adapter_done)
    );

    iter_digit_stream_state_replay_top #(
        .num_rows(NUM_ROWS),
        .degree(DEGREE),
        .data_width(DATA_WIDTH),
        .msb_first(1),
        .row_idx_width(1),
        .digit_idx_width(DIGIT_IDX_WIDTH)
    ) state_replay (
        .i_clk(i_clk),
        .i_rst(i_rst),
        .i_commit_swap(i_commit_swap),
        .i_clear_write_bank(i_clear_write_bank),
        .i_load_state(1'b0),
        .i_load_bank_sel(1'b0),
        .i_load_row_idx(1'b0),
        .i_load_state_p({DATA_WIDTH{1'b0}}),
        .i_load_state_n({DATA_WIDTH{1'b0}}),
        .i_write_digit_valid_rows(adapter_write_valid),
        .i_write_digit_idx(adapter_write_idx),
        .i_write_digit_p_rows(adapter_write_p),
        .i_write_digit_n_rows(adapter_write_n),
        .i_replay_digit_idx(replay_digit_idx),
        .i_src_row_idx({DEGREE{1'b0}}),
        .o_read_bank_sel(),
        .o_read_state_p_rows(),
        .o_read_state_n_rows(),
        .o_x0_p_rows(replay_x0_p),
        .o_x0_n_rows(replay_x0_n),
        .o_x1_p_rows(),
        .o_x1_n_rows(),
        .o_x2_p_rows(),
        .o_x2_n_rows(),
        .o_x3_p_rows(),
        .o_x3_n_rows()
    );

    iter_digit_stream_delta_bound #(
        .data_width(DATA_WIDTH),
        .bound_width(BOUND_WIDTH),
        .acc_width(ACC_WIDTH),
        .digit_idx_width(DIGIT_IDX_WIDTH)
    ) delta_bound (
        .i_clk(i_clk),
        .i_rst(i_rst),
        .i_start(replay_digit_idx == {DIGIT_IDX_WIDTH{1'b0}}),
        .i_valid(1'b1),
        .i_digit_idx(replay_digit_idx),
        .i_new_digit_p(replay_x0_p),
        .i_new_digit_n(replay_x0_n),
        .i_old_digit_p(old_state_p_word[DATA_WIDTH - 1 - replay_digit_idx]),
        .i_old_digit_n(old_state_n_word[DATA_WIDTH - 1 - replay_digit_idx]),
        .o_valid(delta_valid),
        .o_prefix_delta(delta_prefix),
        .o_abs_upper(delta_abs_upper),
        .o_final(delta_final)
    );

    always #5 i_clk = ~i_clk;

    initial begin
        i_clk = 1'b0;
        i_rst = 1'b1;
        i_start = 1'b0;
        i_valid_digit = 1'b0;
        i_last_digit = 1'b0;
        i_digit_idx = {DIGIT_IDX_WIDTH{1'b0}};
        i_state_digit_p_terms = {DEGREE{1'b0}};
        i_state_digit_n_terms = {DEGREE{1'b0}};
        i_coeff_p_terms = {8'd2, 8'd0, 8'd7, 8'd9};
        i_coeff_n_terms = {8'd0, 8'd3, 8'd0, 8'd0};
        i_bias_p = 10'd5;
        i_bias_n = 10'd1;
        i_commit_swap = 1'b0;
        i_clear_write_bank = 1'b0;
        replay_digit_idx = {DIGIT_IDX_WIDTH{1'b0}};
        full_seen = 1'b0;
        full_sum_seen = {ACC_WIDTH{1'b0}};
        expected_delta = {ACC_WIDTH{1'b0}};
        delta_seen = 1'b0;
        delta_seen_value = {ACC_WIDTH{1'b0}};

        state0_p_word = 11'd12;
        state0_n_word = 11'd1;
        state1_p_word = 11'd7;
        state2_n_word = 11'd4;
        state3_p_word = 11'd3;
        old_state_p_word = 11'd5;
        old_state_n_word = 11'd0;

        repeat (2) @(negedge i_clk);
        i_rst = 1'b0;

        @(negedge i_clk);
        i_clear_write_bank = 1'b1;
        @(negedge i_clk);
        i_clear_write_bank = 1'b0;

        for (di = 0; di < DATA_WIDTH; di = di + 1) begin
            bit_sel = DATA_WIDTH - 1 - di;
            i_start = (di == 0);
            i_valid_digit = 1'b1;
            i_last_digit = (di == DATA_WIDTH - 1);
            i_digit_idx = di[DIGIT_IDX_WIDTH-1:0];
            i_state_digit_p_terms[0] = state0_p_word[bit_sel];
            i_state_digit_n_terms[0] = state0_n_word[bit_sel];
            i_state_digit_p_terms[1] = state1_p_word[bit_sel];
            i_state_digit_n_terms[1] = 1'b0;
            i_state_digit_p_terms[2] = 1'b0;
            i_state_digit_n_terms[2] = state2_n_word[bit_sel];
            i_state_digit_p_terms[3] = state3_p_word[bit_sel];
            i_state_digit_n_terms[3] = 1'b0;
            @(negedge i_clk);
            if (full_valid && !full_seen) begin
                full_seen = 1'b1;
                full_sum_seen = full_sum;
            end
        end

        i_start = 1'b0;
        i_valid_digit = 1'b1;
        i_last_digit = 1'b0;
        i_digit_idx = DATA_WIDTH - 1;
        i_state_digit_p_terms = {DEGREE{1'b0}};
        i_state_digit_n_terms = {DEGREE{1'b0}};
        i_bias_p = {BIAS_WIDTH{1'b0}};
        i_bias_n = {BIAS_WIDTH{1'b0}};

        wait_count = 0;
        while ((!full_seen || !adapter_done) && wait_count < 32) begin
            @(negedge i_clk);
            if (full_valid && !full_seen) begin
                full_seen = 1'b1;
                full_sum_seen = full_sum;
            end
            wait_count = wait_count + 1;
        end

        i_valid_digit = 1'b0;
        if (!full_seen || !adapter_done) begin
            $display("ERROR state delta setup full_seen=%0d adapter_done=%0d", full_seen, adapter_done);
            $fatal;
        end

        @(negedge i_clk);
        i_commit_swap = 1'b1;
        @(negedge i_clk);
        i_commit_swap = 1'b0;

        expected_delta = full_sum_seen - 32'sd5;

        for (di = 0; di < DATA_WIDTH; di = di + 1) begin
            replay_digit_idx = di[DIGIT_IDX_WIDTH-1:0];
            @(posedge i_clk);
            #1;
            if (delta_valid && delta_final) begin
                delta_seen = 1'b1;
                delta_seen_value = delta_prefix;
            end
        end

        if (!delta_seen || delta_seen_value !== expected_delta || delta_abs_upper !== expected_delta[BOUND_WIDTH-1:0]) begin
            $display("ERROR delta bound got seen=%0d delta=%0d abs=%0d expected_delta=%0d",
                delta_seen, delta_seen_value, delta_abs_upper, expected_delta);
            $fatal;
        end

        $display("PASS tb_iter_solver_native_state_delta_bound delta=%0d abs=%0d",
            delta_seen_value, delta_abs_upper);
        $finish;
    end
endmodule
