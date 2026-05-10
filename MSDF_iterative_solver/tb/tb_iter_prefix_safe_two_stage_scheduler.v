`timescale 1ns / 1ps

module tb_iter_prefix_safe_two_stage_scheduler;
    localparam integer NUM_ROWS = 4;
    localparam integer DEGREE = 3;
    localparam integer DATA_WIDTH = 8;
    localparam integer COEFF_WIDTH = 8;
    localparam integer MARGIN_WIDTH = 24;
    localparam integer DIGIT_IDX_WIDTH = $clog2(DATA_WIDTH);
    localparam integer ROW_ID_WIDTH = $clog2(NUM_ROWS);
    localparam integer LEAD_WIDTH = DIGIT_IDX_WIDTH + 1;
    localparam integer COUNT_WIDTH = $clog2(NUM_ROWS + 1);

    reg i_clk;
    reg i_rst;
    reg i_start;
    reg i_valid_prefix;
    reg [DIGIT_IDX_WIDTH - 1 : 0] i_digit_idx;
    reg [NUM_ROWS * DEGREE * COEFF_WIDTH - 1 : 0] i_coeff_abs_terms_rows;
    reg [NUM_ROWS * MARGIN_WIDTH - 1 : 0] i_selection_margin_rows;
    reg i_consumer_ready;
    wire o_consumer_valid;
    wire [ROW_ID_WIDTH - 1 : 0] o_consumer_row_id;
    wire [DIGIT_IDX_WIDTH - 1 : 0] o_consumer_digit_idx;
    wire [LEAD_WIDTH - 1 : 0] o_consumer_lead_cycles;
    wire [NUM_ROWS - 1 : 0] o_row_issue_pulse;
    wire [NUM_ROWS - 1 : 0] o_row_issued_mask;
    wire [NUM_ROWS - 1 : 0] o_queue_pending_mask;
    wire [COUNT_WIDTH - 1 : 0] o_queue_pending_count;
    wire [31 : 0] o_dispatch_count;
    wire o_duplicate_issue;
    wire o_all_issued;

    iter_prefix_safe_two_stage_scheduler #(
        .num_rows(NUM_ROWS),
        .degree(DEGREE),
        .data_width(DATA_WIDTH),
        .coeff_width(COEFF_WIDTH),
        .margin_width(MARGIN_WIDTH)
    ) dut (
        .i_clk(i_clk),
        .i_rst(i_rst),
        .i_start(i_start),
        .i_valid_prefix(i_valid_prefix),
        .i_digit_idx(i_digit_idx),
        .i_coeff_abs_terms_rows(i_coeff_abs_terms_rows),
        .i_selection_margin_rows(i_selection_margin_rows),
        .i_consumer_ready(i_consumer_ready),
        .o_consumer_valid(o_consumer_valid),
        .o_consumer_row_id(o_consumer_row_id),
        .o_consumer_digit_idx(o_consumer_digit_idx),
        .o_consumer_lead_cycles(o_consumer_lead_cycles),
        .o_row_issue_pulse(o_row_issue_pulse),
        .o_row_issued_mask(o_row_issued_mask),
        .o_queue_pending_mask(o_queue_pending_mask),
        .o_queue_pending_count(o_queue_pending_count),
        .o_dispatch_count(o_dispatch_count),
        .o_duplicate_issue(o_duplicate_issue),
        .o_all_issued(o_all_issued)
    );

    always #5 i_clk = ~i_clk;

    task set_row_coeffs;
        input integer row;
        input integer c0;
        input integer c1;
        input integer c2;
        begin
            i_coeff_abs_terms_rows[row * DEGREE * COEFF_WIDTH + 0 * COEFF_WIDTH +: COEFF_WIDTH] =
                c0[COEFF_WIDTH - 1 : 0];
            i_coeff_abs_terms_rows[row * DEGREE * COEFF_WIDTH + 1 * COEFF_WIDTH +: COEFF_WIDTH] =
                c1[COEFF_WIDTH - 1 : 0];
            i_coeff_abs_terms_rows[row * DEGREE * COEFF_WIDTH + 2 * COEFF_WIDTH +: COEFF_WIDTH] =
                c2[COEFF_WIDTH - 1 : 0];
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

    task expect_head;
        input integer exp_row;
        input integer exp_digit;
        input integer exp_lead;
        begin
            if (!o_consumer_valid ||
                o_consumer_row_id !== exp_row[ROW_ID_WIDTH - 1 : 0] ||
                o_consumer_digit_idx !== exp_digit[DIGIT_IDX_WIDTH - 1 : 0] ||
                o_consumer_lead_cycles !== exp_lead[LEAD_WIDTH - 1 : 0]) begin
                $display("ERROR scheduler head got valid/row/digit/lead %0d/%0d/%0d/%0d exp 1/%0d/%0d/%0d",
                    o_consumer_valid,
                    o_consumer_row_id,
                    o_consumer_digit_idx,
                    o_consumer_lead_cycles,
                    exp_row,
                    exp_digit,
                    exp_lead);
                $fatal;
            end
        end
    endtask

    task drain_one;
        input integer exp_row;
        input integer exp_digit;
        input integer exp_lead;
        input [NUM_ROWS - 1 : 0] exp_mask_after;
        input integer exp_count_after;
        input integer exp_dispatch_after;
        begin
            @(negedge i_clk);
            expect_head(exp_row, exp_digit, exp_lead);
            i_consumer_ready <= 1'b1;
            @(posedge i_clk);
            #1;
            if (o_queue_pending_mask !== exp_mask_after ||
                o_queue_pending_count !== exp_count_after[COUNT_WIDTH - 1 : 0] ||
                o_dispatch_count !== exp_dispatch_after) begin
                $display("ERROR scheduler drain after row=%0d mask/count/dispatch %b/%0d/%0d exp %b/%0d/%0d",
                    exp_row,
                    o_queue_pending_mask,
                    o_queue_pending_count,
                    o_dispatch_count,
                    exp_mask_after,
                    exp_count_after,
                    exp_dispatch_after);
                $fatal;
            end
            i_consumer_ready <= 1'b0;
        end
    endtask

    initial begin
        i_clk = 1'b0;
        i_rst = 1'b1;
        i_start = 1'b0;
        i_valid_prefix = 1'b0;
        i_digit_idx = {DIGIT_IDX_WIDTH{1'b0}};
        i_coeff_abs_terms_rows = {NUM_ROWS * DEGREE * COEFF_WIDTH{1'b0}};
        i_selection_margin_rows = {NUM_ROWS * MARGIN_WIDTH{1'b0}};
        i_consumer_ready = 1'b0;

        set_row_coeffs(0, 1, 1, 0); // sum 2
        set_row_coeffs(1, 1, 2, 1); // sum 4
        set_row_coeffs(2, 2, 4, 2); // sum 8
        set_row_coeffs(3, 4, 8, 4); // sum 16

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
        @(posedge i_clk);
        #1;

        if (o_queue_pending_mask !== 4'b1111 ||
            o_queue_pending_count !== 3'd4 ||
            !o_all_issued ||
            o_duplicate_issue) begin
            $display("ERROR scheduler queued summary mask/count/all/dup %b/%0d/%0d/%0d",
                o_queue_pending_mask,
                o_queue_pending_count,
                o_all_issued,
                o_duplicate_issue);
            $fatal;
        end

        drain_one(0, 2, 5, 4'b1110, 3, 1);
        drain_one(1, 4, 3, 4'b1100, 2, 2);
        drain_one(2, 6, 1, 4'b1000, 1, 3);
        drain_one(3, 7, 0, 4'b0000, 0, 4);

        if (o_consumer_valid) begin
            $display("ERROR scheduler valid after full drain");
            $fatal;
        end

        $display("PASS tb_iter_prefix_safe_two_stage_scheduler");
        $finish;
    end
endmodule
