`timescale 1ns / 1ps

module tb_iter_prefix_safe_row_start_queue;
    localparam integer NUM_ROWS = 4;
    localparam integer DATA_WIDTH = 8;
    localparam integer DIGIT_IDX_WIDTH = $clog2(DATA_WIDTH);
    localparam integer ROW_ID_WIDTH = $clog2(NUM_ROWS);
    localparam integer LEAD_WIDTH = DIGIT_IDX_WIDTH + 1;
    localparam integer COUNT_WIDTH = $clog2(NUM_ROWS + 1);

    reg i_clk;
    reg i_rst;
    reg i_start;
    reg [NUM_ROWS - 1 : 0] i_issue_rows;
    reg [DIGIT_IDX_WIDTH - 1 : 0] i_issue_digit_idx;
    reg i_consumer_ready;
    wire o_consumer_valid;
    wire [ROW_ID_WIDTH - 1 : 0] o_consumer_row_id;
    wire [DIGIT_IDX_WIDTH - 1 : 0] o_consumer_digit_idx;
    wire [LEAD_WIDTH - 1 : 0] o_consumer_lead_cycles;
    wire [NUM_ROWS - 1 : 0] o_pending_mask;
    wire [COUNT_WIDTH - 1 : 0] o_pending_count;
    wire [31 : 0] o_dispatch_count;
    wire o_duplicate_issue;

    iter_prefix_safe_row_start_queue #(
        .num_rows(NUM_ROWS),
        .data_width(DATA_WIDTH)
    ) dut (
        .i_clk(i_clk),
        .i_rst(i_rst),
        .i_start(i_start),
        .i_issue_rows(i_issue_rows),
        .i_issue_digit_idx(i_issue_digit_idx),
        .i_consumer_ready(i_consumer_ready),
        .o_consumer_valid(o_consumer_valid),
        .o_consumer_row_id(o_consumer_row_id),
        .o_consumer_digit_idx(o_consumer_digit_idx),
        .o_consumer_lead_cycles(o_consumer_lead_cycles),
        .o_pending_mask(o_pending_mask),
        .o_pending_count(o_pending_count),
        .o_dispatch_count(o_dispatch_count),
        .o_duplicate_issue(o_duplicate_issue)
    );

    always #5 i_clk = ~i_clk;

    task drive_issue;
        input [NUM_ROWS - 1 : 0] rows;
        input integer digit_idx;
        input ready;
        begin
            @(negedge i_clk);
            i_issue_rows <= rows;
            i_issue_digit_idx <= digit_idx[DIGIT_IDX_WIDTH - 1 : 0];
            i_consumer_ready <= ready;
            @(posedge i_clk);
            #1;
            i_issue_rows <= {NUM_ROWS{1'b0}};
        end
    endtask

    task drive_ready;
        input ready;
        begin
            @(negedge i_clk);
            i_issue_rows <= {NUM_ROWS{1'b0}};
            i_consumer_ready <= ready;
            @(posedge i_clk);
            #1;
        end
    endtask

    task expect_queue;
        input [NUM_ROWS - 1 : 0] exp_mask;
        input integer exp_count;
        input exp_valid;
        input integer exp_row;
        input integer exp_digit;
        input integer exp_lead;
        begin
            if (o_pending_mask !== exp_mask ||
                o_pending_count !== exp_count[COUNT_WIDTH - 1 : 0] ||
                o_consumer_valid !== exp_valid) begin
                $display("ERROR queue mask/count/valid got %b/%0d/%0d exp %b/%0d/%0d",
                    o_pending_mask,
                    o_pending_count,
                    o_consumer_valid,
                    exp_mask,
                    exp_count,
                    exp_valid);
                $fatal;
            end
            if (exp_valid) begin
                if (o_consumer_row_id !== exp_row[ROW_ID_WIDTH - 1 : 0] ||
                    o_consumer_digit_idx !== exp_digit[DIGIT_IDX_WIDTH - 1 : 0] ||
                    o_consumer_lead_cycles !== exp_lead[LEAD_WIDTH - 1 : 0]) begin
                    $display("ERROR queue head row/digit/lead got %0d/%0d/%0d exp %0d/%0d/%0d",
                        o_consumer_row_id,
                        o_consumer_digit_idx,
                        o_consumer_lead_cycles,
                        exp_row,
                        exp_digit,
                        exp_lead);
                    $fatal;
                end
            end
        end
    endtask

    initial begin
        i_clk = 1'b0;
        i_rst = 1'b1;
        i_start = 1'b0;
        i_issue_rows = {NUM_ROWS{1'b0}};
        i_issue_digit_idx = {DIGIT_IDX_WIDTH{1'b0}};
        i_consumer_ready = 1'b0;

        repeat (2) @(posedge i_clk);
        i_rst <= 1'b0;

        @(negedge i_clk);
        i_start <= 1'b1;
        @(negedge i_clk);
        i_start <= 1'b0;

        drive_issue(4'b0011, 2, 1'b0);
        expect_queue(4'b0011, 2, 1'b1, 0, 2, 5);

        drive_ready(1'b1);
        expect_queue(4'b0010, 1, 1'b1, 1, 2, 5);
        if (o_dispatch_count !== 32'd1) begin
            $display("ERROR dispatch_count after row0 = %0d", o_dispatch_count);
            $fatal;
        end

        drive_ready(1'b1);
        expect_queue(4'b0000, 0, 1'b0, 0, 0, 0);
        if (o_dispatch_count !== 32'd2) begin
            $display("ERROR dispatch_count after row1 = %0d", o_dispatch_count);
            $fatal;
        end

        drive_issue(4'b1100, 6, 1'b1);
        expect_queue(4'b1100, 2, 1'b1, 2, 6, 1);

        drive_ready(1'b1);
        expect_queue(4'b1000, 1, 1'b1, 3, 6, 1);

        drive_ready(1'b1);
        expect_queue(4'b0000, 0, 1'b0, 0, 0, 0);
        if (o_dispatch_count !== 32'd4) begin
            $display("ERROR final dispatch_count = %0d", o_dispatch_count);
            $fatal;
        end

        drive_issue(4'b0001, 3, 1'b0);
        expect_queue(4'b0001, 1, 1'b1, 0, 3, 4);

        drive_issue(4'b0001, 3, 1'b0);
        if (!o_duplicate_issue) begin
            $display("ERROR duplicate issue was not detected");
            $fatal;
        end

        $display("PASS tb_iter_prefix_safe_row_start_queue");
        $finish;
    end
endmodule
