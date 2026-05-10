`timescale 1ns / 1ps

module tb_iter_prefix_safe_issue_controller;
    localparam integer NUM_ROWS = 4;
    localparam integer DEGREE = 3;
    localparam integer DATA_WIDTH = 8;
    localparam integer COEFF_WIDTH = 8;
    localparam integer MARGIN_WIDTH = 24;
    localparam integer DIGIT_IDX_WIDTH = $clog2(DATA_WIDTH);

    reg i_clk;
    reg i_rst;
    reg i_start;
    reg i_valid_prefix;
    reg [DIGIT_IDX_WIDTH - 1 : 0] i_digit_idx;
    reg [NUM_ROWS * DEGREE * COEFF_WIDTH - 1 : 0] i_coeff_abs_terms_rows;
    reg [NUM_ROWS * MARGIN_WIDTH - 1 : 0] i_selection_margin_rows;
    wire [NUM_ROWS - 1 : 0] o_row_issue_pulse;
    wire [NUM_ROWS - 1 : 0] o_row_issued_mask;
    wire o_all_issued;
    wire [NUM_ROWS * DATA_WIDTH - 1 : 0] o_tail_bound_rows;
    wire [NUM_ROWS * MARGIN_WIDTH - 1 : 0] o_weighted_tail_rows;

    integer di;

    iter_prefix_safe_issue_controller #(
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
        .o_row_issue_pulse(o_row_issue_pulse),
        .o_row_issued_mask(o_row_issued_mask),
        .o_all_issued(o_all_issued),
        .o_tail_bound_rows(o_tail_bound_rows),
        .o_weighted_tail_rows(o_weighted_tail_rows)
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

    task drive_digit;
        input integer digit_idx;
        begin
            @(negedge i_clk);
            i_valid_prefix <= 1'b1;
            i_digit_idx <= digit_idx[DIGIT_IDX_WIDTH - 1 : 0];
            @(posedge i_clk);
            #1;
        end
    endtask

    task expect_pulse_mask;
        input [NUM_ROWS - 1 : 0] exp_pulse;
        input [NUM_ROWS - 1 : 0] exp_mask;
        begin
            if (o_row_issue_pulse !== exp_pulse ||
                o_row_issued_mask !== exp_mask) begin
                $display("ERROR issue state digit=%0d pulse=%b/%b mask=%b/%b",
                    i_digit_idx,
                    o_row_issue_pulse,
                    exp_pulse,
                    o_row_issued_mask,
                    exp_mask);
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

        // Row coefficient sums: 2, 4, 8, 16.
        set_row_coeffs(0, 1, 1, 0);
        set_row_coeffs(1, 1, 2, 1);
        set_row_coeffs(2, 2, 4, 2);
        set_row_coeffs(3, 4, 8, 4);

        // Margins selected so rows become safe at different prefix depths.
        set_row_margin(0, 65);   // digit 2: tail=31, weighted=62 < 65
        set_row_margin(1, 33);   // digit 4: tail=7,  weighted=28 < 33
        set_row_margin(2, 9);    // digit 6: tail=1,  weighted=8  < 9
        set_row_margin(3, 1);    // final digit only: weighted=0 < 1

        repeat (2) @(posedge i_clk);
        i_rst <= 1'b0;
        @(negedge i_clk);
        i_start <= 1'b1;
        @(negedge i_clk);
        i_start <= 1'b0;

        drive_digit(0);
        expect_pulse_mask(4'b0000, 4'b0000);

        drive_digit(1);
        expect_pulse_mask(4'b0000, 4'b0000);

        drive_digit(2);
        expect_pulse_mask(4'b0001, 4'b0001);

        drive_digit(3);
        expect_pulse_mask(4'b0000, 4'b0001);

        drive_digit(4);
        expect_pulse_mask(4'b0010, 4'b0011);

        drive_digit(5);
        expect_pulse_mask(4'b0000, 4'b0011);

        drive_digit(6);
        expect_pulse_mask(4'b0100, 4'b0111);

        drive_digit(7);
        expect_pulse_mask(4'b1000, 4'b1111);

        if (!o_all_issued) begin
            $display("ERROR all rows should be issued");
            $fatal;
        end

        @(negedge i_clk);
        i_valid_prefix <= 1'b0;
        i_start <= 1'b1;
        @(posedge i_clk);
        #1;
        if (o_row_issued_mask !== 4'b0000) begin
            $display("ERROR start should clear issue mask got=%b", o_row_issued_mask);
            $fatal;
        end

        $display("PASS tb_iter_prefix_safe_issue_controller");
        $finish;
    end
endmodule
