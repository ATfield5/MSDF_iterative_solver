`timescale 1ns / 1ps

// Constant-coefficient contribution for magnitude p/n rails.
//
// The original operator selector uses a bitwise complement convention tied to
// its digit-window representation.  The solver-native fixed-coefficient path
// stores coefficients as magnitude rails, so multiplying by a negative input
// digit must swap p/n rails rather than complementing both vectors.

module iter_const_coeff_digit_contrib_rail #(
    parameter integer bit_width = 8
) (
    input                          i_digit_p,
    input                          i_digit_n,
    input      [bit_width - 1 : 0] i_coeff_vec_p,
    input      [bit_width - 1 : 0] i_coeff_vec_n,
    output reg [bit_width - 1 : 0] o_vec_p,
    output reg [bit_width - 1 : 0] o_vec_n
);

    always @(*) begin
        case ({i_digit_p, i_digit_n})
            2'b10: begin
                o_vec_p = i_coeff_vec_p;
                o_vec_n = i_coeff_vec_n;
            end
            2'b01: begin
                o_vec_p = i_coeff_vec_n;
                o_vec_n = i_coeff_vec_p;
            end
            default: begin
                o_vec_p = {bit_width{1'b0}};
                o_vec_n = {bit_width{1'b0}};
            end
        endcase
    end

endmodule
