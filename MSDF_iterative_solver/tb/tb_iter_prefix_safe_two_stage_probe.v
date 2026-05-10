`timescale 1ns / 1ps

module tb_iter_prefix_safe_two_stage_probe;
    localparam integer NUM_ROWS = 4;
    localparam integer DEGREE = 3;
    localparam integer DATA_WIDTH = 8;
    localparam integer COEFF_WIDTH = 8;
    localparam integer MARGIN_WIDTH = 24;
    localparam integer DIGIT_IDX_WIDTH = $clog2(DATA_WIDTH);
    localparam integer LEAD_WIDTH = DIGIT_IDX_WIDTH + 1;

    reg i_clk;
    reg i_rst;
    reg i_start;
    reg i_valid_prefix;
    reg [DIGIT_IDX_WIDTH - 1 : 0] i_digit_idx;
    reg [NUM_ROWS * DEGREE * COEFF_WIDTH - 1 : 0] i_coeff_abs_terms_rows;
    reg [NUM_ROWS * MARGIN_WIDTH - 1 : 0] i_selection_margin_rows;
    wire [NUM_ROWS - 1 : 0] o_consumer_issue_rows;
    wire [NUM_ROWS - 1 : 0] o_consumer_issued_mask;
    wire [NUM_ROWS * DIGIT_IDX_WIDTH - 1 : 0] o_issue_digit_idx_rows;
    wire [NUM_ROWS * LEAD_WIDTH - 1 : 0] o_lead_cycles_rows;
    wire [LEAD_WIDTH - 1 : 0] o_max_lead_cycles;
    wire [31 : 0] o_early_issue_count;
    wire o_all_issued;

    iter_prefix_safe_two_stage_probe #(
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
        .o_consumer_issue_rows(o_consumer_issue_rows),
        .o_consumer_issued_mask(o_consumer_issued_mask),
        .o_issue_digit_idx_rows(o_issue_digit_idx_rows),
        .o_lead_cycles_rows(o_lead_cycles_rows),
        .o_max_lead_cycles(o_max_lead_cycles),
        .o_early_issue_count(o_early_issue_count),
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

    task drive_digit_expect;
        input integer digit_idx;
        input [NUM_ROWS - 1 : 0] exp_issue;
        input [NUM_ROWS - 1 : 0] exp_mask;
        begin
            @(negedge i_clk);
            i_valid_prefix <= 1'b1;
            i_digit_idx <= digit_idx[DIGIT_IDX_WIDTH - 1 : 0];
            @(posedge i_clk);
            #1;
            if (o_consumer_issue_rows !== exp_issue ||
                o_consumer_issued_mask !== exp_mask) begin
                $display("ERROR two-stage issue digit=%0d issue=%b/%b mask=%b/%b",
                    digit_idx,
                    o_consumer_issue_rows,
                    exp_issue,
                    o_consumer_issued_mask,
                    exp_mask);
                $fatal;
            end
        end
    endtask

    task check_row_record;
        input integer row;
        input integer exp_digit;
        input integer exp_lead;
        reg [DIGIT_IDX_WIDTH - 1 : 0] got_digit;
        reg [LEAD_WIDTH - 1 : 0] got_lead;
        begin
            got_digit = o_issue_digit_idx_rows[row * DIGIT_IDX_WIDTH +: DIGIT_IDX_WIDTH];
            got_lead = o_lead_cycles_rows[row * LEAD_WIDTH +: LEAD_WIDTH];
            if (got_digit !== exp_digit[DIGIT_IDX_WIDTH - 1 : 0] ||
                got_lead !== exp_lead[LEAD_WIDTH - 1 : 0]) begin
                $display("ERROR row record row=%0d digit=%0d/%0d lead=%0d/%0d",
                    row,
                    got_digit,
                    exp_digit,
                    got_lead,
                    exp_lead);
                $fatal;
            end
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

        drive_digit_expect(0, 4'b0000, 4'b0000);
        drive_digit_expect(1, 4'b0000, 4'b0000);
        drive_digit_expect(2, 4'b0001, 4'b0001);
        drive_digit_expect(3, 4'b0000, 4'b0001);
        drive_digit_expect(4, 4'b0010, 4'b0011);
        drive_digit_expect(5, 4'b0000, 4'b0011);
        drive_digit_expect(6, 4'b0100, 4'b0111);
        drive_digit_expect(7, 4'b1000, 4'b1111);

        @(negedge i_clk);
        i_valid_prefix <= 1'b0;
        @(posedge i_clk);
        #1;

        check_row_record(0, 2, 5);
        check_row_record(1, 4, 3);
        check_row_record(2, 6, 1);
        check_row_record(3, 7, 0);

        if (o_max_lead_cycles !== 4'd5 ||
            o_early_issue_count !== 32'd3 ||
            !o_all_issued) begin
            $display("ERROR lead summary max=%0d early=%0d all=%0d",
                o_max_lead_cycles,
                o_early_issue_count,
                o_all_issued);
            $fatal;
        end

        $display("PASS tb_iter_prefix_safe_two_stage_probe");
        $finish;
    end
endmodule
