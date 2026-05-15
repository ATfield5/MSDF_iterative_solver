`timescale 1ns / 1ps

module tb_iter_pagerank_online_mma4_frac_stage_cluster;
    localparam integer num_rows = 4;
    localparam integer degree = 4;
    localparam integer bit_width = 6;
    localparam integer data_width = bit_width + 3;
    localparam integer bias_width = bit_width + 2;
    localparam integer digit_idx_width = $clog2(data_width);

    reg clk = 1'b0;
    reg rst = 1'b1;
    reg clear = 1'b0;
    reg start = 1'b0;
    reg valid_digit = 1'b0;
    reg [digit_idx_width - 1 : 0] digit_idx = {digit_idx_width{1'b0}};
    reg [num_rows * degree - 1 : 0] state_p_terms_rows = {num_rows * degree{1'b0}};
    reg [num_rows * degree - 1 : 0] state_n_terms_rows = {num_rows * degree{1'b0}};
    reg [num_rows * degree * bit_width - 1 : 0] coeff_p_terms_rows = {num_rows * degree * bit_width{1'b0}};
    reg [num_rows * degree * bit_width - 1 : 0] coeff_n_terms_rows = {num_rows * degree * bit_width{1'b0}};
    reg [num_rows * bias_width - 1 : 0] bias_p_rows = {num_rows * bias_width{1'b0}};
    reg [num_rows * bias_width - 1 : 0] bias_n_rows = {num_rows * bias_width{1'b0}};

    wire [num_rows - 1 : 0] ref_valid_rows;
    wire [num_rows * digit_idx_width - 1 : 0] ref_digit_idx_rows;
    wire [num_rows - 1 : 0] ref_digit_p_rows;
    wire [num_rows - 1 : 0] ref_digit_n_rows;
    wire [num_rows - 1 : 0] ref_done_rows;
    wire ref_busy;

    wire [num_rows - 1 : 0] dut_valid_rows;
    wire [num_rows * digit_idx_width - 1 : 0] dut_digit_idx_rows;
    wire [num_rows - 1 : 0] dut_digit_p_rows;
    wire [num_rows - 1 : 0] dut_digit_n_rows;
    wire [num_rows - 1 : 0] dut_done_rows;
    wire dut_busy;

    integer cycle;
    integer d;
    integer r;
    integer t;
    integer errors;
    integer ref_count;
    integer dut_count;

    always #5 clk = ~clk;

    iter_prior_online_mma8_stream_stage_cluster #(
        .num_rows(num_rows),
        .degree(degree),
        .bit_width(bit_width),
        .data_width(data_width),
        .bias_width(bias_width),
        .digit_idx_width(digit_idx_width)
    ) ref_stage (
        .i_clk(clk),
        .i_rst(rst),
        .i_clear(clear),
        .i_start(start),
        .i_valid_digit(valid_digit),
        .i_digit_idx(digit_idx),
        .i_state_digit_p_terms_rows(state_p_terms_rows),
        .i_state_digit_n_terms_rows(state_n_terms_rows),
        .i_coeff_p_terms_rows(coeff_p_terms_rows),
        .i_coeff_n_terms_rows(coeff_n_terms_rows),
        .i_bias_p_rows(bias_p_rows),
        .i_bias_n_rows(bias_n_rows),
        .o_commit_valid_rows(ref_valid_rows),
        .o_commit_digit_idx_rows(ref_digit_idx_rows),
        .o_commit_digit_p_rows(ref_digit_p_rows),
        .o_commit_digit_n_rows(ref_digit_n_rows),
        .o_commit_done_rows(ref_done_rows),
        .o_busy(ref_busy)
    );

    iter_pagerank_online_mma4_frac_stage_cluster #(
        .num_rows(num_rows),
        .degree(degree),
        .bit_width(bit_width),
        .data_width(data_width),
        .bias_width(bias_width),
        .digit_idx_width(digit_idx_width)
    ) dut_stage (
        .i_clk(clk),
        .i_rst(rst),
        .i_clear(clear),
        .i_start(start),
        .i_valid_digit(valid_digit),
        .i_digit_idx(digit_idx),
        .i_state_digit_p_terms_rows(state_p_terms_rows),
        .i_state_digit_n_terms_rows(state_n_terms_rows),
        .i_coeff_p_terms_rows(coeff_p_terms_rows),
        .i_coeff_n_terms_rows(coeff_n_terms_rows),
        .i_bias_p_rows(bias_p_rows),
        .i_bias_n_rows(bias_n_rows),
        .o_commit_valid_rows(dut_valid_rows),
        .o_commit_digit_idx_rows(dut_digit_idx_rows),
        .o_commit_digit_p_rows(dut_digit_p_rows),
        .o_commit_digit_n_rows(dut_digit_n_rows),
        .o_commit_done_rows(dut_done_rows),
        .o_busy(dut_busy)
    );

    task drive_digit;
        input integer idx;
        begin
            digit_idx = idx[digit_idx_width - 1 : 0];
            for (r = 0; r < num_rows; r = r + 1) begin
                for (t = 0; t < degree; t = t + 1) begin
                    state_p_terms_rows[r * degree + t] = ((idx + r + t) % 3) == 0;
                    state_n_terms_rows[r * degree + t] = ((idx + r + t) % 7) == 0;
                end
            end
        end
    endtask

    initial begin
        errors = 0;
        ref_count = 0;
        dut_count = 0;
        for (r = 0; r < num_rows; r = r + 1) begin
            bias_p_rows[r * bias_width +: bias_width] = 7'b0010101 + r;
            bias_n_rows[r * bias_width +: bias_width] = 7'b0000010;
            for (t = 0; t < degree; t = t + 1) begin
                coeff_p_terms_rows[(r * degree + t) * bit_width +: bit_width] =
                    6'b000101 + r + t;
                coeff_n_terms_rows[(r * degree + t) * bit_width +: bit_width] =
                    (t == 2) ? 6'b000001 : 6'b000000;
            end
        end

        repeat (4) @(posedge clk);
        rst = 1'b0;
        @(posedge clk);
        start = 1'b1;
        valid_digit = 1'b1;
        drive_digit(0);
        @(posedge clk);
        start = 1'b0;
        for (d = 1; d < data_width; d = d + 1) begin
            drive_digit(d);
            @(posedge clk);
        end
        valid_digit = 1'b0;

        for (cycle = 0; cycle < 80; cycle = cycle + 1) begin
            @(posedge clk);
        end

        if (ref_count != data_width || dut_count != data_width) begin
            $display("COUNT_MISMATCH ref=%0d dut=%0d expected=%0d", ref_count, dut_count, data_width);
            errors = errors + 1;
        end

        if (errors == 0) begin
            $display("PASS tb_iter_pagerank_online_mma4_frac_stage_cluster ref_count=%0d dut_count=%0d", ref_count, dut_count);
            $finish;
        end else begin
            $display("FAIL tb_iter_pagerank_online_mma4_frac_stage_cluster errors=%0d", errors);
            $finish(1);
        end
    end

    always @(posedge clk) begin
        if (!rst) begin
            if (ref_valid_rows[0]) begin
                ref_count <= ref_count + 1;
            end
            if (dut_valid_rows[0]) begin
                dut_count <= dut_count + 1;
            end
            if (ref_valid_rows !== dut_valid_rows) begin
                $display("VALID_MISMATCH ref=%b dut=%b", ref_valid_rows, dut_valid_rows);
                errors <= errors + 1;
            end
            if (ref_valid_rows[0] && dut_valid_rows[0]) begin
                if (ref_digit_idx_rows !== dut_digit_idx_rows ||
                    ref_digit_p_rows !== dut_digit_p_rows ||
                    ref_digit_n_rows !== dut_digit_n_rows ||
                    ref_done_rows !== dut_done_rows) begin
                    $display("DATA_MISMATCH ref_idx=%h dut_idx=%h ref_p=%b dut_p=%b ref_n=%b dut_n=%b ref_done=%b dut_done=%b",
                        ref_digit_idx_rows, dut_digit_idx_rows,
                        ref_digit_p_rows, dut_digit_p_rows,
                        ref_digit_n_rows, dut_digit_n_rows,
                        ref_done_rows, dut_done_rows);
                    errors <= errors + 1;
                end
            end
        end
    end

endmodule
