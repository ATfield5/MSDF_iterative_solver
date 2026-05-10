`timescale 1ns / 1ps

// Two-iteration solver-native affine cluster checkpoint.
//
// This test is stronger than the identity closed-loop checkpoint:
//   iter1: direct source digit streams -> non-identity affine rows -> state bank
//   iter2: replayed signed-digit states -> non-identity affine rows -> state bank
//
// It verifies that committed signed-digit state is not merely readable, but can
// be consumed by the next solver-native row-update iteration with positive and
// negative fixed coefficients.

module tb_iter_solver_native_two_iter_affine_cluster;
    localparam integer NUM_ROWS = 2;
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
    reg [NUM_ROWS*DEGREE-1:0] state_digit_p_terms_rows;
    reg [NUM_ROWS*DEGREE-1:0] state_digit_n_terms_rows;
    reg [NUM_ROWS*DEGREE*BIT_WIDTH-1:0] coeff_p_terms_rows;
    reg [NUM_ROWS*DEGREE*BIT_WIDTH-1:0] coeff_n_terms_rows;
    reg [NUM_ROWS*BIAS_WIDTH-1:0] bias_p_rows;
    reg [NUM_ROWS*BIAS_WIDTH-1:0] bias_n_rows;

    wire [NUM_ROWS-1:0] full_valid_rows;
    wire signed [ACC_WIDTH-1:0] full_sum0;
    wire signed [ACC_WIDTH-1:0] full_sum1;
    wire [NUM_ROWS-1:0] native_valid_rows;
    wire [NUM_ROWS-1:0] native_z_p_rows;
    wire [NUM_ROWS-1:0] native_z_n_rows;
    wire [NUM_ROWS-1:0] adapter_write_valid_rows;
    wire [NUM_ROWS-1:0] adapter_write_p_rows;
    wire [NUM_ROWS-1:0] adapter_write_n_rows;
    wire [DIGIT_IDX_WIDTH-1:0] adapter_write_idx0;
    wire [DIGIT_IDX_WIDTH-1:0] adapter_write_idx1;
    wire [NUM_ROWS-1:0] adapter_done_rows;

    reg commit_swap;
    reg clear_write_bank;
    reg [DIGIT_IDX_WIDTH-1:0] replay_digit_idx;
    reg [NUM_ROWS*DEGREE-1:0] src_row_idx;
    wire [NUM_ROWS*DATA_WIDTH-1:0] read_state_p_rows;
    wire [NUM_ROWS*DATA_WIDTH-1:0] read_state_n_rows;
    wire [NUM_ROWS-1:0] replay_x0_p_rows;
    wire [NUM_ROWS-1:0] replay_x0_n_rows;
    wire [NUM_ROWS-1:0] replay_x1_p_rows;
    wire [NUM_ROWS-1:0] replay_x1_n_rows;

    reg [DATA_WIDTH-1:0] row0_state0_p;
    reg [DATA_WIDTH-1:0] row0_state0_n;
    reg [DATA_WIDTH-1:0] row0_state1_p;
    reg [DATA_WIDTH-1:0] row0_state2_n;
    reg [DATA_WIDTH-1:0] row0_state3_p;
    reg [DATA_WIDTH-1:0] row1_state0_n;
    reg [DATA_WIDTH-1:0] row1_state1_p;
    reg [DATA_WIDTH-1:0] row1_state2_p;
    reg [DATA_WIDTH-1:0] row1_state2_n;
    reg [DATA_WIDTH-1:0] row1_state3_p;

    integer di;
    integer bit_sel;
    integer wait_count;
    reg full_seen0;
    reg full_seen1;
    reg signed [ACC_WIDTH-1:0] full_sum_seen0;
    reg signed [ACC_WIDTH-1:0] full_sum_seen1;
    reg signed [ACC_WIDTH-1:0] replay_sum0;
    reg signed [ACC_WIDTH-1:0] replay_sum1;

    iter_digit_serial_full_row_update_delta_slice #(
        .degree(DEGREE),
        .bit_width(BIT_WIDTH),
        .data_width(DATA_WIDTH),
        .bias_width(BIAS_WIDTH),
        .bound_width(BOUND_WIDTH),
        .acc_width(ACC_WIDTH)
    ) full_ref0 (
        .i_clk(i_clk),
        .i_rst(i_rst),
        .i_start(i_start),
        .i_valid_digit(i_valid_digit),
        .i_last_digit(i_last_digit),
        .i_digit_idx(i_digit_idx),
        .i_state_digit_p_terms(state_digit_p_terms_rows[0*DEGREE +: DEGREE]),
        .i_state_digit_n_terms(state_digit_n_terms_rows[0*DEGREE +: DEGREE]),
        .i_coeff_p_terms(coeff_p_terms_rows[0*DEGREE*BIT_WIDTH +: DEGREE*BIT_WIDTH]),
        .i_coeff_n_terms(coeff_n_terms_rows[0*DEGREE*BIT_WIDTH +: DEGREE*BIT_WIDTH]),
        .i_bias_p(bias_p_rows[0*BIAS_WIDTH +: BIAS_WIDTH]),
        .i_bias_n(bias_n_rows[0*BIAS_WIDTH +: BIAS_WIDTH]),
        .i_old_state_p({DATA_WIDTH{1'b0}}),
        .i_old_state_n({DATA_WIDTH{1'b0}}),
        .i_tail_bound({BOUND_WIDTH{1'b0}}),
        .o_busy(),
        .o_valid(full_valid_rows[0]),
        .o_sum(full_sum0),
        .o_sum_p(),
        .o_sum_n(),
        .o_abs_upper(),
        .o_prefix_valid(),
        .o_prefix_abs_upper()
    );

    iter_digit_serial_full_row_update_delta_slice #(
        .degree(DEGREE),
        .bit_width(BIT_WIDTH),
        .data_width(DATA_WIDTH),
        .bias_width(BIAS_WIDTH),
        .bound_width(BOUND_WIDTH),
        .acc_width(ACC_WIDTH)
    ) full_ref1 (
        .i_clk(i_clk),
        .i_rst(i_rst),
        .i_start(i_start),
        .i_valid_digit(i_valid_digit),
        .i_last_digit(i_last_digit),
        .i_digit_idx(i_digit_idx),
        .i_state_digit_p_terms(state_digit_p_terms_rows[1*DEGREE +: DEGREE]),
        .i_state_digit_n_terms(state_digit_n_terms_rows[1*DEGREE +: DEGREE]),
        .i_coeff_p_terms(coeff_p_terms_rows[1*DEGREE*BIT_WIDTH +: DEGREE*BIT_WIDTH]),
        .i_coeff_n_terms(coeff_n_terms_rows[1*DEGREE*BIT_WIDTH +: DEGREE*BIT_WIDTH]),
        .i_bias_p(bias_p_rows[1*BIAS_WIDTH +: BIAS_WIDTH]),
        .i_bias_n(bias_n_rows[1*BIAS_WIDTH +: BIAS_WIDTH]),
        .i_old_state_p({DATA_WIDTH{1'b0}}),
        .i_old_state_n({DATA_WIDTH{1'b0}}),
        .i_tail_bound({BOUND_WIDTH{1'b0}}),
        .o_busy(),
        .o_valid(full_valid_rows[1]),
        .o_sum(full_sum1),
        .o_sum_p(),
        .o_sum_n(),
        .o_abs_upper(),
        .o_prefix_valid(),
        .o_prefix_abs_upper()
    );

    genvar ri;
    generate
        for (ri = 0; ri < NUM_ROWS; ri = ri + 1) begin : g_native_rows
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
                .i_state_digit_p_terms(state_digit_p_terms_rows[ri*DEGREE +: DEGREE]),
                .i_state_digit_n_terms(state_digit_n_terms_rows[ri*DEGREE +: DEGREE]),
                .i_coeff_p_terms(coeff_p_terms_rows[ri*DEGREE*BIT_WIDTH +: DEGREE*BIT_WIDTH]),
                .i_coeff_n_terms(coeff_n_terms_rows[ri*DEGREE*BIT_WIDTH +: DEGREE*BIT_WIDTH]),
                .i_bias_p(bias_p_rows[ri*BIAS_WIDTH +: BIAS_WIDTH]),
                .i_bias_n(bias_n_rows[ri*BIAS_WIDTH +: BIAS_WIDTH]),
                .o_valid(native_valid_rows[ri]),
                .o_x_new_digit_p(native_z_p_rows[ri]),
                .o_x_new_digit_n(native_z_n_rows[ri]),
                .o_affine_p(),
                .o_affine_n(),
                .o_residual_p(),
                .o_residual_n()
            );
        end
    endgenerate

    iter_solver_native_commit_adapter #(
        .state_width(DATA_WIDTH),
        .skip_digits(SKIP_DIGITS),
        .digit_idx_width(DIGIT_IDX_WIDTH)
    ) commit_adapter0 (
        .i_clk(i_clk),
        .i_rst(i_rst),
        .i_clear(clear_write_bank),
        .i_valid(native_valid_rows[0]),
        .i_digit_p(native_z_p_rows[0]),
        .i_digit_n(native_z_n_rows[0]),
        .o_write_valid(adapter_write_valid_rows[0]),
        .o_write_digit_idx(adapter_write_idx0),
        .o_write_digit_p(adapter_write_p_rows[0]),
        .o_write_digit_n(adapter_write_n_rows[0]),
        .o_done(adapter_done_rows[0])
    );

    iter_solver_native_commit_adapter #(
        .state_width(DATA_WIDTH),
        .skip_digits(SKIP_DIGITS),
        .digit_idx_width(DIGIT_IDX_WIDTH)
    ) commit_adapter1 (
        .i_clk(i_clk),
        .i_rst(i_rst),
        .i_clear(clear_write_bank),
        .i_valid(native_valid_rows[1]),
        .i_digit_p(native_z_p_rows[1]),
        .i_digit_n(native_z_n_rows[1]),
        .o_write_valid(adapter_write_valid_rows[1]),
        .o_write_digit_idx(adapter_write_idx1),
        .o_write_digit_p(adapter_write_p_rows[1]),
        .o_write_digit_n(adapter_write_n_rows[1]),
        .o_done(adapter_done_rows[1])
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
        .i_commit_swap(commit_swap),
        .i_clear_write_bank(clear_write_bank),
        .i_load_state(1'b0),
        .i_load_bank_sel(1'b0),
        .i_load_row_idx(1'b0),
        .i_load_state_p({DATA_WIDTH{1'b0}}),
        .i_load_state_n({DATA_WIDTH{1'b0}}),
        .i_write_digit_valid_rows(adapter_write_valid_rows),
        .i_write_digit_idx(adapter_write_idx0),
        .i_write_digit_p_rows(adapter_write_p_rows),
        .i_write_digit_n_rows(adapter_write_n_rows),
        .i_replay_digit_idx(replay_digit_idx),
        .i_src_row_idx(src_row_idx),
        .o_read_bank_sel(),
        .o_read_state_p_rows(read_state_p_rows),
        .o_read_state_n_rows(read_state_n_rows),
        .o_x0_p_rows(replay_x0_p_rows),
        .o_x0_n_rows(replay_x0_n_rows),
        .o_x1_p_rows(replay_x1_p_rows),
        .o_x1_n_rows(replay_x1_n_rows),
        .o_x2_p_rows(),
        .o_x2_n_rows(),
        .o_x3_p_rows(),
        .o_x3_n_rows()
    );

    always #5 i_clk = ~i_clk;

    task automatic pulse_clear_write_bank;
        begin
            @(negedge i_clk);
            clear_write_bank = 1'b1;
            @(negedge i_clk);
            clear_write_bank = 1'b0;
        end
    endtask

    task automatic commit_and_swap;
        begin
            @(negedge i_clk);
            commit_swap = 1'b1;
            @(negedge i_clk);
            commit_swap = 1'b0;
        end
    endtask

    task automatic configure_iter1;
        begin
            coeff_p_terms_rows = {NUM_ROWS*DEGREE*BIT_WIDTH{1'b0}};
            coeff_n_terms_rows = {NUM_ROWS*DEGREE*BIT_WIDTH{1'b0}};
            bias_p_rows = {NUM_ROWS*BIAS_WIDTH{1'b0}};
            bias_n_rows = {NUM_ROWS*BIAS_WIDTH{1'b0}};

            coeff_p_terms_rows[0*DEGREE*BIT_WIDTH +: DEGREE*BIT_WIDTH]
                = {8'd2, 8'd0, 8'd7, 8'd9};
            coeff_n_terms_rows[0*DEGREE*BIT_WIDTH +: DEGREE*BIT_WIDTH]
                = {8'd0, 8'd3, 8'd0, 8'd0};
            bias_p_rows[0*BIAS_WIDTH +: BIAS_WIDTH] = 10'd5;
            bias_n_rows[0*BIAS_WIDTH +: BIAS_WIDTH] = 10'd1;

            coeff_p_terms_rows[1*DEGREE*BIT_WIDTH +: DEGREE*BIT_WIDTH]
                = {8'd0, 8'd4, 8'd0, 8'd6};
            coeff_n_terms_rows[1*DEGREE*BIT_WIDTH +: DEGREE*BIT_WIDTH]
                = {8'd5, 8'd0, 8'd2, 8'd0};
            bias_p_rows[1*BIAS_WIDTH +: BIAS_WIDTH] = 10'd0;
            bias_n_rows[1*BIAS_WIDTH +: BIAS_WIDTH] = 10'd9;
        end
    endtask

    task automatic configure_iter2;
        begin
            coeff_p_terms_rows = {NUM_ROWS*DEGREE*BIT_WIDTH{1'b0}};
            coeff_n_terms_rows = {NUM_ROWS*DEGREE*BIT_WIDTH{1'b0}};
            bias_p_rows = {NUM_ROWS*BIAS_WIDTH{1'b0}};
            bias_n_rows = {NUM_ROWS*BIAS_WIDTH{1'b0}};

            // row0' = row0 + row1
            coeff_p_terms_rows[0*DEGREE*BIT_WIDTH +: DEGREE*BIT_WIDTH]
                = {8'd0, 8'd0, 8'd1, 8'd1};

            // row1' = row0 - row1
            coeff_p_terms_rows[1*DEGREE*BIT_WIDTH +: DEGREE*BIT_WIDTH]
                = {8'd0, 8'd0, 8'd0, 8'd1};
            coeff_n_terms_rows[1*DEGREE*BIT_WIDTH +: DEGREE*BIT_WIDTH]
                = {8'd0, 8'd0, 8'd1, 8'd0};
        end
    endtask

    task automatic set_iter1_digits;
        input integer bit_index;
        begin
            state_digit_p_terms_rows = {NUM_ROWS*DEGREE{1'b0}};
            state_digit_n_terms_rows = {NUM_ROWS*DEGREE{1'b0}};

            state_digit_p_terms_rows[0*DEGREE + 0] = row0_state0_p[bit_index];
            state_digit_n_terms_rows[0*DEGREE + 0] = row0_state0_n[bit_index];
            state_digit_p_terms_rows[0*DEGREE + 1] = row0_state1_p[bit_index];
            state_digit_n_terms_rows[0*DEGREE + 1] = 1'b0;
            state_digit_p_terms_rows[0*DEGREE + 2] = 1'b0;
            state_digit_n_terms_rows[0*DEGREE + 2] = row0_state2_n[bit_index];
            state_digit_p_terms_rows[0*DEGREE + 3] = row0_state3_p[bit_index];
            state_digit_n_terms_rows[0*DEGREE + 3] = 1'b0;

            state_digit_p_terms_rows[1*DEGREE + 0] = 1'b0;
            state_digit_n_terms_rows[1*DEGREE + 0] = row1_state0_n[bit_index];
            state_digit_p_terms_rows[1*DEGREE + 1] = row1_state1_p[bit_index];
            state_digit_n_terms_rows[1*DEGREE + 1] = 1'b0;
            state_digit_p_terms_rows[1*DEGREE + 2] = row1_state2_p[bit_index];
            state_digit_n_terms_rows[1*DEGREE + 2] = row1_state2_n[bit_index];
            state_digit_p_terms_rows[1*DEGREE + 3] = row1_state3_p[bit_index];
            state_digit_n_terms_rows[1*DEGREE + 3] = 1'b0;
        end
    endtask

    task automatic set_iter2_replay_digits;
        begin
            state_digit_p_terms_rows = {NUM_ROWS*DEGREE{1'b0}};
            state_digit_n_terms_rows = {NUM_ROWS*DEGREE{1'b0}};

            state_digit_p_terms_rows[0*DEGREE + 0] = replay_x0_p_rows[0];
            state_digit_n_terms_rows[0*DEGREE + 0] = replay_x0_n_rows[0];
            state_digit_p_terms_rows[0*DEGREE + 1] = replay_x1_p_rows[0];
            state_digit_n_terms_rows[0*DEGREE + 1] = replay_x1_n_rows[0];

            state_digit_p_terms_rows[1*DEGREE + 0] = replay_x0_p_rows[1];
            state_digit_n_terms_rows[1*DEGREE + 0] = replay_x0_n_rows[1];
            state_digit_p_terms_rows[1*DEGREE + 1] = replay_x1_p_rows[1];
            state_digit_n_terms_rows[1*DEGREE + 1] = replay_x1_n_rows[1];
        end
    endtask

    task automatic configure_mix_src_rows;
        begin
            src_row_idx = {NUM_ROWS*DEGREE{1'b0}};
            src_row_idx[0*DEGREE + 0] = 1'b0;
            src_row_idx[0*DEGREE + 1] = 1'b1;
            src_row_idx[1*DEGREE + 0] = 1'b0;
            src_row_idx[1*DEGREE + 1] = 1'b1;
        end
    endtask

    task automatic configure_self_replay_src_rows;
        begin
            src_row_idx = {NUM_ROWS*DEGREE{1'b0}};
            src_row_idx[0*DEGREE + 0] = 1'b0;
            src_row_idx[1*DEGREE + 0] = 1'b1;
        end
    endtask

    task automatic drain_and_capture;
        input signed [ACC_WIDTH-1:0] expected0;
        input signed [ACC_WIDTH-1:0] expected1;
        begin
            i_start = 1'b0;
            i_valid_digit = 1'b1;
            i_last_digit = 1'b0;
            i_digit_idx = DATA_WIDTH - 1;
            state_digit_p_terms_rows = {NUM_ROWS*DEGREE{1'b0}};
            state_digit_n_terms_rows = {NUM_ROWS*DEGREE{1'b0}};
            bias_p_rows = {NUM_ROWS*BIAS_WIDTH{1'b0}};
            bias_n_rows = {NUM_ROWS*BIAS_WIDTH{1'b0}};

            wait_count = 0;
            while ((!(full_seen0 && full_seen1) || !(adapter_done_rows[0] && adapter_done_rows[1])) &&
                   wait_count < 40) begin
                @(negedge i_clk);
                if (full_valid_rows[0] && !full_seen0) begin
                    full_seen0 = 1'b1;
                    full_sum_seen0 = full_sum0;
                end
                if (full_valid_rows[1] && !full_seen1) begin
                    full_seen1 = 1'b1;
                    full_sum_seen1 = full_sum1;
                end
                wait_count = wait_count + 1;
            end

            i_valid_digit = 1'b0;

            if (!full_seen0 || !full_seen1 || !adapter_done_rows[0] || !adapter_done_rows[1]) begin
                $display("ERROR capture full_seen=%0d%0d done=%0d%0d",
                    full_seen1, full_seen0, adapter_done_rows[1], adapter_done_rows[0]);
                $fatal;
            end

            if (full_sum_seen0 !== expected0 || full_sum_seen1 !== expected1) begin
                $display("ERROR full reference mismatch got0=%0d exp0=%0d got1=%0d exp1=%0d",
                    full_sum_seen0, expected0, full_sum_seen1, expected1);
                $fatal;
            end
        end
    endtask

    task automatic run_iter1;
        begin
            configure_iter1();
            full_seen0 = 1'b0;
            full_seen1 = 1'b0;
            full_sum_seen0 = {ACC_WIDTH{1'b0}};
            full_sum_seen1 = {ACC_WIDTH{1'b0}};

            for (di = 0; di < DATA_WIDTH; di = di + 1) begin
                bit_sel = DATA_WIDTH - 1 - di;
                i_start = (di == 0);
                i_valid_digit = 1'b1;
                i_last_digit = (di == DATA_WIDTH - 1);
                i_digit_idx = di[DIGIT_IDX_WIDTH-1:0];
                set_iter1_digits(bit_sel);
                @(negedge i_clk);
                if (full_valid_rows[0] && !full_seen0) begin
                    full_seen0 = 1'b1;
                    full_sum_seen0 = full_sum0;
                end
                if (full_valid_rows[1] && !full_seen1) begin
                    full_seen1 = 1'b1;
                    full_sum_seen1 = full_sum1;
                end
            end

            drain_and_capture(32'sd170, -32'sd92);
            commit_and_swap();
        end
    endtask

    task automatic run_iter2_from_replay;
        begin
            configure_iter2();
            configure_mix_src_rows();
            full_seen0 = 1'b0;
            full_seen1 = 1'b0;
            full_sum_seen0 = {ACC_WIDTH{1'b0}};
            full_sum_seen1 = {ACC_WIDTH{1'b0}};

            for (di = 0; di < DATA_WIDTH; di = di + 1) begin
                replay_digit_idx = di[DIGIT_IDX_WIDTH-1:0];
                #1;
                i_start = (di == 0);
                i_valid_digit = 1'b1;
                i_last_digit = (di == DATA_WIDTH - 1);
                i_digit_idx = di[DIGIT_IDX_WIDTH-1:0];
                set_iter2_replay_digits();
                @(negedge i_clk);
                if (full_valid_rows[0] && !full_seen0) begin
                    full_seen0 = 1'b1;
                    full_sum_seen0 = full_sum0;
                end
                if (full_valid_rows[1] && !full_seen1) begin
                    full_seen1 = 1'b1;
                    full_sum_seen1 = full_sum1;
                end
            end

            drain_and_capture(32'sd78, 32'sd262);
            commit_and_swap();
        end
    endtask

    task automatic reconstruct_self_replay;
        output signed [ACC_WIDTH-1:0] row0_value;
        output signed [ACC_WIDTH-1:0] row1_value;
        begin
            configure_self_replay_src_rows();
            row0_value = 32'sd0;
            row1_value = 32'sd0;
            for (di = 0; di < DATA_WIDTH; di = di + 1) begin
                replay_digit_idx = di[DIGIT_IDX_WIDTH-1:0];
                #1;
                row0_value = row0_value <<< 1;
                row1_value = row1_value <<< 1;
                if (replay_x0_p_rows[0] && !replay_x0_n_rows[0]) begin
                    row0_value = row0_value + 1;
                end else if (!replay_x0_p_rows[0] && replay_x0_n_rows[0]) begin
                    row0_value = row0_value - 1;
                end
                if (replay_x0_p_rows[1] && !replay_x0_n_rows[1]) begin
                    row1_value = row1_value + 1;
                end else if (!replay_x0_p_rows[1] && replay_x0_n_rows[1]) begin
                    row1_value = row1_value - 1;
                end
            end
        end
    endtask

    initial begin
        i_clk = 1'b0;
        i_rst = 1'b1;
        i_start = 1'b0;
        i_valid_digit = 1'b0;
        i_last_digit = 1'b0;
        i_digit_idx = {DIGIT_IDX_WIDTH{1'b0}};
        state_digit_p_terms_rows = {NUM_ROWS*DEGREE{1'b0}};
        state_digit_n_terms_rows = {NUM_ROWS*DEGREE{1'b0}};
        coeff_p_terms_rows = {NUM_ROWS*DEGREE*BIT_WIDTH{1'b0}};
        coeff_n_terms_rows = {NUM_ROWS*DEGREE*BIT_WIDTH{1'b0}};
        bias_p_rows = {NUM_ROWS*BIAS_WIDTH{1'b0}};
        bias_n_rows = {NUM_ROWS*BIAS_WIDTH{1'b0}};
        commit_swap = 1'b0;
        clear_write_bank = 1'b0;
        replay_digit_idx = {DIGIT_IDX_WIDTH{1'b0}};
        src_row_idx = {NUM_ROWS*DEGREE{1'b0}};
        full_seen0 = 1'b0;
        full_seen1 = 1'b0;
        full_sum_seen0 = {ACC_WIDTH{1'b0}};
        full_sum_seen1 = {ACC_WIDTH{1'b0}};
        replay_sum0 = {ACC_WIDTH{1'b0}};
        replay_sum1 = {ACC_WIDTH{1'b0}};

        row0_state0_p = 11'd12;
        row0_state0_n = 11'd1;
        row0_state1_p = 11'd7;
        row0_state2_n = 11'd4;
        row0_state3_p = 11'd3;
        row1_state0_n = 11'd8;
        row1_state1_p = 11'd5;
        row1_state2_p = 11'd2;
        row1_state2_n = 11'd7;
        row1_state3_p = 11'd1;

        repeat (2) @(negedge i_clk);
        i_rst = 1'b0;

        pulse_clear_write_bank();
        run_iter1();

        pulse_clear_write_bank();
        run_iter2_from_replay();

        reconstruct_self_replay(replay_sum0, replay_sum1);
        if (replay_sum0 !== 32'sd78 || replay_sum1 !== 32'sd262) begin
            $display("ERROR two-iter final replay row0=%0d row1=%0d p=%h n=%h",
                replay_sum0, replay_sum1, read_state_p_rows, read_state_n_rows);
            $fatal;
        end

        $display("PASS tb_iter_solver_native_two_iter_affine_cluster iter1=(170,-92) iter2=(%0d,%0d)",
            replay_sum0, replay_sum1);
        $finish;
    end
endmodule
