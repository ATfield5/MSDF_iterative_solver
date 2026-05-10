`timescale 1ns / 1ps

module tb_iter_wavefront_radius1_commit_multistage_cluster;
    parameter integer NUM_STAGES = 4;
    parameter integer NUM_ROWS = 3;
    parameter integer DEGREE = 4;
    parameter integer BIT_WIDTH = 5;
    parameter integer DATA_WIDTH = 8;
    parameter integer SKIP_DIGITS = 4;
    parameter integer INTER_STAGE_DELAY_CYCLES = 0;
    localparam integer BIAS_WIDTH = BIT_WIDTH + 2;
    localparam integer DIGIT_IDX_WIDTH = $clog2(DATA_WIDTH);
    localparam integer ROW_IDX_WIDTH = (NUM_ROWS <= 2) ? 1 : $clog2(NUM_ROWS);

    reg i_clk;
    reg i_rst;
    reg i_start;
    reg i_valid_digit;
    reg [DIGIT_IDX_WIDTH - 1 : 0] i_digit_idx;
    reg [NUM_ROWS * DEGREE - 1 : 0] i_stage0_state_digit_p_terms_rows;
    reg [NUM_ROWS * DEGREE - 1 : 0] i_stage0_state_digit_n_terms_rows;
    reg [NUM_STAGES * NUM_ROWS * DEGREE * BIT_WIDTH - 1 : 0] i_coeff_p_terms_stages;
    reg [NUM_STAGES * NUM_ROWS * DEGREE * BIT_WIDTH - 1 : 0] i_coeff_n_terms_stages;
    reg [NUM_STAGES * NUM_ROWS * BIAS_WIDTH - 1 : 0] i_bias_p_stages;
    reg [NUM_STAGES * NUM_ROWS * BIAS_WIDTH - 1 : 0] i_bias_n_stages;

    wire [NUM_STAGES * NUM_ROWS - 1 : 0] w_stage_commit_valid_rows;
    wire [NUM_STAGES * NUM_ROWS * DIGIT_IDX_WIDTH - 1 : 0] w_stage_commit_digit_idx_rows;
    wire [NUM_STAGES * NUM_ROWS - 1 : 0] w_stage_commit_digit_p_rows;
    wire [NUM_STAGES * NUM_ROWS - 1 : 0] w_stage_commit_digit_n_rows;
    wire [NUM_STAGES * NUM_ROWS - 1 : 0] w_stage_commit_done_rows;
    wire [NUM_ROWS - 1 : 0] w_final_valid_rows;
    wire [NUM_ROWS * DIGIT_IDX_WIDTH - 1 : 0] w_final_digit_idx_rows;
    wire [NUM_ROWS - 1 : 0] w_final_digit_p_rows;
    wire [NUM_ROWS - 1 : 0] w_final_digit_n_rows;
    wire [NUM_STAGES * 32 - 1 : 0] w_stage_valid_count;
    wire [NUM_STAGES - 1 : 0] w_stage_done;
    wire [NUM_STAGES - 2 : 0] w_stage_started_before_prev_done;

    reg ref_rst;
    reg ref_clear;
    reg ref_start;
    reg ref_valid_digit;
    reg [DIGIT_IDX_WIDTH - 1 : 0] ref_digit_idx;
    reg [NUM_ROWS * DEGREE - 1 : 0] ref_state_digit_p_terms_rows;
    reg [NUM_ROWS * DEGREE - 1 : 0] ref_state_digit_n_terms_rows;
    reg [NUM_ROWS * DEGREE * BIT_WIDTH - 1 : 0] ref_coeff_p_terms_rows;
    reg [NUM_ROWS * DEGREE * BIT_WIDTH - 1 : 0] ref_coeff_n_terms_rows;
    reg [NUM_ROWS * BIAS_WIDTH - 1 : 0] ref_bias_p_rows;
    reg [NUM_ROWS * BIAS_WIDTH - 1 : 0] ref_bias_n_rows;
    wire [NUM_ROWS - 1 : 0] ref_commit_valid_rows;
    wire [NUM_ROWS * DIGIT_IDX_WIDTH - 1 : 0] ref_commit_digit_idx_rows;
    wire [NUM_ROWS - 1 : 0] ref_commit_digit_p_rows;
    wire [NUM_ROWS - 1 : 0] ref_commit_digit_n_rows;

    reg [NUM_ROWS * DATA_WIDTH - 1 : 0] captured_wavefront_final_p_rows;
    reg [NUM_ROWS * DATA_WIDTH - 1 : 0] captured_wavefront_final_n_rows;
    reg [NUM_ROWS * DATA_WIDTH - 1 : 0] captured_ref_prev_p_rows;
    reg [NUM_ROWS * DATA_WIDTH - 1 : 0] captured_ref_prev_n_rows;
    reg [NUM_ROWS * DATA_WIDTH - 1 : 0] captured_ref_curr_p_rows;
    reg [NUM_ROWS * DATA_WIDTH - 1 : 0] captured_ref_curr_n_rows;
    reg [31 : 0] wavefront_capture_count;
    reg [31 : 0] ref_capture_count;
    reg [31 : 0] cycle_count;
    reg [31 : 0] wavefront_done_cycle;
    reg [31 : 0] ref_elapsed_cycle;
    reg wavefront_done_seen;

    integer stage;
    integer di;
    integer ri;
    integer term;
    integer wait_count;
    integer fullwait_done_cycle;

    iter_wavefront_radius1_commit_multistage_cluster #(
        .num_stages(NUM_STAGES),
        .num_rows(NUM_ROWS),
        .degree(DEGREE),
        .bit_width(BIT_WIDTH),
        .data_width(DATA_WIDTH),
        .bias_width(BIAS_WIDTH),
        .skip_digits(SKIP_DIGITS),
        .inter_stage_delay_cycles(INTER_STAGE_DELAY_CYCLES)
    ) dut (
        .i_clk(i_clk),
        .i_rst(i_rst),
        .i_start(i_start),
        .i_valid_digit(i_valid_digit),
        .i_digit_idx(i_digit_idx),
        .i_stage0_state_digit_p_terms_rows(i_stage0_state_digit_p_terms_rows),
        .i_stage0_state_digit_n_terms_rows(i_stage0_state_digit_n_terms_rows),
        .i_coeff_p_terms_stages(i_coeff_p_terms_stages),
        .i_coeff_n_terms_stages(i_coeff_n_terms_stages),
        .i_bias_p_stages(i_bias_p_stages),
        .i_bias_n_stages(i_bias_n_stages),
        .i_stage_src_row_idx({NUM_ROWS * DEGREE * ROW_IDX_WIDTH{1'b0}}),
        .i_external_stage_source_p_rows({NUM_STAGES * NUM_ROWS{1'b0}}),
        .i_external_stage_source_n_rows({NUM_STAGES * NUM_ROWS{1'b0}}),
        .o_stage_commit_valid_rows(w_stage_commit_valid_rows),
        .o_stage_commit_digit_idx_rows(w_stage_commit_digit_idx_rows),
        .o_stage_commit_digit_p_rows(w_stage_commit_digit_p_rows),
        .o_stage_commit_digit_n_rows(w_stage_commit_digit_n_rows),
        .o_stage_commit_done_rows(w_stage_commit_done_rows),
        .o_final_valid_rows(w_final_valid_rows),
        .o_final_digit_idx_rows(w_final_digit_idx_rows),
        .o_final_digit_p_rows(w_final_digit_p_rows),
        .o_final_digit_n_rows(w_final_digit_n_rows),
        .o_stage_valid_count(w_stage_valid_count),
        .o_stage_done(w_stage_done),
        .o_stage_started_before_prev_done(w_stage_started_before_prev_done)
    );

    iter_wavefront_commit_stage_cluster #(
        .num_rows(NUM_ROWS),
        .degree(DEGREE),
        .bit_width(BIT_WIDTH),
        .data_width(DATA_WIDTH),
        .bias_width(BIAS_WIDTH),
        .skip_digits(SKIP_DIGITS)
    ) ref_stage (
        .i_clk(i_clk),
        .i_rst(ref_rst),
        .i_clear(ref_clear),
        .i_start(ref_start),
        .i_valid_digit(ref_valid_digit),
        .i_digit_idx(ref_digit_idx),
        .i_state_digit_p_terms_rows(ref_state_digit_p_terms_rows),
        .i_state_digit_n_terms_rows(ref_state_digit_n_terms_rows),
        .i_coeff_p_terms_rows(ref_coeff_p_terms_rows),
        .i_coeff_n_terms_rows(ref_coeff_n_terms_rows),
        .i_bias_p_rows(ref_bias_p_rows),
        .i_bias_n_rows(ref_bias_n_rows),
        .o_raw_valid_rows(),
        .o_raw_digit_p_rows(),
        .o_raw_digit_n_rows(),
        .o_commit_valid_rows(ref_commit_valid_rows),
        .o_commit_digit_idx_rows(ref_commit_digit_idx_rows),
        .o_commit_digit_p_rows(ref_commit_digit_p_rows),
        .o_commit_digit_n_rows(ref_commit_digit_n_rows),
        .o_commit_done_rows()
    );

    always #5 i_clk = ~i_clk;

    task set_coeff;
        input integer stage_idx;
        input integer row;
        input integer term_idx;
        input integer val;
        integer base;
        integer magnitude;
        begin
            base = (((stage_idx * NUM_ROWS + row) * DEGREE + term_idx) * BIT_WIDTH);
            magnitude = (val >= 0) ? val : -val;
            if (val >= 0) begin
                i_coeff_p_terms_stages[base +: BIT_WIDTH] = magnitude[BIT_WIDTH - 1 : 0];
                i_coeff_n_terms_stages[base +: BIT_WIDTH] = {BIT_WIDTH{1'b0}};
            end else begin
                i_coeff_p_terms_stages[base +: BIT_WIDTH] = {BIT_WIDTH{1'b0}};
                i_coeff_n_terms_stages[base +: BIT_WIDTH] = magnitude[BIT_WIDTH - 1 : 0];
            end
        end
    endtask

    task set_bias;
        input integer stage_idx;
        input integer row;
        input integer val;
        integer base;
        integer magnitude;
        begin
            base = (stage_idx * NUM_ROWS + row) * BIAS_WIDTH;
            magnitude = (val >= 0) ? val : -val;
            if (val >= 0) begin
                i_bias_p_stages[base +: BIAS_WIDTH] = magnitude[BIAS_WIDTH - 1 : 0];
                i_bias_n_stages[base +: BIAS_WIDTH] = {BIAS_WIDTH{1'b0}};
            end else begin
                i_bias_p_stages[base +: BIAS_WIDTH] = {BIAS_WIDTH{1'b0}};
                i_bias_n_stages[base +: BIAS_WIDTH] = magnitude[BIAS_WIDTH - 1 : 0];
            end
        end
    endtask

    task load_ref_stage;
        input integer stage_idx;
        begin
            for (ri = 0; ri < NUM_ROWS; ri = ri + 1) begin
                ref_coeff_p_terms_rows[ri * DEGREE * BIT_WIDTH +: DEGREE * BIT_WIDTH] =
                    i_coeff_p_terms_stages[(stage_idx * NUM_ROWS + ri) *
                        DEGREE * BIT_WIDTH +: DEGREE * BIT_WIDTH];
                ref_coeff_n_terms_rows[ri * DEGREE * BIT_WIDTH +: DEGREE * BIT_WIDTH] =
                    i_coeff_n_terms_stages[(stage_idx * NUM_ROWS + ri) *
                        DEGREE * BIT_WIDTH +: DEGREE * BIT_WIDTH];
                ref_bias_p_rows[ri * BIAS_WIDTH +: BIAS_WIDTH] =
                    i_bias_p_stages[(stage_idx * NUM_ROWS + ri) * BIAS_WIDTH +: BIAS_WIDTH];
                ref_bias_n_rows[ri * BIAS_WIDTH +: BIAS_WIDTH] =
                    i_bias_n_stages[(stage_idx * NUM_ROWS + ri) * BIAS_WIDTH +: BIAS_WIDTH];
            end
        end
    endtask

    task set_stage0_source_digits;
        input integer digit_idx;
        integer row;
        begin
            i_stage0_state_digit_p_terms_rows = {NUM_ROWS * DEGREE{1'b0}};
            i_stage0_state_digit_n_terms_rows = {NUM_ROWS * DEGREE{1'b0}};
            for (row = 0; row < NUM_ROWS; row = row + 1) begin
                i_stage0_state_digit_p_terms_rows[row * DEGREE + 0] =
                    ((digit_idx + row) % 2 == 0);
                i_stage0_state_digit_p_terms_rows[row * DEGREE + 1] =
                    ((digit_idx & 3) == row);
                i_stage0_state_digit_n_terms_rows[row * DEGREE + 2] =
                    ((digit_idx % 3) == (row % 3));
                i_stage0_state_digit_p_terms_rows[row * DEGREE + 3] =
                    (digit_idx == (DATA_WIDTH - 1 - row));
            end
        end
    endtask

    task set_ref_source_digits;
        input integer stage_idx;
        input integer digit_idx;
        integer row;
        begin
            ref_state_digit_p_terms_rows = {NUM_ROWS * DEGREE{1'b0}};
            ref_state_digit_n_terms_rows = {NUM_ROWS * DEGREE{1'b0}};
            if (stage_idx == 0) begin
                for (row = 0; row < NUM_ROWS; row = row + 1) begin
                    ref_state_digit_p_terms_rows[row * DEGREE + 0] =
                        ((digit_idx + row) % 2 == 0);
                    ref_state_digit_p_terms_rows[row * DEGREE + 1] =
                        ((digit_idx & 3) == row);
                    ref_state_digit_n_terms_rows[row * DEGREE + 2] =
                        ((digit_idx % 3) == (row % 3));
                    ref_state_digit_p_terms_rows[row * DEGREE + 3] =
                        (digit_idx == (DATA_WIDTH - 1 - row));
                end
            end else begin
                for (row = 0; row < NUM_ROWS; row = row + 1) begin
                    if (row > 0) begin
                        ref_state_digit_p_terms_rows[row * DEGREE + 0] =
                            captured_ref_prev_p_rows[(row - 1) * DATA_WIDTH + digit_idx];
                        ref_state_digit_n_terms_rows[row * DEGREE + 0] =
                            captured_ref_prev_n_rows[(row - 1) * DATA_WIDTH + digit_idx];
                    end
                    ref_state_digit_p_terms_rows[row * DEGREE + 1] =
                        captured_ref_prev_p_rows[row * DATA_WIDTH + digit_idx];
                    ref_state_digit_n_terms_rows[row * DEGREE + 1] =
                        captured_ref_prev_n_rows[row * DATA_WIDTH + digit_idx];
                    if (row < NUM_ROWS - 1) begin
                        ref_state_digit_p_terms_rows[row * DEGREE + 2] =
                            captured_ref_prev_p_rows[(row + 1) * DATA_WIDTH + digit_idx];
                        ref_state_digit_n_terms_rows[row * DEGREE + 2] =
                            captured_ref_prev_n_rows[(row + 1) * DATA_WIDTH + digit_idx];
                    end
                end
            end
        end
    endtask

    always @(posedge i_clk) begin
        #1;
        if (i_rst || i_start) begin
            wavefront_capture_count = 32'd0;
            captured_wavefront_final_p_rows = {NUM_ROWS * DATA_WIDTH{1'b0}};
            captured_wavefront_final_n_rows = {NUM_ROWS * DATA_WIDTH{1'b0}};
            cycle_count = 32'd0;
            wavefront_done_cycle = 32'd0;
            wavefront_done_seen = 1'b0;
        end else begin
            cycle_count = cycle_count + 1'b1;
            if (w_final_valid_rows[0]) begin
                for (ri = 0; ri < NUM_ROWS; ri = ri + 1) begin
                    captured_wavefront_final_p_rows[ri * DATA_WIDTH +
                        w_final_digit_idx_rows[DIGIT_IDX_WIDTH - 1 : 0]] =
                        w_final_digit_p_rows[ri];
                    captured_wavefront_final_n_rows[ri * DATA_WIDTH +
                        w_final_digit_idx_rows[DIGIT_IDX_WIDTH - 1 : 0]] =
                        w_final_digit_n_rows[ri];
                end
                wavefront_capture_count = wavefront_capture_count + 1'b1;
            end
            if (!wavefront_done_seen && w_stage_done[NUM_STAGES - 1]) begin
                wavefront_done_seen = 1'b1;
                wavefront_done_cycle = cycle_count;
            end
        end
    end

    always @(posedge i_clk) begin
        #1;
        if (ref_rst || ref_clear) begin
            ref_capture_count = 32'd0;
            captured_ref_curr_p_rows = {NUM_ROWS * DATA_WIDTH{1'b0}};
            captured_ref_curr_n_rows = {NUM_ROWS * DATA_WIDTH{1'b0}};
            ref_elapsed_cycle = 32'd0;
        end else begin
            ref_elapsed_cycle = ref_elapsed_cycle + 1'b1;
            if (ref_commit_valid_rows[0]) begin
                for (ri = 0; ri < NUM_ROWS; ri = ri + 1) begin
                    captured_ref_curr_p_rows[ri * DATA_WIDTH +
                        ref_commit_digit_idx_rows[DIGIT_IDX_WIDTH - 1 : 0]] =
                        ref_commit_digit_p_rows[ri];
                    captured_ref_curr_n_rows[ri * DATA_WIDTH +
                        ref_commit_digit_idx_rows[DIGIT_IDX_WIDTH - 1 : 0]] =
                        ref_commit_digit_n_rows[ri];
                end
                ref_capture_count = ref_capture_count + 1'b1;
            end
        end
    end

    initial begin
        i_clk = 1'b0;
        i_rst = 1'b1;
        i_start = 1'b0;
        i_valid_digit = 1'b0;
        i_digit_idx = {DIGIT_IDX_WIDTH{1'b0}};
        i_stage0_state_digit_p_terms_rows = {NUM_ROWS * DEGREE{1'b0}};
        i_stage0_state_digit_n_terms_rows = {NUM_ROWS * DEGREE{1'b0}};
        i_coeff_p_terms_stages = {NUM_STAGES * NUM_ROWS * DEGREE * BIT_WIDTH{1'b0}};
        i_coeff_n_terms_stages = {NUM_STAGES * NUM_ROWS * DEGREE * BIT_WIDTH{1'b0}};
        i_bias_p_stages = {NUM_STAGES * NUM_ROWS * BIAS_WIDTH{1'b0}};
        i_bias_n_stages = {NUM_STAGES * NUM_ROWS * BIAS_WIDTH{1'b0}};
        ref_rst = 1'b1;
        ref_clear = 1'b0;
        ref_start = 1'b0;
        ref_valid_digit = 1'b0;
        ref_digit_idx = {DIGIT_IDX_WIDTH{1'b0}};
        ref_state_digit_p_terms_rows = {NUM_ROWS * DEGREE{1'b0}};
        ref_state_digit_n_terms_rows = {NUM_ROWS * DEGREE{1'b0}};
        ref_coeff_p_terms_rows = {NUM_ROWS * DEGREE * BIT_WIDTH{1'b0}};
        ref_coeff_n_terms_rows = {NUM_ROWS * DEGREE * BIT_WIDTH{1'b0}};
        ref_bias_p_rows = {NUM_ROWS * BIAS_WIDTH{1'b0}};
        ref_bias_n_rows = {NUM_ROWS * BIAS_WIDTH{1'b0}};
        captured_ref_prev_p_rows = {NUM_ROWS * DATA_WIDTH{1'b0}};
        captured_ref_prev_n_rows = {NUM_ROWS * DATA_WIDTH{1'b0}};
        fullwait_done_cycle = 0;

        for (stage = 0; stage < NUM_STAGES; stage = stage + 1) begin
            for (ri = 0; ri < NUM_ROWS; ri = ri + 1) begin
                for (term = 0; term < DEGREE; term = term + 1) begin
                    set_coeff(stage, ri, term, 0);
                end
                if (stage == 0) begin
                    set_coeff(stage, ri, 0, ri + 1);
                    set_coeff(stage, ri, 1, 2);
                    set_coeff(stage, ri, 2, 3);
                    set_coeff(stage, ri, 3, 1);
                end else begin
                    set_coeff(stage, ri, 0, 1);
                    set_coeff(stage, ri, 1, 2);
                    set_coeff(stage, ri, 2, 1);
                end
            end
        end
        set_bias(0, 0, 3);
        set_bias(0, 1, 1);
        set_bias(0, 2, -2);
        set_bias(2, 1, 1);

        repeat (2) @(posedge i_clk);
        i_rst = 1'b0;

        for (di = 0; di < DATA_WIDTH; di = di + 1) begin
            @(negedge i_clk);
            set_stage0_source_digits(di);
            i_start = (di == 0);
            i_valid_digit = 1'b1;
            i_digit_idx = di[DIGIT_IDX_WIDTH - 1 : 0];
        end

        @(negedge i_clk);
        i_start = 1'b0;
        i_valid_digit = 1'b0;
        i_stage0_state_digit_p_terms_rows = {NUM_ROWS * DEGREE{1'b0}};
        i_stage0_state_digit_n_terms_rows = {NUM_ROWS * DEGREE{1'b0}};

        wait_count = 0;
        while (!wavefront_done_seen && wait_count < 256) begin
            @(negedge i_clk);
            wait_count = wait_count + 1;
        end

        if (!wavefront_done_seen || wavefront_capture_count !== DATA_WIDTH) begin
            $display("ERROR commit wavefront lifecycle final_count=%0d done=%0d",
                wavefront_capture_count,
                wavefront_done_seen);
            $fatal;
        end
        if (w_stage_started_before_prev_done !== {(NUM_STAGES - 1){1'b1}}) begin
            $display("ERROR expected commit stages to start before previous done flags=%b",
                w_stage_started_before_prev_done);
            $fatal;
        end

        ref_rst = 1'b0;
        for (stage = 0; stage < NUM_STAGES; stage = stage + 1) begin
            load_ref_stage(stage);
            ref_clear = 1'b1;
            @(negedge i_clk);
            ref_clear = 1'b0;
            for (di = 0; di < DATA_WIDTH; di = di + 1) begin
                @(negedge i_clk);
                set_ref_source_digits(stage, di);
                ref_start = (di == 0);
                ref_valid_digit = 1'b1;
                ref_digit_idx = di[DIGIT_IDX_WIDTH - 1 : 0];
            end

            @(negedge i_clk);
            ref_start = 1'b0;
            ref_valid_digit = 1'b0;
            ref_state_digit_p_terms_rows = {NUM_ROWS * DEGREE{1'b0}};
            ref_state_digit_n_terms_rows = {NUM_ROWS * DEGREE{1'b0}};

            wait_count = 0;
            while (ref_capture_count < DATA_WIDTH && wait_count < 128) begin
                @(negedge i_clk);
                wait_count = wait_count + 1;
            end

            if (ref_capture_count !== DATA_WIDTH) begin
                $display("ERROR commit fullwait reference stage=%0d count=%0d",
                    stage,
                    ref_capture_count);
                $fatal;
            end

            fullwait_done_cycle = fullwait_done_cycle + ref_elapsed_cycle;
            captured_ref_prev_p_rows = captured_ref_curr_p_rows;
            captured_ref_prev_n_rows = captured_ref_curr_n_rows;
        end

        if (captured_wavefront_final_p_rows !== captured_ref_prev_p_rows ||
            captured_wavefront_final_n_rows !== captured_ref_prev_n_rows) begin
            $display("ERROR commit wavefront/reference mismatch wf=%h/%h ref=%h/%h",
                captured_wavefront_final_p_rows,
                captured_wavefront_final_n_rows,
                captured_ref_prev_p_rows,
                captured_ref_prev_n_rows);
            $fatal;
        end

        if (wavefront_done_cycle >= fullwait_done_cycle) begin
            $display("ERROR expected commit wavefront faster wavefront=%0d fullwait=%0d",
                wavefront_done_cycle,
                fullwait_done_cycle);
            $fatal;
        end

        $display("PASS tb_iter_wavefront_radius1_commit_multistage_cluster");
        $display("INFO commit stages=%0d skip=%0d delay=%0d wavefront_done_cycle=%0d fullwait_model_cycle=%0d saved_cycles=%0d",
            NUM_STAGES,
            SKIP_DIGITS,
            INTER_STAGE_DELAY_CYCLES,
            wavefront_done_cycle,
            fullwait_done_cycle,
            fullwait_done_cycle - wavefront_done_cycle);
        $finish;
    end
endmodule
