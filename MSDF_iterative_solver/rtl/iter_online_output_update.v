`timescale 1ns / 1ps

// Generic online output-and-update primitive.
//
// This is the solver-side equivalent of the original operator library's
// output_and_update stage.  It inspects the most-significant window of the
// current residual/state vector v_j, emits one signed digit z_j in p/n form,
// and returns the updated residual window for w_{j+1}.
//
// The digit decision uses the top 3 bits of the sampled window, matching the
// original operator implementation:
//   positive top-3 pattern -> +1
//   zero / near-zero        ->  0
//   negative top-3 pattern -> -1
//
// The updated residual keeps the lower SAMPLE_WIDTH-2 bits untouched and only
// adjusts the top 2 bits by +/-1 or 0 according to the emitted digit.

module iter_online_output_update #(
    parameter integer sample_width = 5
) (
    input      [sample_width - 1 : 0] i_v_p_msd,
    input      [sample_width - 1 : 0] i_v_n_msd,
    output reg [sample_width - 2 : 0] o_w_p_msd,
    output reg [sample_width - 2 : 0] o_w_n_msd,
    output reg                        o_z_p,
    output reg                        o_z_n
);

    wire [sample_width - 1 : 0] w_v_value;
    wire [2 : 0] w_v_sample;
    reg  [sample_width - 1 : 0] r_w_update;
    wire w_w_sgn;
    reg  [sample_width - 2 : 0] r_w_mag;

    assign w_v_value = i_v_p_msd - i_v_n_msd;
    assign w_v_sample = w_v_value[sample_width - 1 -: 3];
    assign w_w_sgn = r_w_update[sample_width - 1];

    always @(*) begin
        case (w_v_sample)
            3'b011, 3'b010, 3'b001: begin
                o_z_p = 1'b1;
                o_z_n = 1'b0;
            end
            3'b000, 3'b111: begin
                o_z_p = 1'b0;
                o_z_n = 1'b0;
            end
            default: begin
                o_z_p = 1'b0;
                o_z_n = 1'b1;
            end
        endcase
    end

    always @(*) begin
        case ({o_z_p, o_z_n})
            2'b10: r_w_update[sample_width - 1 : sample_width - 2] =
                w_v_value[sample_width - 1 : sample_width - 2] - 1'b1;
            2'b01: r_w_update[sample_width - 1 : sample_width - 2] =
                w_v_value[sample_width - 1 : sample_width - 2] + 1'b1;
            default: r_w_update[sample_width - 1 : sample_width - 2] =
                w_v_value[sample_width - 1 : sample_width - 2];
        endcase
        r_w_update[sample_width - 3 : 0] = w_v_value[sample_width - 3 : 0];
    end

    always @(*) begin
        if (w_w_sgn) begin
            r_w_mag = ~r_w_update[sample_width - 2 : 0] + 1'b1;
        end else begin
            r_w_mag = r_w_update[sample_width - 2 : 0];
        end

        o_w_p_msd = w_w_sgn ? {(sample_width - 1){1'b0}} : r_w_mag;
        o_w_n_msd = w_w_sgn ? r_w_mag : {(sample_width - 1){1'b0}};
    end

endmodule
