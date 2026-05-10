`timescale 1ns / 1ps

module tb_iter_prefix_safe_scheduler_solver_native_replay;
    localparam integer NUM_ROWS = 4;
    localparam integer DEGREE = 4;
    localparam integer DATA_WIDTH = 8;
    localparam integer BIT_WIDTH = DATA_WIDTH - 3;
    localparam integer COEFF_WIDTH = 8;
    localparam integer BIAS_WIDTH = BIT_WIDTH + 2;
    localparam integer MARGIN_WIDTH = 24;
    localparam integer DIGIT_IDX_WIDTH = $clog2(DATA_WIDTH);
    localparam integer ROW_ID_WIDTH = $clog2(NUM_ROWS);
    localparam integer LEAD_WIDTH = DIGIT_IDX_WIDTH + 1;
    localparam integer TABLE_BITS = NUM_ROWS * DATA_WIDTH * DEGREE;

    reg i_clk;
    reg i_rst;
    reg i_start;
    reg i_valid_prefix;
    reg [DIGIT_IDX_WIDTH - 1 : 0] i_digit_idx;
    reg [NUM_ROWS * DEGREE * COEFF_WIDTH - 1 : 0] i_coeff_abs_terms_rows;
    reg [NUM_ROWS * MARGIN_WIDTH - 1 : 0] i_selection_margin_rows;
    reg [TABLE_BITS - 1 : 0] r_digit_p_table;
    reg [TABLE_BITS - 1 : 0] r_digit_n_table;
    reg [DEGREE * BIT_WIDTH - 1 : 0] r_coeff_p_terms;
    reg [DEGREE * BIT_WIDTH - 1 : 0] r_coeff_n_terms;
    reg [BIAS_WIDTH - 1 : 0] r_bias_p;
    reg [BIAS_WIDTH - 1 : 0] r_bias_n;

    wire w_lane_ready;
    wire w_consumer_valid;
    wire [ROW_ID_WIDTH - 1 : 0] w_consumer_row_id;
    wire [DIGIT_IDX_WIDTH - 1 : 0] w_consumer_digit_idx;
    wire [LEAD_WIDTH - 1 : 0] w_consumer_lead_cycles;
    wire [NUM_ROWS - 1 : 0] w_queue_pending_mask;
    wire [31 : 0] w_dispatch_count;
    wire w_all_issued;
    wire w_duplicate_issue;

    wire w_source_req_valid;
    wire [ROW_ID_WIDTH - 1 : 0] w_source_req_row_id;
    wire [DIGIT_IDX_WIDTH - 1 : 0] w_source_req_digit_idx;
    wire [DEGREE - 1 : 0] w_replay_p_terms;
    wire [DEGREE - 1 : 0] w_replay_n_terms;
    wire w_replay_valid;
    wire w_x_valid;
    wire w_x_new_digit_p;
    wire w_x_new_digit_n;
    wire w_lane_done_pulse;
    wire [ROW_ID_WIDTH - 1 : 0] w_done_row_id;
    wire [DIGIT_IDX_WIDTH - 1 : 0] w_done_issue_digit_idx;
    wire [LEAD_WIDTH - 1 : 0] w_done_lead_cycles;
    wire [31 : 0] w_accept_count;
    wire [31 : 0] w_output_digit_count;
    wire [31 : 0] w_done_count;
    wire [LEAD_WIDTH - 1 : 0] w_max_lead_cycles;

    wire w_ref_valid;
    wire w_ref_digit_p;
    wire w_ref_digit_n;
    wire w_ref_start;

    reg [NUM_ROWS - 1 : 0] r_done_mask;
    reg [NUM_ROWS * DIGIT_IDX_WIDTH - 1 : 0] r_done_issue_digit_rows;
    reg [NUM_ROWS * LEAD_WIDTH - 1 : 0] r_done_lead_rows;
    reg [31 : 0] r_cycle_count;
    reg [31 : 0] r_source_req_count;
    reg [31 : 0] r_nonzero_source_count;
    reg [31 : 0] r_output_compare_count;

    iter_prefix_safe_two_stage_scheduler #(
        .num_rows(NUM_ROWS),
        .degree(DEGREE),
        .data_width(DATA_WIDTH),
        .coeff_width(COEFF_WIDTH),
        .margin_width(MARGIN_WIDTH)
    ) scheduler (
        .i_clk(i_clk),
        .i_rst(i_rst),
        .i_start(i_start),
        .i_valid_prefix(i_valid_prefix),
        .i_digit_idx(i_digit_idx),
        .i_coeff_abs_terms_rows(i_coeff_abs_terms_rows),
        .i_selection_margin_rows(i_selection_margin_rows),
        .i_consumer_ready(w_lane_ready),
        .o_consumer_valid(w_consumer_valid),
        .o_consumer_row_id(w_consumer_row_id),
        .o_consumer_digit_idx(w_consumer_digit_idx),
        .o_consumer_lead_cycles(w_consumer_lead_cycles),
        .o_row_issue_pulse(),
        .o_row_issued_mask(),
        .o_queue_pending_mask(w_queue_pending_mask),
        .o_queue_pending_count(),
        .o_dispatch_count(w_dispatch_count),
        .o_duplicate_issue(w_duplicate_issue),
        .o_all_issued(w_all_issued)
    );

    iter_prefix_safe_digit_replay_source #(
        .num_rows(NUM_ROWS),
        .degree(DEGREE),
        .data_width(DATA_WIDTH)
    ) replay_source (
        .i_req_valid(w_source_req_valid),
        .i_req_row_id(w_source_req_row_id),
        .i_req_digit_idx(w_source_req_digit_idx),
        .i_digit_p_table(r_digit_p_table),
        .i_digit_n_table(r_digit_n_table),
        .o_resp_valid(w_replay_valid),
        .o_state_digit_p_terms(w_replay_p_terms),
        .o_state_digit_n_terms(w_replay_n_terms)
    );

    iter_prefix_safe_solver_native_row_lane #(
        .num_rows(NUM_ROWS),
        .bit_width(BIT_WIDTH),
        .degree(DEGREE),
        .data_width(DATA_WIDTH),
        .bias_width(BIAS_WIDTH)
    ) row_lane (
        .i_clk(i_clk),
        .i_rst(i_rst),
        .i_start(i_start),
        .i_cmd_valid(w_consumer_valid),
        .o_cmd_ready(w_lane_ready),
        .i_cmd_row_id(w_consumer_row_id),
        .i_cmd_digit_idx(w_consumer_digit_idx),
        .i_cmd_lead_cycles(w_consumer_lead_cycles),
        .o_source_req_valid(w_source_req_valid),
        .o_source_req_row_id(w_source_req_row_id),
        .o_source_req_digit_idx(w_source_req_digit_idx),
        .i_state_digit_p_terms(w_replay_p_terms),
        .i_state_digit_n_terms(w_replay_n_terms),
        .i_coeff_p_terms(r_coeff_p_terms),
        .i_coeff_n_terms(r_coeff_n_terms),
        .i_bias_p(r_bias_p),
        .i_bias_n(r_bias_n),
        .o_x_valid(w_x_valid),
        .o_x_new_digit_p(w_x_new_digit_p),
        .o_x_new_digit_n(w_x_new_digit_n),
        .o_busy(),
        .o_done_pulse(w_lane_done_pulse),
        .o_done_row_id(w_done_row_id),
        .o_done_issue_digit_idx(w_done_issue_digit_idx),
        .o_done_lead_cycles(w_done_lead_cycles),
        .o_accept_count(w_accept_count),
        .o_output_digit_count(w_output_digit_count),
        .o_done_count(w_done_count),
        .o_max_lead_cycles(w_max_lead_cycles)
    );

    assign w_ref_start = w_source_req_valid &&
        (w_source_req_digit_idx == {DIGIT_IDX_WIDTH{1'b0}});

    iter_solver_native_row_digit_engine #(
        .bit_width(BIT_WIDTH),
        .degree(DEGREE),
        .data_width(DATA_WIDTH),
        .bias_width(BIAS_WIDTH)
    ) ref_engine (
        .i_clk(i_clk),
        .i_rst(i_rst),
        .i_start(w_ref_start),
        .i_valid_digit(w_source_req_valid),
        .i_digit_idx(w_source_req_digit_idx),
        .i_state_digit_p_terms(w_replay_p_terms),
        .i_state_digit_n_terms(w_replay_n_terms),
        .i_coeff_p_terms(r_coeff_p_terms),
        .i_coeff_n_terms(r_coeff_n_terms),
        .i_bias_p(r_bias_p),
        .i_bias_n(r_bias_n),
        .o_valid(w_ref_valid),
        .o_x_new_digit_p(w_ref_digit_p),
        .o_x_new_digit_n(w_ref_digit_n),
        .o_affine_p(),
        .o_affine_n(),
        .o_residual_p(),
        .o_residual_n()
    );

    always #5 i_clk = ~i_clk;

    task set_row_coeffs;
        input integer row;
        input integer c0;
        input integer c1;
        input integer c2;
        input integer c3;
        begin
            i_coeff_abs_terms_rows[row * DEGREE * COEFF_WIDTH + 0 * COEFF_WIDTH +: COEFF_WIDTH] =
                c0[COEFF_WIDTH - 1 : 0];
            i_coeff_abs_terms_rows[row * DEGREE * COEFF_WIDTH + 1 * COEFF_WIDTH +: COEFF_WIDTH] =
                c1[COEFF_WIDTH - 1 : 0];
            i_coeff_abs_terms_rows[row * DEGREE * COEFF_WIDTH + 2 * COEFF_WIDTH +: COEFF_WIDTH] =
                c2[COEFF_WIDTH - 1 : 0];
            i_coeff_abs_terms_rows[row * DEGREE * COEFF_WIDTH + 3 * COEFF_WIDTH +: COEFF_WIDTH] =
                c3[COEFF_WIDTH - 1 : 0];
        end
    endtask

    task set_row_margin;
        input integer row;
        input integer margin;
        begin
            i_selection_margin_rows[row * MARGIN_WIDTH +: MARGIN_WIDTH] =
                margin[MARGIN_WIDTH - 1 : 0];
        end
    endtask

    task set_source_digit;
        input integer row;
        input integer digit;
        input [DEGREE - 1 : 0] p_terms;
        input [DEGREE - 1 : 0] n_terms;
        integer base;
        begin
            base = ((row * DATA_WIDTH + digit) * DEGREE);
            r_digit_p_table[base +: DEGREE] = p_terms;
            r_digit_n_table[base +: DEGREE] = n_terms;
        end
    endtask

    task init_source_table;
        integer row;
        integer digit;
        reg [DEGREE - 1 : 0] p_terms;
        reg [DEGREE - 1 : 0] n_terms;
        begin
            r_digit_p_table = {TABLE_BITS{1'b0}};
            r_digit_n_table = {TABLE_BITS{1'b0}};
            for (row = 0; row < NUM_ROWS; row = row + 1) begin
                for (digit = 0; digit < DATA_WIDTH; digit = digit + 1) begin
                    p_terms = {DEGREE{1'b0}};
                    n_terms = {DEGREE{1'b0}};
                    p_terms[0] = (digit[0] == 1'b0);
                    p_terms[1] = (digit[1:0] == row[1:0]);
                    n_terms[2] = ((digit % 3) == (row % 3));
                    p_terms[3] = (digit == (DATA_WIDTH - 1 - row));
                    set_source_digit(row, digit, p_terms, n_terms);
                end
            end
        end
    endtask

    task drive_prefix_digit;
        input integer digit_idx;
        begin
            @(negedge i_clk);
            i_valid_prefix <= 1'b1;
            i_digit_idx <= digit_idx[DIGIT_IDX_WIDTH - 1 : 0];
            @(posedge i_clk);
            #1;
        end
    endtask

    task check_done_record;
        input integer row;
        input integer exp_digit;
        input integer exp_lead;
        reg [DIGIT_IDX_WIDTH - 1 : 0] got_digit;
        reg [LEAD_WIDTH - 1 : 0] got_lead;
        begin
            got_digit = r_done_issue_digit_rows[row * DIGIT_IDX_WIDTH +: DIGIT_IDX_WIDTH];
            got_lead = r_done_lead_rows[row * LEAD_WIDTH +: LEAD_WIDTH];
            if (!r_done_mask[row] ||
                got_digit !== exp_digit[DIGIT_IDX_WIDTH - 1 : 0] ||
                got_lead !== exp_lead[LEAD_WIDTH - 1 : 0]) begin
                $display("ERROR replay done row=%0d mask=%b digit=%0d/%0d lead=%0d/%0d",
                    row,
                    r_done_mask,
                    got_digit,
                    exp_digit,
                    got_lead,
                    exp_lead);
                $fatal;
            end
        end
    endtask

    always @(posedge i_clk) begin
        if (i_rst || i_start) begin
            r_done_mask <= {NUM_ROWS{1'b0}};
            r_done_issue_digit_rows <= {NUM_ROWS * DIGIT_IDX_WIDTH{1'b0}};
            r_done_lead_rows <= {NUM_ROWS * LEAD_WIDTH{1'b0}};
            r_cycle_count <= 32'd0;
            r_source_req_count <= 32'd0;
            r_nonzero_source_count <= 32'd0;
            r_output_compare_count <= 32'd0;
        end else begin
            r_cycle_count <= r_cycle_count + 1'b1;

            if (w_source_req_valid) begin
                r_source_req_count <= r_source_req_count + 1'b1;
                if ((w_replay_p_terms | w_replay_n_terms) != {DEGREE{1'b0}}) begin
                    r_nonzero_source_count <= r_nonzero_source_count + 1'b1;
                end
                if (!w_replay_valid) begin
                    $display("ERROR replay response invalid during source request");
                    $fatal;
                end
            end

            if (w_x_valid !== w_ref_valid ||
                w_x_new_digit_p !== w_ref_digit_p ||
                w_x_new_digit_n !== w_ref_digit_n) begin
                $display("ERROR row-lane/ref mismatch valid=%0d/%0d p=%0d/%0d n=%0d/%0d",
                    w_x_valid,
                    w_ref_valid,
                    w_x_new_digit_p,
                    w_ref_digit_p,
                    w_x_new_digit_n,
                    w_ref_digit_n);
                $fatal;
            end
            if (w_x_valid) begin
                r_output_compare_count <= r_output_compare_count + 1'b1;
            end

            if (w_lane_done_pulse) begin
                r_done_mask[w_done_row_id] <= 1'b1;
                r_done_issue_digit_rows[w_done_row_id * DIGIT_IDX_WIDTH +: DIGIT_IDX_WIDTH]
                    <= w_done_issue_digit_idx;
                r_done_lead_rows[w_done_row_id * LEAD_WIDTH +: LEAD_WIDTH]
                    <= w_done_lead_cycles;
            end
        end
    end

    initial begin
        i_clk = 1'b0;
        i_rst = 1'b1;
        i_start = 1'b0;
        i_valid_prefix = 1'b0;
        i_digit_idx = {DIGIT_IDX_WIDTH{1'b0}};
        i_coeff_abs_terms_rows = {NUM_ROWS * DEGREE * COEFF_WIDTH{1'b0}};
        i_selection_margin_rows = {NUM_ROWS * MARGIN_WIDTH{1'b0}};
        r_coeff_p_terms = {DEGREE * BIT_WIDTH{1'b0}};
        r_coeff_n_terms = {DEGREE * BIT_WIDTH{1'b0}};
        r_bias_p = 7'b0010101;
        r_bias_n = 7'b0000000;
        init_source_table();

        r_coeff_p_terms[0 * BIT_WIDTH +: BIT_WIDTH] = 5'd1;
        r_coeff_p_terms[1 * BIT_WIDTH +: BIT_WIDTH] = 5'd2;
        r_coeff_p_terms[2 * BIT_WIDTH +: BIT_WIDTH] = 5'd4;
        r_coeff_p_terms[3 * BIT_WIDTH +: BIT_WIDTH] = 5'd1;

        set_row_coeffs(0, 1, 1, 0, 0); // sum 2
        set_row_coeffs(1, 1, 2, 1, 0); // sum 4
        set_row_coeffs(2, 2, 4, 2, 0); // sum 8
        set_row_coeffs(3, 4, 8, 4, 0); // sum 16

        set_row_margin(0, 65); // first safe at digit 2
        set_row_margin(1, 33); // first safe at digit 4
        set_row_margin(2, 9);  // first safe at digit 6
        set_row_margin(3, 1);  // first safe at digit 7

        repeat (2) @(posedge i_clk);
        i_rst <= 1'b0;

        @(negedge i_clk);
        i_start <= 1'b1;
        @(negedge i_clk);
        i_start <= 1'b0;

        drive_prefix_digit(0);
        drive_prefix_digit(1);
        drive_prefix_digit(2);
        drive_prefix_digit(3);
        drive_prefix_digit(4);
        drive_prefix_digit(5);
        drive_prefix_digit(6);
        drive_prefix_digit(7);

        @(negedge i_clk);
        i_valid_prefix <= 1'b0;

        while (w_done_count < NUM_ROWS) begin
            @(posedge i_clk);
            #1;
            if (r_cycle_count > 32'd180) begin
                $display("ERROR replay timeout accept=%0d done=%0d out=%0d src=%0d pending=%b",
                    w_accept_count,
                    w_done_count,
                    w_output_digit_count,
                    r_source_req_count,
                    w_queue_pending_mask);
                $fatal;
            end
        end

        @(posedge i_clk);
        #1;

        check_done_record(0, 2, 5);
        check_done_record(1, 4, 3);
        check_done_record(2, 6, 1);
        check_done_record(3, 7, 0);

        if (w_accept_count !== 32'd4 ||
            w_done_count !== 32'd4 ||
            w_dispatch_count !== 32'd4 ||
            w_output_digit_count !== NUM_ROWS * DATA_WIDTH ||
            r_output_compare_count !== NUM_ROWS * DATA_WIDTH ||
            r_source_req_count !== NUM_ROWS * DATA_WIDTH ||
            r_nonzero_source_count == 32'd0 ||
            w_queue_pending_mask !== 4'b0000 ||
            w_max_lead_cycles !== 4'd5 ||
            !w_all_issued ||
            w_duplicate_issue) begin
            $display("ERROR replay summary accept=%0d done=%0d dispatch=%0d out=%0d cmp=%0d src=%0d nz=%0d pending=%b maxlead=%0d all=%0d dup=%0d",
                w_accept_count,
                w_done_count,
                w_dispatch_count,
                w_output_digit_count,
                r_output_compare_count,
                r_source_req_count,
                r_nonzero_source_count,
                w_queue_pending_mask,
                w_max_lead_cycles,
                w_all_issued,
                w_duplicate_issue);
            $fatal;
        end

        $display("PASS tb_iter_prefix_safe_scheduler_solver_native_replay");
        $display("INFO accept=%0d done=%0d source_req=%0d nonzero_source=%0d output_digits=%0d maxlead=%0d",
            w_accept_count,
            w_done_count,
            r_source_req_count,
            r_nonzero_source_count,
            w_output_digit_count,
            w_max_lead_cycles);
        $finish;
    end
endmodule
