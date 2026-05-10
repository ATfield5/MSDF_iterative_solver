`timescale 1ns / 1ps

// Lightweight next-iteration row-engine consumer stub.
//
// This module is not the real row-update datapath.  It is a protocol and
// scheduling probe that accepts one prefix-safe row-start command, stays busy
// for SERVICE_CYCLES occupied cycles, then emits a done pulse with the command
// metadata.  It lets the prefix-safe scheduler be tested with realistic
// ready/valid backpressure before it is connected to the solver-native row
// digit engine.

module iter_prefix_safe_consumer_stub #(
    parameter integer num_rows = 4,
    parameter integer data_width = 11,
    parameter integer service_cycles = 3,
    parameter integer digit_idx_width = (data_width <= 2) ? 1 : $clog2(data_width),
    parameter integer row_id_width = (num_rows <= 2) ? 1 : $clog2(num_rows),
    parameter integer lead_width = digit_idx_width + 1,
    parameter integer countdown_width = (service_cycles <= 1) ? 1 : $clog2(service_cycles + 1)
) (
    input                                   i_clk,
    input                                   i_rst,
    input                                   i_start,
    input                                   i_cmd_valid,
    output                                  o_cmd_ready,
    input      [row_id_width - 1 : 0]       i_cmd_row_id,
    input      [digit_idx_width - 1 : 0]    i_cmd_digit_idx,
    input      [lead_width - 1 : 0]         i_cmd_lead_cycles,
    output reg                              o_busy,
    output reg                              o_done_pulse,
    output reg [row_id_width - 1 : 0]       o_done_row_id,
    output reg [digit_idx_width - 1 : 0]    o_done_digit_idx,
    output reg [lead_width - 1 : 0]         o_done_lead_cycles,
    output reg [31 : 0]                     o_accept_count,
    output reg [31 : 0]                     o_done_count,
    output reg [31 : 0]                     o_busy_cycles,
    output reg [31 : 0]                     o_backpressure_cycles,
    output reg [lead_width - 1 : 0]         o_max_lead_cycles
);

    reg [countdown_width - 1 : 0] r_countdown;
    reg [row_id_width - 1 : 0] r_active_row_id;
    reg [digit_idx_width - 1 : 0] r_active_digit_idx;
    reg [lead_width - 1 : 0] r_active_lead_cycles;

    wire w_accept;

    assign o_cmd_ready = !o_busy;
    assign w_accept = i_cmd_valid && o_cmd_ready;

    always @(posedge i_clk) begin
        if (i_rst || i_start) begin
            o_busy <= 1'b0;
            o_done_pulse <= 1'b0;
            o_done_row_id <= {row_id_width{1'b0}};
            o_done_digit_idx <= {digit_idx_width{1'b0}};
            o_done_lead_cycles <= {lead_width{1'b0}};
            o_accept_count <= 32'd0;
            o_done_count <= 32'd0;
            o_busy_cycles <= 32'd0;
            o_backpressure_cycles <= 32'd0;
            o_max_lead_cycles <= {lead_width{1'b0}};
            r_countdown <= {countdown_width{1'b0}};
            r_active_row_id <= {row_id_width{1'b0}};
            r_active_digit_idx <= {digit_idx_width{1'b0}};
            r_active_lead_cycles <= {lead_width{1'b0}};
        end else begin
            o_done_pulse <= 1'b0;

            if (o_busy) begin
                o_busy_cycles <= o_busy_cycles + 1'b1;
            end
            if (i_cmd_valid && !o_cmd_ready) begin
                o_backpressure_cycles <= o_backpressure_cycles + 1'b1;
            end

            if (o_busy) begin
                if (r_countdown <= {{(countdown_width - 1){1'b0}}, 1'b1}) begin
                    o_busy <= 1'b0;
                    r_countdown <= {countdown_width{1'b0}};
                    o_done_pulse <= 1'b1;
                    o_done_row_id <= r_active_row_id;
                    o_done_digit_idx <= r_active_digit_idx;
                    o_done_lead_cycles <= r_active_lead_cycles;
                    o_done_count <= o_done_count + 1'b1;
                end else begin
                    r_countdown <= r_countdown - 1'b1;
                end
            end

            if (w_accept) begin
                o_accept_count <= o_accept_count + 1'b1;
                r_active_row_id <= i_cmd_row_id;
                r_active_digit_idx <= i_cmd_digit_idx;
                r_active_lead_cycles <= i_cmd_lead_cycles;
                if (i_cmd_lead_cycles > o_max_lead_cycles) begin
                    o_max_lead_cycles <= i_cmd_lead_cycles;
                end

                if (service_cycles <= 1) begin
                    o_busy <= 1'b0;
                    r_countdown <= {countdown_width{1'b0}};
                    o_done_pulse <= 1'b1;
                    o_done_row_id <= i_cmd_row_id;
                    o_done_digit_idx <= i_cmd_digit_idx;
                    o_done_lead_cycles <= i_cmd_lead_cycles;
                    o_done_count <= o_done_count + 1'b1;
                end else begin
                    o_busy <= 1'b1;
                    r_countdown <= service_cycles - 1;
                end
            end
        end
    end

endmodule
