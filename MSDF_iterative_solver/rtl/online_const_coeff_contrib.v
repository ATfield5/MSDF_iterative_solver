`timescale 1ns / 1ps

module online_const_coeff_contrib #(
    parameter bit_width = 8
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
                o_vec_p = ~i_coeff_vec_p;
                o_vec_n = ~i_coeff_vec_n;
            end
            default: begin
                o_vec_p = {bit_width{1'b0}};
                o_vec_n = {bit_width{1'b0}};
            end
        endcase
    end

endmodule
