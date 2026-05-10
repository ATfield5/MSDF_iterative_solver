`timescale 1ns / 1ps

// Convert an online-delayed solver-native output stream into fixed-width
// digit-stream state-bank writes.
//
// The solver-native row engine emits a signed-digit trace with leading online
// latency/guard digits.  The solver state must stay fixed-width across
// iterations, so this adapter skips the leading digits and forwards the next
// STATE_WIDTH digits to the state bank.  It does not reconstruct a full word.

module iter_solver_native_commit_adapter #(
    parameter integer state_width = 11,
    parameter integer skip_digits = 8,
    parameter integer count_width = (state_width + skip_digits + 2 <= 2) ? 1 : $clog2(state_width + skip_digits + 2),
    parameter integer digit_idx_width = (state_width <= 2) ? 1 : $clog2(state_width)
) (
    input                              i_clk,
    input                              i_rst,
    input                              i_clear,
    input                              i_valid,
    input                              i_digit_p,
    input                              i_digit_n,
    output reg                         o_write_valid,
    output reg [digit_idx_width-1:0]   o_write_digit_idx,
    output reg                         o_write_digit_p,
    output reg                         o_write_digit_n,
    output reg                         o_done
);

    localparam [count_width-1:0] CAPTURE_START = skip_digits;
    localparam [count_width-1:0] CAPTURE_END = skip_digits + state_width;
    localparam [count_width-1:0] CAPTURE_LAST = skip_digits + state_width - 1;

    reg [count_width-1:0] r_count;
    reg [count_width-1:0] w_capture_idx;
    reg w_in_capture_window;
    reg w_is_last_capture;

    always @(*) begin
        w_capture_idx = r_count - CAPTURE_START;
        w_in_capture_window =
            (r_count >= CAPTURE_START) &&
            (r_count < CAPTURE_END);
        w_is_last_capture =
            (r_count == CAPTURE_LAST);
    end

    always @(posedge i_clk) begin
        if (i_rst || i_clear) begin
            r_count <= {count_width{1'b0}};
            o_write_valid <= 1'b0;
            o_write_digit_idx <= {digit_idx_width{1'b0}};
            o_write_digit_p <= 1'b0;
            o_write_digit_n <= 1'b0;
            o_done <= 1'b0;
        end else begin
            o_write_valid <= 1'b0;
            o_done <= 1'b0;
            if (i_valid) begin
                if (w_in_capture_window) begin
                    o_write_valid <= 1'b1;
                    o_write_digit_idx <= w_capture_idx[digit_idx_width-1:0];
                    o_write_digit_p <= i_digit_p;
                    o_write_digit_n <= i_digit_n;
                    o_done <= w_is_last_capture;
                end
                r_count <= r_count + 1'b1;
            end
        end
    end

endmodule
