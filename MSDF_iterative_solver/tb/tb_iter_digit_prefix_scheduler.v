`timescale 1ns / 1ps

module tb_iter_digit_prefix_scheduler;
    localparam integer NUM_CLUSTERS = 4;
    localparam integer NUM_ROWS = 2;
    localparam integer DATA_WIDTH = 6;
    localparam integer DIGIT_IDX_WIDTH = $clog2(DATA_WIDTH);

    reg i_clk;
    reg i_rst;
    reg i_start;
    reg i_enable_prefix_gating;
    reg [NUM_CLUSTERS * NUM_ROWS - 1 : 0] i_base_issue_rows;
    reg [NUM_CLUSTERS - 1 : 0] i_cluster_valid;
    reg [NUM_CLUSTERS - 1 : 0] i_cluster_certified;

    wire o_busy;
    wire o_done;
    wire [DIGIT_IDX_WIDTH - 1 : 0] o_digit_idx;
    wire [NUM_CLUSTERS * NUM_ROWS - 1 : 0] o_issue_rows;
    wire [NUM_CLUSTERS - 1 : 0] o_active_clusters;
    wire [31 : 0] o_active_digit_cycles;
    wire [31 : 0] o_gated_digit_cycles;
    wire [31 : 0] o_cert_prefix_digit_sum;
    wire [31 : 0] o_certified_block_count;

    iter_digit_prefix_scheduler #(
        .num_clusters(NUM_CLUSTERS),
        .num_rows(NUM_ROWS),
        .data_width(DATA_WIDTH)
    ) dut (
        .i_clk(i_clk),
        .i_rst(i_rst),
        .i_start(i_start),
        .i_enable_prefix_gating(i_enable_prefix_gating),
        .i_base_issue_rows(i_base_issue_rows),
        .i_cluster_valid(i_cluster_valid),
        .i_cluster_certified(i_cluster_certified),
        .o_busy(o_busy),
        .o_done(o_done),
        .o_digit_idx(o_digit_idx),
        .o_issue_rows(o_issue_rows),
        .o_active_clusters(o_active_clusters),
        .o_active_digit_cycles(o_active_digit_cycles),
        .o_gated_digit_cycles(o_gated_digit_cycles),
        .o_cert_prefix_digit_sum(o_cert_prefix_digit_sum),
        .o_certified_block_count(o_certified_block_count)
    );

    always #5 i_clk = ~i_clk;

    task pulse_start;
        begin
            @(negedge i_clk);
            i_start <= 1'b1;
            @(negedge i_clk);
            i_start <= 1'b0;
        end
    endtask

    task wait_done;
        integer guard;
        begin
            guard = 0;
            while (!o_done && guard < 32) begin
                @(posedge i_clk);
                #1;
                guard = guard + 1;
            end
            if (!o_done) begin
                $display("ERROR scheduler timeout");
                $fatal;
            end
        end
    endtask

    initial begin
        i_clk = 1'b0;
        i_rst = 1'b1;
        i_start = 1'b0;
        i_enable_prefix_gating = 1'b0;
        i_base_issue_rows = {NUM_CLUSTERS * NUM_ROWS{1'b1}};
        i_cluster_valid = {NUM_CLUSTERS{1'b0}};
        i_cluster_certified = {NUM_CLUSTERS{1'b0}};

        repeat (3) @(posedge i_clk);
        i_rst <= 1'b0;

        pulse_start();
        wait_done();

        if (o_active_digit_cycles !== DATA_WIDTH ||
            o_gated_digit_cycles !== 32'd0 ||
            o_certified_block_count !== 32'd0 ||
            o_cert_prefix_digit_sum !== 32'd0) begin
            $display("ERROR ungated counters active=%0d gated=%0d cert_count=%0d cert_sum=%0d",
                o_active_digit_cycles,
                o_gated_digit_cycles,
                o_certified_block_count,
                o_cert_prefix_digit_sum);
            $fatal;
        end

        @(negedge i_clk);
        i_enable_prefix_gating <= 1'b1;
        pulse_start();

        #1;
        if (o_digit_idx !== 0 || o_issue_rows !== {NUM_CLUSTERS * NUM_ROWS{1'b1}}) begin
            $display("ERROR first gated issue digit=%0d issue=%b", o_digit_idx, o_issue_rows);
            $fatal;
        end

        i_cluster_valid = 4'b0011;
        i_cluster_certified = 4'b0001;
        @(posedge i_clk);
        #1;
        if (o_active_clusters !== 4'b1110) begin
            $display("ERROR cluster0 should be gated active=%b", o_active_clusters);
            $fatal;
        end

        @(negedge i_clk);
        i_cluster_valid = 4'b1110;
        i_cluster_certified = 4'b1110;
        @(posedge i_clk);
        #1;
        if (!o_done) begin
            $display("ERROR scheduler should finish after all clusters gated");
            $fatal;
        end

        @(negedge i_clk);
        i_cluster_valid <= 4'b0000;
        i_cluster_certified <= 4'b0000;

        if (o_certified_block_count !== 32'd4 ||
            o_cert_prefix_digit_sum !== 32'd7) begin
            $display("ERROR gated cert counters count=%0d sum=%0d",
                o_certified_block_count,
                o_cert_prefix_digit_sum);
            $fatal;
        end

        $display("PASS tb_iter_digit_prefix_scheduler");
        $finish;
    end
endmodule
