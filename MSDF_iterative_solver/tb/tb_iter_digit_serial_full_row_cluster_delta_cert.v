`timescale 1ns / 1ps

module tb_iter_digit_serial_full_row_cluster_delta_cert;
    localparam integer NUM_ROWS = 4;
    localparam integer DEGREE = 4;
    localparam integer BIT_WIDTH = 8;
    localparam integer DATA_WIDTH = BIT_WIDTH + 3;
    localparam integer BIAS_WIDTH = BIT_WIDTH + 2;
    localparam integer BOUND_WIDTH = BIT_WIDTH + 5;
    localparam integer COEFF_WIDTH = 8;
    localparam integer ACC_WIDTH = 24;
    localparam integer MAC_ACC_WIDTH = 32;
    localparam integer BLOCK_SIZE = 2;
    localparam integer NUM_BLOCKS = 2;
    localparam integer DIGIT_IDX_WIDTH = $clog2(DATA_WIDTH);

    reg i_clk;
    reg i_rst;
    reg i_start;
    reg i_valid_digit;
    reg i_last_digit;
    reg [DIGIT_IDX_WIDTH - 1 : 0] i_digit_idx;
    reg [NUM_ROWS * DEGREE - 1 : 0] i_state_digit_p_terms_rows;
    reg [NUM_ROWS * DEGREE - 1 : 0] i_state_digit_n_terms_rows;
    reg [NUM_ROWS * DEGREE * BIT_WIDTH - 1 : 0] i_coeff_p_terms_rows;
    reg [NUM_ROWS * DEGREE * BIT_WIDTH - 1 : 0] i_coeff_n_terms_rows;
    reg [NUM_ROWS * BIAS_WIDTH - 1 : 0] i_bias_p_rows;
    reg [NUM_ROWS * BIAS_WIDTH - 1 : 0] i_bias_n_rows;
    reg [NUM_ROWS * DATA_WIDTH - 1 : 0] i_old_state_p_rows;
    reg [NUM_ROWS * DATA_WIDTH - 1 : 0] i_old_state_n_rows;
    reg [BOUND_WIDTH - 1 : 0] i_tail_bound;
    reg [NUM_ROWS * NUM_BLOCKS * COEFF_WIDTH - 1 : 0] i_block_weights;
    reg [ACC_WIDTH - 1 : 0] i_eta;
    wire [NUM_ROWS - 1 : 0] o_valid_rows;
    wire [NUM_ROWS * MAC_ACC_WIDTH - 1 : 0] o_sum_rows;
    wire [NUM_ROWS * DATA_WIDTH - 1 : 0] o_sum_p_rows;
    wire [NUM_ROWS * DATA_WIDTH - 1 : 0] o_sum_n_rows;
    wire [NUM_ROWS * BOUND_WIDTH - 1 : 0] o_abs_upper_rows;
    wire [NUM_BLOCKS * BOUND_WIDTH - 1 : 0] o_block_bounds;
    wire o_cluster_valid;
    wire o_cluster_certified;
    wire [ACC_WIDTH - 1 : 0] o_cluster_max_error;

    reg [NUM_ROWS * DEGREE * DATA_WIDTH - 1 : 0] state_p_terms_rows;
    reg [NUM_ROWS * DEGREE * DATA_WIDTH - 1 : 0] state_n_terms_rows;

    iter_digit_serial_full_row_cluster_delta_cert #(
        .num_rows(NUM_ROWS),
        .degree(DEGREE),
        .bit_width(BIT_WIDTH),
        .data_width(DATA_WIDTH),
        .bias_width(BIAS_WIDTH),
        .bound_width(BOUND_WIDTH),
        .coeff_width(COEFF_WIDTH),
        .acc_width(ACC_WIDTH),
        .mac_acc_width(MAC_ACC_WIDTH),
        .block_size(BLOCK_SIZE),
        .num_blocks(NUM_BLOCKS)
    ) dut (
        .i_clk(i_clk),
        .i_rst(i_rst),
        .i_start(i_start),
        .i_valid_digit(i_valid_digit),
        .i_last_digit(i_last_digit),
        .i_digit_idx(i_digit_idx),
        .i_state_digit_p_terms_rows(i_state_digit_p_terms_rows),
        .i_state_digit_n_terms_rows(i_state_digit_n_terms_rows),
        .i_coeff_p_terms_rows(i_coeff_p_terms_rows),
        .i_coeff_n_terms_rows(i_coeff_n_terms_rows),
        .i_bias_p_rows(i_bias_p_rows),
        .i_bias_n_rows(i_bias_n_rows),
        .i_old_state_p_rows(i_old_state_p_rows),
        .i_old_state_n_rows(i_old_state_n_rows),
        .i_tail_bound(i_tail_bound),
        .i_block_weights(i_block_weights),
        .i_eta(i_eta),
        .o_valid_rows(o_valid_rows),
        .o_sum_rows(o_sum_rows),
        .o_sum_p_rows(o_sum_p_rows),
        .o_sum_n_rows(o_sum_n_rows),
        .o_abs_upper_rows(o_abs_upper_rows),
        .o_block_bounds(o_block_bounds),
        .o_cluster_valid(o_cluster_valid),
        .o_cluster_certified(o_cluster_certified),
        .o_cluster_max_error(o_cluster_max_error)
    );

    always #5 i_clk = ~i_clk;

    task automatic set_data_field;
        inout [NUM_ROWS * DEGREE * DATA_WIDTH - 1 : 0] vec;
        input integer row;
        input integer term;
        input [DATA_WIDTH - 1 : 0] value;
        begin
            vec[(row * DEGREE + term) * DATA_WIDTH +: DATA_WIDTH] = value;
        end
    endtask

    task automatic set_coeff_field;
        inout [NUM_ROWS * DEGREE * BIT_WIDTH - 1 : 0] vec;
        input integer row;
        input integer term;
        input [BIT_WIDTH - 1 : 0] value;
        begin
            vec[(row * DEGREE + term) * BIT_WIDTH +: BIT_WIDTH] = value;
        end
    endtask

    task automatic rail_from_sum;
        input signed [MAC_ACC_WIDTH - 1 : 0] sum_value;
        output [DATA_WIDTH - 1 : 0] rail_p;
        output [DATA_WIDTH - 1 : 0] rail_n;
        reg [MAC_ACC_WIDTH - 1 : 0] abs_sum;
        reg [MAC_ACC_WIDTH - 1 : 0] state_max;
        begin
            abs_sum = sum_value[MAC_ACC_WIDTH - 1] ? (~sum_value + 1'b1) : sum_value;
            state_max = {{(MAC_ACC_WIDTH - DATA_WIDTH){1'b0}}, {DATA_WIDTH{1'b1}}};
            if (sum_value[MAC_ACC_WIDTH - 1]) begin
                rail_p = {DATA_WIDTH{1'b0}};
                rail_n = (abs_sum > state_max) ? {DATA_WIDTH{1'b1}} : abs_sum[DATA_WIDTH - 1 : 0];
            end else begin
                rail_p = (abs_sum > state_max) ? {DATA_WIDTH{1'b1}} : abs_sum[DATA_WIDTH - 1 : 0];
                rail_n = {DATA_WIDTH{1'b0}};
            end
        end
    endtask

    integer ri;
    integer ti;
    integer bi;
    integer di;
    integer bit_sel;
    integer wait_count;
    reg signed [DATA_WIDTH : 0] state_term;
    reg signed [DATA_WIDTH : 0] old_state_term;
    reg signed [BIT_WIDTH : 0] coeff_term;
    reg signed [BIAS_WIDTH : 0] bias_term;
    reg signed [MAC_ACC_WIDTH - 1 : 0] expected_sum [0 : NUM_ROWS - 1];
    reg [DATA_WIDTH - 1 : 0] expected_p [0 : NUM_ROWS - 1];
    reg [DATA_WIDTH - 1 : 0] expected_n [0 : NUM_ROWS - 1];
    reg [BOUND_WIDTH - 1 : 0] expected_abs [0 : NUM_ROWS - 1];
    reg [BOUND_WIDTH - 1 : 0] expected_block [0 : NUM_BLOCKS - 1];
    reg [ACC_WIDTH - 1 : 0] expected_row_error;
    reg [ACC_WIDTH - 1 : 0] expected_max_error;

    initial begin
        i_clk = 1'b0;
        i_rst = 1'b1;
        i_start = 1'b0;
        i_valid_digit = 1'b0;
        i_last_digit = 1'b0;
        i_digit_idx = {DIGIT_IDX_WIDTH{1'b0}};
        i_state_digit_p_terms_rows = {NUM_ROWS * DEGREE{1'b0}};
        i_state_digit_n_terms_rows = {NUM_ROWS * DEGREE{1'b0}};
        i_coeff_p_terms_rows = {NUM_ROWS * DEGREE * BIT_WIDTH{1'b0}};
        i_coeff_n_terms_rows = {NUM_ROWS * DEGREE * BIT_WIDTH{1'b0}};
        i_bias_p_rows = {NUM_ROWS * BIAS_WIDTH{1'b0}};
        i_bias_n_rows = {NUM_ROWS * BIAS_WIDTH{1'b0}};
        i_old_state_p_rows = {NUM_ROWS * DATA_WIDTH{1'b0}};
        i_old_state_n_rows = {NUM_ROWS * DATA_WIDTH{1'b0}};
        i_tail_bound = 13'd2;
        i_block_weights = {NUM_ROWS * NUM_BLOCKS * COEFF_WIDTH{1'b0}};
        i_eta = 24'd4095;
        state_p_terms_rows = {NUM_ROWS * DEGREE * DATA_WIDTH{1'b0}};
        state_n_terms_rows = {NUM_ROWS * DEGREE * DATA_WIDTH{1'b0}};

        repeat (2) @(negedge i_clk);
        i_rst = 1'b0;

        for (ri = 0; ri < NUM_ROWS; ri = ri + 1) begin
            for (ti = 0; ti < DEGREE; ti = ti + 1) begin
                set_data_field(state_p_terms_rows, ri, ti, (ri + 1) * (ti + 2));
                set_data_field(state_n_terms_rows, ri, ti, (ti == 2) ? (ri + 1) : 0);
                set_coeff_field(i_coeff_p_terms_rows, ri, ti, (ri + ti + 1));
                set_coeff_field(i_coeff_n_terms_rows, ri, ti, (ti == 1) ? 2 : 0);
            end
            i_bias_p_rows[ri * BIAS_WIDTH +: BIAS_WIDTH] = ri + 3;
            i_bias_n_rows[ri * BIAS_WIDTH +: BIAS_WIDTH] = (ri == 2) ? 4 : 1;
            i_old_state_p_rows[ri * DATA_WIDTH +: DATA_WIDTH] = ri + 2;
            i_old_state_n_rows[ri * DATA_WIDTH +: DATA_WIDTH] = (ri == 3) ? 5 : 0;
        end

        for (ri = 0; ri < NUM_ROWS; ri = ri + 1) begin
            for (bi = 0; bi < NUM_BLOCKS; bi = bi + 1) begin
                i_block_weights[(ri * NUM_BLOCKS + bi) * COEFF_WIDTH +: COEFF_WIDTH] = ri + bi + 1;
            end
        end

        for (ri = 0; ri < NUM_ROWS; ri = ri + 1) begin
            bias_term =
                $signed({1'b0, i_bias_p_rows[ri * BIAS_WIDTH +: BIAS_WIDTH]}) -
                $signed({1'b0, i_bias_n_rows[ri * BIAS_WIDTH +: BIAS_WIDTH]});
            expected_sum[ri] = {{(MAC_ACC_WIDTH - BIAS_WIDTH - 1){bias_term[BIAS_WIDTH]}}, bias_term};
            for (ti = 0; ti < DEGREE; ti = ti + 1) begin
                state_term =
                    $signed({1'b0, state_p_terms_rows[(ri * DEGREE + ti) * DATA_WIDTH +: DATA_WIDTH]}) -
                    $signed({1'b0, state_n_terms_rows[(ri * DEGREE + ti) * DATA_WIDTH +: DATA_WIDTH]});
                coeff_term =
                    $signed({1'b0, i_coeff_p_terms_rows[(ri * DEGREE + ti) * BIT_WIDTH +: BIT_WIDTH]}) -
                    $signed({1'b0, i_coeff_n_terms_rows[(ri * DEGREE + ti) * BIT_WIDTH +: BIT_WIDTH]});
                expected_sum[ri] = expected_sum[ri] + (state_term * coeff_term);
            end
            rail_from_sum(expected_sum[ri], expected_p[ri], expected_n[ri]);
            old_state_term =
                $signed({1'b0, i_old_state_p_rows[ri * DATA_WIDTH +: DATA_WIDTH]}) -
                $signed({1'b0, i_old_state_n_rows[ri * DATA_WIDTH +: DATA_WIDTH]});
            expected_abs[ri] = (expected_sum[ri] >= old_state_term)
                ? (expected_sum[ri] - old_state_term + i_tail_bound)
                : (old_state_term - expected_sum[ri] + i_tail_bound);
        end

        for (bi = 0; bi < NUM_BLOCKS; bi = bi + 1) begin
            expected_block[bi] = expected_abs[bi * BLOCK_SIZE];
            for (ri = bi * BLOCK_SIZE; ri < (bi + 1) * BLOCK_SIZE; ri = ri + 1) begin
                if (expected_abs[ri] > expected_block[bi]) begin
                    expected_block[bi] = expected_abs[ri];
                end
            end
        end

        expected_max_error = {ACC_WIDTH{1'b0}};
        for (ri = 0; ri < NUM_ROWS; ri = ri + 1) begin
            expected_row_error = {ACC_WIDTH{1'b0}};
            for (bi = 0; bi < NUM_BLOCKS; bi = bi + 1) begin
                expected_row_error = expected_row_error +
                    expected_block[bi] * i_block_weights[(ri * NUM_BLOCKS + bi) * COEFF_WIDTH +: COEFF_WIDTH];
            end
            if (expected_row_error > expected_max_error) begin
                expected_max_error = expected_row_error;
            end
        end

        for (di = 0; di < DATA_WIDTH; di = di + 1) begin
            bit_sel = DATA_WIDTH - 1 - di;
            for (ri = 0; ri < NUM_ROWS; ri = ri + 1) begin
                for (ti = 0; ti < DEGREE; ti = ti + 1) begin
                    i_state_digit_p_terms_rows[ri * DEGREE + ti] =
                        state_p_terms_rows[(ri * DEGREE + ti) * DATA_WIDTH + bit_sel];
                    i_state_digit_n_terms_rows[ri * DEGREE + ti] =
                        state_n_terms_rows[(ri * DEGREE + ti) * DATA_WIDTH + bit_sel];
                end
            end
            i_digit_idx = di[DIGIT_IDX_WIDTH - 1 : 0];
            i_valid_digit = 1'b1;
            i_last_digit = (di == DATA_WIDTH - 1);
            i_start = (di == 0);
            @(negedge i_clk);
        end

        i_start = 1'b0;
        i_valid_digit = 1'b0;
        i_last_digit = 1'b0;
        wait_count = 0;
        while (!o_cluster_valid && wait_count < 16) begin
            @(negedge i_clk);
            wait_count = wait_count + 1;
        end
        #1;

        if (!o_cluster_valid ||
            o_cluster_max_error !== expected_max_error ||
            o_cluster_certified !== (expected_max_error <= i_eta)) begin
            $display("ERROR cluster cert valid=%0d max=%0d/%0d cert=%0d/%0d",
                o_cluster_valid,
                o_cluster_max_error,
                expected_max_error,
                o_cluster_certified,
                (expected_max_error <= i_eta));
            $fatal;
        end

        for (ri = 0; ri < NUM_ROWS; ri = ri + 1) begin
            if (o_sum_rows[ri * MAC_ACC_WIDTH +: MAC_ACC_WIDTH] !== expected_sum[ri] ||
                o_sum_p_rows[ri * DATA_WIDTH +: DATA_WIDTH] !== expected_p[ri] ||
                o_sum_n_rows[ri * DATA_WIDTH +: DATA_WIDTH] !== expected_n[ri] ||
                o_abs_upper_rows[ri * BOUND_WIDTH +: BOUND_WIDTH] !== expected_abs[ri]) begin
                $display("ERROR row %0d full-digit cluster output mismatch", ri);
                $fatal;
            end
        end

        $display("PASS tb_iter_digit_serial_full_row_cluster_delta_cert");
        $finish;
    end
endmodule
