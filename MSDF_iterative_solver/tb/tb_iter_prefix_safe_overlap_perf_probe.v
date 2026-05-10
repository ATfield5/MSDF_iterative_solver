`timescale 1ns / 1ps

module tb_iter_prefix_safe_overlap_perf_probe;
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
    reg i_full_commit_valid;
    reg [DIGIT_IDX_WIDTH - 1 : 0] i_digit_idx;
    reg [NUM_ROWS * DEGREE * COEFF_WIDTH - 1 : 0] i_coeff_abs_terms_rows;
    reg [NUM_ROWS * MARGIN_WIDTH - 1 : 0] i_selection_margin_rows;
    reg [TABLE_BITS - 1 : 0] r_digit_p_table;
    reg [TABLE_BITS - 1 : 0] r_digit_n_table;
    reg [DEGREE * BIT_WIDTH - 1 : 0] r_coeff_p_terms;
    reg [DEGREE * BIT_WIDTH - 1 : 0] r_coeff_n_terms;
    reg [BIAS_WIDTH - 1 : 0] r_bias_p;
    reg [BIAS_WIDTH - 1 : 0] r_bias_n;

    wire w_prefix_ready;
    wire w_prefix_cmd_valid;
    wire [ROW_ID_WIDTH - 1 : 0] w_prefix_cmd_row_id;
    wire [DIGIT_IDX_WIDTH - 1 : 0] w_prefix_cmd_digit_idx;
    wire [LEAD_WIDTH - 1 : 0] w_prefix_cmd_lead_cycles;
    wire [NUM_ROWS - 1 : 0] w_prefix_pending_mask;
    wire [31 : 0] w_prefix_dispatch_count;
    wire w_prefix_all_issued;
    wire w_prefix_duplicate_issue;
    wire w_prefix_source_req_valid;
    wire [ROW_ID_WIDTH - 1 : 0] w_prefix_source_req_row_id;
    wire [DIGIT_IDX_WIDTH - 1 : 0] w_prefix_source_req_digit_idx;
    wire [DEGREE - 1 : 0] w_prefix_replay_p_terms;
    wire [DEGREE - 1 : 0] w_prefix_replay_n_terms;
    wire w_prefix_done_pulse;
    wire [31 : 0] w_prefix_accept_count;
    wire [31 : 0] w_prefix_output_digit_count;
    wire [31 : 0] w_prefix_done_count;
    wire [LEAD_WIDTH - 1 : 0] w_prefix_max_lead_cycles;

    wire w_full_ready;
    wire w_full_cmd_valid;
    wire [ROW_ID_WIDTH - 1 : 0] w_full_cmd_row_id;
    wire [DIGIT_IDX_WIDTH - 1 : 0] w_full_cmd_digit_idx;
    wire [LEAD_WIDTH - 1 : 0] w_full_cmd_lead_cycles;
    wire [NUM_ROWS - 1 : 0] w_full_pending_mask;
    wire [31 : 0] w_full_dispatch_count;
    wire w_full_all_issued;
    wire w_full_duplicate_issue;
    wire w_full_source_req_valid;
    wire [ROW_ID_WIDTH - 1 : 0] w_full_source_req_row_id;
    wire [DIGIT_IDX_WIDTH - 1 : 0] w_full_source_req_digit_idx;
    wire [DEGREE - 1 : 0] w_full_replay_p_terms;
    wire [DEGREE - 1 : 0] w_full_replay_n_terms;
    wire w_full_done_pulse;
    wire [31 : 0] w_full_accept_count;
    wire [31 : 0] w_full_output_digit_count;
    wire [31 : 0] w_full_done_count;
    wire [LEAD_WIDTH - 1 : 0] w_full_max_lead_cycles;

    reg [31 : 0] r_cycle_count;
    reg [31 : 0] r_prefix_done_cycle;
    reg [31 : 0] r_full_done_cycle;
    reg r_prefix_done_seen;
    reg r_full_done_seen;

    iter_prefix_safe_two_stage_scheduler #(
        .num_rows(NUM_ROWS),
        .degree(DEGREE),
        .data_width(DATA_WIDTH),
        .coeff_width(COEFF_WIDTH),
        .margin_width(MARGIN_WIDTH)
    ) prefix_scheduler (
        .i_clk(i_clk),
        .i_rst(i_rst),
        .i_start(i_start),
        .i_valid_prefix(i_valid_prefix),
        .i_digit_idx(i_digit_idx),
        .i_coeff_abs_terms_rows(i_coeff_abs_terms_rows),
        .i_selection_margin_rows(i_selection_margin_rows),
        .i_consumer_ready(w_prefix_ready),
        .o_consumer_valid(w_prefix_cmd_valid),
        .o_consumer_row_id(w_prefix_cmd_row_id),
        .o_consumer_digit_idx(w_prefix_cmd_digit_idx),
        .o_consumer_lead_cycles(w_prefix_cmd_lead_cycles),
        .o_row_issue_pulse(),
        .o_row_issued_mask(),
        .o_queue_pending_mask(w_prefix_pending_mask),
        .o_queue_pending_count(),
        .o_dispatch_count(w_prefix_dispatch_count),
        .o_duplicate_issue(w_prefix_duplicate_issue),
        .o_all_issued(w_prefix_all_issued)
    );

    iter_fullword_row_start_scheduler #(
        .num_rows(NUM_ROWS),
        .data_width(DATA_WIDTH)
    ) full_scheduler (
        .i_clk(i_clk),
        .i_rst(i_rst),
        .i_start(i_start),
        .i_full_commit_valid(i_full_commit_valid),
        .i_consumer_ready(w_full_ready),
        .o_consumer_valid(w_full_cmd_valid),
        .o_consumer_row_id(w_full_cmd_row_id),
        .o_consumer_digit_idx(w_full_cmd_digit_idx),
        .o_consumer_lead_cycles(w_full_cmd_lead_cycles),
        .o_queue_pending_mask(w_full_pending_mask),
        .o_queue_pending_count(),
        .o_dispatch_count(w_full_dispatch_count),
        .o_duplicate_issue(w_full_duplicate_issue),
        .o_all_issued(w_full_all_issued)
    );

    iter_prefix_safe_digit_replay_source #(
        .num_rows(NUM_ROWS),
        .degree(DEGREE),
        .data_width(DATA_WIDTH)
    ) prefix_replay (
        .i_req_valid(w_prefix_source_req_valid),
        .i_req_row_id(w_prefix_source_req_row_id),
        .i_req_digit_idx(w_prefix_source_req_digit_idx),
        .i_digit_p_table(r_digit_p_table),
        .i_digit_n_table(r_digit_n_table),
        .o_resp_valid(),
        .o_state_digit_p_terms(w_prefix_replay_p_terms),
        .o_state_digit_n_terms(w_prefix_replay_n_terms)
    );

    iter_prefix_safe_digit_replay_source #(
        .num_rows(NUM_ROWS),
        .degree(DEGREE),
        .data_width(DATA_WIDTH)
    ) full_replay (
        .i_req_valid(w_full_source_req_valid),
        .i_req_row_id(w_full_source_req_row_id),
        .i_req_digit_idx(w_full_source_req_digit_idx),
        .i_digit_p_table(r_digit_p_table),
        .i_digit_n_table(r_digit_n_table),
        .o_resp_valid(),
        .o_state_digit_p_terms(w_full_replay_p_terms),
        .o_state_digit_n_terms(w_full_replay_n_terms)
    );

    iter_prefix_safe_solver_native_row_lane #(
        .num_rows(NUM_ROWS),
        .bit_width(BIT_WIDTH),
        .degree(DEGREE),
        .data_width(DATA_WIDTH),
        .bias_width(BIAS_WIDTH)
    ) prefix_lane (
        .i_clk(i_clk),
        .i_rst(i_rst),
        .i_start(i_start),
        .i_cmd_valid(w_prefix_cmd_valid),
        .o_cmd_ready(w_prefix_ready),
        .i_cmd_row_id(w_prefix_cmd_row_id),
        .i_cmd_digit_idx(w_prefix_cmd_digit_idx),
        .i_cmd_lead_cycles(w_prefix_cmd_lead_cycles),
        .o_source_req_valid(w_prefix_source_req_valid),
        .o_source_req_row_id(w_prefix_source_req_row_id),
        .o_source_req_digit_idx(w_prefix_source_req_digit_idx),
        .i_state_digit_p_terms(w_prefix_replay_p_terms),
        .i_state_digit_n_terms(w_prefix_replay_n_terms),
        .i_coeff_p_terms(r_coeff_p_terms),
        .i_coeff_n_terms(r_coeff_n_terms),
        .i_bias_p(r_bias_p),
        .i_bias_n(r_bias_n),
        .o_x_valid(),
        .o_x_new_digit_p(),
        .o_x_new_digit_n(),
        .o_busy(),
        .o_done_pulse(w_prefix_done_pulse),
        .o_done_row_id(),
        .o_done_issue_digit_idx(),
        .o_done_lead_cycles(),
        .o_accept_count(w_prefix_accept_count),
        .o_output_digit_count(w_prefix_output_digit_count),
        .o_done_count(w_prefix_done_count),
        .o_max_lead_cycles(w_prefix_max_lead_cycles)
    );

    iter_prefix_safe_solver_native_row_lane #(
        .num_rows(NUM_ROWS),
        .bit_width(BIT_WIDTH),
        .degree(DEGREE),
        .data_width(DATA_WIDTH),
        .bias_width(BIAS_WIDTH)
    ) full_lane (
        .i_clk(i_clk),
        .i_rst(i_rst),
        .i_start(i_start),
        .i_cmd_valid(w_full_cmd_valid),
        .o_cmd_ready(w_full_ready),
        .i_cmd_row_id(w_full_cmd_row_id),
        .i_cmd_digit_idx(w_full_cmd_digit_idx),
        .i_cmd_lead_cycles(w_full_cmd_lead_cycles),
        .o_source_req_valid(w_full_source_req_valid),
        .o_source_req_row_id(w_full_source_req_row_id),
        .o_source_req_digit_idx(w_full_source_req_digit_idx),
        .i_state_digit_p_terms(w_full_replay_p_terms),
        .i_state_digit_n_terms(w_full_replay_n_terms),
        .i_coeff_p_terms(r_coeff_p_terms),
        .i_coeff_n_terms(r_coeff_n_terms),
        .i_bias_p(r_bias_p),
        .i_bias_n(r_bias_n),
        .o_x_valid(),
        .o_x_new_digit_p(),
        .o_x_new_digit_n(),
        .o_busy(),
        .o_done_pulse(w_full_done_pulse),
        .o_done_row_id(),
        .o_done_issue_digit_idx(),
        .o_done_lead_cycles(),
        .o_accept_count(w_full_accept_count),
        .o_output_digit_count(w_full_output_digit_count),
        .o_done_count(w_full_done_count),
        .o_max_lead_cycles(w_full_max_lead_cycles)
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
            i_full_commit_valid <= (digit_idx == DATA_WIDTH - 1);
            @(posedge i_clk);
            #1;
        end
    endtask

    always @(posedge i_clk) begin
        if (i_rst || i_start) begin
            r_cycle_count <= 32'd0;
            r_prefix_done_cycle <= 32'd0;
            r_full_done_cycle <= 32'd0;
            r_prefix_done_seen <= 1'b0;
            r_full_done_seen <= 1'b0;
        end else begin
            r_cycle_count <= r_cycle_count + 1'b1;
            if (!r_prefix_done_seen && (w_prefix_done_count == NUM_ROWS)) begin
                r_prefix_done_seen <= 1'b1;
                r_prefix_done_cycle <= r_cycle_count;
            end
            if (!r_full_done_seen && (w_full_done_count == NUM_ROWS)) begin
                r_full_done_seen <= 1'b1;
                r_full_done_cycle <= r_cycle_count;
            end
        end
    end

    initial begin
        i_clk = 1'b0;
        i_rst = 1'b1;
        i_start = 1'b0;
        i_valid_prefix = 1'b0;
        i_full_commit_valid = 1'b0;
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
        i_full_commit_valid <= 1'b0;

        while (!r_prefix_done_seen || !r_full_done_seen) begin
            @(posedge i_clk);
            #1;
            if (r_cycle_count > 32'd220) begin
                $display("ERROR perf timeout prefix_done=%0d full_done=%0d p_cnt=%0d f_cnt=%0d",
                    r_prefix_done_seen,
                    r_full_done_seen,
                    w_prefix_done_count,
                    w_full_done_count);
                $fatal;
            end
        end

        if (w_prefix_accept_count !== NUM_ROWS ||
            w_full_accept_count !== NUM_ROWS ||
            w_prefix_output_digit_count !== NUM_ROWS * DATA_WIDTH ||
            w_full_output_digit_count !== NUM_ROWS * DATA_WIDTH ||
            w_prefix_dispatch_count !== NUM_ROWS ||
            w_full_dispatch_count !== NUM_ROWS ||
            !w_prefix_all_issued ||
            !w_full_all_issued ||
            w_prefix_duplicate_issue ||
            w_full_duplicate_issue ||
            w_prefix_pending_mask !== {NUM_ROWS{1'b0}} ||
            w_full_pending_mask !== {NUM_ROWS{1'b0}}) begin
            $display("ERROR perf summary p_acc=%0d f_acc=%0d p_out=%0d f_out=%0d p_disp=%0d f_disp=%0d p_pend=%b f_pend=%b",
                w_prefix_accept_count,
                w_full_accept_count,
                w_prefix_output_digit_count,
                w_full_output_digit_count,
                w_prefix_dispatch_count,
                w_full_dispatch_count,
                w_prefix_pending_mask,
                w_full_pending_mask);
            $fatal;
        end

        if (r_prefix_done_cycle >= r_full_done_cycle) begin
            $display("ERROR expected prefix overlap to finish earlier prefix=%0d full=%0d",
                r_prefix_done_cycle,
                r_full_done_cycle);
            $fatal;
        end

        $display("PASS tb_iter_prefix_safe_overlap_perf_probe");
        $display("INFO prefix_done_cycle=%0d fullword_done_cycle=%0d saved_cycles=%0d maxlead=%0d",
            r_prefix_done_cycle,
            r_full_done_cycle,
            r_full_done_cycle - r_prefix_done_cycle,
            w_prefix_max_lead_cycles);
        $finish;
    end
endmodule
