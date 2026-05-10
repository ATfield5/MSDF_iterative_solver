`timescale 1ns / 1ps

module tb_iter_wavefront_superstep_cluster_state_top;
    localparam integer SUPERSTEP_STAGES = 4;
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
    localparam integer ROW_IDX_WIDTH = 1;
    localparam integer DIGIT_IDX_WIDTH = $clog2(DATA_WIDTH);

    reg i_clk;
    reg i_rst;
    reg i_start;
    reg i_valid_digit;
    reg [DIGIT_IDX_WIDTH - 1 : 0] i_digit_idx;
    reg i_use_replay;
    reg i_clear_write_bank;
    reg i_commit_swap;
    reg i_load_state;
    reg i_load_bank_sel;
    reg [ROW_IDX_WIDTH - 1 : 0] i_load_row_idx;
    reg [DATA_WIDTH - 1 : 0] i_load_state_p;
    reg [DATA_WIDTH - 1 : 0] i_load_state_n;
    reg [NUM_ROWS * DEGREE * ROW_IDX_WIDTH - 1 : 0] i_src_row_idx;
    reg [NUM_ROWS - 1 : 0] i_ext_x0_p_rows;
    reg [NUM_ROWS - 1 : 0] i_ext_x0_n_rows;
    reg [NUM_ROWS - 1 : 0] i_ext_x1_p_rows;
    reg [NUM_ROWS - 1 : 0] i_ext_x1_n_rows;
    reg [NUM_ROWS - 1 : 0] i_ext_x2_p_rows;
    reg [NUM_ROWS - 1 : 0] i_ext_x2_n_rows;
    reg [NUM_ROWS - 1 : 0] i_ext_x3_p_rows;
    reg [NUM_ROWS - 1 : 0] i_ext_x3_n_rows;
    reg [NUM_ROWS * DEGREE * BIT_WIDTH - 1 : 0] i_coeff_p_terms_rows;
    reg [NUM_ROWS * DEGREE * BIT_WIDTH - 1 : 0] i_coeff_n_terms_rows;
    reg [NUM_ROWS * BIAS_WIDTH - 1 : 0] i_bias_p_rows;
    reg [NUM_ROWS * BIAS_WIDTH - 1 : 0] i_bias_n_rows;
    reg [NUM_ROWS * NUM_BLOCKS * COEFF_WIDTH - 1 : 0] i_block_weights;
    reg [ACC_WIDTH - 1 : 0] i_eta;
    reg [BOUND_WIDTH - 1 : 0] i_tail_bound;

    wire [NUM_ROWS - 1 : 0] w_final_valid_rows;
    wire [NUM_ROWS * DIGIT_IDX_WIDTH - 1 : 0] w_final_digit_idx_rows;
    wire [NUM_ROWS - 1 : 0] w_final_digit_p_rows;
    wire [NUM_ROWS - 1 : 0] w_final_digit_n_rows;
    wire [NUM_ROWS * DATA_WIDTH - 1 : 0] w_read_state_p_rows;
    wire [NUM_ROWS * DATA_WIDTH - 1 : 0] w_read_state_n_rows;
    wire w_cluster_valid;
    wire w_cluster_certified;
    wire [ACC_WIDTH - 1 : 0] w_cluster_max_error;
    wire [SUPERSTEP_STAGES - 1 : 0] w_stage_done;

    reg [DATA_WIDTH - 1 : 0] captured_final_p_word;
    reg [DATA_WIDTH - 1 : 0] captured_final_n_word;
    reg cert_seen;
    integer di;
    integer bit_sel;
    integer wait_count;

    iter_wavefront_superstep_cluster_state_top #(
        .superstep_stages(SUPERSTEP_STAGES),
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
        .skip_digits(SKIP_DIGITS),
        .row_idx_width(ROW_IDX_WIDTH)
    ) dut (
        .i_clk(i_clk),
        .i_rst(i_rst),
        .i_start(i_start),
        .i_valid_digit(i_valid_digit),
        .i_digit_idx(i_digit_idx),
        .i_use_replay(i_use_replay),
        .i_clear_write_bank(i_clear_write_bank),
        .i_commit_swap(i_commit_swap),
        .i_load_state(i_load_state),
        .i_load_bank_sel(i_load_bank_sel),
        .i_load_row_idx(i_load_row_idx),
        .i_load_state_p(i_load_state_p),
        .i_load_state_n(i_load_state_n),
        .i_src_row_idx(i_src_row_idx),
        .i_inter_stage_source_p_rows({SUPERSTEP_STAGES * NUM_ROWS{1'b0}}),
        .i_inter_stage_source_n_rows({SUPERSTEP_STAGES * NUM_ROWS{1'b0}}),
        .i_ext_x0_p_rows(i_ext_x0_p_rows),
        .i_ext_x0_n_rows(i_ext_x0_n_rows),
        .i_ext_x1_p_rows(i_ext_x1_p_rows),
        .i_ext_x1_n_rows(i_ext_x1_n_rows),
        .i_ext_x2_p_rows(i_ext_x2_p_rows),
        .i_ext_x2_n_rows(i_ext_x2_n_rows),
        .i_ext_x3_p_rows(i_ext_x3_p_rows),
        .i_ext_x3_n_rows(i_ext_x3_n_rows),
        .i_coeff_p_terms_rows(i_coeff_p_terms_rows),
        .i_coeff_n_terms_rows(i_coeff_n_terms_rows),
        .i_bias_p_rows(i_bias_p_rows),
        .i_bias_n_rows(i_bias_n_rows),
        .i_block_weights(i_block_weights),
        .i_eta(i_eta),
        .i_tail_bound(i_tail_bound),
        .o_replay_x0_p_rows(),
        .o_replay_x0_n_rows(),
        .o_replay_x1_p_rows(),
        .o_replay_x1_n_rows(),
        .o_replay_x2_p_rows(),
        .o_replay_x2_n_rows(),
        .o_replay_x3_p_rows(),
        .o_replay_x3_n_rows(),
        .o_final_valid_rows(w_final_valid_rows),
        .o_final_digit_idx_rows(w_final_digit_idx_rows),
        .o_final_digit_p_rows(w_final_digit_p_rows),
        .o_final_digit_n_rows(w_final_digit_n_rows),
        .o_read_state_p_rows(w_read_state_p_rows),
        .o_read_state_n_rows(w_read_state_n_rows),
        .o_cluster_valid(w_cluster_valid),
        .o_cluster_certified(w_cluster_certified),
        .o_cluster_max_error(w_cluster_max_error),
        .o_stage_commit_valid_rows(),
        .o_stage_commit_digit_idx_rows(),
        .o_stage_commit_digit_p_rows(),
        .o_stage_commit_digit_n_rows(),
        .o_stage_done(w_stage_done)
    );

    always #5 i_clk = ~i_clk;

    task set_source_digits;
        input integer digit_idx;
        begin
            i_ext_x0_p_rows = (digit_idx == 1 || digit_idx == 3 || digit_idx == 6);
            i_ext_x0_n_rows = (digit_idx == 5);
            i_ext_x1_p_rows = {NUM_ROWS{1'b0}};
            i_ext_x1_n_rows = {NUM_ROWS{1'b0}};
            i_ext_x2_p_rows = {NUM_ROWS{1'b0}};
            i_ext_x2_n_rows = {NUM_ROWS{1'b0}};
            i_ext_x3_p_rows = {NUM_ROWS{1'b0}};
            i_ext_x3_n_rows = {NUM_ROWS{1'b0}};
        end
    endtask

    always @(posedge i_clk) begin
        #1;
        if (i_rst || i_start) begin
            captured_final_p_word = {DATA_WIDTH{1'b0}};
            captured_final_n_word = {DATA_WIDTH{1'b0}};
            cert_seen = 1'b0;
        end else begin
            if (w_final_valid_rows[0]) begin
                bit_sel = DATA_WIDTH - 1 - w_final_digit_idx_rows[DIGIT_IDX_WIDTH - 1 : 0];
                captured_final_p_word[bit_sel] = w_final_digit_p_rows[0];
                captured_final_n_word[bit_sel] = w_final_digit_n_rows[0];
            end
            if (w_cluster_valid) begin
                cert_seen = 1'b1;
            end
        end
    end

    initial begin
        i_clk = 1'b0;
        i_rst = 1'b1;
        i_start = 1'b0;
        i_valid_digit = 1'b0;
        i_digit_idx = {DIGIT_IDX_WIDTH{1'b0}};
        i_use_replay = 1'b0;
        i_clear_write_bank = 1'b0;
        i_commit_swap = 1'b0;
        i_load_state = 1'b0;
        i_load_bank_sel = 1'b0;
        i_load_row_idx = {ROW_IDX_WIDTH{1'b0}};
        i_load_state_p = {DATA_WIDTH{1'b0}};
        i_load_state_n = {DATA_WIDTH{1'b0}};
        i_src_row_idx = {NUM_ROWS * DEGREE * ROW_IDX_WIDTH{1'b0}};
        i_ext_x0_p_rows = {NUM_ROWS{1'b0}};
        i_ext_x0_n_rows = {NUM_ROWS{1'b0}};
        i_ext_x1_p_rows = {NUM_ROWS{1'b0}};
        i_ext_x1_n_rows = {NUM_ROWS{1'b0}};
        i_ext_x2_p_rows = {NUM_ROWS{1'b0}};
        i_ext_x2_n_rows = {NUM_ROWS{1'b0}};
        i_ext_x3_p_rows = {NUM_ROWS{1'b0}};
        i_ext_x3_n_rows = {NUM_ROWS{1'b0}};
        i_coeff_p_terms_rows = {NUM_ROWS * DEGREE * BIT_WIDTH{1'b0}};
        i_coeff_n_terms_rows = {NUM_ROWS * DEGREE * BIT_WIDTH{1'b0}};
        i_bias_p_rows = {NUM_ROWS * BIAS_WIDTH{1'b0}};
        i_bias_n_rows = {NUM_ROWS * BIAS_WIDTH{1'b0}};
        i_block_weights = 8'd1;
        i_eta = 24'hffffff;
        i_tail_bound = {BOUND_WIDTH{1'b0}};

        i_coeff_p_terms_rows[0 * BIT_WIDTH +: BIT_WIDTH] = 5'd1;
        i_coeff_p_terms_rows[1 * BIT_WIDTH +: BIT_WIDTH] = 5'd1;

        repeat (2) @(posedge i_clk);
        i_rst = 1'b0;

        @(negedge i_clk);
        i_clear_write_bank = 1'b1;
        @(negedge i_clk);
        i_clear_write_bank = 1'b0;

        for (di = 0; di < DATA_WIDTH; di = di + 1) begin
            @(negedge i_clk);
            set_source_digits(di);
            i_start = (di == 0);
            i_valid_digit = 1'b1;
            i_digit_idx = di[DIGIT_IDX_WIDTH - 1 : 0];
        end

        @(negedge i_clk);
        i_start = 1'b0;
        i_valid_digit = 1'b0;
        set_source_digits(DATA_WIDTH);

        wait_count = 0;
        while ((!cert_seen || !w_stage_done[SUPERSTEP_STAGES - 1]) && wait_count < 256) begin
            @(negedge i_clk);
            wait_count = wait_count + 1;
        end

        if (!cert_seen || !w_cluster_certified) begin
            $display("ERROR superstep cert valid=%0d certified=%0d max_error=%0d",
                cert_seen,
                w_cluster_certified,
                w_cluster_max_error);
            $fatal;
        end

        @(negedge i_clk);
        i_commit_swap = 1'b1;
        @(negedge i_clk);
        i_commit_swap = 1'b0;
        #1;

        if (w_read_state_p_rows[DATA_WIDTH - 1 : 0] !== captured_final_p_word ||
            w_read_state_n_rows[DATA_WIDTH - 1 : 0] !== captured_final_n_word) begin
            $display("ERROR superstep state commit mismatch read=%h/%h expected=%h/%h",
                w_read_state_p_rows[DATA_WIDTH - 1 : 0],
                w_read_state_n_rows[DATA_WIDTH - 1 : 0],
                captured_final_p_word,
                captured_final_n_word);
            $fatal;
        end

        $display("PASS tb_iter_wavefront_superstep_cluster_state_top max_error=%0d state=%h/%h",
            w_cluster_max_error,
            w_read_state_p_rows[DATA_WIDTH - 1 : 0],
            w_read_state_n_rows[DATA_WIDTH - 1 : 0]);
        $finish;
    end
endmodule
