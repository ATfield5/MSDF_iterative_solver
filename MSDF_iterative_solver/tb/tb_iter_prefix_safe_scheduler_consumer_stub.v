`timescale 1ns / 1ps

module tb_iter_prefix_safe_scheduler_consumer_stub;
    localparam integer NUM_ROWS = 4;
    localparam integer DEGREE = 3;
    localparam integer DATA_WIDTH = 8;
    localparam integer COEFF_WIDTH = 8;
    localparam integer MARGIN_WIDTH = 24;
    localparam integer SERVICE_CYCLES = 2;
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

    wire w_consumer_ready;
    wire w_consumer_valid;
    wire [ROW_ID_WIDTH - 1 : 0] w_consumer_row_id;
    wire [DIGIT_IDX_WIDTH - 1 : 0] w_consumer_digit_idx;
    wire [LEAD_WIDTH - 1 : 0] w_consumer_lead_cycles;
    wire [NUM_ROWS - 1 : 0] w_queue_pending_mask;
    wire [COUNT_WIDTH - 1 : 0] w_queue_pending_count;
    wire [31 : 0] w_scheduler_dispatch_count;
    wire w_all_issued;
    wire w_duplicate_issue;

    wire w_stub_busy;
    wire w_done_pulse;
    wire [ROW_ID_WIDTH - 1 : 0] w_done_row_id;
    wire [DIGIT_IDX_WIDTH - 1 : 0] w_done_digit_idx;
    wire [LEAD_WIDTH - 1 : 0] w_done_lead_cycles;
    wire [31 : 0] w_accept_count;
    wire [31 : 0] w_done_count;
    wire [31 : 0] w_busy_cycles;
    wire [31 : 0] w_backpressure_cycles;
    wire [LEAD_WIDTH - 1 : 0] w_max_lead_cycles;

    reg [NUM_ROWS * DIGIT_IDX_WIDTH - 1 : 0] r_done_digit_idx_rows;
    reg [NUM_ROWS * LEAD_WIDTH - 1 : 0] r_done_lead_rows;
    reg [NUM_ROWS - 1 : 0] r_done_mask;
    reg [31 : 0] r_cycle_count;

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
        .i_consumer_ready(w_consumer_ready),
        .o_consumer_valid(w_consumer_valid),
        .o_consumer_row_id(w_consumer_row_id),
        .o_consumer_digit_idx(w_consumer_digit_idx),
        .o_consumer_lead_cycles(w_consumer_lead_cycles),
        .o_row_issue_pulse(),
        .o_row_issued_mask(),
        .o_queue_pending_mask(w_queue_pending_mask),
        .o_queue_pending_count(w_queue_pending_count),
        .o_dispatch_count(w_scheduler_dispatch_count),
        .o_duplicate_issue(w_duplicate_issue),
        .o_all_issued(w_all_issued)
    );

    iter_prefix_safe_consumer_stub #(
        .num_rows(NUM_ROWS),
        .data_width(DATA_WIDTH),
        .service_cycles(SERVICE_CYCLES)
    ) consumer (
        .i_clk(i_clk),
        .i_rst(i_rst),
        .i_start(i_start),
        .i_cmd_valid(w_consumer_valid),
        .o_cmd_ready(w_consumer_ready),
        .i_cmd_row_id(w_consumer_row_id),
        .i_cmd_digit_idx(w_consumer_digit_idx),
        .i_cmd_lead_cycles(w_consumer_lead_cycles),
        .o_busy(w_stub_busy),
        .o_done_pulse(w_done_pulse),
        .o_done_row_id(w_done_row_id),
        .o_done_digit_idx(w_done_digit_idx),
        .o_done_lead_cycles(w_done_lead_cycles),
        .o_accept_count(w_accept_count),
        .o_done_count(w_done_count),
        .o_busy_cycles(w_busy_cycles),
        .o_backpressure_cycles(w_backpressure_cycles),
        .o_max_lead_cycles(w_max_lead_cycles)
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

    task check_done_record;
        input integer row;
        input integer exp_digit;
        input integer exp_lead;
        reg [DIGIT_IDX_WIDTH - 1 : 0] got_digit;
        reg [LEAD_WIDTH - 1 : 0] got_lead;
        begin
            got_digit = r_done_digit_idx_rows[row * DIGIT_IDX_WIDTH +: DIGIT_IDX_WIDTH];
            got_lead = r_done_lead_rows[row * LEAD_WIDTH +: LEAD_WIDTH];
            if (!r_done_mask[row] ||
                got_digit !== exp_digit[DIGIT_IDX_WIDTH - 1 : 0] ||
                got_lead !== exp_lead[LEAD_WIDTH - 1 : 0]) begin
                $display("ERROR done record row=%0d mask=%b digit=%0d/%0d lead=%0d/%0d",
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
            r_done_digit_idx_rows <= {NUM_ROWS * DIGIT_IDX_WIDTH{1'b0}};
            r_done_lead_rows <= {NUM_ROWS * LEAD_WIDTH{1'b0}};
            r_cycle_count <= 32'd0;
        end else begin
            r_cycle_count <= r_cycle_count + 1'b1;
            if (w_done_pulse) begin
                r_done_mask[w_done_row_id] <= 1'b1;
                r_done_digit_idx_rows[w_done_row_id * DIGIT_IDX_WIDTH +: DIGIT_IDX_WIDTH]
                    <= w_done_digit_idx;
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

        while (w_done_count < NUM_ROWS) begin
            @(posedge i_clk);
            #1;
            if (r_cycle_count > 32'd80) begin
                $display("ERROR timeout accept=%0d done=%0d pending=%b valid=%0d ready=%0d",
                    w_accept_count,
                    w_done_count,
                    w_queue_pending_mask,
                    w_consumer_valid,
                    w_consumer_ready);
                $fatal;
            end
        end

        // The monitor records the registered done pulse one clock after the
        // consumer updates done_count.
        @(posedge i_clk);
        #1;

        check_done_record(0, 2, 5);
        check_done_record(1, 4, 3);
        check_done_record(2, 6, 1);
        check_done_record(3, 7, 0);

        if (w_accept_count !== 32'd4 ||
            w_done_count !== 32'd4 ||
            w_scheduler_dispatch_count !== 32'd4 ||
            w_queue_pending_mask !== 4'b0000 ||
            w_max_lead_cycles !== 4'd5 ||
            !w_all_issued ||
            w_duplicate_issue) begin
            $display("ERROR final summary accept=%0d done=%0d dispatch=%0d pending=%b maxlead=%0d all=%0d dup=%0d",
                w_accept_count,
                w_done_count,
                w_scheduler_dispatch_count,
                w_queue_pending_mask,
                w_max_lead_cycles,
                w_all_issued,
                w_duplicate_issue);
            $fatal;
        end

        if (w_backpressure_cycles == 32'd0) begin
            $display("ERROR expected nonzero backpressure from service latency");
            $fatal;
        end

        $display("PASS tb_iter_prefix_safe_scheduler_consumer_stub");
        $display("INFO accept=%0d done=%0d busy=%0d backpressure=%0d maxlead=%0d",
            w_accept_count,
            w_done_count,
            w_busy_cycles,
            w_backpressure_cycles,
            w_max_lead_cycles);
        $finish;
    end
endmodule
