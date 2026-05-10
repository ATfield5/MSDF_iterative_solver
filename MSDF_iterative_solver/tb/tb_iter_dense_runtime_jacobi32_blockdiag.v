`timescale 1ns / 1ps

module tb_iter_dense_runtime_jacobi32_blockdiag;
    localparam integer NUM_TOTAL_CLUSTERS = 8;
    localparam integer NUM_CLUSTERS = 8;
    localparam integer NUM_ROWS = 4;
    localparam integer DEGREE = 4;
    localparam integer BIT_WIDTH = 8;
    localparam integer BOUND_WIDTH = BIT_WIDTH + 5;
    localparam integer BLOCK_SIZE = 2;
    localparam integer NUM_BLOCKS = (NUM_ROWS + BLOCK_SIZE - 1) / BLOCK_SIZE;
    localparam integer COEFF_WIDTH = 8;
    localparam integer ACC_WIDTH = 24;
    localparam integer DATA_WIDTH = BIT_WIDTH + 3;
    localparam integer ROW_IDX_WIDTH = 2;
    localparam integer CLUSTER_ADDR_WIDTH = 3;
    localparam integer CLUSTER_SLOT_WIDTH = 3;
    localparam integer BIAS_WIDTH = BIT_WIDTH + 2;
    localparam integer VALID_WIDTH = NUM_ROWS * DEGREE;
    localparam integer SRC_WIDTH = NUM_ROWS * DEGREE * ROW_IDX_WIDTH;
    localparam integer COEFF_TERMS_WIDTH = NUM_ROWS * DEGREE * BIT_WIDTH;
    localparam integer BIAS_VEC_WIDTH = NUM_ROWS * BIAS_WIDTH;
    localparam integer TEMPLATE_PAYLOAD_WIDTH =
        VALID_WIDTH + SRC_WIDTH + 2 * COEFF_TERMS_WIDTH + 2 * BIAS_VEC_WIDTH;
    localparam integer BLOCK_WEIGHTS_WIDTH = NUM_ROWS * NUM_BLOCKS * COEFF_WIDTH;
    localparam integer CERT_PAYLOAD_WIDTH = BLOCK_WEIGHTS_WIDTH + ACC_WIDTH;

    reg i_clk;
    reg i_rst;
    reg i_cfg_template_we;
    reg i_cfg_cert_we;
    reg [CLUSTER_ADDR_WIDTH - 1 : 0] i_cfg_cluster_addr;
    reg [TEMPLATE_PAYLOAD_WIDTH - 1 : 0] i_cfg_template_word;
    reg [CERT_PAYLOAD_WIDTH - 1 : 0] i_cfg_cert_word;
    reg i_load_window;
    reg i_cfg_state_we;
    reg [CLUSTER_SLOT_WIDTH - 1 : 0] i_cfg_state_cluster_slot;
    reg i_cfg_state_bank_sel;
    reg [ROW_IDX_WIDTH - 1 : 0] i_cfg_state_row_idx;
    reg [DATA_WIDTH - 1 : 0] i_cfg_state_p;
    reg [DATA_WIDTH - 1 : 0] i_cfg_state_n;
    reg i_start_iter;
    reg i_commit_iter;
    reg [CLUSTER_ADDR_WIDTH - 1 : 0] i_base_cluster_idx;
    reg [NUM_CLUSTERS - 1 : 0] i_use_replay_clusters;
    reg [$clog2(DATA_WIDTH) - 1 : 0] i_replay_digit_idx;
    reg [NUM_CLUSTERS * NUM_ROWS - 1 : 0] i_issue_rows_clusters;
    reg [NUM_CLUSTERS * BOUND_WIDTH - 1 : 0] i_tail_bound_clusters;
    reg i_counter_clear;

    reg [TEMPLATE_PAYLOAD_WIDTH - 1 : 0] template_mem [0 : NUM_TOTAL_CLUSTERS - 1];
    reg [CERT_PAYLOAD_WIDTH - 1 : 0] cert_mem [0 : NUM_TOTAL_CLUSTERS - 1];
    reg [NUM_ROWS - 1 : 0] x0_p_mem [0 : NUM_CLUSTERS - 1];
    reg [NUM_ROWS - 1 : 0] x1_p_mem [0 : NUM_CLUSTERS - 1];
    reg [NUM_ROWS - 1 : 0] x2_p_mem [0 : NUM_CLUSTERS - 1];
    reg [NUM_ROWS - 1 : 0] x3_p_mem [0 : NUM_CLUSTERS - 1];
    reg [ACC_WIDTH - 1 : 0] gold_max_error_mem [0 : NUM_CLUSTERS - 1];
    reg gold_certified_mem [0 : NUM_CLUSTERS - 1];

    reg [NUM_CLUSTERS * NUM_ROWS - 1 : 0] x0_p_clusters;
    reg [NUM_CLUSTERS * NUM_ROWS - 1 : 0] x1_p_clusters;
    reg [NUM_CLUSTERS * NUM_ROWS - 1 : 0] x2_p_clusters;
    reg [NUM_CLUSTERS * NUM_ROWS - 1 : 0] x3_p_clusters;
    reg [NUM_CLUSTERS * TEMPLATE_PAYLOAD_WIDTH - 1 : 0] expected_template_words;
    reg [NUM_CLUSTERS * CERT_PAYLOAD_WIDTH - 1 : 0] expected_cert_words;

    wire [NUM_CLUSTERS * TEMPLATE_PAYLOAD_WIDTH - 1 : 0] o_template_words_clusters;
    wire [NUM_CLUSTERS * CERT_PAYLOAD_WIDTH - 1 : 0] o_cert_param_words_clusters;
    wire [NUM_CLUSTERS * NUM_ROWS - 1 : 0] o_sched_row_active_clusters;
    wire [NUM_CLUSTERS - 1 : 0] o_cluster_valid;
    wire [NUM_CLUSTERS - 1 : 0] o_cluster_certified;
    wire [NUM_CLUSTERS * ACC_WIDTH - 1 : 0] o_cluster_max_error;
    wire [NUM_CLUSTERS * NUM_ROWS * DATA_WIDTH - 1 : 0] o_x_old_p_rows_clusters;
    wire o_window_valid;
    wire o_window_busy;
    wire [31 : 0] o_total_cycles;
    wire [31 : 0] o_issue_cycles;
    wire [31 : 0] o_cert_wait_cycles;
    wire [31 : 0] o_iter_count;
    wire [31 : 0] o_converged_iter;
    wire [31 : 0] o_cfg_template_write_count;
    wire [31 : 0] o_cfg_cert_write_count;
    wire [31 : 0] o_cfg_state_write_count;
    wire [31 : 0] o_window_load_count;
    wire [31 : 0] o_window_busy_cycles;
    wire [31 : 0] o_window_ready_cycles;
    wire o_iter_done;
    wire o_iter_converged;
    wire o_iter_continue;
    wire [NUM_CLUSTERS - 1 : 0] o_seen_mask;

    iter_dense_small_runtime_top #(
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
        .row_idx_width(ROW_IDX_WIDTH),
        .cluster_addr_width(CLUSTER_ADDR_WIDTH),
        .cluster_slot_width(CLUSTER_SLOT_WIDTH),
        .runtime_mem_style(1)
    ) dut (
        .i_clk(i_clk),
        .i_rst(i_rst),
        .i_cfg_template_we(i_cfg_template_we),
        .i_cfg_cert_we(i_cfg_cert_we),
        .i_cfg_cluster_addr(i_cfg_cluster_addr),
        .i_cfg_template_word(i_cfg_template_word),
        .i_cfg_cert_word(i_cfg_cert_word),
        .i_load_window(i_load_window),
        .i_cfg_state_we(i_cfg_state_we),
        .i_cfg_state_cluster_slot(i_cfg_state_cluster_slot),
        .i_cfg_state_bank_sel(i_cfg_state_bank_sel),
        .i_cfg_state_row_idx(i_cfg_state_row_idx),
        .i_cfg_state_p(i_cfg_state_p),
        .i_cfg_state_n(i_cfg_state_n),
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
        .i_counter_clear(i_counter_clear),
        .o_window_valid(o_window_valid),
        .o_window_busy(o_window_busy),
        .o_total_cycles(o_total_cycles),
        .o_issue_cycles(o_issue_cycles),
        .o_cert_wait_cycles(o_cert_wait_cycles),
        .o_iter_count(o_iter_count),
        .o_converged_iter(o_converged_iter),
        .o_cfg_template_write_count(o_cfg_template_write_count),
        .o_cfg_cert_write_count(o_cfg_cert_write_count),
        .o_cfg_state_write_count(o_cfg_state_write_count),
        .o_window_load_count(o_window_load_count),
        .o_window_busy_cycles(o_window_busy_cycles),
        .o_window_ready_cycles(o_window_ready_cycles),
        .o_template_words_clusters(o_template_words_clusters),
        .o_cert_param_words_clusters(o_cert_param_words_clusters),
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
        .o_x_old_p_rows_clusters(o_x_old_p_rows_clusters),
        .o_x_old_n_rows_clusters(),
        .o_iter_done(o_iter_done),
        .o_iter_converged(o_iter_converged),
        .o_iter_continue(o_iter_continue),
        .o_seen_mask(o_seen_mask),
        .o_cert_mask()
    );

    always #5 i_clk = ~i_clk;

    task pack_vectors;
        integer k;
        begin
            x0_p_clusters = {NUM_CLUSTERS * NUM_ROWS{1'b0}};
            x1_p_clusters = {NUM_CLUSTERS * NUM_ROWS{1'b0}};
            x2_p_clusters = {NUM_CLUSTERS * NUM_ROWS{1'b0}};
            x3_p_clusters = {NUM_CLUSTERS * NUM_ROWS{1'b0}};
            expected_template_words = {NUM_CLUSTERS * TEMPLATE_PAYLOAD_WIDTH{1'b0}};
            expected_cert_words = {NUM_CLUSTERS * CERT_PAYLOAD_WIDTH{1'b0}};
            for (k = 0; k < NUM_CLUSTERS; k = k + 1) begin
                x0_p_clusters[k * NUM_ROWS +: NUM_ROWS] = x0_p_mem[k];
                x1_p_clusters[k * NUM_ROWS +: NUM_ROWS] = x1_p_mem[k];
                x2_p_clusters[k * NUM_ROWS +: NUM_ROWS] = x2_p_mem[k];
                x3_p_clusters[k * NUM_ROWS +: NUM_ROWS] = x3_p_mem[k];
                expected_template_words[k * TEMPLATE_PAYLOAD_WIDTH +: TEMPLATE_PAYLOAD_WIDTH] = template_mem[k];
                expected_cert_words[k * CERT_PAYLOAD_WIDTH +: CERT_PAYLOAD_WIDTH] = cert_mem[k];
            end
        end
    endtask

    task cfg_write_cluster;
        input integer cluster_idx;
        begin
            @(negedge i_clk);
            i_cfg_cluster_addr <= cluster_idx[CLUSTER_ADDR_WIDTH - 1 : 0];
            i_cfg_template_word <= template_mem[cluster_idx];
            i_cfg_cert_word <= cert_mem[cluster_idx];
            i_cfg_template_we <= 1'b1;
            i_cfg_cert_we <= 1'b1;
            @(negedge i_clk);
            i_cfg_template_we <= 1'b0;
            i_cfg_cert_we <= 1'b0;
        end
    endtask

    task cfg_load_state;
        input integer cluster_slot;
        input [ROW_IDX_WIDTH - 1 : 0] row_idx;
        input [DATA_WIDTH - 1 : 0] state_p;
        begin
            @(negedge i_clk);
            i_cfg_state_cluster_slot <= cluster_slot[CLUSTER_SLOT_WIDTH - 1 : 0];
            i_cfg_state_bank_sel <= 1'b0;
            i_cfg_state_row_idx <= row_idx;
            i_cfg_state_p <= state_p;
            i_cfg_state_n <= {DATA_WIDTH{1'b0}};
            i_cfg_state_we <= 1'b1;
            @(negedge i_clk);
            i_cfg_state_we <= 1'b0;
            i_cfg_state_p <= {DATA_WIDTH{1'b0}};
        end
    endtask

    task load_window;
        integer wi;
        begin
            @(negedge i_clk);
            i_load_window <= 1'b1;
            @(negedge i_clk);
            i_load_window <= 1'b0;
            for (wi = 0; wi < 24; wi = wi + 1) begin
                @(posedge i_clk);
                if (o_window_valid) begin
                    wi = 24;
                end
            end
            if (!o_window_valid || o_window_busy) begin
                $display("ERROR jacobi32 window load did not finish");
                $fatal;
            end
        end
    endtask

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

    integer ci;
    integer cycles_waited;
    reg [DATA_WIDTH - 1 : 0] expected_state_word;
    initial begin
        $readmemh("MSDF_iterative_solver/generated/rtl_vectors/jacobi32_blockdiag/templates.memh", template_mem);
        $readmemh("MSDF_iterative_solver/generated/rtl_vectors/jacobi32_blockdiag/cert_params.memh", cert_mem);
        $readmemh("MSDF_iterative_solver/generated/rtl_vectors/jacobi32_blockdiag/x0_p.memh", x0_p_mem);
        $readmemh("MSDF_iterative_solver/generated/rtl_vectors/jacobi32_blockdiag/x1_p.memh", x1_p_mem);
        $readmemh("MSDF_iterative_solver/generated/rtl_vectors/jacobi32_blockdiag/x2_p.memh", x2_p_mem);
        $readmemh("MSDF_iterative_solver/generated/rtl_vectors/jacobi32_blockdiag/x3_p.memh", x3_p_mem);
        $readmemh("MSDF_iterative_solver/generated/rtl_vectors/jacobi32_blockdiag/gold_max_error.memh", gold_max_error_mem);
        $readmemh("MSDF_iterative_solver/generated/rtl_vectors/jacobi32_blockdiag/gold_certified.memh", gold_certified_mem);
        pack_vectors();

        i_clk = 1'b0;
        i_rst = 1'b1;
        i_cfg_template_we = 1'b0;
        i_cfg_cert_we = 1'b0;
        i_cfg_cluster_addr = 0;
        i_cfg_template_word = 0;
        i_cfg_cert_word = 0;
        i_load_window = 1'b0;
        i_cfg_state_we = 1'b0;
        i_cfg_state_cluster_slot = 0;
        i_cfg_state_bank_sel = 1'b0;
        i_cfg_state_row_idx = 0;
        i_cfg_state_p = 0;
        i_cfg_state_n = 0;
        i_start_iter = 1'b0;
        i_commit_iter = 1'b0;
        i_base_cluster_idx = 0;
        i_use_replay_clusters = {NUM_CLUSTERS{1'b0}};
        i_replay_digit_idx = 0;
        i_issue_rows_clusters = 0;
        i_tail_bound_clusters = {NUM_CLUSTERS{13'd1}};
        i_counter_clear = 1'b0;

        repeat (2) @(posedge i_clk);
        i_rst <= 1'b0;

        for (ci = 0; ci < NUM_CLUSTERS; ci = ci + 1) begin
            cfg_write_cluster(ci);
        end
        load_window();
        for (ci = 0; ci < NUM_CLUSTERS; ci = ci + 1) begin
            expected_state_word = ci + 1;
            cfg_load_state(ci, 2'd0, expected_state_word);
        end

        @(posedge i_clk);
        #1;
        if (o_template_words_clusters !== expected_template_words ||
            o_cert_param_words_clusters !== expected_cert_words) begin
            $display("ERROR jacobi32 runtime payload mismatch");
            $fatal;
        end
        for (ci = 0; ci < NUM_CLUSTERS; ci = ci + 1) begin
            expected_state_word = ci + 1;
            if (o_x_old_p_rows_clusters[ci * NUM_ROWS * DATA_WIDTH +: DATA_WIDTH]
                !== expected_state_word) begin
                $display("ERROR jacobi32 state load mismatch cluster=%0d", ci);
                $fatal;
            end
        end

        // The generated Jacobi32-blockdiag golden vectors model the first
        // iteration from the standard zero initial state. The non-zero writes
        // above only exercise the runtime state-load path; overwrite them to
        // zero before launching the arithmetic/certification datapath.
        for (ci = 0; ci < NUM_CLUSTERS; ci = ci + 1) begin
            cfg_load_state(ci, 2'd0, {DATA_WIDTH{1'b0}});
        end

        if (o_sched_row_active_clusters !== {NUM_CLUSTERS * NUM_ROWS{1'b1}}) begin
            $display("ERROR jacobi32 row-active mask mismatch");
            $fatal;
        end
        if (o_cfg_template_write_count !== NUM_CLUSTERS ||
            o_cfg_cert_write_count !== NUM_CLUSTERS ||
            o_cfg_state_write_count !== (2 * NUM_CLUSTERS) ||
            o_window_load_count !== 32'd1 ||
            o_window_busy_cycles === 32'd0 ||
            o_window_ready_cycles === 32'd0) begin
            $display("ERROR jacobi32 loader counters tmpl=%0d cert=%0d state=%0d load=%0d busy=%0d ready=%0d",
                o_cfg_template_write_count,
                o_cfg_cert_write_count,
                o_cfg_state_write_count,
                o_window_load_count,
                o_window_busy_cycles,
                o_window_ready_cycles);
            $fatal;
        end

        pulse_start_iter();
        launch_once();
        cycles_waited = 0;
        while (!o_iter_done && cycles_waited < 40) begin
            @(posedge i_clk);
            cycles_waited = cycles_waited + 1;
        end
        if (!o_iter_done || o_seen_mask !== {NUM_CLUSTERS{1'b1}}) begin
            $display("ERROR jacobi32 iteration did not finish");
            $fatal;
        end

        for (ci = 0; ci < NUM_CLUSTERS; ci = ci + 1) begin
            if (o_cluster_max_error[ci * ACC_WIDTH +: ACC_WIDTH] !== gold_max_error_mem[ci]) begin
                $display("ERROR jacobi32 max_error cluster=%0d got=%0d expected=%0d",
                    ci, o_cluster_max_error[ci * ACC_WIDTH +: ACC_WIDTH], gold_max_error_mem[ci]);
                $fatal;
            end
            if (o_cluster_certified[ci] !== gold_certified_mem[ci]) begin
                $display("ERROR jacobi32 certified cluster=%0d got=%0d expected=%0d",
                    ci, o_cluster_certified[ci], gold_certified_mem[ci]);
                $fatal;
            end
        end

        if (!o_iter_converged || o_iter_continue) begin
            $display("ERROR jacobi32 iteration decision mismatch conv=%0d cont=%0d",
                o_iter_converged, o_iter_continue);
            $fatal;
        end
        @(posedge i_clk);
        #1;
        if (o_iter_count !== 32'd1 ||
            o_issue_cycles !== 32'd1 ||
            o_cert_wait_cycles === 32'd0 ||
            o_converged_iter !== 32'd1) begin
            $display("ERROR jacobi32 counters iter=%0d issue=%0d cert_wait=%0d conv_iter=%0d total=%0d",
                o_iter_count, o_issue_cycles, o_cert_wait_cycles, o_converged_iter, o_total_cycles);
            $fatal;
        end

        $display("COUNTERS jacobi32_blockdiag total=%0d issue=%0d cert_wait=%0d iter=%0d conv_iter=%0d cfg_template=%0d cfg_cert=%0d cfg_state=%0d window_load=%0d window_busy=%0d window_ready=%0d",
            o_total_cycles,
            o_issue_cycles,
            o_cert_wait_cycles,
            o_iter_count,
            o_converged_iter,
            o_cfg_template_write_count,
            o_cfg_cert_write_count,
            o_cfg_state_write_count,
            o_window_load_count,
            o_window_busy_cycles,
            o_window_ready_cycles);
        $display("PASS tb_iter_dense_runtime_jacobi32_blockdiag");
        $finish;
    end
endmodule
