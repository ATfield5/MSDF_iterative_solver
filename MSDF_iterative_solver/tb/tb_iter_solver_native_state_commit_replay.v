`timescale 1ns / 1ps

// Solver-native row-output -> digit-stream state bank -> replay checkpoint.
//
// The solver-native row engine emits a signed-digit rail trace.  This test
// writes that trace directly into the digit-stream state bank, commits it, then
// replays the stored digits and reconstructs the numerical value.  The value
// must match the full-digit bridge reference even though the stored p/n bit
// pattern is not the bridge's magnitude-rail pattern.

module tb_iter_solver_native_state_commit_replay;
    localparam integer NUM_ROWS = 1;
    localparam integer DEGREE = 4;
    localparam integer BIT_WIDTH = 8;
    localparam integer DATA_WIDTH = BIT_WIDTH + 3;
    localparam integer BIAS_WIDTH = BIT_WIDTH + 2;
    localparam integer BOUND_WIDTH = BIT_WIDTH + 5;
    localparam integer ACC_WIDTH = 32;
    localparam integer DIGIT_IDX_WIDTH = $clog2(DATA_WIDTH);
    localparam integer EXTRA_DRAIN_DIGITS = 8;
    localparam integer TRACE_WIDTH = DATA_WIDTH + EXTRA_DRAIN_DIGITS;
    localparam integer TRACE_IDX_WIDTH = $clog2(TRACE_WIDTH);

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

    reg i_commit_swap;
    reg i_clear_write_bank;
    reg [NUM_ROWS-1:0] i_write_digit_valid_rows;
    reg [TRACE_IDX_WIDTH-1:0] i_write_digit_idx;
    reg [NUM_ROWS-1:0] i_write_digit_p_rows;
    reg [NUM_ROWS-1:0] i_write_digit_n_rows;
    reg [TRACE_IDX_WIDTH-1:0] i_replay_digit_idx;
    wire [TRACE_WIDTH-1:0] read_state_p_rows;
    wire [TRACE_WIDTH-1:0] read_state_n_rows;
    wire [NUM_ROWS-1:0] replay_x0_p_rows;
    wire [NUM_ROWS-1:0] replay_x0_n_rows;

    integer di;
    integer ti;
    integer bit_sel;
    integer wait_count;
    integer valid_count;
    reg full_seen;
    reg signed [ACC_WIDTH-1:0] full_sum_seen;
    reg signed [ACC_WIDTH-1:0] replay_sum;
    reg [DATA_WIDTH-1:0] state0_p_word;
    reg [DATA_WIDTH-1:0] state0_n_word;
    reg [DATA_WIDTH-1:0] state1_p_word;
    reg [DATA_WIDTH-1:0] state2_n_word;
    reg [DATA_WIDTH-1:0] state3_p_word;

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
        .i_old_state_p({DATA_WIDTH{1'b0}}),
        .i_old_state_n({DATA_WIDTH{1'b0}}),
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

    iter_digit_stream_state_replay_top #(
        .num_rows(NUM_ROWS),
        .degree(DEGREE),
        .data_width(TRACE_WIDTH),
        .msb_first(1),
        .row_idx_width(1),
        .digit_idx_width(TRACE_IDX_WIDTH)
    ) state_replay (
        .i_clk(i_clk),
        .i_rst(i_rst),
        .i_commit_swap(i_commit_swap),
        .i_clear_write_bank(i_clear_write_bank),
        .i_load_state(1'b0),
        .i_load_bank_sel(1'b0),
        .i_load_row_idx(1'b0),
        .i_load_state_p({TRACE_WIDTH{1'b0}}),
        .i_load_state_n({TRACE_WIDTH{1'b0}}),
        .i_write_digit_valid_rows(i_write_digit_valid_rows),
        .i_write_digit_idx(i_write_digit_idx),
        .i_write_digit_p_rows(i_write_digit_p_rows),
        .i_write_digit_n_rows(i_write_digit_n_rows),
        .i_replay_digit_idx(i_replay_digit_idx),
        .i_src_row_idx({DEGREE{1'b0}}),
        .o_read_bank_sel(),
        .o_read_state_p_rows(read_state_p_rows),
        .o_read_state_n_rows(read_state_n_rows),
        .o_x0_p_rows(replay_x0_p_rows),
        .o_x0_n_rows(replay_x0_n_rows),
        .o_x1_p_rows(),
        .o_x1_n_rows(),
        .o_x2_p_rows(),
        .o_x2_n_rows(),
        .o_x3_p_rows(),
        .o_x3_n_rows()
    );

    always #5 i_clk = ~i_clk;

    task automatic clear_write_inputs;
        begin
            i_commit_swap = 1'b0;
            i_clear_write_bank = 1'b0;
            i_write_digit_valid_rows = {NUM_ROWS{1'b0}};
            i_write_digit_idx = {TRACE_IDX_WIDTH{1'b0}};
            i_write_digit_p_rows = {NUM_ROWS{1'b0}};
            i_write_digit_n_rows = {NUM_ROWS{1'b0}};
            i_replay_digit_idx = {TRACE_IDX_WIDTH{1'b0}};
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
        i_bias_p = 10'd5;
        i_bias_n = 10'd1;
        clear_write_inputs();
        valid_count = 0;
        full_seen = 1'b0;
        full_sum_seen = {ACC_WIDTH{1'b0}};
        replay_sum = {ACC_WIDTH{1'b0}};
        state0_p_word = 11'd12;
        state0_n_word = 11'd1;
        state1_p_word = 11'd7;
        state2_n_word = 11'd4;
        state3_p_word = 11'd3;

        repeat (2) @(negedge i_clk);
        i_rst = 1'b0;

        i_coeff_p_terms = {8'd2, 8'd0, 8'd7, 8'd9};
        i_coeff_n_terms = {8'd0, 8'd3, 8'd0, 8'd0};

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
            if (native_valid && valid_count < TRACE_WIDTH) begin
                i_write_digit_valid_rows = 1'b1;
                i_write_digit_idx = valid_count[TRACE_IDX_WIDTH-1:0];
                i_write_digit_p_rows = native_z_p;
                i_write_digit_n_rows = native_z_n;
                valid_count = valid_count + 1;
            end else begin
                i_write_digit_valid_rows = 1'b0;
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
            end
            if (native_valid && valid_count < TRACE_WIDTH) begin
                i_write_digit_valid_rows = 1'b1;
                i_write_digit_idx = valid_count[TRACE_IDX_WIDTH-1:0];
                i_write_digit_p_rows = native_z_p;
                i_write_digit_n_rows = native_z_n;
                valid_count = valid_count + 1;
            end else begin
                i_write_digit_valid_rows = 1'b0;
            end
            wait_count = wait_count + 1;
        end

        i_valid_digit = 1'b0;
        i_write_digit_valid_rows = 1'b0;

        if (!full_seen || valid_count !== TRACE_WIDTH) begin
            $display("ERROR native state commit capture full_seen=%0d valid_count=%0d", full_seen, valid_count);
            $fatal;
        end

        @(negedge i_clk);
        i_commit_swap = 1'b1;
        @(negedge i_clk);
        i_commit_swap = 1'b0;

        for (di = 0; di < TRACE_WIDTH; di = di + 1) begin
            i_replay_digit_idx = di[TRACE_IDX_WIDTH-1:0];
            #1;
            replay_sum = replay_sum <<< 1;
            if (replay_x0_p_rows[0] && !replay_x0_n_rows[0]) begin
                replay_sum = replay_sum + 1;
            end else if (!replay_x0_p_rows[0] && replay_x0_n_rows[0]) begin
                replay_sum = replay_sum - 1;
            end
        end

        if (replay_sum !== full_sum_seen) begin
            $display("ERROR replayed signed-digit state value=%0d expected=%0d p=%h n=%h",
                replay_sum, full_sum_seen, read_state_p_rows, read_state_n_rows);
            $fatal;
        end

        $display("PASS tb_iter_solver_native_state_commit_replay value=%0d p=%h n=%h",
            replay_sum, read_state_p_rows, read_state_n_rows);
        $finish;
    end
endmodule
