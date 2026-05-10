`timescale 1ns / 1ps

// Two-bank row-state ping-pong storage.
//
// Bank semantics:
// - one bank is the active read bank for the current iteration;
// - the other bank is the write bank for current row-update outputs;
// - i_commit_swap flips the banks after an iteration completes.

module iter_state_ping_pong_bank #(
    parameter integer num_rows = 4,
    parameter integer data_width = 11,
    parameter integer row_idx_width = (num_rows <= 2) ? 1 : $clog2(num_rows)
) (
    input                                       i_clk,
    input                                       i_rst,
    input                                       i_commit_swap,
    input                                       i_load_state,
    input                                       i_load_bank_sel,
    input      [row_idx_width - 1 : 0]          i_load_row_idx,
    input      [data_width - 1 : 0]             i_load_state_p,
    input      [data_width - 1 : 0]             i_load_state_n,
    input      [num_rows - 1 : 0]               i_valid_rows,
    input      [num_rows * data_width - 1 : 0]  i_write_state_p_rows,
    input      [num_rows * data_width - 1 : 0]  i_write_state_n_rows,
    output                                      o_read_bank_sel,
    output     [num_rows * data_width - 1 : 0]  o_read_state_p_rows,
    output     [num_rows * data_width - 1 : 0]  o_read_state_n_rows
);

    reg r_read_bank_sel;
    reg [num_rows * data_width - 1 : 0] r_bank0_p_rows;
    reg [num_rows * data_width - 1 : 0] r_bank0_n_rows;
    reg [num_rows * data_width - 1 : 0] r_bank1_p_rows;
    reg [num_rows * data_width - 1 : 0] r_bank1_n_rows;
    integer ri;

    always @(posedge i_clk) begin
        if (i_rst) begin
            r_read_bank_sel <= 1'b0;
            r_bank0_p_rows <= {num_rows * data_width{1'b0}};
            r_bank0_n_rows <= {num_rows * data_width{1'b0}};
            r_bank1_p_rows <= {num_rows * data_width{1'b0}};
            r_bank1_n_rows <= {num_rows * data_width{1'b0}};
        end else begin
            for (ri = 0; ri < num_rows; ri = ri + 1) begin
                if (i_valid_rows[ri]) begin
                    if (r_read_bank_sel) begin
                        r_bank0_p_rows[(ri + 1) * data_width - 1 -: data_width]
                            <= i_write_state_p_rows[(ri + 1) * data_width - 1 -: data_width];
                        r_bank0_n_rows[(ri + 1) * data_width - 1 -: data_width]
                            <= i_write_state_n_rows[(ri + 1) * data_width - 1 -: data_width];
                    end else begin
                        r_bank1_p_rows[(ri + 1) * data_width - 1 -: data_width]
                            <= i_write_state_p_rows[(ri + 1) * data_width - 1 -: data_width];
                        r_bank1_n_rows[(ri + 1) * data_width - 1 -: data_width]
                            <= i_write_state_n_rows[(ri + 1) * data_width - 1 -: data_width];
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

endmodule
