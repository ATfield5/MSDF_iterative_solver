`timescale 1ns / 1ps

module tb_iter_wavefront_two_stage_row_pipeline;
    localparam integer BIT_WIDTH = 5;
    localparam integer DEGREE = 4;
    localparam integer DATA_WIDTH = 8;
    localparam integer BIAS_WIDTH = BIT_WIDTH + 2;
    localparam integer DIGIT_IDX_WIDTH = $clog2(DATA_WIDTH);

    reg i_clk;
    reg i_rst;
    reg i_start;
    reg i_valid_digit;
    reg [DIGIT_IDX_WIDTH - 1 : 0] i_digit_idx;
    reg [DEGREE - 1 : 0] i_stage0_state_digit_p_terms;
    reg [DEGREE - 1 : 0] i_stage0_state_digit_n_terms;
    reg [DEGREE * BIT_WIDTH - 1 : 0] i_stage0_coeff_p_terms;
    reg [DEGREE * BIT_WIDTH - 1 : 0] i_stage0_coeff_n_terms;
    reg [BIAS_WIDTH - 1 : 0] i_stage0_bias_p;
    reg [BIAS_WIDTH - 1 : 0] i_stage0_bias_n;
    reg [DEGREE * BIT_WIDTH - 1 : 0] i_stage1_coeff_p_terms;
    reg [DEGREE * BIT_WIDTH - 1 : 0] i_stage1_coeff_n_terms;
    reg [BIAS_WIDTH - 1 : 0] i_stage1_bias_p;
    reg [BIAS_WIDTH - 1 : 0] i_stage1_bias_n;

    wire w_stage0_valid;
    wire w_stage0_digit_p;
    wire w_stage0_digit_n;
    wire w_stage1_valid;
    wire w_stage1_digit_p;
    wire w_stage1_digit_n;
    wire [31 : 0] w_stage0_valid_count;
    wire [31 : 0] w_stage1_valid_count;
    wire w_stage1_started_before_stage0_done;
    wire w_stage0_done;
    wire w_stage1_done;

    reg ref_rst;
    reg ref_start;
    reg ref_valid_digit;
    reg [DIGIT_IDX_WIDTH - 1 : 0] ref_digit_idx;
    reg [DEGREE - 1 : 0] ref_state_digit_p_terms;
    reg [DEGREE - 1 : 0] ref_state_digit_n_terms;
    wire ref_valid;
    wire ref_digit_p;
    wire ref_digit_n;

    reg [DATA_WIDTH - 1 : 0] captured_stage0_p;
    reg [DATA_WIDTH - 1 : 0] captured_stage0_n;
    reg [DATA_WIDTH - 1 : 0] captured_wavefront_stage1_p;
    reg [DATA_WIDTH - 1 : 0] captured_wavefront_stage1_n;
    reg [DATA_WIDTH - 1 : 0] captured_ref_stage1_p;
    reg [DATA_WIDTH - 1 : 0] captured_ref_stage1_n;
    reg [31 : 0] stage0_capture_count;
    reg [31 : 0] wavefront_stage1_capture_count;
    reg [31 : 0] ref_stage1_capture_count;
    reg [31 : 0] cycle_count;
    reg [31 : 0] stage0_done_cycle;
    reg [31 : 0] wavefront_done_cycle;
    reg [31 : 0] ref_elapsed_cycle;
    reg stage0_done_seen;
    reg wavefront_done_seen;
    integer di;
    integer wait_count;
    integer fullwait_done_cycle;

    iter_wavefront_two_stage_row_pipeline #(
        .bit_width(BIT_WIDTH),
        .degree(DEGREE),
        .data_width(DATA_WIDTH),
        .bias_width(BIAS_WIDTH)
    ) dut (
        .i_clk(i_clk),
        .i_rst(i_rst),
        .i_start(i_start),
        .i_valid_digit(i_valid_digit),
        .i_digit_idx(i_digit_idx),
        .i_stage0_state_digit_p_terms(i_stage0_state_digit_p_terms),
        .i_stage0_state_digit_n_terms(i_stage0_state_digit_n_terms),
        .i_stage0_coeff_p_terms(i_stage0_coeff_p_terms),
        .i_stage0_coeff_n_terms(i_stage0_coeff_n_terms),
        .i_stage0_bias_p(i_stage0_bias_p),
        .i_stage0_bias_n(i_stage0_bias_n),
        .i_stage1_coeff_p_terms(i_stage1_coeff_p_terms),
        .i_stage1_coeff_n_terms(i_stage1_coeff_n_terms),
        .i_stage1_bias_p(i_stage1_bias_p),
        .i_stage1_bias_n(i_stage1_bias_n),
        .o_stage0_valid(w_stage0_valid),
        .o_stage0_digit_p(w_stage0_digit_p),
        .o_stage0_digit_n(w_stage0_digit_n),
        .o_stage1_valid(w_stage1_valid),
        .o_stage1_digit_p(w_stage1_digit_p),
        .o_stage1_digit_n(w_stage1_digit_n),
        .o_stage0_valid_count(w_stage0_valid_count),
        .o_stage1_valid_count(w_stage1_valid_count),
        .o_stage1_started_before_stage0_done(w_stage1_started_before_stage0_done),
        .o_stage0_done(w_stage0_done),
        .o_stage1_done(w_stage1_done)
    );

    iter_solver_native_row_digit_engine #(
        .bit_width(BIT_WIDTH),
        .degree(DEGREE),
        .data_width(DATA_WIDTH),
        .bias_width(BIAS_WIDTH)
    ) ref_stage1 (
        .i_clk(i_clk),
        .i_rst(ref_rst),
        .i_start(ref_start),
        .i_valid_digit(ref_valid_digit),
        .i_digit_idx(ref_digit_idx),
        .i_state_digit_p_terms(ref_state_digit_p_terms),
        .i_state_digit_n_terms(ref_state_digit_n_terms),
        .i_coeff_p_terms(i_stage1_coeff_p_terms),
        .i_coeff_n_terms(i_stage1_coeff_n_terms),
        .i_bias_p(i_stage1_bias_p),
        .i_bias_n(i_stage1_bias_n),
        .o_valid(ref_valid),
        .o_x_new_digit_p(ref_digit_p),
        .o_x_new_digit_n(ref_digit_n),
        .o_affine_p(),
        .o_affine_n(),
        .o_residual_p(),
        .o_residual_n()
    );

    always #5 i_clk = ~i_clk;

    task set_stage0_source_digit;
        input integer digit_idx;
        begin
            i_stage0_state_digit_p_terms = {DEGREE{1'b0}};
            i_stage0_state_digit_n_terms = {DEGREE{1'b0}};
            i_stage0_state_digit_p_terms[0] = (digit_idx[0] == 1'b0);
            i_stage0_state_digit_p_terms[1] = (digit_idx[1:0] == 2'd1);
            i_stage0_state_digit_n_terms[2] = ((digit_idx % 3) == 1);
            i_stage0_state_digit_p_terms[3] = (digit_idx == 5);
        end
    endtask

    always @(posedge i_clk) begin
        #1;
        if (i_rst || i_start) begin
            stage0_capture_count = 32'd0;
            wavefront_stage1_capture_count = 32'd0;
            captured_stage0_p = {DATA_WIDTH{1'b0}};
            captured_stage0_n = {DATA_WIDTH{1'b0}};
            captured_wavefront_stage1_p = {DATA_WIDTH{1'b0}};
            captured_wavefront_stage1_n = {DATA_WIDTH{1'b0}};
            cycle_count = 32'd0;
            stage0_done_cycle = 32'd0;
            wavefront_done_cycle = 32'd0;
            stage0_done_seen = 1'b0;
            wavefront_done_seen = 1'b0;
        end else begin
            cycle_count = cycle_count + 1'b1;
            if (w_stage0_valid) begin
                captured_stage0_p[stage0_capture_count] = w_stage0_digit_p;
                captured_stage0_n[stage0_capture_count] = w_stage0_digit_n;
                stage0_capture_count = stage0_capture_count + 1'b1;
            end
            if (w_stage1_valid) begin
                captured_wavefront_stage1_p[wavefront_stage1_capture_count] = w_stage1_digit_p;
                captured_wavefront_stage1_n[wavefront_stage1_capture_count] = w_stage1_digit_n;
                wavefront_stage1_capture_count = wavefront_stage1_capture_count + 1'b1;
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
            ref_stage1_capture_count = 32'd0;
            captured_ref_stage1_p = {DATA_WIDTH{1'b0}};
            captured_ref_stage1_n = {DATA_WIDTH{1'b0}};
            ref_elapsed_cycle = 32'd0;
        end else begin
            ref_elapsed_cycle = ref_elapsed_cycle + 1'b1;
            if (ref_valid) begin
                captured_ref_stage1_p[ref_stage1_capture_count] = ref_digit_p;
                captured_ref_stage1_n[ref_stage1_capture_count] = ref_digit_n;
                ref_stage1_capture_count = ref_stage1_capture_count + 1'b1;
            end
        end
    end

    initial begin
        i_clk = 1'b0;
        i_rst = 1'b1;
        i_start = 1'b0;
        i_valid_digit = 1'b0;
        i_digit_idx = {DIGIT_IDX_WIDTH{1'b0}};
        i_stage0_state_digit_p_terms = {DEGREE{1'b0}};
        i_stage0_state_digit_n_terms = {DEGREE{1'b0}};
        i_stage0_coeff_p_terms = {DEGREE * BIT_WIDTH{1'b0}};
        i_stage0_coeff_n_terms = {DEGREE * BIT_WIDTH{1'b0}};
        i_stage0_bias_p = 7'b0010101;
        i_stage0_bias_n = 7'b0000000;
        i_stage1_coeff_p_terms = {DEGREE * BIT_WIDTH{1'b0}};
        i_stage1_coeff_n_terms = {DEGREE * BIT_WIDTH{1'b0}};
        i_stage1_bias_p = {BIAS_WIDTH{1'b0}};
        i_stage1_bias_n = {BIAS_WIDTH{1'b0}};
        ref_rst = 1'b1;
        ref_start = 1'b0;
        ref_valid_digit = 1'b0;
        ref_digit_idx = {DIGIT_IDX_WIDTH{1'b0}};
        ref_state_digit_p_terms = {DEGREE{1'b0}};
        ref_state_digit_n_terms = {DEGREE{1'b0}};

        i_stage0_coeff_p_terms[0 * BIT_WIDTH +: BIT_WIDTH] = 5'd1;
        i_stage0_coeff_p_terms[1 * BIT_WIDTH +: BIT_WIDTH] = 5'd2;
        i_stage0_coeff_p_terms[2 * BIT_WIDTH +: BIT_WIDTH] = 5'd4;
        i_stage0_coeff_p_terms[3 * BIT_WIDTH +: BIT_WIDTH] = 5'd1;
        i_stage1_coeff_p_terms[0 * BIT_WIDTH +: BIT_WIDTH] = 5'd1;

        repeat (2) @(posedge i_clk);
        i_rst = 1'b0;

        for (di = 0; di < DATA_WIDTH; di = di + 1) begin
            @(negedge i_clk);
            set_stage0_source_digit(di);
            i_start = (di == 0);
            i_valid_digit = 1'b1;
            i_digit_idx = di[DIGIT_IDX_WIDTH - 1 : 0];
        end

        @(negedge i_clk);
        i_start = 1'b0;
        i_valid_digit = 1'b0;
        i_stage0_state_digit_p_terms = {DEGREE{1'b0}};
        i_stage0_state_digit_n_terms = {DEGREE{1'b0}};

        wait_count = 0;
        while (!wavefront_done_seen && wait_count < 64) begin
            @(negedge i_clk);
            wait_count = wait_count + 1;
        end

        if (!wavefront_done_seen ||
            stage0_capture_count !== DATA_WIDTH ||
            wavefront_stage1_capture_count !== DATA_WIDTH ||
            !w_stage1_started_before_stage0_done) begin
            $display("ERROR wavefront lifecycle stage0_count=%0d stage1_count=%0d started_before_done=%0d",
                stage0_capture_count,
                wavefront_stage1_capture_count,
                w_stage1_started_before_stage0_done);
            $fatal;
        end

        ref_rst = 1'b0;
        for (di = 0; di < DATA_WIDTH; di = di + 1) begin
            @(negedge i_clk);
            ref_state_digit_p_terms = {DEGREE{1'b0}};
            ref_state_digit_n_terms = {DEGREE{1'b0}};
            ref_state_digit_p_terms[0] = captured_stage0_p[di];
            ref_state_digit_n_terms[0] = captured_stage0_n[di];
            ref_start = (di == 0);
            ref_valid_digit = 1'b1;
            ref_digit_idx = di[DIGIT_IDX_WIDTH - 1 : 0];
        end

        @(negedge i_clk);
        ref_start = 1'b0;
        ref_valid_digit = 1'b0;
        ref_state_digit_p_terms = {DEGREE{1'b0}};
        ref_state_digit_n_terms = {DEGREE{1'b0}};

        wait_count = 0;
        while (ref_stage1_capture_count < DATA_WIDTH && wait_count < 64) begin
            @(negedge i_clk);
            wait_count = wait_count + 1;
        end

        if (ref_stage1_capture_count !== DATA_WIDTH) begin
            $display("ERROR full-wait reference count=%0d", ref_stage1_capture_count);
            $fatal;
        end

        if (captured_wavefront_stage1_p !== captured_ref_stage1_p ||
            captured_wavefront_stage1_n !== captured_ref_stage1_n) begin
            $display("ERROR wavefront/reference mismatch wf=%h/%h ref=%h/%h",
                captured_wavefront_stage1_p,
                captured_wavefront_stage1_n,
                captured_ref_stage1_p,
                captured_ref_stage1_n);
            $fatal;
        end

        fullwait_done_cycle = stage0_done_cycle + ref_elapsed_cycle;
        if (wavefront_done_cycle >= fullwait_done_cycle) begin
            $display("ERROR expected wavefront faster wavefront=%0d fullwait=%0d",
                wavefront_done_cycle,
                fullwait_done_cycle);
            $fatal;
        end

        $display("PASS tb_iter_wavefront_two_stage_row_pipeline");
        $display("INFO stage0_done_cycle=%0d wavefront_done_cycle=%0d fullwait_model_cycle=%0d saved_cycles=%0d",
            stage0_done_cycle,
            wavefront_done_cycle,
            fullwait_done_cycle,
            fullwait_done_cycle - wavefront_done_cycle);
        $finish;
    end
endmodule
