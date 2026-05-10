`timescale 1ns / 1ps

module tb_iter_digit_stream_delta_bound;
    localparam integer DATA_WIDTH = 5;
    localparam integer BOUND_WIDTH = 8;
    localparam integer ACC_WIDTH = 16;
    localparam integer DIGIT_IDX_WIDTH = $clog2(DATA_WIDTH);

    reg i_clk;
    reg i_rst;
    reg i_start;
    reg i_valid;
    reg [DIGIT_IDX_WIDTH-1:0] i_digit_idx;
    reg i_new_digit_p;
    reg i_new_digit_n;
    reg i_old_digit_p;
    reg i_old_digit_n;
    wire o_valid;
    wire signed [ACC_WIDTH-1:0] o_prefix_delta;
    wire [BOUND_WIDTH-1:0] o_abs_upper;
    wire o_final;

    reg [DATA_WIDTH-1:0] new_word;
    reg [DATA_WIDTH-1:0] old_word;
    integer di;
    integer bit_sel;

    iter_digit_stream_delta_bound #(
        .data_width(DATA_WIDTH),
        .bound_width(BOUND_WIDTH),
        .acc_width(ACC_WIDTH),
        .digit_idx_width(DIGIT_IDX_WIDTH)
    ) dut (
        .i_clk(i_clk),
        .i_rst(i_rst),
        .i_start(i_start),
        .i_valid(i_valid),
        .i_digit_idx(i_digit_idx),
        .i_new_digit_p(i_new_digit_p),
        .i_new_digit_n(i_new_digit_n),
        .i_old_digit_p(i_old_digit_p),
        .i_old_digit_n(i_old_digit_n),
        .o_valid(o_valid),
        .o_prefix_delta(o_prefix_delta),
        .o_abs_upper(o_abs_upper),
        .o_final(o_final)
    );

    always #5 i_clk = ~i_clk;

    initial begin
        i_clk = 1'b0;
        i_rst = 1'b1;
        i_start = 1'b0;
        i_valid = 1'b0;
        i_digit_idx = {DIGIT_IDX_WIDTH{1'b0}};
        i_new_digit_p = 1'b0;
        i_new_digit_n = 1'b0;
        i_old_digit_p = 1'b0;
        i_old_digit_n = 1'b0;
        new_word = 5'b00101; // +5
        old_word = 5'b00010; // +2

        repeat (2) @(negedge i_clk);
        i_rst = 1'b0;

        for (di = 0; di < DATA_WIDTH; di = di + 1) begin
            bit_sel = DATA_WIDTH - 1 - di;
            i_start = (di == 0);
            i_valid = 1'b1;
            i_digit_idx = di[DIGIT_IDX_WIDTH-1:0];
            i_new_digit_p = new_word[bit_sel];
            i_new_digit_n = 1'b0;
            i_old_digit_p = old_word[bit_sel];
            i_old_digit_n = 1'b0;
            @(posedge i_clk);
            #1;
            if (!o_valid) begin
                $display("ERROR delta bound missing valid at digit %0d", di);
                $fatal;
            end
            if (o_abs_upper < 8'd3) begin
                $display("ERROR delta bound not conservative at digit %0d got %0d", di, o_abs_upper);
                $fatal;
            end
        end

        if (!o_final || o_prefix_delta !== 16'sd3 || o_abs_upper !== 8'd3) begin
            $display("ERROR final delta got final=%0d prefix=%0d abs=%0d", o_final, o_prefix_delta, o_abs_upper);
            $fatal;
        end

        i_valid = 1'b0;
        i_start = 1'b0;
        $display("PASS tb_iter_digit_stream_delta_bound");
        $finish;
    end
endmodule
