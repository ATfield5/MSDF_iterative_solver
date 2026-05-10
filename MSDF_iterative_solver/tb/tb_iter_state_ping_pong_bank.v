`timescale 1ns / 1ps

module tb_iter_state_ping_pong_bank;
    localparam integer NUM_ROWS = 4;
    localparam integer DATA_WIDTH = 11;

    reg i_clk;
    reg i_rst;
    reg i_commit_swap;
    reg i_load_state;
    reg i_load_bank_sel;
    reg [1 : 0] i_load_row_idx;
    reg [DATA_WIDTH - 1 : 0] i_load_state_p;
    reg [DATA_WIDTH - 1 : 0] i_load_state_n;
    reg [NUM_ROWS - 1 : 0] i_valid_rows;
    reg [NUM_ROWS * DATA_WIDTH - 1 : 0] i_write_state_p_rows;
    reg [NUM_ROWS * DATA_WIDTH - 1 : 0] i_write_state_n_rows;
    wire o_read_bank_sel;
    wire [NUM_ROWS * DATA_WIDTH - 1 : 0] o_read_state_p_rows;
    wire [NUM_ROWS * DATA_WIDTH - 1 : 0] o_read_state_n_rows;

    iter_state_ping_pong_bank #(
        .num_rows(NUM_ROWS),
        .data_width(DATA_WIDTH)
    ) dut (
        .i_clk(i_clk),
        .i_rst(i_rst),
        .i_commit_swap(i_commit_swap),
        .i_load_state(i_load_state),
        .i_load_bank_sel(i_load_bank_sel),
        .i_load_row_idx(i_load_row_idx),
        .i_load_state_p(i_load_state_p),
        .i_load_state_n(i_load_state_n),
        .i_valid_rows(i_valid_rows),
        .i_write_state_p_rows(i_write_state_p_rows),
        .i_write_state_n_rows(i_write_state_n_rows),
        .o_read_bank_sel(o_read_bank_sel),
        .o_read_state_p_rows(o_read_state_p_rows),
        .o_read_state_n_rows(o_read_state_n_rows)
    );

    always #5 i_clk = ~i_clk;

    initial begin
        i_clk = 1'b0;
        i_rst = 1'b1;
        i_commit_swap = 1'b0;
        i_load_state = 1'b0;
        i_load_bank_sel = 1'b0;
        i_load_row_idx = 2'd0;
        i_load_state_p = 0;
        i_load_state_n = 0;
        i_valid_rows = 4'b0000;
        i_write_state_p_rows = 0;
        i_write_state_n_rows = 0;

        repeat (2) @(posedge i_clk);
        i_rst <= 1'b0;

        // Runtime-load a row in the active read bank before normal iteration writes.
        @(posedge i_clk);
        i_load_state <= 1'b1;
        i_load_bank_sel <= 1'b0;
        i_load_row_idx <= 2'd2;
        i_load_state_p <= 11'd21;
        i_load_state_n <= 11'd1;
        @(posedge i_clk);
        i_load_state <= 1'b0;
        i_load_state_p <= 0;
        i_load_state_n <= 0;
        #1;
        if (o_read_state_p_rows[3 * DATA_WIDTH - 1 -: DATA_WIDTH] !== 11'd21 ||
            o_read_state_n_rows[3 * DATA_WIDTH - 1 -: DATA_WIDTH] !== 11'd1) begin
            $display("ERROR pingpong runtime load mismatch");
            $fatal;
        end

        // Write first state set into write bank while read bank remains zero.
        @(posedge i_clk);
        i_valid_rows <= 4'b1111;
        i_write_state_p_rows <= {
            11'd4, 11'd3, 11'd2, 11'd1
        };
        i_write_state_n_rows <= 0;
        @(posedge i_clk);
        i_valid_rows <= 4'b0000;
        i_write_state_p_rows <= 0;
        if (o_read_bank_sel !== 1'b0 ||
            o_read_state_p_rows !== {11'd0, 11'd21, 11'd0, 11'd0} ||
            o_read_state_n_rows !== {11'd0, 11'd1, 11'd0, 11'd0}) begin
            $display("ERROR pingpong read bank0 unexpected before first commit");
            $fatal;
        end

        // Commit and read the first written bank.
        @(posedge i_clk);
        i_commit_swap <= 1'b1;
        @(posedge i_clk);
        i_commit_swap <= 1'b0;
        #1;
        if (o_read_bank_sel !== 1'b1 || o_read_state_p_rows !== {11'd4, 11'd3, 11'd2, 11'd1}) begin
            $display("ERROR pingpong first commit mismatch");
            $fatal;
        end

        // Write second state into the other bank.
        @(posedge i_clk);
        i_valid_rows <= 4'b1111;
        i_write_state_p_rows <= {
            11'd8, 11'd7, 11'd6, 11'd5
        };
        @(posedge i_clk);
        i_valid_rows <= 4'b0000;
        i_write_state_p_rows <= 0;
        #1;
        if (o_read_state_p_rows !== {11'd4, 11'd3, 11'd2, 11'd1}) begin
            $display("ERROR pingpong read bank changed before second commit");
            $fatal;
        end

        // Commit and read the second written bank.
        @(posedge i_clk);
        i_commit_swap <= 1'b1;
        @(posedge i_clk);
        i_commit_swap <= 1'b0;
        #1;
        if (o_read_bank_sel !== 1'b0 || o_read_state_p_rows !== {11'd8, 11'd7, 11'd6, 11'd5}) begin
            $display("ERROR pingpong second commit mismatch");
            $fatal;
        end

        $display("PASS tb_iter_state_ping_pong_bank");
        $finish;
    end
endmodule
