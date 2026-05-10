`timescale 1ns / 1ps

// Digit-stream ping-pong state storage.
//
// This module is the first hardware boundary for the all-digit-stream solver
// path.  Unlike iter_state_ping_pong_bank, the iteration write side does not
// accept a full row word.  It accepts one p/n digit per active row per cycle and
// writes that digit into the inactive bank.  After DATA_WIDTH digit cycles, the
// controller can commit-swap the banks and replay the newly written state in
// the next iteration.
//
// The storage is still physically a row word because replay needs random digit
// access by digit_idx.  The important contract change is at the commit boundary:
// row-update results are committed as a digit stream, not as a reconstructed
// full binary/rail word.

module iter_digit_stream_state_ping_pong_bank #(
    parameter integer num_rows = 4,
    parameter integer data_width = 11,
    parameter integer msb_first = 1,
    parameter integer row_idx_width = (num_rows <= 2) ? 1 : $clog2(num_rows),
    parameter integer digit_idx_width = (data_width <= 2) ? 1 : $clog2(data_width)
) (
    input                                       i_clk,
    input                                       i_rst,
    input                                       i_commit_swap,
    input                                       i_clear_write_bank,

    // Host/debug full-word load path.  This keeps binary/rail I/O bring-up
    // simple while the solver datapath moves to digit-stream commit.
    input                                       i_load_state,
    input                                       i_load_bank_sel,
    input      [row_idx_width - 1 : 0]          i_load_row_idx,
    input      [data_width - 1 : 0]             i_load_state_p,
    input      [data_width - 1 : 0]             i_load_state_n,

    // Iteration digit-stream write path into the inactive bank.
    input      [num_rows - 1 : 0]               i_write_digit_valid_rows,
    input      [digit_idx_width - 1 : 0]        i_write_digit_idx,
    input      [num_rows - 1 : 0]               i_write_digit_p_rows,
    input      [num_rows - 1 : 0]               i_write_digit_n_rows,

    output                                      o_read_bank_sel,
    output     [num_rows * data_width - 1 : 0]  o_read_state_p_rows,
    output     [num_rows * data_width - 1 : 0]  o_read_state_n_rows,
    output     [num_rows * data_width - 1 : 0]  o_write_state_p_rows,
    output     [num_rows * data_width - 1 : 0]  o_write_state_n_rows
);

    reg r_read_bank_sel;
    reg [num_rows * data_width - 1 : 0] r_bank0_p_rows;
    reg [num_rows * data_width - 1 : 0] r_bank0_n_rows;
    reg [num_rows * data_width - 1 : 0] r_bank1_p_rows;
    reg [num_rows * data_width - 1 : 0] r_bank1_n_rows;

    integer ri;
    integer bit_sel;

    always @(*) begin
        bit_sel = msb_first ? (data_width - 1 - i_write_digit_idx) : i_write_digit_idx;
    end

    always @(posedge i_clk) begin
        if (i_rst) begin
            r_read_bank_sel <= 1'b0;
            r_bank0_p_rows <= {num_rows * data_width{1'b0}};
            r_bank0_n_rows <= {num_rows * data_width{1'b0}};
            r_bank1_p_rows <= {num_rows * data_width{1'b0}};
            r_bank1_n_rows <= {num_rows * data_width{1'b0}};
        end else begin
            if (i_clear_write_bank) begin
                if (r_read_bank_sel) begin
                    r_bank0_p_rows <= {num_rows * data_width{1'b0}};
                    r_bank0_n_rows <= {num_rows * data_width{1'b0}};
                end else begin
                    r_bank1_p_rows <= {num_rows * data_width{1'b0}};
                    r_bank1_n_rows <= {num_rows * data_width{1'b0}};
                end
            end

            for (ri = 0; ri < num_rows; ri = ri + 1) begin
                if (i_write_digit_valid_rows[ri]) begin
                    if (r_read_bank_sel) begin
                        r_bank0_p_rows[ri * data_width + bit_sel] <= i_write_digit_p_rows[ri];
                        r_bank0_n_rows[ri * data_width + bit_sel] <= i_write_digit_n_rows[ri];
                    end else begin
                        r_bank1_p_rows[ri * data_width + bit_sel] <= i_write_digit_p_rows[ri];
                        r_bank1_n_rows[ri * data_width + bit_sel] <= i_write_digit_n_rows[ri];
                    end
                end
            end

            if (i_load_state) begin
                if (i_load_bank_sel) begin
                    r_bank1_p_rows[(i_load_row_idx + 1) * data_width - 1 -: data_width]
                        <= i_load_state_p;
                    r_bank1_n_rows[(i_load_row_idx + 1) * data_width - 1 -: data_width]
                        <= i_load_state_n;
                end else begin
                    r_bank0_p_rows[(i_load_row_idx + 1) * data_width - 1 -: data_width]
                        <= i_load_state_p;
                    r_bank0_n_rows[(i_load_row_idx + 1) * data_width - 1 -: data_width]
                        <= i_load_state_n;
                end
            end

            if (i_commit_swap) begin
                r_read_bank_sel <= ~r_read_bank_sel;
            end
        end
    end

    assign o_read_bank_sel = r_read_bank_sel;
    assign o_read_state_p_rows = r_read_bank_sel ? r_bank1_p_rows : r_bank0_p_rows;
    assign o_read_state_n_rows = r_read_bank_sel ? r_bank1_n_rows : r_bank0_n_rows;
    assign o_write_state_p_rows = r_read_bank_sel ? r_bank0_p_rows : r_bank1_p_rows;
    assign o_write_state_n_rows = r_read_bank_sel ? r_bank0_n_rows : r_bank1_n_rows;

endmodule
