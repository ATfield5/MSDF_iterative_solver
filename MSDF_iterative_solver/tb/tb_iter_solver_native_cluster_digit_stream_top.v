`timescale 1ns / 1ps

// Directed test for iter_solver_native_cluster_digit_stream_top.
//
// This repeats the two-iteration affine checkpoint through the reusable cluster
// shell instead of hand-wiring row engines, commit adapters and state replay in
// the testbench.

module tb_iter_solver_native_cluster_digit_stream_top;
    localparam integer NUM_ROWS = 2;
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
    reg [NUM_ROWS-1:0] i_ena_rows;
    reg [DIGIT_IDX_WIDTH-1:0] i_digit_idx;
    reg i_use_replay;
    reg i_clear_write_bank;
    reg i_commit_swap;
    reg [NUM_ROWS*DEGREE-1:0] src_row_idx;
    reg [NUM_ROWS-1:0] ext_x0_p_rows;
    reg [NUM_ROWS-1:0] ext_x0_n_rows;
    reg [NUM_ROWS-1:0] ext_x1_p_rows;
    reg [NUM_ROWS-1:0] ext_x1_n_rows;
    reg [NUM_ROWS-1:0] ext_x2_p_rows;
    reg [NUM_ROWS-1:0] ext_x2_n_rows;
    reg [NUM_ROWS-1:0] ext_x3_p_rows;
    reg [NUM_ROWS-1:0] ext_x3_n_rows;
    reg [NUM_ROWS*DEGREE*BIT_WIDTH-1:0] coeff_p_terms_rows;
    reg [NUM_ROWS*DEGREE*BIT_WIDTH-1:0] coeff_n_terms_rows;
    reg [NUM_ROWS*BIAS_WIDTH-1:0] bias_p_rows;
    reg [NUM_ROWS*BIAS_WIDTH-1:0] bias_n_rows;
    reg [NUM_ROWS*DEGREE-1:0] ref_state_digit_p_terms_rows;
    reg [NUM_ROWS*DEGREE-1:0] ref_state_digit_n_terms_rows;

    wire [NUM_ROWS-1:0] replay_x0_p_rows;
    wire [NUM_ROWS-1:0] replay_x0_n_rows;
    wire [NUM_ROWS-1:0] replay_x1_p_rows;
    wire [NUM_ROWS-1:0] replay_x1_n_rows;
    wire [NUM_ROWS-1:0] write_done_rows;
    wire [NUM_ROWS*DATA_WIDTH-1:0] read_state_p_rows;
    wire [NUM_ROWS*DATA_WIDTH-1:0] read_state_n_rows;
    wire [NUM_ROWS-1:0] full_valid_rows;
    wire signed [ACC_WIDTH-1:0] full_sum0;
    wire signed [ACC_WIDTH-1:0] full_sum1;

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

    iter_solver_native_cluster_digit_stream_top #(
        .num_rows(NUM_ROWS),
        .degree(DEGREE),
        .bit_width(BIT_WIDTH),
        .data_width(DATA_WIDTH),
        .bias_width(BIAS_WIDTH),
        .row_idx_width(1),
        .digit_idx_width(DIGIT_IDX_WIDTH)
    ) dut (
        .i_clk(i_clk),
        .i_rst(i_rst),
        .i_start(i_start),
        .i_valid_digit(i_valid_digit),
        .i_ena_rows(i_ena_rows),
        .i_digit_idx(i_digit_idx),
        .i_use_replay(i_use_replay),
        .i_clear_write_bank(i_clear_write_bank),
        .i_commit_swap(i_commit_swap),
        .i_load_state(1'b0),
        .i_load_bank_sel(1'b0),
        .i_load_row_idx(1'b0),
        .i_load_state_p({DATA_WIDTH{1'b0}}),
        .i_load_state_n({DATA_WIDTH{1'b0}}),
        .i_src_row_idx(src_row_idx),
        .i_ext_x0_p_rows(ext_x0_p_rows),
        .i_ext_x0_n_rows(ext_x0_n_rows),
        .i_ext_x1_p_rows(ext_x1_p_rows),
        .i_ext_x1_n_rows(ext_x1_n_rows),
        .i_ext_x2_p_rows(ext_x2_p_rows),
        .i_ext_x2_n_rows(ext_x2_n_rows),
        .i_ext_x3_p_rows(ext_x3_p_rows),
        .i_ext_x3_n_rows(ext_x3_n_rows),
        .i_coeff_p_terms_rows(coeff_p_terms_rows),
        .i_coeff_n_terms_rows(coeff_n_terms_rows),
        .i_bias_p_rows(bias_p_rows),
        .i_bias_n_rows(bias_n_rows),
        .o_replay_x0_p_rows(replay_x0_p_rows),
        .o_replay_x0_n_rows(replay_x0_n_rows),
        .o_replay_x1_p_rows(replay_x1_p_rows),
        .o_replay_x1_n_rows(replay_x1_n_rows),
        .o_replay_x2_p_rows(),
        .o_replay_x2_n_rows(),
        .o_replay_x3_p_rows(),
        .o_replay_x3_n_rows(),
        .o_row_valid(),
        .o_row_digit_p(),
        .o_row_digit_n(),
        .o_write_valid_rows(),
        .o_write_digit_idx_rows(),
        .o_write_digit_p_rows(),
        .o_write_digit_n_rows(),
        .o_write_done_rows(write_done_rows),
        .o_read_state_p_rows(read_state_p_rows),
        .o_read_state_n_rows(read_state_n_rows)
    );

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
        .i_state_digit_p_terms(ref_state_digit_p_terms_rows[0*DEGREE +: DEGREE]),
        .i_state_digit_n_terms(ref_state_digit_n_terms_rows[0*DEGREE +: DEGREE]),
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
        .i_state_digit_p_terms(ref_state_digit_p_terms_rows[1*DEGREE +: DEGREE]),
        .i_state_digit_n_terms(ref_state_digit_n_terms_rows[1*DEGREE +: DEGREE]),
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

    always #5 i_clk = ~i_clk;

    task automatic configure_iter1;
        begin
            i_use_replay = 1'b0;
            coeff_p_terms_rows = {NUM_ROWS*DEGREE*BIT_WIDTH{1'b0}};
            coeff_n_terms_rows = {NUM_ROWS*DEGREE*BIT_WIDTH{1'b0}};
            bias_p_rows = {NUM_ROWS*BIAS_WIDTH{1'b0}};
            bias_n_rows = {NUM_ROWS*BIAS_WIDTH{1'b0}};

            coeff_p_terms_rows[0*DEGREE*BIT_WIDTH +: DEGREE*BIT_WIDTH] = {8'd2, 8'd0, 8'd7, 8'd9};
            coeff_n_terms_rows[0*DEGREE*BIT_WIDTH +: DEGREE*BIT_WIDTH] = {8'd0, 8'd3, 8'd0, 8'd0};
            bias_p_rows[0*BIAS_WIDTH +: BIAS_WIDTH] = 10'd5;
            bias_n_rows[0*BIAS_WIDTH +: BIAS_WIDTH] = 10'd1;

            coeff_p_terms_rows[1*DEGREE*BIT_WIDTH +: DEGREE*BIT_WIDTH] = {8'd0, 8'd4, 8'd0, 8'd6};
            coeff_n_terms_rows[1*DEGREE*BIT_WIDTH +: DEGREE*BIT_WIDTH] = {8'd5, 8'd0, 8'd2, 8'd0};
            bias_p_rows[1*BIAS_WIDTH +: BIAS_WIDTH] = 10'd0;
            bias_n_rows[1*BIAS_WIDTH +: BIAS_WIDTH] = 10'd9;
        end
    endtask

    task automatic configure_iter2;
        begin
            i_use_replay = 1'b1;
            src_row_idx = {NUM_ROWS*DEGREE{1'b0}};
            src_row_idx[0*DEGREE + 0] = 1'b0;
            src_row_idx[0*DEGREE + 1] = 1'b1;
            src_row_idx[1*DEGREE + 0] = 1'b0;
            src_row_idx[1*DEGREE + 1] = 1'b1;

            coeff_p_terms_rows = {NUM_ROWS*DEGREE*BIT_WIDTH{1'b0}};
            coeff_n_terms_rows = {NUM_ROWS*DEGREE*BIT_WIDTH{1'b0}};
            bias_p_rows = {NUM_ROWS*BIAS_WIDTH{1'b0}};
            bias_n_rows = {NUM_ROWS*BIAS_WIDTH{1'b0}};
            coeff_p_terms_rows[0*DEGREE*BIT_WIDTH +: DEGREE*BIT_WIDTH] = {8'd0, 8'd0, 8'd3, 8'd2};
            coeff_p_terms_rows[1*DEGREE*BIT_WIDTH +: DEGREE*BIT_WIDTH] = {8'd0, 8'd0, 8'd0, 8'd3};
            coeff_n_terms_rows[1*DEGREE*BIT_WIDTH +: DEGREE*BIT_WIDTH] = {8'd0, 8'd0, 8'd2, 8'd0};
        end
    endtask

    task automatic set_iter1_digits;
        input integer bit_index;
        begin
            ext_x0_p_rows = {NUM_ROWS{1'b0}};
            ext_x0_n_rows = {NUM_ROWS{1'b0}};
            ext_x1_p_rows = {NUM_ROWS{1'b0}};
            ext_x1_n_rows = {NUM_ROWS{1'b0}};
            ext_x2_p_rows = {NUM_ROWS{1'b0}};
            ext_x2_n_rows = {NUM_ROWS{1'b0}};
            ext_x3_p_rows = {NUM_ROWS{1'b0}};
            ext_x3_n_rows = {NUM_ROWS{1'b0}};
            ref_state_digit_p_terms_rows = {NUM_ROWS*DEGREE{1'b0}};
            ref_state_digit_n_terms_rows = {NUM_ROWS*DEGREE{1'b0}};

            ext_x0_p_rows[0] = row0_state0_p[bit_index];
            ext_x0_n_rows[0] = row0_state0_n[bit_index];
            ext_x1_p_rows[0] = row0_state1_p[bit_index];
            ext_x2_n_rows[0] = row0_state2_n[bit_index];
            ext_x3_p_rows[0] = row0_state3_p[bit_index];

            ext_x0_n_rows[1] = row1_state0_n[bit_index];
            ext_x1_p_rows[1] = row1_state1_p[bit_index];
            ext_x2_p_rows[1] = row1_state2_p[bit_index];
            ext_x2_n_rows[1] = row1_state2_n[bit_index];
            ext_x3_p_rows[1] = row1_state3_p[bit_index];

            ref_state_digit_p_terms_rows[0*DEGREE + 0] = ext_x0_p_rows[0];
            ref_state_digit_n_terms_rows[0*DEGREE + 0] = ext_x0_n_rows[0];
            ref_state_digit_p_terms_rows[0*DEGREE + 1] = ext_x1_p_rows[0];
            ref_state_digit_n_terms_rows[0*DEGREE + 1] = ext_x1_n_rows[0];
            ref_state_digit_p_terms_rows[0*DEGREE + 2] = ext_x2_p_rows[0];
            ref_state_digit_n_terms_rows[0*DEGREE + 2] = ext_x2_n_rows[0];
            ref_state_digit_p_terms_rows[0*DEGREE + 3] = ext_x3_p_rows[0];
            ref_state_digit_n_terms_rows[0*DEGREE + 3] = ext_x3_n_rows[0];

            ref_state_digit_p_terms_rows[1*DEGREE + 0] = ext_x0_p_rows[1];
            ref_state_digit_n_terms_rows[1*DEGREE + 0] = ext_x0_n_rows[1];
            ref_state_digit_p_terms_rows[1*DEGREE + 1] = ext_x1_p_rows[1];
            ref_state_digit_n_terms_rows[1*DEGREE + 1] = ext_x1_n_rows[1];
            ref_state_digit_p_terms_rows[1*DEGREE + 2] = ext_x2_p_rows[1];
            ref_state_digit_n_terms_rows[1*DEGREE + 2] = ext_x2_n_rows[1];
            ref_state_digit_p_terms_rows[1*DEGREE + 3] = ext_x3_p_rows[1];
            ref_state_digit_n_terms_rows[1*DEGREE + 3] = ext_x3_n_rows[1];
        end
    endtask

    task automatic set_iter2_ref_digits;
        begin
            ref_state_digit_p_terms_rows = {NUM_ROWS*DEGREE{1'b0}};
            ref_state_digit_n_terms_rows = {NUM_ROWS*DEGREE{1'b0}};
            ref_state_digit_p_terms_rows[0*DEGREE + 0] = replay_x0_p_rows[0];
            ref_state_digit_n_terms_rows[0*DEGREE + 0] = replay_x0_n_rows[0];
            ref_state_digit_p_terms_rows[0*DEGREE + 1] = replay_x1_p_rows[0];
            ref_state_digit_n_terms_rows[0*DEGREE + 1] = replay_x1_n_rows[0];
            ref_state_digit_p_terms_rows[1*DEGREE + 0] = replay_x0_p_rows[1];
            ref_state_digit_n_terms_rows[1*DEGREE + 0] = replay_x0_n_rows[1];
            ref_state_digit_p_terms_rows[1*DEGREE + 1] = replay_x1_p_rows[1];
            ref_state_digit_n_terms_rows[1*DEGREE + 1] = replay_x1_n_rows[1];
        end
    endtask

    task automatic pulse_clear;
        begin
            @(negedge i_clk);
            i_clear_write_bank = 1'b1;
            @(negedge i_clk);
            i_clear_write_bank = 1'b0;
        end
    endtask

    task automatic commit_swap;
        begin
            @(negedge i_clk);
            i_commit_swap = 1'b1;
            @(negedge i_clk);
            i_commit_swap = 1'b0;
        end
    endtask

    task automatic drain_and_check;
        input signed [ACC_WIDTH-1:0] exp0;
        input signed [ACC_WIDTH-1:0] exp1;
        begin
            i_start = 1'b0;
            i_valid_digit = 1'b0;
            i_last_digit = 1'b0;
            i_digit_idx = DATA_WIDTH - 1;
            ref_state_digit_p_terms_rows = {NUM_ROWS*DEGREE{1'b0}};
            ref_state_digit_n_terms_rows = {NUM_ROWS*DEGREE{1'b0}};
            ext_x0_p_rows = {NUM_ROWS{1'b0}};
            ext_x0_n_rows = {NUM_ROWS{1'b0}};
            ext_x1_p_rows = {NUM_ROWS{1'b0}};
            ext_x1_n_rows = {NUM_ROWS{1'b0}};
            ext_x2_p_rows = {NUM_ROWS{1'b0}};
            ext_x2_n_rows = {NUM_ROWS{1'b0}};
            ext_x3_p_rows = {NUM_ROWS{1'b0}};
            ext_x3_n_rows = {NUM_ROWS{1'b0}};
            bias_p_rows = {NUM_ROWS*BIAS_WIDTH{1'b0}};
            bias_n_rows = {NUM_ROWS*BIAS_WIDTH{1'b0}};

            wait_count = 0;
            while ((!(full_seen0 && full_seen1) || !(write_done_rows[0] && write_done_rows[1])) &&
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

            if (full_sum_seen0 !== exp0 || full_sum_seen1 !== exp1 ||
                !write_done_rows[0] || !write_done_rows[1]) begin
                $display("ERROR drain got0=%0d exp0=%0d got1=%0d exp1=%0d done=%b",
                    full_sum_seen0, exp0, full_sum_seen1, exp1, write_done_rows);
                $fatal;
            end
        end
    endtask

    task automatic run_iter1;
        begin
            configure_iter1();
            full_seen0 = 1'b0;
            full_seen1 = 1'b0;
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
            drain_and_check(32'sd170, -32'sd92);
            commit_swap();
        end
    endtask

    task automatic run_iter2;
        begin
            configure_iter2();
            full_seen0 = 1'b0;
            full_seen1 = 1'b0;
            for (di = 0; di < DATA_WIDTH; di = di + 1) begin
                i_digit_idx = di[DIGIT_IDX_WIDTH-1:0];
                #1;
                i_start = (di == 0);
                i_valid_digit = 1'b1;
                i_last_digit = (di == DATA_WIDTH - 1);
                set_iter2_ref_digits();
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
            drain_and_check(32'sd64, 32'sd694);
            commit_swap();
        end
    endtask

    task automatic reconstruct_self_replay;
        begin
            src_row_idx = {NUM_ROWS*DEGREE{1'b0}};
            src_row_idx[0*DEGREE + 0] = 1'b0;
            src_row_idx[1*DEGREE + 0] = 1'b1;
            i_use_replay = 1'b1;
            replay_sum0 = 32'sd0;
            replay_sum1 = 32'sd0;
            for (di = 0; di < DATA_WIDTH; di = di + 1) begin
                i_digit_idx = di[DIGIT_IDX_WIDTH-1:0];
                #1;
                replay_sum0 = replay_sum0 <<< 1;
                replay_sum1 = replay_sum1 <<< 1;
                if (replay_x0_p_rows[0] && !replay_x0_n_rows[0]) begin
                    replay_sum0 = replay_sum0 + 1;
                end else if (!replay_x0_p_rows[0] && replay_x0_n_rows[0]) begin
                    replay_sum0 = replay_sum0 - 1;
                end
                if (replay_x0_p_rows[1] && !replay_x0_n_rows[1]) begin
                    replay_sum1 = replay_sum1 + 1;
                end else if (!replay_x0_p_rows[1] && replay_x0_n_rows[1]) begin
                    replay_sum1 = replay_sum1 - 1;
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
        i_ena_rows = {NUM_ROWS{1'b1}};
        i_digit_idx = {DIGIT_IDX_WIDTH{1'b0}};
        i_use_replay = 1'b0;
        i_clear_write_bank = 1'b0;
        i_commit_swap = 1'b0;
        src_row_idx = {NUM_ROWS*DEGREE{1'b0}};
        ext_x0_p_rows = {NUM_ROWS{1'b0}};
        ext_x0_n_rows = {NUM_ROWS{1'b0}};
        ext_x1_p_rows = {NUM_ROWS{1'b0}};
        ext_x1_n_rows = {NUM_ROWS{1'b0}};
        ext_x2_p_rows = {NUM_ROWS{1'b0}};
        ext_x2_n_rows = {NUM_ROWS{1'b0}};
        ext_x3_p_rows = {NUM_ROWS{1'b0}};
        ext_x3_n_rows = {NUM_ROWS{1'b0}};
        coeff_p_terms_rows = {NUM_ROWS*DEGREE*BIT_WIDTH{1'b0}};
        coeff_n_terms_rows = {NUM_ROWS*DEGREE*BIT_WIDTH{1'b0}};
        bias_p_rows = {NUM_ROWS*BIAS_WIDTH{1'b0}};
        bias_n_rows = {NUM_ROWS*BIAS_WIDTH{1'b0}};
        ref_state_digit_p_terms_rows = {NUM_ROWS*DEGREE{1'b0}};
        ref_state_digit_n_terms_rows = {NUM_ROWS*DEGREE{1'b0}};
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

        pulse_clear();
        run_iter1();
        pulse_clear();
        run_iter2();
        reconstruct_self_replay();

        if (replay_sum0 !== 32'sd64 || replay_sum1 !== 32'sd694) begin
            $display("ERROR cluster shell final row0=%0d row1=%0d p=%h n=%h",
                replay_sum0, replay_sum1, read_state_p_rows, read_state_n_rows);
            $fatal;
        end

        $display("PASS tb_iter_solver_native_cluster_digit_stream_top iter1=(170,-92) scaled_iter2=(%0d,%0d)",
            replay_sum0, replay_sum1);
        $finish;
    end
endmodule
