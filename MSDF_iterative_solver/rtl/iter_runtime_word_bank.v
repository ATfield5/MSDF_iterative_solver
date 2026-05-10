`timescale 1ns / 1ps

// Runtime-loadable packed-word bank.
//
// This is the first replacement for pure $readmemh parameter banks. The write
// side models a configuration packet interface, while the read side exposes a
// contiguous active window for the parallel cluster datapath.

module iter_runtime_word_bank #(
    parameter integer num_total_words = 2,
    parameter integer num_read_words = 2,
    parameter integer word_width = 128,
    parameter integer addr_width = (num_total_words <= 2) ? 1 : $clog2(num_total_words)
) (
    input                                       i_clk,
    input                                       i_rst,
    input                                       i_cfg_we,
    input      [addr_width - 1 : 0]             i_cfg_addr,
    input      [word_width - 1 : 0]             i_cfg_wdata,
    input                                       i_window_load,
    input      [addr_width - 1 : 0]             i_base_addr,
    output reg                                  o_window_valid,
    output reg                                  o_window_busy,
    output reg [num_read_words * word_width - 1 : 0] o_words
);

    localparam integer read_idx_width = (num_read_words <= 2) ? 1 : $clog2(num_read_words);

    reg [word_width - 1 : 0] r_words [0 : num_total_words - 1];
    reg [addr_width - 1 : 0] r_base_addr;
    reg [read_idx_width - 1 : 0] r_load_idx;
    integer ri;
    integer mem_idx;

    always @(posedge i_clk) begin
        if (i_rst) begin
            for (ri = 0; ri < num_total_words; ri = ri + 1) begin
                r_words[ri] <= {word_width{1'b0}};
            end
            r_base_addr <= {addr_width{1'b0}};
            r_load_idx <= {read_idx_width{1'b0}};
            o_window_valid <= 1'b0;
            o_window_busy <= 1'b0;
            o_words <= {num_read_words * word_width{1'b0}};
        end else if (i_cfg_we) begin
            r_words[i_cfg_addr] <= i_cfg_wdata;
        end

        if (!i_rst) begin
            if (i_window_load && !o_window_busy) begin
                r_base_addr <= i_base_addr;
                r_load_idx <= {read_idx_width{1'b0}};
                o_window_valid <= 1'b0;
                o_window_busy <= 1'b1;
                o_words <= {num_read_words * word_width{1'b0}};
            end else if (o_window_busy) begin
                mem_idx = r_base_addr + r_load_idx;
                if (mem_idx < num_total_words) begin
                    o_words[r_load_idx * word_width +: word_width] <= r_words[mem_idx];
                end else begin
                    o_words[r_load_idx * word_width +: word_width] <= {word_width{1'b0}};
                end

                if (r_load_idx == num_read_words - 1) begin
                    o_window_busy <= 1'b0;
                    o_window_valid <= 1'b1;
                end else begin
                    r_load_idx <= r_load_idx + 1'b1;
                end
            end
        end
    end

endmodule
