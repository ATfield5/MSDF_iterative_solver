`timescale 1ns / 1ps

// Inline delta/certification test for the solver-native cluster shell.
//
// Old state is preloaded as (5, 2).  The solver-native stream writes
// new state (7, -3).  The inline digit delta path must report max error 5:
//
//   |7 - 5| = 2
//   |-3 - 2| = 5

module tb_iter_solver_native_cluster_delta_cert_top;
    localparam integer NUM_ROWS = 2;
    localparam integer DEGREE = 4;
    localparam integer BIT_WIDTH = 8;
    localparam integer DATA_WIDTH = BIT_WIDTH + 3;
    localparam integer BIAS_WIDTH = BIT_WIDTH + 2;
    localparam integer BOUND_WIDTH = BIT_WIDTH + 5;
    localparam integer COEFF_WIDTH = 16;
    localparam integer ACC_WIDTH = 40;
    localparam integer BLOCK_SIZE = 2;
    localparam integer NUM_BLOCKS = 1;
    localparam integer DIGIT_IDX_WIDTH = $clog2(DATA_WIDTH);

    reg i_clk;
    reg i_rst;
    reg i_start;
    reg i_valid_digit;
    reg [NUM_ROWS-1:0] i_ena_rows;
    reg [DIGIT_IDX_WIDTH-1:0] i_digit_idx;
    reg i_use_replay;
    reg i_clear_write_bank;
    reg i_commit_swap;
    reg i_load_state;
    reg i_load_bank_sel;
    reg i_load_row_idx;
    reg [DATA_WIDTH-1:0] i_load_state_p;
    reg [DATA_WIDTH-1:0] i_load_state_n;
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
    reg [NUM_ROWS*NUM_BLOCKS*COEFF_WIDTH-1:0] block_weights;
    reg [ACC_WIDTH-1:0] eta;

    wire [NUM_ROWS-1:0] replay_x0_p_rows;
    wire [NUM_ROWS-1:0] replay_x0_n_rows;
    wire [NUM_ROWS-1:0] write_done_rows;
    wire [NUM_ROWS*BOUND_WIDTH-1:0] abs_upper_rows;
    wire cluster_valid;
    wire cluster_certified;
    wire [ACC_WIDTH-1:0] cluster_max_error;

    integer di;
    integer bit_sel;
    integer wait_count;
    reg signed [31:0] replay_sum0;
    reg signed [31:0] replay_sum1;
    reg [DATA_WIDTH-1:0] new0_p;
    reg [DATA_WIDTH-1:0] new1_n;
    reg cluster_seen;
    reg done_seen;
    reg certified_seen;
    reg [ACC_WIDTH-1:0] max_error_seen;

    iter_solver_native_cluster_delta_cert_top #(
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
        .i_load_state(i_load_state),
        .i_load_bank_sel(i_load_bank_sel),
        .i_load_row_idx(i_load_row_idx),
        .i_load_state_p(i_load_state_p),
        .i_load_state_n(i_load_state_n),
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
        .i_block_weights(block_weights),
        .i_eta(eta),
        .i_tail_bound({BOUND_WIDTH{1'b0}}),
        .o_replay_x0_p_rows(replay_x0_p_rows),
        .o_replay_x0_n_rows(replay_x0_n_rows),
        .o_replay_x1_p_rows(),
        .o_replay_x1_n_rows(),
        .o_write_done_rows(write_done_rows),
        .o_abs_upper_rows(abs_upper_rows),
        .o_block_bounds(),
        .o_cluster_valid(cluster_valid),
        .o_cluster_certified(cluster_certified),
        .o_cluster_max_error(cluster_max_error),
        .o_read_state_p_rows(),
        .o_read_state_n_rows()
    );

    always #5 i_clk = ~i_clk;

    task automatic load_row;
        input row_idx;
        input [DATA_WIDTH-1:0] state_p;
        input [DATA_WIDTH-1:0] state_n;
        begin
            @(negedge i_clk);
            i_load_state = 1'b1;
            i_load_bank_sel = 1'b0;
            i_load_row_idx = row_idx;
            i_load_state_p = state_p;
            i_load_state_n = state_n;
            @(negedge i_clk);
            i_load_state = 1'b0;
            i_load_state_p = {DATA_WIDTH{1'b0}};
            i_load_state_n = {DATA_WIDTH{1'b0}};
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

    initial begin
        i_clk = 1'b0;
        i_rst = 1'b1;
        i_start = 1'b0;
        i_valid_digit = 1'b0;
        i_ena_rows = {NUM_ROWS{1'b1}};
        i_digit_idx = {DIGIT_IDX_WIDTH{1'b0}};
        i_use_replay = 1'b0;
        i_clear_write_bank = 1'b0;
        i_commit_swap = 1'b0;
        i_load_state = 1'b0;
        i_load_bank_sel = 1'b0;
        i_load_row_idx = 1'b0;
        i_load_state_p = {DATA_WIDTH{1'b0}};
        i_load_state_n = {DATA_WIDTH{1'b0}};
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
        block_weights = {NUM_ROWS*NUM_BLOCKS*COEFF_WIDTH{1'b0}};
        eta = 40'd10;
        replay_sum0 = 32'sd0;
        replay_sum1 = 32'sd0;
        new0_p = 11'd7;
        new1_n = 11'd3;
        cluster_seen = 1'b0;
        done_seen = 1'b0;
        certified_seen = 1'b0;
        max_error_seen = {ACC_WIDTH{1'b0}};

        coeff_p_terms_rows[0*DEGREE*BIT_WIDTH +: DEGREE*BIT_WIDTH] = {8'd0, 8'd0, 8'd0, 8'd1};
        coeff_p_terms_rows[1*DEGREE*BIT_WIDTH +: DEGREE*BIT_WIDTH] = {8'd0, 8'd0, 8'd0, 8'd1};
        block_weights[0*COEFF_WIDTH +: COEFF_WIDTH] = 16'd1;
        block_weights[1*COEFF_WIDTH +: COEFF_WIDTH] = 16'd1;

        repeat (2) @(negedge i_clk);
        i_rst = 1'b0;

        load_row(1'b0, 11'd5, 11'd0);
        load_row(1'b1, 11'd2, 11'd0);
        pulse_clear();

        // Emit new state row0=7, row1=-3 through term0 with coefficient +1.
        for (di = 0; di < DATA_WIDTH; di = di + 1) begin
            bit_sel = DATA_WIDTH - 1 - di;
            i_start = (di == 0);
            i_valid_digit = 1'b1;
            i_digit_idx = di[DIGIT_IDX_WIDTH-1:0];
            ext_x0_p_rows[0] = new0_p[bit_sel];
            ext_x0_n_rows[0] = 1'b0;
            ext_x0_p_rows[1] = 1'b0;
            ext_x0_n_rows[1] = new1_n[bit_sel];
            @(negedge i_clk);
        end

        i_start = 1'b0;
        i_valid_digit = 1'b0;
        i_digit_idx = DATA_WIDTH - 1;
        ext_x0_p_rows = {NUM_ROWS{1'b0}};
        ext_x0_n_rows = {NUM_ROWS{1'b0}};

        wait_count = 0;
        while ((!(cluster_seen && done_seen)) && wait_count < 48) begin
            @(negedge i_clk);
            if (cluster_valid) begin
                cluster_seen = 1'b1;
                certified_seen = cluster_certified;
                max_error_seen = cluster_max_error;
            end
            if (write_done_rows[0] && write_done_rows[1]) begin
                done_seen = 1'b1;
            end
            wait_count = wait_count + 1;
        end
        i_valid_digit = 1'b0;

        if (!cluster_seen || !certified_seen || max_error_seen !== 40'd5 || !done_seen) begin
            $display("ERROR delta cert valid=%0d certified=%0d max_error=%0d abs=%h done=%0d",
                cluster_seen, certified_seen, max_error_seen, abs_upper_rows, done_seen);
            $fatal;
        end

        commit_swap();

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

        if (replay_sum0 !== 32'sd7 || replay_sum1 !== -32'sd3) begin
            $display("ERROR final replay row0=%0d row1=%0d", replay_sum0, replay_sum1);
            $fatal;
        end

        $display("PASS tb_iter_solver_native_cluster_delta_cert_top max_error=%0d final=(%0d,%0d)",
            max_error_seen, replay_sum0, replay_sum1);
        $finish;
    end
endmodule
