`timescale 1ns / 1ps

module tb_iter_digit_stream_state_ping_pong_bank;
    localparam integer NUM_ROWS = 4;
    localparam integer DATA_WIDTH = 6;
    localparam integer ROW_IDX_WIDTH = 2;
    localparam integer DIGIT_IDX_WIDTH = 3;

    reg i_clk;
    reg i_rst;
    reg i_commit_swap;
    reg i_clear_write_bank;
    reg i_load_state;
    reg i_load_bank_sel;
    reg [ROW_IDX_WIDTH - 1 : 0] i_load_row_idx;
    reg [DATA_WIDTH - 1 : 0] i_load_state_p;
    reg [DATA_WIDTH - 1 : 0] i_load_state_n;
    reg [NUM_ROWS - 1 : 0] i_write_digit_valid_rows;
    reg [DIGIT_IDX_WIDTH - 1 : 0] i_write_digit_idx;
    reg [NUM_ROWS - 1 : 0] i_write_digit_p_rows;
    reg [NUM_ROWS - 1 : 0] i_write_digit_n_rows;

    wire o_read_bank_sel;
    wire [NUM_ROWS * DATA_WIDTH - 1 : 0] o_read_state_p_rows;
    wire [NUM_ROWS * DATA_WIDTH - 1 : 0] o_read_state_n_rows;
    wire [NUM_ROWS * DATA_WIDTH - 1 : 0] o_write_state_p_rows;
    wire [NUM_ROWS * DATA_WIDTH - 1 : 0] o_write_state_n_rows;

    reg [NUM_ROWS * DATA_WIDTH - 1 : 0] target0_p;
    reg [NUM_ROWS * DATA_WIDTH - 1 : 0] target0_n;
    reg [NUM_ROWS * DATA_WIDTH - 1 : 0] target1_p;
    reg [NUM_ROWS * DATA_WIDTH - 1 : 0] target1_n;
    integer di;
    integer ri;
    integer bit_sel;

    iter_digit_stream_state_ping_pong_bank #(
        .num_rows(NUM_ROWS),
        .data_width(DATA_WIDTH),
        .msb_first(1),
        .row_idx_width(ROW_IDX_WIDTH),
        .digit_idx_width(DIGIT_IDX_WIDTH)
    ) dut (
        .i_clk(i_clk),
        .i_rst(i_rst),
        .i_commit_swap(i_commit_swap),
        .i_clear_write_bank(i_clear_write_bank),
        .i_load_state(i_load_state),
        .i_load_bank_sel(i_load_bank_sel),
        .i_load_row_idx(i_load_row_idx),
        .i_load_state_p(i_load_state_p),
        .i_load_state_n(i_load_state_n),
        .i_write_digit_valid_rows(i_write_digit_valid_rows),
        .i_write_digit_idx(i_write_digit_idx),
        .i_write_digit_p_rows(i_write_digit_p_rows),
        .i_write_digit_n_rows(i_write_digit_n_rows),
        .o_read_bank_sel(o_read_bank_sel),
        .o_read_state_p_rows(o_read_state_p_rows),
        .o_read_state_n_rows(o_read_state_n_rows),
        .o_write_state_p_rows(o_write_state_p_rows),
        .o_write_state_n_rows(o_write_state_n_rows)
    );

    always #5 i_clk = ~i_clk;

    task clear_inputs;
        begin
            i_commit_swap = 1'b0;
            i_clear_write_bank = 1'b0;
            i_load_state = 1'b0;
            i_load_bank_sel = 1'b0;
            i_load_row_idx = {ROW_IDX_WIDTH{1'b0}};
            i_load_state_p = {DATA_WIDTH{1'b0}};
            i_load_state_n = {DATA_WIDTH{1'b0}};
            i_write_digit_valid_rows = {NUM_ROWS{1'b0}};
            i_write_digit_idx = {DIGIT_IDX_WIDTH{1'b0}};
            i_write_digit_p_rows = {NUM_ROWS{1'b0}};
            i_write_digit_n_rows = {NUM_ROWS{1'b0}};
        end
    endtask

    task load_row;
        input integer row_idx;
        input [DATA_WIDTH - 1 : 0] p_word;
        input [DATA_WIDTH - 1 : 0] n_word;
        begin
            @(posedge i_clk);
            i_load_state <= 1'b1;
            i_load_bank_sel <= 1'b0;
            i_load_row_idx <= row_idx[ROW_IDX_WIDTH - 1 : 0];
            i_load_state_p <= p_word;
            i_load_state_n <= n_word;
            @(posedge i_clk);
            i_load_state <= 1'b0;
            i_load_state_p <= {DATA_WIDTH{1'b0}};
            i_load_state_n <= {DATA_WIDTH{1'b0}};
        end
    endtask

    task write_digit_word;
        input [NUM_ROWS * DATA_WIDTH - 1 : 0] p_rows;
        input [NUM_ROWS * DATA_WIDTH - 1 : 0] n_rows;
        begin
            @(posedge i_clk);
            i_clear_write_bank <= 1'b1;
            @(posedge i_clk);
            i_clear_write_bank <= 1'b0;

            for (di = 0; di < DATA_WIDTH; di = di + 1) begin
                bit_sel = DATA_WIDTH - 1 - di;
                i_write_digit_idx <= di[DIGIT_IDX_WIDTH - 1 : 0];
                i_write_digit_valid_rows <= {NUM_ROWS{1'b1}};
                for (ri = 0; ri < NUM_ROWS; ri = ri + 1) begin
                    i_write_digit_p_rows[ri] <= p_rows[ri * DATA_WIDTH + bit_sel];
                    i_write_digit_n_rows[ri] <= n_rows[ri * DATA_WIDTH + bit_sel];
                end
                @(posedge i_clk);
            end

            i_write_digit_valid_rows <= {NUM_ROWS{1'b0}};
            i_write_digit_p_rows <= {NUM_ROWS{1'b0}};
            i_write_digit_n_rows <= {NUM_ROWS{1'b0}};
        end
    endtask

    task commit_and_check;
        input [NUM_ROWS * DATA_WIDTH - 1 : 0] exp_p;
        input [NUM_ROWS * DATA_WIDTH - 1 : 0] exp_n;
        begin
            @(posedge i_clk);
            i_commit_swap <= 1'b1;
            @(posedge i_clk);
            i_commit_swap <= 1'b0;
            #1;
            if (o_read_state_p_rows !== exp_p || o_read_state_n_rows !== exp_n) begin
                $display("ERROR digit-stream bank read mismatch");
                $display("  got p=%b n=%b", o_read_state_p_rows, o_read_state_n_rows);
                $display("  exp p=%b n=%b", exp_p, exp_n);
                $fatal;
            end
        end
    endtask

    initial begin
        i_clk = 1'b0;
        i_rst = 1'b1;
        clear_inputs();
        target0_p = {
            6'b000101,
            6'b111000,
            6'b001100,
            6'b101010
        };
        target0_n = {
            6'b000000,
            6'b000111,
            6'b010101,
            6'b000001
        };
        target1_p = {
            6'b010101,
            6'b001001,
            6'b100000,
            6'b000011
        };
        target1_n = {
            6'b000010,
            6'b010010,
            6'b000001,
            6'b111100
        };

        repeat (3) @(posedge i_clk);
        i_rst <= 1'b0;

        load_row(0, 6'b000001, 6'b000000);
        load_row(1, 6'b000010, 6'b000000);
        load_row(2, 6'b000011, 6'b000000);
        load_row(3, 6'b000100, 6'b000000);
        #1;
        if (o_read_state_p_rows !== {6'b000100, 6'b000011, 6'b000010, 6'b000001}) begin
            $display("ERROR host load path mismatch");
            $fatal;
        end

        write_digit_word(target0_p, target0_n);
        commit_and_check(target0_p, target0_n);

        write_digit_word(target1_p, target1_n);
        commit_and_check(target1_p, target1_n);

        $display("PASS tb_iter_digit_stream_state_ping_pong_bank");
        $finish;
    end
endmodule
