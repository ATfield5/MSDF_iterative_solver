`timescale 1ns / 1ps

// Convert a signed two's-complement binary value into unsigned differential
// rails. Positive values are placed on p, negative values on n.

module iter_signed_to_rail #(
    parameter integer in_width = 12,
    parameter integer rail_width = 11
) (
    input signed [in_width - 1 : 0] i_value,
    output reg [rail_width - 1 : 0] o_value_p,
    output reg [rail_width - 1 : 0] o_value_n
);

    reg [in_width - 1 : 0] r_abs_value;
    reg [rail_width - 1 : 0] r_sat_value;

    always @(*) begin
        if (i_value < 0) begin
            r_abs_value = -i_value;
        end else begin
            r_abs_value = i_value;
        end

        if (|r_abs_value[in_width - 1 : rail_width]) begin
            r_sat_value = {rail_width{1'b1}};
        end else begin
            r_sat_value = r_abs_value[rail_width - 1 : 0];
        end

        if (i_value < 0) begin
            o_value_p = {rail_width{1'b0}};
            o_value_n = r_sat_value;
        end else begin
            o_value_p = r_sat_value;
            o_value_n = {rail_width{1'b0}};
        end
    end

endmodule
