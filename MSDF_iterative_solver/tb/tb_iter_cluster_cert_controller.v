`timescale 1ns / 1ps

module tb_iter_cluster_cert_controller;
    localparam integer NUM_CLUSTERS = 3;

    reg i_clk;
    reg i_rst;
    reg i_start_iter;
    reg [NUM_CLUSTERS-1:0] i_cluster_valid;
    reg [NUM_CLUSTERS-1:0] i_cluster_certified;
    wire o_iter_done;
    wire o_iter_converged;
    wire o_iter_continue;
    wire [NUM_CLUSTERS-1:0] o_seen_mask;
    wire [NUM_CLUSTERS-1:0] o_cert_mask;

    iter_cluster_cert_controller #(
        .num_clusters(NUM_CLUSTERS)
    ) dut (
        .i_clk(i_clk),
        .i_rst(i_rst),
        .i_start_iter(i_start_iter),
        .i_cluster_valid(i_cluster_valid),
        .i_cluster_certified(i_cluster_certified),
        .o_iter_done(o_iter_done),
        .o_iter_converged(o_iter_converged),
        .o_iter_continue(o_iter_continue),
        .o_seen_mask(o_seen_mask),
        .o_cert_mask(o_cert_mask)
    );

    always #5 i_clk = ~i_clk;

    task drive_cluster;
        input [NUM_CLUSTERS-1:0] valid_bits;
        input [NUM_CLUSTERS-1:0] cert_bits;
        begin
            i_cluster_valid = valid_bits;
            i_cluster_certified = cert_bits;
            @(posedge i_clk);
        end
    endtask

    initial begin
        i_clk = 1'b0;
        i_rst = 1'b1;
        i_start_iter = 1'b0;
        i_cluster_valid = 3'b000;
        i_cluster_certified = 3'b000;

        repeat (2) @(posedge i_clk);
        i_rst <= 1'b0;

        // Iteration 1: all clusters certify.
        @(negedge i_clk);
        i_start_iter = 1'b1;
        @(posedge i_clk);
        @(negedge i_clk);
        i_start_iter = 1'b0;

        drive_cluster(3'b001, 3'b001);
        drive_cluster(3'b010, 3'b010);
        drive_cluster(3'b100, 3'b100);
        #1;
        if (!o_iter_done || !o_iter_converged || o_iter_continue ||
            o_seen_mask !== 3'b111 || o_cert_mask !== 3'b111) begin
            $display("ERROR tb_iter_cluster_cert_controller iter1 done=%b conv=%b cont=%b seen=%b cert=%b",
                o_iter_done, o_iter_converged, o_iter_continue, o_seen_mask, o_cert_mask);
            $fatal;
        end
        i_cluster_valid = 3'b000;
        i_cluster_certified = 3'b000;
        @(posedge i_clk);

        // Iteration 2: one cluster fails certification.
        @(negedge i_clk);
        i_start_iter = 1'b1;
        @(posedge i_clk);
        @(negedge i_clk);
        i_start_iter = 1'b0;

        drive_cluster(3'b001, 3'b001);
        drive_cluster(3'b010, 3'b000);
        drive_cluster(3'b100, 3'b100);
        #1;
        if (!o_iter_done || o_iter_converged || !o_iter_continue ||
            o_seen_mask !== 3'b111 || o_cert_mask !== 3'b101) begin
            $display("ERROR tb_iter_cluster_cert_controller iter2 done=%b conv=%b cont=%b seen=%b cert=%b",
                o_iter_done, o_iter_converged, o_iter_continue, o_seen_mask, o_cert_mask);
            $fatal;
        end
        i_cluster_valid = 3'b000;
        i_cluster_certified = 3'b000;
        @(posedge i_clk);

        $display("PASS tb_iter_cluster_cert_controller");
        $finish;
    end
endmodule
