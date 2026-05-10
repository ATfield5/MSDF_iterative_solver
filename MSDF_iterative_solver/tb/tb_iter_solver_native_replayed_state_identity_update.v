`timescale 1ns / 1ps

// Replayed signed-digit state -> solver-native row engine -> state commit.
//
// This is the smallest closed-loop datapath checkpoint.  It preloads the state
// bank with signed-digit row states, replays them as row-engine source digits,
// applies an identity row update, commits the row-engine output into the
// inactive bank, swaps banks, and verifies the replayed values are preserved.

module tb_iter_solver_native_replayed_state_identity_update;
    localparam integer NUM_ROWS = 2;
    localparam integer DEGREE = 4;
    localparam integer BIT_WIDTH = 8;
    localparam integer DATA_WIDTH = BIT_WIDTH + 3;
    localparam integer BIAS_WIDTH = BIT_WIDTH + 2;
    localparam integer DIGIT_IDX_WIDTH = $clog2(DATA_WIDTH);
    localparam integer SKIP_DIGITS = 8;

    reg i_clk;
    reg i_rst;
    reg i_start;
    reg i_valid_digit;
    reg [DIGIT_IDX_WIDTH-1:0] digit_idx;
    reg [NUM_ROWS*DEGREE-1:0] state_digit_p_terms_rows;
    reg [NUM_ROWS*DEGREE-1:0] state_digit_n_terms_rows;
    reg [NUM_ROWS*DEGREE*BIT_WIDTH-1:0] coeff_p_terms_rows;
    reg [NUM_ROWS*DEGREE*BIT_WIDTH-1:0] coeff_n_terms_rows;

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
    reg load_state;
    reg load_bank_sel;
    reg load_row_idx;
    reg [DATA_WIDTH-1:0] load_state_p;
    reg [DATA_WIDTH-1:0] load_state_n;
    reg [DIGIT_IDX_WIDTH-1:0] replay_digit_idx;
    reg [NUM_ROWS*DEGREE-1:0] src_row_idx;
    wire [NUM_ROWS-1:0] replay_x0_p_rows;
    wire [NUM_ROWS-1:0] replay_x0_n_rows;

    integer di;
    integer wait_count;
    reg signed [31:0] replay_sum0;
    reg signed [31:0] replay_sum1;

    genvar ri;
    generate
        for (ri = 0; ri < NUM_ROWS; ri = ri + 1) begin : g_identity_rows
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
                .i_digit_idx(digit_idx),
                .i_state_digit_p_terms(state_digit_p_terms_rows[ri*DEGREE +: DEGREE]),
                .i_state_digit_n_terms(state_digit_n_terms_rows[ri*DEGREE +: DEGREE]),
                .i_coeff_p_terms(coeff_p_terms_rows[ri*DEGREE*BIT_WIDTH +: DEGREE*BIT_WIDTH]),
                .i_coeff_n_terms(coeff_n_terms_rows[ri*DEGREE*BIT_WIDTH +: DEGREE*BIT_WIDTH]),
                .i_bias_p({BIAS_WIDTH{1'b0}}),
                .i_bias_n({BIAS_WIDTH{1'b0}}),
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
        .i_load_state(load_state),
        .i_load_bank_sel(load_bank_sel),
        .i_load_row_idx(load_row_idx),
        .i_load_state_p(load_state_p),
        .i_load_state_n(load_state_n),
        .i_write_digit_valid_rows(adapter_write_valid_rows),
        .i_write_digit_idx(adapter_write_idx0),
        .i_write_digit_p_rows(adapter_write_p_rows),
        .i_write_digit_n_rows(adapter_write_n_rows),
        .i_replay_digit_idx(replay_digit_idx),
        .i_src_row_idx(src_row_idx),
        .o_read_bank_sel(),
        .o_read_state_p_rows(),
        .o_read_state_n_rows(),
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

    task automatic load_row;
        input row_idx;
        input [DATA_WIDTH-1:0] value_p;
        input [DATA_WIDTH-1:0] value_n;
        begin
            @(negedge i_clk);
            load_state = 1'b1;
            load_bank_sel = 1'b0;
            load_row_idx = row_idx;
            load_state_p = value_p;
            load_state_n = value_n;
            @(negedge i_clk);
            load_state = 1'b0;
            load_state_p = {DATA_WIDTH{1'b0}};
            load_state_n = {DATA_WIDTH{1'b0}};
        end
    endtask

    initial begin
        i_clk = 1'b0;
        i_rst = 1'b1;
        i_start = 1'b0;
        i_valid_digit = 1'b0;
        digit_idx = {DIGIT_IDX_WIDTH{1'b0}};
        state_digit_p_terms_rows = {NUM_ROWS*DEGREE{1'b0}};
        state_digit_n_terms_rows = {NUM_ROWS*DEGREE{1'b0}};
        coeff_p_terms_rows = {NUM_ROWS*DEGREE*BIT_WIDTH{1'b0}};
        coeff_n_terms_rows = {NUM_ROWS*DEGREE*BIT_WIDTH{1'b0}};
        commit_swap = 1'b0;
        clear_write_bank = 1'b0;
        load_state = 1'b0;
        load_bank_sel = 1'b0;
        load_row_idx = 1'b0;
        load_state_p = {DATA_WIDTH{1'b0}};
        load_state_n = {DATA_WIDTH{1'b0}};
        replay_digit_idx = {DIGIT_IDX_WIDTH{1'b0}};
        src_row_idx = {NUM_ROWS*DEGREE{1'b0}};
        replay_sum0 = 32'sd0;
        replay_sum1 = 32'sd0;

        // term0 is self, remaining terms are zero.
        src_row_idx[0*DEGREE + 0] = 1'b0;
        src_row_idx[1*DEGREE + 0] = 1'b1;
        coeff_p_terms_rows[0*DEGREE*BIT_WIDTH +: DEGREE*BIT_WIDTH] = {8'd0, 8'd0, 8'd0, 8'd1};
        coeff_p_terms_rows[1*DEGREE*BIT_WIDTH +: DEGREE*BIT_WIDTH] = {8'd0, 8'd0, 8'd0, 8'd1};

        repeat (2) @(negedge i_clk);
        i_rst = 1'b0;

        // Signed-digit rails from the previous checkpoint:
        // row0 = 0x154 - 0x0aa = 170
        // row1 = 0x048 - 0x0a4 = -92
        load_row(1'b0, 11'h154, 11'h0aa);
        load_row(1'b1, 11'h048, 11'h0a4);

        @(negedge i_clk);
        clear_write_bank = 1'b1;
        @(negedge i_clk);
        clear_write_bank = 1'b0;

        for (di = 0; di < DATA_WIDTH; di = di + 1) begin
            replay_digit_idx = di[DIGIT_IDX_WIDTH-1:0];
            #1;
            state_digit_p_terms_rows = {NUM_ROWS*DEGREE{1'b0}};
            state_digit_n_terms_rows = {NUM_ROWS*DEGREE{1'b0}};
            state_digit_p_terms_rows[0*DEGREE + 0] = replay_x0_p_rows[0];
            state_digit_n_terms_rows[0*DEGREE + 0] = replay_x0_n_rows[0];
            state_digit_p_terms_rows[1*DEGREE + 0] = replay_x0_p_rows[1];
            state_digit_n_terms_rows[1*DEGREE + 0] = replay_x0_n_rows[1];
            i_start = (di == 0);
            i_valid_digit = 1'b1;
            digit_idx = di[DIGIT_IDX_WIDTH-1:0];
            @(negedge i_clk);
        end

        i_start = 1'b0;
        i_valid_digit = 1'b1;
        digit_idx = DATA_WIDTH - 1;
        state_digit_p_terms_rows = {NUM_ROWS*DEGREE{1'b0}};
        state_digit_n_terms_rows = {NUM_ROWS*DEGREE{1'b0}};

        wait_count = 0;
        while (!(adapter_done_rows[0] && adapter_done_rows[1]) && wait_count < 32) begin
            @(negedge i_clk);
            wait_count = wait_count + 1;
        end
        i_valid_digit = 1'b0;

        if (!(adapter_done_rows[0] && adapter_done_rows[1])) begin
            $display("ERROR identity update did not finish");
            $fatal;
        end

        @(negedge i_clk);
        commit_swap = 1'b1;
        @(negedge i_clk);
        commit_swap = 1'b0;

        replay_sum0 = 32'sd0;
        replay_sum1 = 32'sd0;
        for (di = 0; di < DATA_WIDTH; di = di + 1) begin
            replay_digit_idx = di[DIGIT_IDX_WIDTH-1:0];
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

        if (replay_sum0 !== 32'sd170 || replay_sum1 !== -32'sd92) begin
            $display("ERROR identity replay row0=%0d row1=%0d", replay_sum0, replay_sum1);
            $fatal;
        end

        $display("PASS tb_iter_solver_native_replayed_state_identity_update row0=%0d row1=%0d",
            replay_sum0, replay_sum1);
        $finish;
    end
endmodule
