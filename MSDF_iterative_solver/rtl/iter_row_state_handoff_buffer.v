`timescale 1ns / 1ps

// Minimal row-state handoff buffer.
//
// This buffer stores row-level affine-update outputs and exposes them as the
// next iteration's x_old state. It does not reconstruct a full online replay
// stream yet; it only closes the first real state-transfer boundary needed by
// the delta/certification path.

module iter_row_state_handoff_buffer #(
    parameter integer num_rows = 4,
    parameter integer data_width = 11
) (
    input                                       i_clk,
    input                                       i_rst,
    input                                       i_clear,
    input      [num_rows - 1 : 0]               i_valid_rows,
    input      [num_rows * data_width - 1 : 0]  i_state_p_rows,
    input      [num_rows * data_width - 1 : 0]  i_state_n_rows,
    output reg [num_rows * data_width - 1 : 0]  o_state_p_rows,
    output reg [num_rows * data_width - 1 : 0]  o_state_n_rows
);

    integer ri;
    always @(posedge i_clk) begin
        if (i_rst || i_clear) begin
            o_state_p_rows <= {num_rows * data_width{1'b0}};
            o_state_n_rows <= {num_rows * data_width{1'b0}};
        end else begin
            for (ri = 0; ri < num_rows; ri = ri + 1) begin
                if (i_valid_rows[ri]) begin
                    o_state_p_rows[(ri + 1) * data_width - 1 -: data_width]
                        <= i_state_p_rows[(ri + 1) * data_width - 1 -: data_width];
                    o_state_n_rows[(ri + 1) * data_width - 1 -: data_width]
                        <= i_state_n_rows[(ri + 1) * data_width - 1 -: data_width];
                end
            end
        end
    end

endmodule
