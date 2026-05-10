`timescale 1ns / 1ps

// Finite smoke test for the prior paper's MSDF_MUL_ADD_8 operator.
//
// The original TB_MMA8 in MSDF_operator_srcs does not call $finish, so this
// wrapper provides a reproducible P1 entry point.  It intentionally checks only
// the operator-level contract: a stream of input signed digits eventually
// produces output signed digits and region flags.  Solver-level state replay,
// convergence and PageRank control are tested by the new runtime TBs.

module tb_prior_mma8_smoke;
    reg i_clk;
    reg i_rst;
    reg i_ena;
    reg [7 : 0] i_x_p;
    reg [7 : 0] i_x_n;
    reg [7 : 0] i_y_p;
    reg [7 : 0] i_y_n;
    reg i_a_p;
    reg i_a_n;

    wire o_z_p;
    wire o_z_n;
    wire o_int;
    wire o_unit;
    wire o_frac;

    integer cycle;
    integer out_count;
    integer int_count;
    integer unit_count;
    integer frac_count;
    reg [63 : 0] z_p_trace;
    reg [63 : 0] z_n_trace;

    MSDF_MUL_ADD_8 #(
        .bit_width(8)
    ) dut (
        .i_clk(i_clk),
        .i_rst(i_rst),
        .i_ena(i_ena),
        .i_x_p(i_x_p),
        .i_x_n(i_x_n),
        .i_y_p(i_y_p),
        .i_y_n(i_y_n),
        .i_a_p(i_a_p),
        .i_a_n(i_a_n),
        .o_z_p(o_z_p),
        .o_z_n(o_z_n),
        .o_int(o_int),
        .o_unit(o_unit),
        .o_frac(o_frac)
    );

    always #5 i_clk = ~i_clk;

    always @(posedge i_clk) begin
        if (i_rst) begin
            i_ena <= 1'b0;
            i_x_p <= 8'h00;
            i_x_n <= 8'h00;
            i_y_p <= 8'h00;
            i_y_n <= 8'h00;
            i_a_p <= 1'b0;
            i_a_n <= 1'b0;
        end else if (cycle < 8) begin
            i_ena <= 1'b1;
            i_x_p <= 8'hff;
            i_x_n <= 8'h00;
            i_y_p <= 8'hff;
            i_y_n <= 8'h00;
            i_a_p <= 1'b1;
            i_a_n <= 1'b0;
        end else begin
            i_ena <= 1'b0;
            i_x_p <= 8'h00;
            i_x_n <= 8'h00;
            i_y_p <= 8'h00;
            i_y_n <= 8'h00;
            i_a_p <= 1'b0;
            i_a_n <= 1'b0;
        end
    end

    always @(posedge i_clk) begin
        if (i_rst) begin
            cycle <= 0;
            out_count <= 0;
            int_count <= 0;
            unit_count <= 0;
            frac_count <= 0;
            z_p_trace <= 64'd0;
            z_n_trace <= 64'd0;
        end else begin
            cycle <= cycle + 1;
            if (o_int || o_unit || o_frac) begin
                z_p_trace[out_count] <= o_z_p;
                z_n_trace[out_count] <= o_z_n;
                out_count <= out_count + 1;
                int_count <= int_count + o_int;
                unit_count <= unit_count + o_unit;
                frac_count <= frac_count + o_frac;
            end
        end
    end

    initial begin
        i_clk = 1'b0;
        i_rst = 1'b1;
        i_ena = 1'b0;
        i_x_p = 8'h00;
        i_x_n = 8'h00;
        i_y_p = 8'h00;
        i_y_n = 8'h00;
        i_a_p = 1'b0;
        i_a_n = 1'b0;

        repeat (4) @(posedge i_clk);
        i_rst <= 1'b0;
        repeat (80) @(posedge i_clk);

        if (out_count == 0 || unit_count == 0 || frac_count == 0) begin
            $display("ERROR prior_mma8 no usable output out=%0d int=%0d unit=%0d frac=%0d",
                out_count, int_count, unit_count, frac_count);
            $fatal;
        end

        $display("COUNTERS prior_mma8_smoke out=%0d int=%0d unit=%0d frac=%0d z_p_trace=%h z_n_trace=%h",
            out_count, int_count, unit_count, frac_count, z_p_trace, z_n_trace);
        $display("PASS tb_prior_mma8_smoke");
        $finish;
    end
endmodule
