`timescale 1ns / 1ps

module tb_iter_dense_small_param_bank_top_file;
    localparam integer NUM_TOTAL_CLUSTERS = 2;
    localparam integer NUM_CLUSTERS = 2;
    localparam integer NUM_ROWS = 4;
    localparam integer DEGREE = 4;
    localparam integer BIT_WIDTH = 8;
    localparam integer BOUND_WIDTH = BIT_WIDTH + 5;
    localparam integer BLOCK_SIZE = 2;
    localparam integer NUM_BLOCKS = (NUM_ROWS + BLOCK_SIZE - 1) / BLOCK_SIZE;
    localparam integer COEFF_WIDTH = 8;
    localparam integer ACC_WIDTH = 24;
    localparam integer DATA_WIDTH = BIT_WIDTH + 3;
    localparam integer CLUSTER_ADDR_WIDTH = 1;

    reg i_clk;
    reg i_rst;
    reg i_start_iter;
    reg i_commit_iter;
    reg [CLUSTER_ADDR_WIDTH - 1 : 0] i_base_cluster_idx;
    reg [NUM_CLUSTERS - 1 : 0] i_use_replay_clusters;
    reg [$clog2(DATA_WIDTH) - 1 : 0] i_replay_digit_idx;
    reg [NUM_CLUSTERS * NUM_ROWS - 1 : 0] i_issue_rows_clusters;
    reg [NUM_ROWS - 1 : 0] x0_p_mem [0 : NUM_CLUSTERS - 1];
    reg [NUM_ROWS - 1 : 0] x1_p_mem [0 : NUM_CLUSTERS - 1];
    reg [NUM_ROWS - 1 : 0] x2_p_mem [0 : NUM_CLUSTERS - 1];
    reg [NUM_ROWS - 1 : 0] x3_p_mem [0 : NUM_CLUSTERS - 1];
    reg [ACC_WIDTH - 1 : 0] gold_max_error_mem [0 : NUM_CLUSTERS - 1];
    wire [NUM_CLUSTERS * NUM_ROWS - 1 : 0] x0_p_clusters;
    wire [NUM_CLUSTERS * NUM_ROWS - 1 : 0] x1_p_clusters;
    wire [NUM_CLUSTERS * NUM_ROWS - 1 : 0] x2_p_clusters;
    wire [NUM_CLUSTERS * NUM_ROWS - 1 : 0] x3_p_clusters;
    reg [NUM_CLUSTERS * BOUND_WIDTH - 1 : 0] i_tail_bound_clusters;

    wire [NUM_CLUSTERS * NUM_ROWS - 1 : 0] o_sched_row_active_clusters;
    wire [NUM_CLUSTERS - 1 : 0] o_cluster_valid, o_cluster_certified;
    wire [NUM_CLUSTERS * ACC_WIDTH - 1 : 0] o_cluster_max_error;
    wire o_iter_done, o_iter_converged, o_iter_continue;
    wire [NUM_CLUSTERS - 1 : 0] o_seen_mask, o_cert_mask;

    assign x0_p_clusters = {x0_p_mem[1], x0_p_mem[0]};
    assign x1_p_clusters = {x1_p_mem[1], x1_p_mem[0]};
    assign x2_p_clusters = {x2_p_mem[1], x2_p_mem[0]};
    assign x3_p_clusters = {x3_p_mem[1], x3_p_mem[0]};

    iter_dense_small_param_bank_top #(
        .num_total_clusters(NUM_TOTAL_CLUSTERS),
        .num_clusters(NUM_CLUSTERS),
        .num_rows(NUM_ROWS),
        .degree(DEGREE),
        .bit_width(BIT_WIDTH),
        .bound_width(BOUND_WIDTH),
        .coeff_width(COEFF_WIDTH),
        .acc_width(ACC_WIDTH),
        .block_size(BLOCK_SIZE),
        .num_blocks(NUM_BLOCKS),
        .data_width(DATA_WIDTH),
        .cluster_addr_width(CLUSTER_ADDR_WIDTH),
        .template_mem_init("MSDF_iterative_solver/generated/rtl_vectors/blockdiag8/templates.memh"),
        .cert_param_mem_init("MSDF_iterative_solver/generated/rtl_vectors/blockdiag8/cert_params.memh")
    ) dut (
        .i_clk(i_clk),
        .i_rst(i_rst),
        .i_start_iter(i_start_iter),
        .i_commit_iter(i_commit_iter),
        .i_base_cluster_idx(i_base_cluster_idx),
        .i_use_replay_clusters(i_use_replay_clusters),
        .i_replay_digit_idx(i_replay_digit_idx),
        .i_issue_rows_clusters(i_issue_rows_clusters),
        .i_x0_p_rows_clusters(x0_p_clusters),
        .i_x0_n_rows_clusters({NUM_CLUSTERS * NUM_ROWS{1'b0}}),
        .i_x1_p_rows_clusters(x1_p_clusters),
        .i_x1_n_rows_clusters({NUM_CLUSTERS * NUM_ROWS{1'b0}}),
        .i_x2_p_rows_clusters(x2_p_clusters),
        .i_x2_n_rows_clusters({NUM_CLUSTERS * NUM_ROWS{1'b0}}),
        .i_x3_p_rows_clusters(x3_p_clusters),
        .i_x3_n_rows_clusters({NUM_CLUSTERS * NUM_ROWS{1'b0}}),
        .i_tail_bound_clusters(i_tail_bound_clusters),
        .o_template_words_clusters(),
        .o_cert_param_words_clusters(),
        .o_sched_row_active_clusters(o_sched_row_active_clusters),
        .o_read_bank_sel_clusters(),
        .o_drv_x0_p_rows_clusters(),
        .o_drv_x0_n_rows_clusters(),
        .o_drv_x1_p_rows_clusters(),
        .o_drv_x1_n_rows_clusters(),
        .o_drv_x2_p_rows_clusters(),
        .o_drv_x2_n_rows_clusters(),
        .o_drv_x3_p_rows_clusters(),
        .o_drv_x3_n_rows_clusters(),
        .o_cluster_valid(o_cluster_valid),
        .o_cluster_certified(o_cluster_certified),
        .o_cluster_max_error(o_cluster_max_error),
        .o_x_old_p_rows_clusters(),
        .o_x_old_n_rows_clusters(),
        .o_iter_done(o_iter_done),
        .o_iter_converged(o_iter_converged),
        .o_iter_continue(o_iter_continue),
        .o_seen_mask(o_seen_mask),
        .o_cert_mask(o_cert_mask)
    );

    always #5 i_clk = ~i_clk;

    task pulse_start_iter;
        begin
            @(negedge i_clk);
            i_start_iter <= 1'b1;
            @(negedge i_clk);
            i_start_iter <= 1'b0;
        end
    endtask

    task launch_once;
        begin
            @(posedge i_clk);
            i_issue_rows_clusters <= {NUM_CLUSTERS * NUM_ROWS{1'b1}};
            @(posedge i_clk);
            i_issue_rows_clusters <= {NUM_CLUSTERS * NUM_ROWS{1'b0}};
        end
    endtask

    integer cycles_waited;
    integer ci;
    initial begin
        $readmemh("MSDF_iterative_solver/generated/rtl_vectors/blockdiag8/x0_p.memh", x0_p_mem);
        $readmemh("MSDF_iterative_solver/generated/rtl_vectors/blockdiag8/x1_p.memh", x1_p_mem);
        $readmemh("MSDF_iterative_solver/generated/rtl_vectors/blockdiag8/x2_p.memh", x2_p_mem);
        $readmemh("MSDF_iterative_solver/generated/rtl_vectors/blockdiag8/x3_p.memh", x3_p_mem);
        $readmemh("MSDF_iterative_solver/generated/rtl_vectors/blockdiag8/gold_max_error.memh", gold_max_error_mem);

        i_clk = 1'b0;
        i_rst = 1'b1;
        i_start_iter = 1'b0;
        i_commit_iter = 1'b0;
        i_base_cluster_idx = 0;
        i_use_replay_clusters = 2'b00;
        i_replay_digit_idx = 0;
        i_issue_rows_clusters = 0;
        i_tail_bound_clusters = {13'd1, 13'd1};

        repeat (2) @(posedge i_clk);
        i_rst <= 1'b0;

        #1;
        if (o_sched_row_active_clusters !== {NUM_CLUSTERS * NUM_ROWS{1'b1}}) begin
            $display("ERROR file top row-active mask mismatch");
            $fatal;
        end

        pulse_start_iter();
        launch_once();
        cycles_waited = 0;
        while (!o_iter_done && cycles_waited < 16) begin
            @(posedge i_clk);
            cycles_waited = cycles_waited + 1;
        end

        if (!o_iter_done || o_seen_mask !== {NUM_CLUSTERS{1'b1}}) begin
            $display("ERROR file top iteration did not finish");
            $fatal;
        end

        for (ci = 0; ci < NUM_CLUSTERS; ci = ci + 1) begin
            if (o_cluster_max_error[(ci + 1) * ACC_WIDTH - 1 -: ACC_WIDTH]
                !== gold_max_error_mem[ci]) begin
                $display("ERROR file top cluster %0d max_error got=%0d expected=%0d",
                    ci,
                    o_cluster_max_error[(ci + 1) * ACC_WIDTH - 1 -: ACC_WIDTH],
                    gold_max_error_mem[ci]);
                $fatal;
            end
            if (o_cluster_certified[ci] !== 1'b0) begin
                $display("ERROR file top cluster %0d certified mismatch", ci);
                $fatal;
            end
        end
        if (!o_iter_continue || o_iter_converged) begin
            $display("ERROR file top iteration decision mismatch");
            $fatal;
        end

        $display("PASS tb_iter_dense_small_param_bank_top_file");
        $finish;
    end
endmodule
