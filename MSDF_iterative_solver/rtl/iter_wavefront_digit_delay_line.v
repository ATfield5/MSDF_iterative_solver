`timescale 1ns / 1ps

// Valid/data delay line for wavefront digit streams.
//
// This is intentionally a no-backpressure primitive.  The current wavefront
// checkpoints use deterministic digit streams, so every source either provides
// one digit per cycle or is idle.  Runtime integration can later replace this
// with a ready/valid FIFO if variable-latency halo traffic is required.

module iter_wavefront_digit_delay_line #(
    parameter integer data_width = 2,
    parameter integer delay_cycles = 1
) (
    input                              i_clk,
    input                              i_rst,
    input                              i_valid,
    input      [data_width - 1 : 0]    i_data,
    output                             o_valid,
    output     [data_width - 1 : 0]    o_data
);

    generate
        if (delay_cycles == 0) begin : gen_passthrough
            assign o_valid = i_valid;
            assign o_data = i_data;
        end else begin : gen_delay
            reg [delay_cycles - 1 : 0] r_valid_pipe;
            reg [delay_cycles * data_width - 1 : 0] r_data_pipe;
            integer di;

            always @(posedge i_clk) begin
                if (i_rst) begin
                    r_valid_pipe <= {delay_cycles{1'b0}};
                    r_data_pipe <= {delay_cycles * data_width{1'b0}};
                end else begin
                    r_valid_pipe[0] <= i_valid;
                    r_data_pipe[0 +: data_width] <= i_valid ? i_data : {data_width{1'b0}};
                    for (di = 1; di < delay_cycles; di = di + 1) begin
                        r_valid_pipe[di] <= r_valid_pipe[di - 1];
                        r_data_pipe[di * data_width +: data_width] <=
                            r_data_pipe[(di - 1) * data_width +: data_width];
                    end
                end
            end

            assign o_valid = r_valid_pipe[delay_cycles - 1];
            assign o_data = r_data_pipe[(delay_cycles - 1) * data_width +: data_width];
        end
    endgenerate

endmodule
