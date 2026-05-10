`timescale 1ns / 1ps

module tb_iter_fixed_degree_state_replay;
    localparam integer NUM_ROWS = 4;
    localparam integer DEGREE = 4;
    localparam integer DATA_WIDTH = 6;
    localparam integer ROW_IDX_WIDTH = 2;

    reg [NUM_ROWS * DATA_WIDTH - 1 : 0] i_state_p_rows;
    reg [NUM_ROWS * DATA_WIDTH - 1 : 0] i_state_n_rows;
    reg [$clog2(DATA_WIDTH) - 1 : 0] i_digit_idx;
    reg [NUM_ROWS * DEGREE * ROW_IDX_WIDTH - 1 : 0] i_src_row_idx;
    wire [NUM_ROWS - 1 : 0] o_x0_p_rows, o_x0_n_rows;
    wire [NUM_ROWS - 1 : 0] o_x1_p_rows, o_x1_n_rows;
    wire [NUM_ROWS - 1 : 0] o_x2_p_rows, o_x2_n_rows;
    wire [NUM_ROWS - 1 : 0] o_x3_p_rows, o_x3_n_rows;

    iter_fixed_degree_state_replay #(
        .num_rows(NUM_ROWS),
        .degree(DEGREE),
        .data_width(DATA_WIDTH),
        .msb_first(1'b1),
        .row_idx_width(ROW_IDX_WIDTH)
    ) dut (
        .i_state_p_rows(i_state_p_rows),
        .i_state_n_rows(i_state_n_rows),
        .i_digit_idx(i_digit_idx),
        .i_src_row_idx(i_src_row_idx),
        .o_x0_p_rows(o_x0_p_rows),
        .o_x0_n_rows(o_x0_n_rows),
        .o_x1_p_rows(o_x1_p_rows),
        .o_x1_n_rows(o_x1_n_rows),
        .o_x2_p_rows(o_x2_p_rows),
        .o_x2_n_rows(o_x2_n_rows),
        .o_x3_p_rows(o_x3_p_rows),
        .o_x3_n_rows(o_x3_n_rows)
    );

    initial begin
        // row0: p=101100, n=000000
        // row1: p=010101, n=000000
        // row2: p=001111, n=100000
        // row3: p=000000, n=110011
        i_state_p_rows = {
            6'b000000,
            6'b001111,
            6'b010101,
            6'b101100
        };
        i_state_n_rows = {
            6'b110011,
            6'b100000,
            6'b000000,
            6'b000000
        };

        // dst row0 -> src [0,1,2,3]
        // dst row1 -> src [3,2,1,0]
        // dst row2 -> src [1,1,1,1]
        // dst row3 -> src [2,3,0,1]
        i_src_row_idx = {
            2'd1, 2'd0, 2'd3, 2'd2,
            2'd1, 2'd1, 2'd1, 2'd1,
            2'd0, 2'd1, 2'd2, 2'd3,
            2'd3, 2'd2, 2'd1, 2'd0
        };

        // MSB slice
        i_digit_idx = 0;
        #1;
        if (o_x0_p_rows !== 4'b0001 || o_x0_n_rows !== 4'b1010 ||
            o_x1_p_rows !== 4'b0000 || o_x1_n_rows !== 4'b1010 ||
            o_x2_p_rows !== 4'b1000 || o_x2_n_rows !== 4'b0001 ||
            o_x3_p_rows !== 4'b0010 || o_x3_n_rows !== 4'b0001) begin
            $display("ERROR tb_iter_fixed_degree_state_replay msb slice mismatch");
            $fatal;
        end

        // LSB slice
        i_digit_idx = DATA_WIDTH - 1;
        #1;
        if (o_x0_p_rows !== 4'b1100 || o_x0_n_rows !== 4'b0010 ||
            o_x1_p_rows !== 4'b0111 || o_x1_n_rows !== 4'b1000 ||
            o_x2_p_rows !== 4'b0111 || o_x2_n_rows !== 4'b0000 ||
            o_x3_p_rows !== 4'b1100 || o_x3_n_rows !== 4'b0001) begin
            $display("ERROR tb_iter_fixed_degree_state_replay lsb slice mismatch");
            $fatal;
        end

        $display("PASS tb_iter_fixed_degree_state_replay");
        $finish;
    end
endmodule
