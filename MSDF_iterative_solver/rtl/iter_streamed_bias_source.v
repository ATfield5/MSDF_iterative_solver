`timescale 1ns / 1ps

// MSB-first bias digit source.
//
// The final solver-native row engine must not inject a full bias rail word on
// every digit cycle.  This module exposes the bias as a digit stream aligned to
// the solver state word.  If the bias word is narrower than the state stream,
// the missing more-significant positions are zero-padded because p/n rails are
// magnitude rails in the current fixed-point contract.

module iter_streamed_bias_source #(
    parameter integer bias_width = 10,
    parameter integer stream_width = 11,
    parameter integer msb_first = 1,
    parameter integer digit_idx_width = (stream_width <= 2) ? 1 : $clog2(stream_width)
) (
    input                              i_valid,
    input      [digit_idx_width-1:0]   i_digit_idx,
    input      [bias_width-1:0]        i_bias_p,
    input      [bias_width-1:0]        i_bias_n,
    output reg                         o_valid,
    output reg                         o_bias_digit_p,
    output reg                         o_bias_digit_n
);

    integer bit_sel;

    always @(*) begin
        bit_sel = msb_first ? (stream_width - 1 - i_digit_idx) : i_digit_idx;
        o_valid = i_valid;
        if (i_valid && bit_sel >= 0 && bit_sel < bias_width) begin
            o_bias_digit_p = i_bias_p[bit_sel];
            o_bias_digit_n = i_bias_n[bit_sel];
        end else begin
            o_bias_digit_p = 1'b0;
            o_bias_digit_n = 1'b0;
        end
    end

endmodule
