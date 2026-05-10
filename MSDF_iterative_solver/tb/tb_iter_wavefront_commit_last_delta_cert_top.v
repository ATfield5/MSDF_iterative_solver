`timescale 1ns / 1ps

module tb_iter_wavefront_commit_last_delta_cert_top;
    localparam integer NUM_STAGES = 4;
    localparam integer NUM_ROWS = 1;
    localparam integer DEGREE = 4;
    localparam integer BIT_WIDTH = 5;
    localparam integer DATA_WIDTH = 8;
    localparam integer SKIP_DIGITS = 4;
    localparam integer BIAS_WIDTH = BIT_WIDTH + 2;
    localparam integer BOUND_WIDTH = BIT_WIDTH + 5;
    localparam integer COEFF_WIDTH = 8;
    localparam integer ACC_WIDTH = 24;
    localparam integer BLOCK_SIZE = 1;
    localparam integer NUM_BLOCKS = 1;
    localparam integer DIGIT_IDX_WIDTH = $clog2(DATA_WIDTH);

`include "iter_tb_signed_digit_reconstruct.vh"

    function automatic signed [31:0] direct_idx_signed_digit_value;
        input [DATA_WIDTH - 1 : 0] word_p;
        input [DATA_WIDTH - 1 : 0] word_n;
        integer idx;
        reg signed [31:0] value;
        begin
            value = 32'sd0;
            for (idx = 0; idx < DATA_WIDTH; idx = idx + 1) begin
                value = value <<< 1;
                if (word_p[idx] && !word_n[idx]) begin
                    value = value + 1;
                end else if (!word_p[idx] && word_n[idx]) begin
                    value = value - 1;
                end
            end
            direct_idx_signed_digit_value = value;
        end
    endfunction

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
    reg [NUM_ROWS * NUM_BLOCKS * COEFF_WIDTH - 1 : 0] i_block_weights;
    reg [ACC_WIDTH - 1 : 0] i_eta;
    reg [BOUND_WIDTH - 1 : 0] i_tail_bound;

    wire [NUM_ROWS - 1 : 0] w_final_valid_rows;
    wire [NUM_ROWS * DIGIT_IDX_WIDTH - 1 : 0] w_final_digit_idx_rows;
    wire [NUM_ROWS - 1 : 0] w_final_digit_p_rows;
    wire [NUM_ROWS - 1 : 0] w_final_digit_n_rows;
    wire [NUM_ROWS * BOUND_WIDTH - 1 : 0] w_abs_upper_rows;
    wire w_cluster_valid;
    wire w_cluster_certified;
    wire [ACC_WIDTH - 1 : 0] w_cluster_max_error;
    wire [NUM_STAGES - 1 : 0] w_stage_done;

    reg [DATA_WIDTH - 1 : 0] captured_final_p;
    reg [DATA_WIDTH - 1 : 0] captured_final_n;
    reg cert_seen;
    reg [ACC_WIDTH - 1 : 0] captured_max_error;
    reg captured_certified;
    integer di;
    integer wait_count;
    integer stage;
    integer term;
    integer final_value;
    integer prev_value;
    integer expected_abs;

    iter_wavefront_commit_last_delta_cert_top #(
        .num_stages(NUM_STAGES),
        .num_rows(NUM_ROWS),
        .degree(DEGREE),
        .bit_width(BIT_WIDTH),
        .data_width(DATA_WIDTH),
        .bias_width(BIAS_WIDTH),
        .bound_width(BOUND_WIDTH),
        .coeff_width(COEFF_WIDTH),
        .acc_width(ACC_WIDTH),
        .block_size(BLOCK_SIZE),
        .num_blocks(NUM_BLOCKS),
        .skip_digits(SKIP_DIGITS)
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
        .i_stage_src_row_idx({NUM_ROWS * DEGREE{1'b0}}),
        .i_external_stage_source_p_rows({NUM_STAGES * NUM_ROWS{1'b0}}),
        .i_external_stage_source_n_rows({NUM_STAGES * NUM_ROWS{1'b0}}),
        .i_block_weights(i_block_weights),
        .i_eta(i_eta),
        .i_tail_bound(i_tail_bound),
        .o_final_valid_rows(w_final_valid_rows),
        .o_final_digit_idx_rows(w_final_digit_idx_rows),
        .o_final_digit_p_rows(w_final_digit_p_rows),
        .o_final_digit_n_rows(w_final_digit_n_rows),
        .o_abs_upper_rows(w_abs_upper_rows),
        .o_block_bounds(),
        .o_cluster_valid(w_cluster_valid),
        .o_cluster_certified(w_cluster_certified),
        .o_cluster_max_error(w_cluster_max_error),
        .o_stage_commit_valid_rows(),
        .o_stage_commit_digit_idx_rows(),
        .o_stage_commit_digit_p_rows(),
        .o_stage_commit_digit_n_rows(),
        .o_stage_valid_count(),
        .o_stage_done(w_stage_done),
        .o_stage_started_before_prev_done()
    );

    always #5 i_clk = ~i_clk;

    task set_coeff;
        input integer stage_idx;
        input integer term_idx;
        input integer val;
        integer base;
        begin
            base = ((stage_idx * DEGREE + term_idx) * BIT_WIDTH);
            i_coeff_p_terms_stages[base +: BIT_WIDTH] = val[BIT_WIDTH - 1 : 0];
        end
    endtask

    task set_stage0_source_digits;
        input integer digit_idx;
        begin
            i_stage0_state_digit_p_terms_rows = {NUM_ROWS * DEGREE{1'b0}};
            i_stage0_state_digit_n_terms_rows = {NUM_ROWS * DEGREE{1'b0}};
            i_stage0_state_digit_p_terms_rows[0] =
                (digit_idx == 1 || digit_idx == 3 || digit_idx == 6);
            i_stage0_state_digit_n_terms_rows[0] =
                (digit_idx == 5);
        end
    endtask

    always @(posedge i_clk) begin
        #1;
        if (i_rst || i_start) begin
            captured_final_p = {DATA_WIDTH{1'b0}};
            captured_final_n = {DATA_WIDTH{1'b0}};
            cert_seen = 1'b0;
            captured_max_error = {ACC_WIDTH{1'b0}};
            captured_certified = 1'b0;
        end else begin
            if (w_final_valid_rows[0]) begin
                captured_final_p[w_final_digit_idx_rows[DIGIT_IDX_WIDTH - 1 : 0]] =
                    w_final_digit_p_rows[0];
                captured_final_n[w_final_digit_idx_rows[DIGIT_IDX_WIDTH - 1 : 0]] =
                    w_final_digit_n_rows[0];
            end
            if (w_cluster_valid) begin
                cert_seen = 1'b1;
                captured_max_error = w_cluster_max_error;
                captured_certified = w_cluster_certified;
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
        i_block_weights = 8'd1;
        i_eta = 24'hffffff;
        i_tail_bound = {BOUND_WIDTH{1'b0}};

        for (stage = 0; stage < NUM_STAGES; stage = stage + 1) begin
            for (term = 0; term < DEGREE; term = term + 1) begin
                set_coeff(stage, term, 0);
            end
            if (stage == 0) begin
                set_coeff(stage, 0, 1);
            end else begin
                set_coeff(stage, 1, 1);
            end
        end

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
        while ((!cert_seen || !w_stage_done[NUM_STAGES - 1]) && wait_count < 256) begin
            @(negedge i_clk);
            wait_count = wait_count + 1;
        end

        if (!cert_seen || !w_stage_done[NUM_STAGES - 1]) begin
            $display("ERROR last-delta cert did not finish cert=%0d done=%b",
                cert_seen,
                w_stage_done);
            $fatal;
        end

        final_value = direct_idx_signed_digit_value(captured_final_p, captured_final_n);
        prev_value = direct_idx_signed_digit_value(dut.r_prev_stage_p_rows, dut.r_prev_stage_n_rows);
        expected_abs = final_value - prev_value;
        if (expected_abs < 0) begin
            expected_abs = -expected_abs;
        end

        if (captured_max_error !== expected_abs[ACC_WIDTH - 1 : 0] ||
            !captured_certified) begin
            $display("ERROR last-delta cert max_error=%0d expected=%0d cert=%0d final=%0d prev=%0d",
                captured_max_error,
                expected_abs,
                captured_certified,
                final_value,
                prev_value);
            $fatal;
        end

        $display("PASS tb_iter_wavefront_commit_last_delta_cert_top final=%0d prev=%0d max_error=%0d",
            final_value,
            prev_value,
            captured_max_error);
        $finish;
    end
endmodule
