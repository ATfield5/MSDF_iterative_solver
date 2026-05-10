`timescale 1ns / 1ps

module tb_iter_wavefront_radius1_two_stage_cluster;
    localparam integer NUM_ROWS = 3;
    localparam integer DEGREE = 4;
    localparam integer BIT_WIDTH = 5;
    localparam integer DATA_WIDTH = 8;
    localparam integer BIAS_WIDTH = BIT_WIDTH + 2;
    localparam integer DIGIT_IDX_WIDTH = $clog2(DATA_WIDTH);

    reg i_clk;
    reg i_rst;
    reg i_start;
    reg i_valid_digit;
    reg [DIGIT_IDX_WIDTH - 1 : 0] i_digit_idx;
    reg [NUM_ROWS * DEGREE - 1 : 0] i_stage0_state_digit_p_terms_rows;
    reg [NUM_ROWS * DEGREE - 1 : 0] i_stage0_state_digit_n_terms_rows;
    reg [NUM_ROWS * DEGREE * BIT_WIDTH - 1 : 0] i_stage0_coeff_p_terms_rows;
    reg [NUM_ROWS * DEGREE * BIT_WIDTH - 1 : 0] i_stage0_coeff_n_terms_rows;
    reg [NUM_ROWS * BIAS_WIDTH - 1 : 0] i_stage0_bias_p_rows;
    reg [NUM_ROWS * BIAS_WIDTH - 1 : 0] i_stage0_bias_n_rows;
    reg [NUM_ROWS * DEGREE * BIT_WIDTH - 1 : 0] i_stage1_coeff_p_terms_rows;
    reg [NUM_ROWS * DEGREE * BIT_WIDTH - 1 : 0] i_stage1_coeff_n_terms_rows;
    reg [NUM_ROWS * BIAS_WIDTH - 1 : 0] i_stage1_bias_p_rows;
    reg [NUM_ROWS * BIAS_WIDTH - 1 : 0] i_stage1_bias_n_rows;

    wire [NUM_ROWS - 1 : 0] w_stage0_valid_rows;
    wire [NUM_ROWS - 1 : 0] w_stage0_digit_p_rows;
    wire [NUM_ROWS - 1 : 0] w_stage0_digit_n_rows;
    wire [NUM_ROWS - 1 : 0] w_stage1_valid_rows;
    wire [NUM_ROWS - 1 : 0] w_stage1_digit_p_rows;
    wire [NUM_ROWS - 1 : 0] w_stage1_digit_n_rows;
    wire [31 : 0] w_stage0_valid_count;
    wire [31 : 0] w_stage1_valid_count;
    wire w_stage1_started_before_stage0_done;
    wire w_stage0_done;
    wire w_stage1_done;

    reg ref_rst;
    reg ref_start;
    reg ref_valid_digit;
    reg [DIGIT_IDX_WIDTH - 1 : 0] ref_digit_idx;
    reg [NUM_ROWS * DEGREE - 1 : 0] ref_state_digit_p_terms_rows;
    reg [NUM_ROWS * DEGREE - 1 : 0] ref_state_digit_n_terms_rows;
    wire [NUM_ROWS - 1 : 0] ref_valid_rows;
    wire [NUM_ROWS - 1 : 0] ref_digit_p_rows;
    wire [NUM_ROWS - 1 : 0] ref_digit_n_rows;

    reg [NUM_ROWS * DATA_WIDTH - 1 : 0] captured_stage0_p_rows;
    reg [NUM_ROWS * DATA_WIDTH - 1 : 0] captured_stage0_n_rows;
    reg [NUM_ROWS * DATA_WIDTH - 1 : 0] captured_wavefront_stage1_p_rows;
    reg [NUM_ROWS * DATA_WIDTH - 1 : 0] captured_wavefront_stage1_n_rows;
    reg [NUM_ROWS * DATA_WIDTH - 1 : 0] captured_ref_stage1_p_rows;
    reg [NUM_ROWS * DATA_WIDTH - 1 : 0] captured_ref_stage1_n_rows;
    reg [31 : 0] stage0_capture_count;
    reg [31 : 0] wavefront_capture_count;
    reg [31 : 0] ref_capture_count;
    reg [31 : 0] cycle_count;
    reg [31 : 0] stage0_done_cycle;
    reg [31 : 0] wavefront_done_cycle;
    reg [31 : 0] ref_elapsed_cycle;
    reg stage0_done_seen;
    reg wavefront_done_seen;
    integer di;
    integer ri;
    integer wait_count;
    integer fullwait_done_cycle;

    iter_wavefront_radius1_two_stage_cluster #(
        .num_rows(NUM_ROWS),
        .degree(DEGREE),
        .bit_width(BIT_WIDTH),
        .data_width(DATA_WIDTH),
        .bias_width(BIAS_WIDTH)
    ) dut (
        .i_clk(i_clk),
        .i_rst(i_rst),
        .i_start(i_start),
        .i_valid_digit(i_valid_digit),
        .i_digit_idx(i_digit_idx),
        .i_stage0_state_digit_p_terms_rows(i_stage0_state_digit_p_terms_rows),
        .i_stage0_state_digit_n_terms_rows(i_stage0_state_digit_n_terms_rows),
        .i_stage0_coeff_p_terms_rows(i_stage0_coeff_p_terms_rows),
        .i_stage0_coeff_n_terms_rows(i_stage0_coeff_n_terms_rows),
        .i_stage0_bias_p_rows(i_stage0_bias_p_rows),
        .i_stage0_bias_n_rows(i_stage0_bias_n_rows),
        .i_stage1_coeff_p_terms_rows(i_stage1_coeff_p_terms_rows),
        .i_stage1_coeff_n_terms_rows(i_stage1_coeff_n_terms_rows),
        .i_stage1_bias_p_rows(i_stage1_bias_p_rows),
        .i_stage1_bias_n_rows(i_stage1_bias_n_rows),
        .o_stage0_valid_rows(w_stage0_valid_rows),
        .o_stage0_digit_p_rows(w_stage0_digit_p_rows),
        .o_stage0_digit_n_rows(w_stage0_digit_n_rows),
        .o_stage1_valid_rows(w_stage1_valid_rows),
        .o_stage1_digit_p_rows(w_stage1_digit_p_rows),
        .o_stage1_digit_n_rows(w_stage1_digit_n_rows),
        .o_stage0_valid_count(w_stage0_valid_count),
        .o_stage1_valid_count(w_stage1_valid_count),
        .o_stage1_started_before_stage0_done(w_stage1_started_before_stage0_done),
        .o_stage0_done(w_stage0_done),
        .o_stage1_done(w_stage1_done)
    );

    genvar gi;
    generate
        for (gi = 0; gi < NUM_ROWS; gi = gi + 1) begin : gen_ref
            iter_solver_native_row_digit_engine #(
                .bit_width(BIT_WIDTH),
                .degree(DEGREE),
                .data_width(DATA_WIDTH),
                .bias_width(BIAS_WIDTH)
            ) ref_engine (
                .i_clk(i_clk),
                .i_rst(ref_rst),
                .i_start(ref_start),
                .i_valid_digit(ref_valid_digit),
                .i_digit_idx(ref_digit_idx),
                .i_state_digit_p_terms(ref_state_digit_p_terms_rows[gi * DEGREE +: DEGREE]),
                .i_state_digit_n_terms(ref_state_digit_n_terms_rows[gi * DEGREE +: DEGREE]),
                .i_coeff_p_terms(i_stage1_coeff_p_terms_rows[gi * DEGREE * BIT_WIDTH +: DEGREE * BIT_WIDTH]),
                .i_coeff_n_terms(i_stage1_coeff_n_terms_rows[gi * DEGREE * BIT_WIDTH +: DEGREE * BIT_WIDTH]),
                .i_bias_p(i_stage1_bias_p_rows[gi * BIAS_WIDTH +: BIAS_WIDTH]),
                .i_bias_n(i_stage1_bias_n_rows[gi * BIAS_WIDTH +: BIAS_WIDTH]),
                .o_valid(ref_valid_rows[gi]),
                .o_x_new_digit_p(ref_digit_p_rows[gi]),
                .o_x_new_digit_n(ref_digit_n_rows[gi]),
                .o_affine_p(),
                .o_affine_n(),
                .o_residual_p(),
                .o_residual_n()
            );
        end
    endgenerate

    always #5 i_clk = ~i_clk;

    task set_coeff;
        input integer row;
        input integer term;
        input integer val;
        begin
            i_stage0_coeff_p_terms_rows[(row * DEGREE + term) * BIT_WIDTH +: BIT_WIDTH] =
                val[BIT_WIDTH - 1 : 0];
        end
    endtask

    task set_stage1_coeff;
        input integer row;
        input integer term;
        input integer val;
        begin
            i_stage1_coeff_p_terms_rows[(row * DEGREE + term) * BIT_WIDTH +: BIT_WIDTH] =
                val[BIT_WIDTH - 1 : 0];
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

    task set_ref_stage1_source_digits;
        input integer digit_idx;
        integer row;
        begin
            ref_state_digit_p_terms_rows = {NUM_ROWS * DEGREE{1'b0}};
            ref_state_digit_n_terms_rows = {NUM_ROWS * DEGREE{1'b0}};
            for (row = 0; row < NUM_ROWS; row = row + 1) begin
                if (row > 0) begin
                    ref_state_digit_p_terms_rows[row * DEGREE + 0] =
                        captured_stage0_p_rows[(row - 1) * DATA_WIDTH + digit_idx];
                    ref_state_digit_n_terms_rows[row * DEGREE + 0] =
                        captured_stage0_n_rows[(row - 1) * DATA_WIDTH + digit_idx];
                end
                ref_state_digit_p_terms_rows[row * DEGREE + 1] =
                    captured_stage0_p_rows[row * DATA_WIDTH + digit_idx];
                ref_state_digit_n_terms_rows[row * DEGREE + 1] =
                    captured_stage0_n_rows[row * DATA_WIDTH + digit_idx];
                if (row < NUM_ROWS - 1) begin
                    ref_state_digit_p_terms_rows[row * DEGREE + 2] =
                        captured_stage0_p_rows[(row + 1) * DATA_WIDTH + digit_idx];
                    ref_state_digit_n_terms_rows[row * DEGREE + 2] =
                        captured_stage0_n_rows[(row + 1) * DATA_WIDTH + digit_idx];
                end
            end
        end
    endtask

    always @(posedge i_clk) begin
        #1;
        if (i_rst || i_start) begin
            stage0_capture_count = 32'd0;
            wavefront_capture_count = 32'd0;
            captured_stage0_p_rows = {NUM_ROWS * DATA_WIDTH{1'b0}};
            captured_stage0_n_rows = {NUM_ROWS * DATA_WIDTH{1'b0}};
            captured_wavefront_stage1_p_rows = {NUM_ROWS * DATA_WIDTH{1'b0}};
            captured_wavefront_stage1_n_rows = {NUM_ROWS * DATA_WIDTH{1'b0}};
            cycle_count = 32'd0;
            stage0_done_cycle = 32'd0;
            wavefront_done_cycle = 32'd0;
            stage0_done_seen = 1'b0;
            wavefront_done_seen = 1'b0;
        end else begin
            cycle_count = cycle_count + 1'b1;
            if (w_stage0_valid_rows[0]) begin
                for (ri = 0; ri < NUM_ROWS; ri = ri + 1) begin
                    captured_stage0_p_rows[ri * DATA_WIDTH + stage0_capture_count] =
                        w_stage0_digit_p_rows[ri];
                    captured_stage0_n_rows[ri * DATA_WIDTH + stage0_capture_count] =
                        w_stage0_digit_n_rows[ri];
                end
                stage0_capture_count = stage0_capture_count + 1'b1;
            end
            if (w_stage1_valid_rows[0]) begin
                for (ri = 0; ri < NUM_ROWS; ri = ri + 1) begin
                    captured_wavefront_stage1_p_rows[ri * DATA_WIDTH + wavefront_capture_count] =
                        w_stage1_digit_p_rows[ri];
                    captured_wavefront_stage1_n_rows[ri * DATA_WIDTH + wavefront_capture_count] =
                        w_stage1_digit_n_rows[ri];
                end
                wavefront_capture_count = wavefront_capture_count + 1'b1;
            end
            if (!stage0_done_seen && w_stage0_done) begin
                stage0_done_seen = 1'b1;
                stage0_done_cycle = cycle_count;
            end
            if (!wavefront_done_seen && w_stage1_done) begin
                wavefront_done_seen = 1'b1;
                wavefront_done_cycle = cycle_count;
            end
        end
    end

    always @(posedge i_clk) begin
        #1;
        if (ref_rst || ref_start) begin
            ref_capture_count = 32'd0;
            captured_ref_stage1_p_rows = {NUM_ROWS * DATA_WIDTH{1'b0}};
            captured_ref_stage1_n_rows = {NUM_ROWS * DATA_WIDTH{1'b0}};
            ref_elapsed_cycle = 32'd0;
        end else begin
            ref_elapsed_cycle = ref_elapsed_cycle + 1'b1;
            if (ref_valid_rows[0]) begin
                for (ri = 0; ri < NUM_ROWS; ri = ri + 1) begin
                    captured_ref_stage1_p_rows[ri * DATA_WIDTH + ref_capture_count] =
                        ref_digit_p_rows[ri];
                    captured_ref_stage1_n_rows[ri * DATA_WIDTH + ref_capture_count] =
                        ref_digit_n_rows[ri];
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
        i_stage0_coeff_p_terms_rows = {NUM_ROWS * DEGREE * BIT_WIDTH{1'b0}};
        i_stage0_coeff_n_terms_rows = {NUM_ROWS * DEGREE * BIT_WIDTH{1'b0}};
        i_stage0_bias_p_rows = {NUM_ROWS * BIAS_WIDTH{1'b0}};
        i_stage0_bias_n_rows = {NUM_ROWS * BIAS_WIDTH{1'b0}};
        i_stage1_coeff_p_terms_rows = {NUM_ROWS * DEGREE * BIT_WIDTH{1'b0}};
        i_stage1_coeff_n_terms_rows = {NUM_ROWS * DEGREE * BIT_WIDTH{1'b0}};
        i_stage1_bias_p_rows = {NUM_ROWS * BIAS_WIDTH{1'b0}};
        i_stage1_bias_n_rows = {NUM_ROWS * BIAS_WIDTH{1'b0}};
        ref_rst = 1'b1;
        ref_start = 1'b0;
        ref_valid_digit = 1'b0;
        ref_digit_idx = {DIGIT_IDX_WIDTH{1'b0}};
        ref_state_digit_p_terms_rows = {NUM_ROWS * DEGREE{1'b0}};
        ref_state_digit_n_terms_rows = {NUM_ROWS * DEGREE{1'b0}};

        for (ri = 0; ri < NUM_ROWS; ri = ri + 1) begin
            set_coeff(ri, 0, ri + 1);
            set_coeff(ri, 1, 2);
            set_coeff(ri, 2, 3);
            set_coeff(ri, 3, 1);
            set_stage1_coeff(ri, 0, 1);
            set_stage1_coeff(ri, 1, 2);
            set_stage1_coeff(ri, 2, 1);
        end
        i_stage0_bias_p_rows[0 * BIAS_WIDTH +: BIAS_WIDTH] = 7'd3;
        i_stage0_bias_p_rows[1 * BIAS_WIDTH +: BIAS_WIDTH] = 7'd1;
        i_stage0_bias_n_rows[2 * BIAS_WIDTH +: BIAS_WIDTH] = 7'd2;

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
        while (!wavefront_done_seen && wait_count < 64) begin
            @(negedge i_clk);
            wait_count = wait_count + 1;
        end

        if (!wavefront_done_seen ||
            stage0_capture_count !== DATA_WIDTH ||
            wavefront_capture_count !== DATA_WIDTH ||
            !w_stage1_started_before_stage0_done) begin
            $display("ERROR radius1 wavefront lifecycle stage0_count=%0d stage1_count=%0d started_before_done=%0d",
                stage0_capture_count,
                wavefront_capture_count,
                w_stage1_started_before_stage0_done);
            $fatal;
        end

        ref_rst = 1'b0;
        for (di = 0; di < DATA_WIDTH; di = di + 1) begin
            @(negedge i_clk);
            set_ref_stage1_source_digits(di);
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
        while (ref_capture_count < DATA_WIDTH && wait_count < 64) begin
            @(negedge i_clk);
            wait_count = wait_count + 1;
        end

        if (ref_capture_count !== DATA_WIDTH) begin
            $display("ERROR radius1 fullwait reference count=%0d", ref_capture_count);
            $fatal;
        end

        if (captured_wavefront_stage1_p_rows !== captured_ref_stage1_p_rows ||
            captured_wavefront_stage1_n_rows !== captured_ref_stage1_n_rows) begin
            $display("ERROR radius1 wavefront/reference mismatch wf=%h/%h ref=%h/%h",
                captured_wavefront_stage1_p_rows,
                captured_wavefront_stage1_n_rows,
                captured_ref_stage1_p_rows,
                captured_ref_stage1_n_rows);
            $fatal;
        end

        fullwait_done_cycle = stage0_done_cycle + ref_elapsed_cycle;
        if (wavefront_done_cycle >= fullwait_done_cycle) begin
            $display("ERROR expected radius1 wavefront faster wavefront=%0d fullwait=%0d",
                wavefront_done_cycle,
                fullwait_done_cycle);
            $fatal;
        end

        $display("PASS tb_iter_wavefront_radius1_two_stage_cluster");
        $display("INFO stage0_done_cycle=%0d wavefront_done_cycle=%0d fullwait_model_cycle=%0d saved_cycles=%0d",
            stage0_done_cycle,
            wavefront_done_cycle,
            fullwait_done_cycle,
            fullwait_done_cycle - wavefront_done_cycle);
        $finish;
    end
endmodule
