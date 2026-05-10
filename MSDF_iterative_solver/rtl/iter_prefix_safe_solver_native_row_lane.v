`timescale 1ns / 1ps

// Prefix-safe command adapter for one solver-native digit row engine.
//
// A prefix-safe row-start command says that enough source prefix is available to
// start the next iteration.  The row engine itself still consumes a normal
// MSB-first digit stream starting at digit 0.  In the final runtime design this
// stream must come from a prefix FIFO/replay buffer.  This adapter provides the
// command-to-engine lifecycle:
//
//   row-start command
//     -> request source digits 0..DATA_WIDTH-1
//     -> run iter_solver_native_row_digit_engine
//     -> emit DATA_WIDTH output digits
//     -> done pulse
//
// The source digit terms are external inputs so this lane can later be connected
// to either a stub source, a digit-stream state bank, or the real prefix replay
// FIFO without changing the command protocol.

module iter_prefix_safe_solver_native_row_lane #(
    parameter integer num_rows = 4,
    parameter integer bit_width = 8,
    parameter integer degree = 4,
    parameter integer data_width = bit_width + 3,
    parameter integer bias_width = bit_width + 2,
    parameter integer sample_width = 5,
    parameter integer affine_guard_shift = 3,
    parameter integer residual_width = data_width + affine_guard_shift + 1,
    parameter integer digit_idx_width = (data_width <= 2) ? 1 : $clog2(data_width),
    parameter integer row_id_width = (num_rows <= 2) ? 1 : $clog2(num_rows),
    parameter integer lead_width = digit_idx_width + 1
) (
    input                                      i_clk,
    input                                      i_rst,
    input                                      i_start,
    input                                      i_cmd_valid,
    output                                     o_cmd_ready,
    input      [row_id_width - 1 : 0]          i_cmd_row_id,
    input      [digit_idx_width - 1 : 0]       i_cmd_digit_idx,
    input      [lead_width - 1 : 0]            i_cmd_lead_cycles,
    output                                     o_source_req_valid,
    output     [row_id_width - 1 : 0]          o_source_req_row_id,
    output     [digit_idx_width - 1 : 0]       o_source_req_digit_idx,
    input      [degree - 1 : 0]                i_state_digit_p_terms,
    input      [degree - 1 : 0]                i_state_digit_n_terms,
    input      [degree * bit_width - 1 : 0]    i_coeff_p_terms,
    input      [degree * bit_width - 1 : 0]    i_coeff_n_terms,
    input      [bias_width - 1 : 0]            i_bias_p,
    input      [bias_width - 1 : 0]            i_bias_n,
    output                                     o_x_valid,
    output                                     o_x_new_digit_p,
    output                                     o_x_new_digit_n,
    output                                     o_busy,
    output reg                                 o_done_pulse,
    output reg [row_id_width - 1 : 0]          o_done_row_id,
    output reg [digit_idx_width - 1 : 0]       o_done_issue_digit_idx,
    output reg [lead_width - 1 : 0]            o_done_lead_cycles,
    output reg [31 : 0]                        o_accept_count,
    output reg [31 : 0]                        o_output_digit_count,
    output reg [31 : 0]                        o_done_count,
    output reg [lead_width - 1 : 0]            o_max_lead_cycles
);

    reg r_input_active;
    reg r_output_active;
    reg [digit_idx_width - 1 : 0] r_feed_digit_idx;
    reg [digit_idx_width : 0] r_output_count;
    reg [row_id_width - 1 : 0] r_active_row_id;
    reg [digit_idx_width - 1 : 0] r_active_issue_digit_idx;
    reg [lead_width - 1 : 0] r_active_lead_cycles;

    wire w_accept;
    wire w_engine_start;
    wire w_engine_valid;

    assign o_cmd_ready = !r_input_active && !r_output_active;
    assign w_accept = i_cmd_valid && o_cmd_ready;
    assign o_source_req_valid = r_input_active;
    assign o_source_req_row_id = r_active_row_id;
    assign o_source_req_digit_idx = r_feed_digit_idx;
    assign w_engine_start = r_input_active && (r_feed_digit_idx == {digit_idx_width{1'b0}});
    assign o_busy = r_input_active || r_output_active;

    iter_solver_native_row_digit_engine #(
        .bit_width(bit_width),
        .degree(degree),
        .data_width(data_width),
        .bias_width(bias_width),
        .sample_width(sample_width),
        .affine_guard_shift(affine_guard_shift),
        .residual_width(residual_width),
        .digit_idx_width(digit_idx_width)
    ) row_engine (
        .i_clk(i_clk),
        .i_rst(i_rst),
        .i_start(w_engine_start),
        .i_valid_digit(r_input_active),
        .i_digit_idx(r_feed_digit_idx),
        .i_state_digit_p_terms(i_state_digit_p_terms),
        .i_state_digit_n_terms(i_state_digit_n_terms),
        .i_coeff_p_terms(i_coeff_p_terms),
        .i_coeff_n_terms(i_coeff_n_terms),
        .i_bias_p(i_bias_p),
        .i_bias_n(i_bias_n),
        .o_valid(w_engine_valid),
        .o_x_new_digit_p(o_x_new_digit_p),
        .o_x_new_digit_n(o_x_new_digit_n),
        .o_affine_p(),
        .o_affine_n(),
        .o_residual_p(),
        .o_residual_n()
    );

    assign o_x_valid = w_engine_valid;

    always @(posedge i_clk) begin
        if (i_rst || i_start) begin
            r_input_active <= 1'b0;
            r_output_active <= 1'b0;
            r_feed_digit_idx <= {digit_idx_width{1'b0}};
            r_output_count <= {(digit_idx_width + 1){1'b0}};
            r_active_row_id <= {row_id_width{1'b0}};
            r_active_issue_digit_idx <= {digit_idx_width{1'b0}};
            r_active_lead_cycles <= {lead_width{1'b0}};
            o_done_pulse <= 1'b0;
            o_done_row_id <= {row_id_width{1'b0}};
            o_done_issue_digit_idx <= {digit_idx_width{1'b0}};
            o_done_lead_cycles <= {lead_width{1'b0}};
            o_accept_count <= 32'd0;
            o_output_digit_count <= 32'd0;
            o_done_count <= 32'd0;
            o_max_lead_cycles <= {lead_width{1'b0}};
        end else begin
            o_done_pulse <= 1'b0;

            if (w_accept) begin
                r_input_active <= 1'b1;
                r_output_active <= 1'b1;
                r_feed_digit_idx <= {digit_idx_width{1'b0}};
                r_output_count <= {(digit_idx_width + 1){1'b0}};
                r_active_row_id <= i_cmd_row_id;
                r_active_issue_digit_idx <= i_cmd_digit_idx;
                r_active_lead_cycles <= i_cmd_lead_cycles;
                o_accept_count <= o_accept_count + 1'b1;
                if (i_cmd_lead_cycles > o_max_lead_cycles) begin
                    o_max_lead_cycles <= i_cmd_lead_cycles;
                end
            end else if (r_input_active) begin
                if (r_feed_digit_idx == data_width - 1) begin
                    r_input_active <= 1'b0;
                end else begin
                    r_feed_digit_idx <= r_feed_digit_idx + 1'b1;
                end
            end

            if (w_engine_valid) begin
                o_output_digit_count <= o_output_digit_count + 1'b1;
                if (r_output_count == data_width - 1) begin
                    r_output_active <= 1'b0;
                    r_output_count <= {(digit_idx_width + 1){1'b0}};
                    o_done_pulse <= 1'b1;
                    o_done_row_id <= r_active_row_id;
                    o_done_issue_digit_idx <= r_active_issue_digit_idx;
                    o_done_lead_cycles <= r_active_lead_cycles;
                    o_done_count <= o_done_count + 1'b1;
                end else begin
                    r_output_count <= r_output_count + 1'b1;
                end
            end
        end
    end

endmodule
