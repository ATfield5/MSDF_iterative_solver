`timescale 1ns / 1ps

module tb_online_delta_linf_cert_core;
    localparam integer DATA_WIDTH = 11;
    localparam integer BOUND_WIDTH = DATA_WIDTH + 2;

    reg i_valid;
    reg [DATA_WIDTH - 1 : 0] i_x_new_p;
    reg [DATA_WIDTH - 1 : 0] i_x_new_n;
    reg [DATA_WIDTH - 1 : 0] i_x_old_p;
    reg [DATA_WIDTH - 1 : 0] i_x_old_n;
    reg [BOUND_WIDTH - 1 : 0] i_tail_bound;
    reg [BOUND_WIDTH - 1 : 0] i_eps_d;
    wire o_valid;
    wire signed [DATA_WIDTH + 1 : 0] o_delta_word;
    wire [BOUND_WIDTH - 1 : 0] o_abs_prefix;
    wire [BOUND_WIDTH - 1 : 0] o_abs_upper;
    wire [BOUND_WIDTH - 1 : 0] o_abs_lower;
    wire o_cert_converged;
    wire o_cert_not_converged;
    wire [1 : 0] o_cert_state;

    online_delta_linf_cert_core #(
        .data_width(DATA_WIDTH),
        .bound_width(BOUND_WIDTH)
    ) dut (
        .i_valid(i_valid),
        .i_x_new_p(i_x_new_p),
        .i_x_new_n(i_x_new_n),
        .i_x_old_p(i_x_old_p),
        .i_x_old_n(i_x_old_n),
        .i_tail_bound(i_tail_bound),
        .i_eps_d(i_eps_d),
        .o_valid(o_valid),
        .o_delta_word(o_delta_word),
        .o_abs_prefix(o_abs_prefix),
        .o_abs_upper(o_abs_upper),
        .o_abs_lower(o_abs_lower),
        .o_cert_converged(o_cert_converged),
        .o_cert_not_converged(o_cert_not_converged),
        .o_cert_state(o_cert_state)
    );

    task run_case;
        input [DATA_WIDTH - 1 : 0] x_new_p;
        input [DATA_WIDTH - 1 : 0] x_new_n;
        input [DATA_WIDTH - 1 : 0] x_old_p;
        input [DATA_WIDTH - 1 : 0] x_old_n;
        input [BOUND_WIDTH - 1 : 0] tail_bound;
        input [BOUND_WIDTH - 1 : 0] eps_d;
        input signed [DATA_WIDTH + 1 : 0] exp_delta;
        input [BOUND_WIDTH - 1 : 0] exp_abs_prefix;
        input [BOUND_WIDTH - 1 : 0] exp_abs_upper;
        input [BOUND_WIDTH - 1 : 0] exp_abs_lower;
        input exp_converged;
        input exp_not_converged;
        input [1 : 0] exp_state;
        begin
            i_valid = 1'b1;
            i_x_new_p = x_new_p;
            i_x_new_n = x_new_n;
            i_x_old_p = x_old_p;
            i_x_old_n = x_old_n;
            i_tail_bound = tail_bound;
            i_eps_d = eps_d;
            #1;

            if (!o_valid) begin
                $display("ERROR tb_online_delta_linf_cert_core o_valid=0");
                $fatal;
            end

            if (o_delta_word !== exp_delta ||
                o_abs_prefix !== exp_abs_prefix ||
                o_abs_upper !== exp_abs_upper ||
                o_abs_lower !== exp_abs_lower ||
                o_cert_converged !== exp_converged ||
                o_cert_not_converged !== exp_not_converged ||
                o_cert_state !== exp_state) begin
                $display("ERROR tb_online_delta_linf_cert_core");
                $display("  got delta=%0d abs=%0d up=%0d low=%0d conv=%b not=%b state=%b",
                    o_delta_word, o_abs_prefix, o_abs_upper, o_abs_lower,
                    o_cert_converged, o_cert_not_converged, o_cert_state);
                $display("  exp delta=%0d abs=%0d up=%0d low=%0d conv=%b not=%b state=%b",
                    exp_delta, exp_abs_prefix, exp_abs_upper, exp_abs_lower,
                    exp_converged, exp_not_converged, exp_state);
                $fatal;
            end
        end
    endtask

    initial begin
        i_valid = 1'b0;
        i_x_new_p = {DATA_WIDTH{1'b0}};
        i_x_new_n = {DATA_WIDTH{1'b0}};
        i_x_old_p = {DATA_WIDTH{1'b0}};
        i_x_old_n = {DATA_WIDTH{1'b0}};
        i_tail_bound = {BOUND_WIDTH{1'b0}};
        i_eps_d = {BOUND_WIDTH{1'b0}};

        // delta = +4, upper = 5, lower = 3 => converged when eps=5
        run_case(
            11'd10, 11'd0,
            11'd6, 11'd0,
            13'd1, 13'd5,
            13'sd4, 13'd4, 13'd5, 13'd3,
            1'b1, 1'b0, 2'b01
        );

        // same delta = +4, but eps=4 => undecided
        run_case(
            11'd10, 11'd0,
            11'd6, 11'd0,
            13'd1, 13'd4,
            13'sd4, 13'd4, 13'd5, 13'd3,
            1'b0, 1'b0, 2'b00
        );

        // delta = -5, upper = 6, lower = 4 => not converged when eps=3
        run_case(
            11'd2, 11'd0,
            11'd7, 11'd0,
            13'd1, 13'd3,
            -13'sd5, 13'd5, 13'd6, 13'd4,
            1'b0, 1'b1, 2'b10
        );

        $display("PASS tb_online_delta_linf_cert_core");
        $finish;
    end
endmodule
