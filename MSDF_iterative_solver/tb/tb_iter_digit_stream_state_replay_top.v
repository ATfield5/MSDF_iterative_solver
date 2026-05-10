`timescale 1ns / 1ps

module tb_iter_digit_stream_state_replay_top;
    localparam integer NUM_ROWS = 4;
    localparam integer DEGREE = 4;
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
    reg [DIGIT_IDX_WIDTH - 1 : 0] i_replay_digit_idx;
    reg [NUM_ROWS * DEGREE * ROW_IDX_WIDTH - 1 : 0] i_src_row_idx;

    wire o_read_bank_sel;
    wire [NUM_ROWS * DATA_WIDTH - 1 : 0] o_read_state_p_rows;
    wire [NUM_ROWS * DATA_WIDTH - 1 : 0] o_read_state_n_rows;
    wire [NUM_ROWS - 1 : 0] o_x0_p_rows;
    wire [NUM_ROWS - 1 : 0] o_x0_n_rows;
    wire [NUM_ROWS - 1 : 0] o_x1_p_rows;
    wire [NUM_ROWS - 1 : 0] o_x1_n_rows;
    wire [NUM_ROWS - 1 : 0] o_x2_p_rows;
    wire [NUM_ROWS - 1 : 0] o_x2_n_rows;
    wire [NUM_ROWS - 1 : 0] o_x3_p_rows;
    wire [NUM_ROWS - 1 : 0] o_x3_n_rows;

    reg [NUM_ROWS * DATA_WIDTH - 1 : 0] target_p;
    reg [NUM_ROWS * DATA_WIDTH - 1 : 0] target_n;
    integer di;
    integer ri;
    integer term;
    integer bit_sel;
    integer src;
    reg exp_digit_p;
    reg exp_digit_n;

    iter_digit_stream_state_replay_top #(
        .num_rows(NUM_ROWS),
        .degree(DEGREE),
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
        .i_replay_digit_idx(i_replay_digit_idx),
        .i_src_row_idx(i_src_row_idx),
        .o_read_bank_sel(o_read_bank_sel),
        .o_read_state_p_rows(o_read_state_p_rows),
        .o_read_state_n_rows(o_read_state_n_rows),
        .o_x0_p_rows(o_x0_p_rows),
        .o_x0_n_rows(o_x0_n_rows),
        .o_x1_p_rows(o_x1_p_rows),
        .o_x1_n_rows(o_x1_n_rows),
        .o_x2_p_rows(o_x2_p_rows),
        .o_x2_n_rows(o_x2_n_rows),
        .o_x3_p_rows(o_x3_p_rows),
        .o_x3_n_rows(o_x3_n_rows)
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
            i_replay_digit_idx = {DIGIT_IDX_WIDTH{1'b0}};
            i_src_row_idx = {NUM_ROWS * DEGREE * ROW_IDX_WIDTH{1'b0}};
        end
    endtask

    task pack_source_indices;
        begin
            for (ri = 0; ri < NUM_ROWS; ri = ri + 1) begin
                for (term = 0; term < DEGREE; term = term + 1) begin
                    src = (ri + term) % NUM_ROWS;
                    i_src_row_idx[((ri * DEGREE + term) + 1) * ROW_IDX_WIDTH - 1 -: ROW_IDX_WIDTH]
                        = src[ROW_IDX_WIDTH - 1 : 0];
                end
            end
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

    task check_replay_digit;
        input integer digit_idx;
        begin
            i_replay_digit_idx = digit_idx[DIGIT_IDX_WIDTH - 1 : 0];
            #1;
            bit_sel = DATA_WIDTH - 1 - digit_idx;
            for (ri = 0; ri < NUM_ROWS; ri = ri + 1) begin
                for (term = 0; term < DEGREE; term = term + 1) begin
                    src = (ri + term) % NUM_ROWS;
                    exp_digit_p = target_p[src * DATA_WIDTH + bit_sel];
                    exp_digit_n = target_n[src * DATA_WIDTH + bit_sel];
                    case (term)
                        0: begin
                            if (o_x0_p_rows[ri] !== exp_digit_p || o_x0_n_rows[ri] !== exp_digit_n) begin
                                $display("ERROR x0 replay row=%0d digit=%0d", ri, digit_idx);
                                $fatal;
                            end
                        end
                        1: begin
                            if (o_x1_p_rows[ri] !== exp_digit_p || o_x1_n_rows[ri] !== exp_digit_n) begin
                                $display("ERROR x1 replay row=%0d digit=%0d", ri, digit_idx);
                                $fatal;
                            end
                        end
                        2: begin
                            if (o_x2_p_rows[ri] !== exp_digit_p || o_x2_n_rows[ri] !== exp_digit_n) begin
                                $display("ERROR x2 replay row=%0d digit=%0d", ri, digit_idx);
                                $fatal;
                            end
                        end
                        default: begin
                            if (o_x3_p_rows[ri] !== exp_digit_p || o_x3_n_rows[ri] !== exp_digit_n) begin
                                $display("ERROR x3 replay row=%0d digit=%0d", ri, digit_idx);
                                $fatal;
                            end
                        end
                    endcase
                end
            end
        end
    endtask

    initial begin
        i_clk = 1'b0;
        i_rst = 1'b1;
        clear_inputs();
        target_p = {
            6'b100001,
            6'b010010,
            6'b001100,
            6'b111000
        };
        target_n = {
            6'b000001,
            6'b100000,
            6'b000011,
            6'b010101
        };
        pack_source_indices();

        repeat (3) @(posedge i_clk);
        i_rst <= 1'b0;

        write_digit_word(target_p, target_n);
        @(posedge i_clk);
        i_commit_swap <= 1'b1;
        @(posedge i_clk);
        i_commit_swap <= 1'b0;
        #1;
        if (o_read_state_p_rows !== target_p || o_read_state_n_rows !== target_n) begin
            $display("ERROR committed read state mismatch");
            $fatal;
        end

        for (di = 0; di < DATA_WIDTH; di = di + 1) begin
            check_replay_digit(di);
        end

        $display("PASS tb_iter_digit_stream_state_replay_top");
        $finish;
    end
endmodule
