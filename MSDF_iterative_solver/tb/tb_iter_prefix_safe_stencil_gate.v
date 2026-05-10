`timescale 1ns / 1ps

module tb_iter_prefix_safe_stencil_gate;
    localparam integer DEGREE = 3;
    localparam integer DATA_WIDTH = 8;
    localparam integer COEFF_WIDTH = 8;
    localparam integer MARGIN_WIDTH = 24;
    localparam integer DIGIT_IDX_WIDTH = $clog2(DATA_WIDTH);

    reg i_valid;
    reg [DIGIT_IDX_WIDTH - 1 : 0] i_digit_idx;
    reg [DEGREE * COEFF_WIDTH - 1 : 0] i_coeff_abs_terms;
    reg [MARGIN_WIDTH - 1 : 0] i_selection_margin;
    wire o_valid;
    wire [DATA_WIDTH - 1 : 0] o_source_tail_bound;
    wire [COEFF_WIDTH + $clog2(DEGREE) - 1 : 0] o_coeff_abs_sum;
    wire [MARGIN_WIDTH - 1 : 0] o_weighted_tail_bound;
    wire o_prefix_safe;
    wire [7 : 0] o_small_weighted_tail_bound;
    wire o_small_prefix_safe;

    iter_prefix_safe_stencil_gate #(
        .degree(DEGREE),
        .data_width(DATA_WIDTH),
        .coeff_width(COEFF_WIDTH),
        .margin_width(MARGIN_WIDTH)
    ) dut (
        .i_valid(i_valid),
        .i_digit_idx(i_digit_idx),
        .i_coeff_abs_terms(i_coeff_abs_terms),
        .i_selection_margin(i_selection_margin),
        .o_valid(o_valid),
        .o_source_tail_bound(o_source_tail_bound),
        .o_coeff_abs_sum(o_coeff_abs_sum),
        .o_weighted_tail_bound(o_weighted_tail_bound),
        .o_prefix_safe(o_prefix_safe)
    );

    iter_prefix_safe_stencil_gate #(
        .degree(DEGREE),
        .data_width(DATA_WIDTH),
        .coeff_width(COEFF_WIDTH),
        .margin_width(8)
    ) small_margin_dut (
        .i_valid(i_valid),
        .i_digit_idx(i_digit_idx),
        .i_coeff_abs_terms(i_coeff_abs_terms),
        .i_selection_margin(8'hff),
        .o_valid(),
        .o_source_tail_bound(),
        .o_coeff_abs_sum(),
        .o_weighted_tail_bound(o_small_weighted_tail_bound),
        .o_prefix_safe(o_small_prefix_safe)
    );

    task check_case;
        input integer digit_idx;
        input integer margin;
        input integer exp_tail;
        input integer exp_weighted;
        input integer exp_safe;
        begin
            i_digit_idx = digit_idx[DIGIT_IDX_WIDTH - 1 : 0];
            i_selection_margin = margin[MARGIN_WIDTH - 1 : 0];
            #1;
            if (!o_valid) begin
                $display("ERROR gate valid missing");
                $fatal;
            end
            if (o_source_tail_bound !== exp_tail[DATA_WIDTH - 1 : 0]) begin
                $display("ERROR tail digit=%0d got=%0d expected=%0d",
                    digit_idx, o_source_tail_bound, exp_tail);
                $fatal;
            end
            if (o_coeff_abs_sum !== 10'd4) begin
                $display("ERROR coeff sum got=%0d expected=4", o_coeff_abs_sum);
                $fatal;
            end
            if (o_weighted_tail_bound !== exp_weighted[MARGIN_WIDTH - 1 : 0]) begin
                $display("ERROR weighted digit=%0d got=%0d expected=%0d",
                    digit_idx, o_weighted_tail_bound, exp_weighted);
                $fatal;
            end
            if (o_prefix_safe !== exp_safe[0]) begin
                $display("ERROR safe digit=%0d margin=%0d got=%0d expected=%0d",
                    digit_idx, margin, o_prefix_safe, exp_safe);
                $fatal;
            end
        end
    endtask

    initial begin
        i_valid = 1'b1;
        i_digit_idx = {DIGIT_IDX_WIDTH{1'b0}};
        // Radius-1 stencil example: |a_-1|=1, |a_0|=2, |a_+1|=1.
        i_coeff_abs_terms = {8'd1, 8'd2, 8'd1};
        i_selection_margin = {MARGIN_WIDTH{1'b0}};

        // p=0: tail=2^(7)-1=127, weighted=508.  Not safe for margin 32.
        check_case(0, 32, 127, 508, 0);

        // p=4: tail=2^(3)-1=7, weighted=28.  Safe for margin 32.
        check_case(4, 32, 7, 28, 1);

        // Strict inequality: weighted=28 is not safe for margin 28.
        check_case(4, 28, 7, 28, 0);

        // Final digit has zero tail.  It is safe for any nonzero margin.
        check_case(7, 1, 0, 0, 1);

        // Saturation is safety-critical: overflowed weighted tails must clamp
        // high instead of wrapping to a falsely safe small value.
        i_coeff_abs_terms = {8'd255, 8'd255, 8'd255};
        i_digit_idx = {DIGIT_IDX_WIDTH{1'b0}};
        #1;
        if (o_small_weighted_tail_bound !== 8'hff ||
            o_small_prefix_safe !== 1'b0) begin
            $display("ERROR small weighted saturation got bound=%0d safe=%0d",
                o_small_weighted_tail_bound,
                o_small_prefix_safe);
            $fatal;
        end

        i_valid = 1'b0;
        #1;
        if (o_prefix_safe !== 1'b0 || o_valid !== 1'b0) begin
            $display("ERROR invalid input should clear valid/safe");
            $fatal;
        end

        $display("PASS tb_iter_prefix_safe_stencil_gate");
        $finish;
    end
endmodule
