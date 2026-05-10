`timescale 1ns / 1ps

module tb_iter_online_output_update;
    reg [4 : 0] i_v5_p;
    reg [4 : 0] i_v5_n;
    wire [3 : 0] o_w5_p;
    wire [3 : 0] o_w5_n;
    wire o_z5_p;
    wire o_z5_n;

    reg [3 : 0] i_v4_p;
    reg [3 : 0] i_v4_n;
    wire [2 : 0] o_w4_p;
    wire [2 : 0] o_w4_n;
    wire o_z4_p;
    wire o_z4_n;

    iter_online_output_update #(
        .sample_width(5)
    ) dut5 (
        .i_v_p_msd(i_v5_p),
        .i_v_n_msd(i_v5_n),
        .o_w_p_msd(o_w5_p),
        .o_w_n_msd(o_w5_n),
        .o_z_p(o_z5_p),
        .o_z_n(o_z5_n)
    );

    iter_online_output_update #(
        .sample_width(4)
    ) dut4 (
        .i_v_p_msd(i_v4_p),
        .i_v_n_msd(i_v4_n),
        .o_w_p_msd(o_w4_p),
        .o_w_n_msd(o_w4_n),
        .o_z_p(o_z4_p),
        .o_z_n(o_z4_n)
    );

    initial begin
        i_v5_p = 5'b01100; i_v5_n = 5'b00000;
        #1;
        if ({o_z5_p, o_z5_n} !== 2'b10 || o_w5_p !== 4'b0100 || o_w5_n !== 4'b0000) begin
            $display("ERROR tb_iter_online_output_update sample5 positive");
            $fatal;
        end

        i_v5_p = 5'b00000; i_v5_n = 5'b01100;
        #1;
        if ({o_z5_p, o_z5_n} !== 2'b01 || o_w5_p !== 4'b0000 || o_w5_n !== 4'b0100) begin
            $display("ERROR tb_iter_online_output_update sample5 negative");
            $fatal;
        end

        i_v5_p = 5'b00000; i_v5_n = 5'b00000;
        #1;
        if ({o_z5_p, o_z5_n} !== 2'b00 || o_w5_p !== 4'b0000 || o_w5_n !== 4'b0000) begin
            $display("ERROR tb_iter_online_output_update sample5 zero");
            $fatal;
        end

        i_v4_p = 4'b0110; i_v4_n = 4'b0000;
        #1;
        if ({o_z4_p, o_z4_n} !== 2'b10 || o_w4_p !== 3'b010 || o_w4_n !== 3'b000) begin
            $display("ERROR tb_iter_online_output_update sample4 positive");
            $fatal;
        end

        i_v4_p = 4'b0000; i_v4_n = 4'b0110;
        #1;
        if ({o_z4_p, o_z4_n} !== 2'b01 || o_w4_p !== 3'b000 || o_w4_n !== 3'b010) begin
            $display("ERROR tb_iter_online_output_update sample4 negative");
            $fatal;
        end

        $display("PASS tb_iter_online_output_update");
        $finish;
    end
endmodule
