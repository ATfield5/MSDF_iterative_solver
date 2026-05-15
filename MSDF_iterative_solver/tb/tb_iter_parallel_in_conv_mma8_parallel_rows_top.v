`timescale 1ns / 1ps

// P4-SP one-stage parallel-rows conventional baseline test.
//
// All 32 rows run in parallel.  Each row has 8 full-word MAC slots.  The test
// reuses the same one-stage datapath for NUM_ITERS PageRank iterations.  The
// first iteration starts from zero state; each output vector is fed back as the
// next iteration input.

module tb_iter_parallel_in_conv_mma8_parallel_rows_top;

`ifndef PARALLEL_IN_VECTOR_DIR
`define PARALLEL_IN_VECTOR_DIR "MSDF_iterative_solver/generated/rtl_vectors/pagerank32_global_parallel_in_fractional"
`endif

`ifdef PARALLEL_IN_DEGREE_VALUE
    localparam integer DEGREE = `PARALLEL_IN_DEGREE_VALUE;
`else
    localparam integer DEGREE = 4;
`endif

    localparam integer NUM_ITERS = 4;
    localparam integer GOLD_FILE_ITERS = 8;
    localparam integer NUM_CLUSTERS = 8;
    localparam integer ROWS_PER_CLUSTER = 4;
    localparam integer TOTAL_ROWS = NUM_CLUSTERS * ROWS_PER_CLUSTER;
    localparam integer PHYSICAL_DEGREE = 8;
    localparam integer TEMPLATE_BIT_WIDTH = 30;
    localparam integer COEFF_WIDTH = 32;
    localparam integer DATA_WIDTH = 32;
    localparam integer BIAS_WIDTH = 32;
    localparam integer BOUND_WIDTH = 16;
    localparam integer SRC_IDX_WIDTH = 5;
    localparam integer ACC_WIDTH = 40;
    localparam integer PRODUCT_WIDTH = 66;
    localparam integer PRODUCT_SHIFT = DATA_WIDTH;
    localparam integer VALID_WIDTH = ROWS_PER_CLUSTER * DEGREE;
    localparam integer SRC_WIDTH = ROWS_PER_CLUSTER * DEGREE * SRC_IDX_WIDTH;
    localparam integer TEMPLATE_COEFF_TERMS_WIDTH = ROWS_PER_CLUSTER * DEGREE * TEMPLATE_BIT_WIDTH;
    localparam integer BIAS_VEC_WIDTH = ROWS_PER_CLUSTER * BIAS_WIDTH;
    localparam integer TEMPLATE_PAYLOAD_WIDTH =
        VALID_WIDTH + SRC_WIDTH + 2 * TEMPLATE_COEFF_TERMS_WIDTH + 2 * BIAS_VEC_WIDTH;

    reg i_clk;
    reg i_rst;
    reg i_clear;
    reg i_start;

    reg [TEMPLATE_PAYLOAD_WIDTH - 1 : 0] template_mem [0 : NUM_CLUSTERS - 1];
    reg [NUM_CLUSTERS * TEMPLATE_PAYLOAD_WIDTH - 1 : 0] template_words_clusters;
    reg [ROWS_PER_CLUSTER * DATA_WIDTH - 1 : 0] gold_state_p_mem [0 : GOLD_FILE_ITERS * NUM_CLUSTERS - 1];
    reg [ROWS_PER_CLUSTER * DATA_WIDTH - 1 : 0] gold_state_n_mem [0 : GOLD_FILE_ITERS * NUM_CLUSTERS - 1];

    wire [NUM_CLUSTERS * VALID_WIDTH - 1 : 0] w_term_valid_mask_clusters;
    wire [NUM_CLUSTERS * SRC_WIDTH - 1 : 0] w_src_row_idx_clusters;
    wire [NUM_CLUSTERS * TEMPLATE_COEFF_TERMS_WIDTH - 1 : 0] w_coeff_p_terms_clusters;
    wire [NUM_CLUSTERS * TEMPLATE_COEFF_TERMS_WIDTH - 1 : 0] w_coeff_n_terms_clusters;
    wire [NUM_CLUSTERS * BIAS_VEC_WIDTH - 1 : 0] w_bias_vec_p_rows_clusters;
    wire [NUM_CLUSTERS * BIAS_VEC_WIDTH - 1 : 0] w_bias_vec_n_rows_clusters;

    reg [TOTAL_ROWS * PHYSICAL_DEGREE * DATA_WIDTH - 1 : 0] state_p_terms_rows;
    reg [TOTAL_ROWS * PHYSICAL_DEGREE * DATA_WIDTH - 1 : 0] state_n_terms_rows;
    reg [TOTAL_ROWS * PHYSICAL_DEGREE * COEFF_WIDTH - 1 : 0] coeff_p_terms_rows;
    reg [TOTAL_ROWS * PHYSICAL_DEGREE * COEFF_WIDTH - 1 : 0] coeff_n_terms_rows;
    reg [DATA_WIDTH - 1 : 0] current_state_p [0 : TOTAL_ROWS - 1];
    reg [DATA_WIDTH - 1 : 0] current_state_n [0 : TOTAL_ROWS - 1];

    wire w_done;
    wire [TOTAL_ROWS * DATA_WIDTH - 1 : 0] w_state_p_rows;
    wire [TOTAL_ROWS * DATA_WIDTH - 1 : 0] w_state_n_rows;
    wire [TOTAL_ROWS * ACC_WIDTH - 1 : 0] w_sum_rows;

    integer cycle_count;
    integer compute_start_cycle;
    integer compute_cycles;
    integer total_compute_cycles;
    integer wait_count;
    integer iter_idx;
    integer ci;
    integer row;
    integer ti;
    integer src_row;
    integer src_cluster;
    integer src_local;
    integer row_cluster;
    integer row_local;
    integer prev_gold_idx;
    integer target_gold_idx;
    reg [DATA_WIDTH - 1 : 0] dut_p_word;
    reg [DATA_WIDTH - 1 : 0] dut_n_word;
    reg [DATA_WIDTH - 1 : 0] gold_p_word;
    reg [DATA_WIDTH - 1 : 0] gold_n_word;

    always #5 i_clk = ~i_clk;

    iter_fixed_degree_template_unpack #(
        .num_clusters(NUM_CLUSTERS),
        .num_rows(ROWS_PER_CLUSTER),
        .degree(DEGREE),
        .bit_width(TEMPLATE_BIT_WIDTH),
        .bias_width(BIAS_WIDTH),
        .row_idx_width(SRC_IDX_WIDTH),
        .valid_width(VALID_WIDTH),
        .src_width(SRC_WIDTH),
        .coeff_terms_width(TEMPLATE_COEFF_TERMS_WIDTH),
        .bias_vec_width(BIAS_VEC_WIDTH),
        .payload_width(TEMPLATE_PAYLOAD_WIDTH)
    ) unpack_templates (
        .i_template_words_clusters(template_words_clusters),
        .o_term_valid_mask_clusters(w_term_valid_mask_clusters),
        .o_src_row_idx_clusters(w_src_row_idx_clusters),
        .o_coeff_p_terms_clusters(w_coeff_p_terms_clusters),
        .o_coeff_n_terms_clusters(w_coeff_n_terms_clusters),
        .o_bias_vec_p_rows_clusters(w_bias_vec_p_rows_clusters),
        .o_bias_vec_n_rows_clusters(w_bias_vec_n_rows_clusters)
    );

    iter_parallel_in_conv_mma8_parallel_rows_top #(
        .num_rows(TOTAL_ROWS),
        .physical_degree(PHYSICAL_DEGREE),
        .data_width(DATA_WIDTH),
        .coeff_width(COEFF_WIDTH),
        .bias_width(BIAS_WIDTH),
        .bound_width(BOUND_WIDTH),
        .acc_width(ACC_WIDTH),
        .product_width(PRODUCT_WIDTH),
        .product_shift(PRODUCT_SHIFT),
        .round_pipeline(1)
    ) dut (
        .i_clk(i_clk),
        .i_rst(i_rst),
        .i_clear(i_clear),
        .i_start(i_start),
        .i_state_p_terms_rows(state_p_terms_rows),
        .i_state_n_terms_rows(state_n_terms_rows),
        .i_coeff_p_terms_rows(coeff_p_terms_rows),
        .i_coeff_n_terms_rows(coeff_n_terms_rows),
        .i_bias_p_rows(w_bias_vec_p_rows_clusters),
        .i_bias_n_rows(w_bias_vec_n_rows_clusters),
        .o_done(w_done),
        .o_state_p_rows(w_state_p_rows),
        .o_state_n_rows(w_state_n_rows),
        .o_sum_rows(w_sum_rows)
    );

    always @(posedge i_clk) begin
        if (i_rst || i_clear) begin
            cycle_count <= 0;
        end else begin
            cycle_count <= cycle_count + 1;
        end
    end

    task load_all_row_inputs;
        begin
            state_p_terms_rows = {TOTAL_ROWS * PHYSICAL_DEGREE * DATA_WIDTH{1'b0}};
            state_n_terms_rows = {TOTAL_ROWS * PHYSICAL_DEGREE * DATA_WIDTH{1'b0}};
            coeff_p_terms_rows = {TOTAL_ROWS * PHYSICAL_DEGREE * COEFF_WIDTH{1'b0}};
            coeff_n_terms_rows = {TOTAL_ROWS * PHYSICAL_DEGREE * COEFF_WIDTH{1'b0}};

            for (row = 0; row < TOTAL_ROWS; row = row + 1) begin
                for (ti = 0; ti < PHYSICAL_DEGREE; ti = ti + 1) begin
                    if (ti < DEGREE) begin
                        src_row = w_src_row_idx_clusters[(row * DEGREE + ti) * SRC_IDX_WIDTH +: SRC_IDX_WIDTH];
                        src_cluster = src_row / ROWS_PER_CLUSTER;
                        src_local = src_row % ROWS_PER_CLUSTER;
                        state_p_terms_rows[(row * PHYSICAL_DEGREE + ti) * DATA_WIDTH +: DATA_WIDTH] =
                            current_state_p[src_row];
                        state_n_terms_rows[(row * PHYSICAL_DEGREE + ti) * DATA_WIDTH +: DATA_WIDTH] =
                            current_state_n[src_row];
                        coeff_p_terms_rows[(row * PHYSICAL_DEGREE + ti) * COEFF_WIDTH +: COEFF_WIDTH] =
                            {{(COEFF_WIDTH - TEMPLATE_BIT_WIDTH){1'b0}},
                            w_coeff_p_terms_clusters[(row * DEGREE + ti) * TEMPLATE_BIT_WIDTH +: TEMPLATE_BIT_WIDTH]};
                        coeff_n_terms_rows[(row * PHYSICAL_DEGREE + ti) * COEFF_WIDTH +: COEFF_WIDTH] =
                            {{(COEFF_WIDTH - TEMPLATE_BIT_WIDTH){1'b0}},
                            w_coeff_n_terms_clusters[(row * DEGREE + ti) * TEMPLATE_BIT_WIDTH +: TEMPLATE_BIT_WIDTH]};
                    end
                end
            end
        end
    endtask

    initial begin
        $readmemh({`PARALLEL_IN_VECTOR_DIR, "/templates.memh"}, template_mem);
        $readmemh({`PARALLEL_IN_VECTOR_DIR, "/conv_gold_state_p_iters.memh"},
            gold_state_p_mem);
        $readmemh({`PARALLEL_IN_VECTOR_DIR, "/conv_gold_state_n_iters.memh"},
            gold_state_n_mem);

        i_clk = 1'b0;
        i_rst = 1'b1;
        i_clear = 1'b0;
        i_start = 1'b0;
        template_words_clusters = {NUM_CLUSTERS * TEMPLATE_PAYLOAD_WIDTH{1'b0}};
        state_p_terms_rows = {TOTAL_ROWS * PHYSICAL_DEGREE * DATA_WIDTH{1'b0}};
        state_n_terms_rows = {TOTAL_ROWS * PHYSICAL_DEGREE * DATA_WIDTH{1'b0}};
        coeff_p_terms_rows = {TOTAL_ROWS * PHYSICAL_DEGREE * COEFF_WIDTH{1'b0}};
        coeff_n_terms_rows = {TOTAL_ROWS * PHYSICAL_DEGREE * COEFF_WIDTH{1'b0}};
        total_compute_cycles = 0;

        for (ci = 0; ci < NUM_CLUSTERS; ci = ci + 1) begin
            template_words_clusters[ci * TEMPLATE_PAYLOAD_WIDTH +: TEMPLATE_PAYLOAD_WIDTH] = template_mem[ci];
        end
        for (row = 0; row < TOTAL_ROWS; row = row + 1) begin
            current_state_p[row] = {DATA_WIDTH{1'b0}};
            current_state_n[row] = {DATA_WIDTH{1'b0}};
        end

        repeat (4) @(posedge i_clk);
        i_rst <= 1'b0;
        @(posedge i_clk);

        compute_start_cycle = cycle_count;
        for (iter_idx = 0; iter_idx < NUM_ITERS; iter_idx = iter_idx + 1) begin
            load_all_row_inputs();
            @(negedge i_clk);
            i_start = 1'b1;
            @(negedge i_clk);
            i_start = 1'b0;

            wait_count = 0;
            while (!w_done && wait_count < 128) begin
                @(posedge i_clk);
                #1;
                wait_count = wait_count + 1;
            end

            if (!w_done) begin
                $display("ERROR parallel-rows conventional timeout iter=%0d", iter_idx);
                $fatal;
            end

            for (row = 0; row < TOTAL_ROWS; row = row + 1) begin
                row_cluster = row / ROWS_PER_CLUSTER;
                row_local = row % ROWS_PER_CLUSTER;
                target_gold_idx = iter_idx * NUM_CLUSTERS + row_cluster;
                dut_p_word = w_state_p_rows[row * DATA_WIDTH +: DATA_WIDTH];
                dut_n_word = w_state_n_rows[row * DATA_WIDTH +: DATA_WIDTH];
                gold_p_word = gold_state_p_mem[target_gold_idx][row_local * DATA_WIDTH +: DATA_WIDTH];
                gold_n_word = gold_state_n_mem[target_gold_idx][row_local * DATA_WIDTH +: DATA_WIDTH];
                if ((dut_p_word !== gold_p_word) || (dut_n_word !== gold_n_word)) begin
                    $display("ERROR parallel-rows state mismatch iter=%0d row=%0d p/n=%h/%h gold=%h/%h sum=%0d",
                        iter_idx, row, dut_p_word, dut_n_word, gold_p_word, gold_n_word,
                        w_sum_rows[row * ACC_WIDTH +: ACC_WIDTH]);
                    $fatal;
                end
                current_state_p[row] = dut_p_word;
                current_state_n[row] = dut_n_word;
            end
        end
        compute_cycles = cycle_count - compute_start_cycle;
        total_compute_cycles = compute_cycles;

        $display("PASS tb_iter_parallel_in_conv_mma8_parallel_rows_top");
        $display("COUNTERS parallel_in_conv_parallel_rows rows=%0d iterations=%0d product_shift=%0d total_compute=%0d row_lanes=%0d macs_per_row=%0d",
            TOTAL_ROWS, NUM_ITERS, PRODUCT_SHIFT, total_compute_cycles, TOTAL_ROWS, PHYSICAL_DEGREE);
        $finish;
    end

endmodule
