`timescale 1ns / 1ps

// Convert unsigned differential rails back into a signed two's-complement
// binary word. The caller should choose out_width >= rail_width + 1.

module iter_rail_to_signed #(
    parameter integer rail_width = 11,
    parameter integer out_width = rail_width + 1
) (
    input      [rail_width - 1 : 0]        i_value_p,
    input      [rail_width - 1 : 0]        i_value_n,
    output signed [out_width - 1 : 0]      o_value
);

    wire signed [out_width - 1 : 0] w_p_ext;
    wire signed [out_width - 1 : 0] w_n_ext;

    assign w_p_ext = $signed({1'b0, i_value_p});
    assign w_n_ext = $signed({1'b0, i_value_n});
    assign o_value = w_p_ext - w_n_ext;

endmodule
