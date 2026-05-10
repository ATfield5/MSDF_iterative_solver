`timescale 1ns / 1ps

// Functional-first row-local delta and L_inf certification slice.
//
// This module sits after the specialized affine row-update core. It converts
// two rail-coded row states into a row-local delta word:
//
//   d_i^(k) = x_i^(k+1) - x_i^(k)
//
// and immediately derives the strict prefix bounds used by the L_inf
// certification path:
//
//   U_i = |d_i_prefix| + tail
//   L_i = max(0, |d_i_prefix| - tail)
//
// The global controller can then aggregate row-local states as:
// - all rows converged  -> CERT_CONVERGED
// - any row not converged -> CERT_NOT_CONVERGED
// - otherwise -> CERT_UNDECIDED
//
// This keeps the first RTL step aligned with the math while avoiding a full
// solver controller in the same patch.

module online_delta_linf_cert_core #(
    parameter integer data_width = 11,
    parameter integer bound_width = data_width + 2
) (
    input                                   i_valid,
    input      [data_width - 1 : 0]         i_x_new_p,
    input      [data_width - 1 : 0]         i_x_new_n,
    input      [data_width - 1 : 0]         i_x_old_p,
    input      [data_width - 1 : 0]         i_x_old_n,
    input      [bound_width - 1 : 0]        i_tail_bound,
    input      [bound_width - 1 : 0]        i_eps_d,
    output reg                              o_valid,
    output reg signed [data_width + 1 : 0]  o_delta_word,
    output reg [bound_width - 1 : 0]        o_abs_prefix,
    output reg [bound_width - 1 : 0]        o_abs_upper,
    output reg [bound_width - 1 : 0]        o_abs_lower,
    output reg                              o_cert_converged,
    output reg                              o_cert_not_converged,
    output reg [1 : 0]                      o_cert_state
);

    localparam [1 : 0] CERT_UNDECIDED     = 2'b00;
    localparam [1 : 0] CERT_CONVERGED     = 2'b01;
    localparam [1 : 0] CERT_NOT_CONVERGED = 2'b10;

    reg signed [data_width : 0] x_new_word;
    reg signed [data_width : 0] x_old_word;
    reg signed [data_width + 1 : 0] delta_word;
    reg [bound_width - 1 : 0] abs_prefix_word;
    reg [bound_width - 1 : 0] upper_word;
    reg [bound_width - 1 : 0] lower_word;

    function automatic signed [data_width : 0] rail_to_signed;
        input [data_width - 1 : 0] vec_p;
        input [data_width - 1 : 0] vec_n;
        reg signed [data_width : 0] ext_p;
        reg signed [data_width : 0] ext_n;
        begin
            ext_p = $signed({1'b0, vec_p});
            ext_n = $signed({1'b0, vec_n});
            rail_to_signed = ext_p - ext_n;
        end
    endfunction

    function automatic [bound_width - 1 : 0] signed_abs_to_bound;
        input signed [data_width + 1 : 0] signed_word;
        reg signed [data_width + 1 : 0] abs_word;
        reg [bound_width - 1 : 0] padded_abs_word;
        begin
            if (signed_word < 0) begin
                abs_word = -signed_word;
            end else begin
                abs_word = signed_word;
            end
            padded_abs_word = {bound_width{1'b0}};
            padded_abs_word[data_width + 1 : 0] = abs_word;
            signed_abs_to_bound = padded_abs_word;
        end
    endfunction

    always @(*) begin
        x_new_word = rail_to_signed(i_x_new_p, i_x_new_n);
        x_old_word = rail_to_signed(i_x_old_p, i_x_old_n);
        delta_word = x_new_word - x_old_word;
        abs_prefix_word = signed_abs_to_bound(delta_word);
        upper_word = abs_prefix_word + i_tail_bound;

        if (abs_prefix_word > i_tail_bound) begin
            lower_word = abs_prefix_word - i_tail_bound;
        end else begin
            lower_word = {bound_width{1'b0}};
        end
    end

    always @(*) begin
        o_valid = i_valid;
        o_delta_word = delta_word;
        o_abs_prefix = abs_prefix_word;
        o_abs_upper = upper_word;
        o_abs_lower = lower_word;

        o_cert_converged = 1'b0;
        o_cert_not_converged = 1'b0;
        o_cert_state = CERT_UNDECIDED;

        if (i_valid) begin
            if (upper_word <= i_eps_d) begin
                o_cert_converged = 1'b1;
                o_cert_state = CERT_CONVERGED;
            end else if (lower_word > i_eps_d) begin
                o_cert_not_converged = 1'b1;
                o_cert_state = CERT_NOT_CONVERGED;
            end
        end
    end

endmodule
