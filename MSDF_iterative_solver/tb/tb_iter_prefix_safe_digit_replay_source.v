`timescale 1ns / 1ps

module tb_iter_prefix_safe_digit_replay_source;
    localparam integer NUM_ROWS = 4;
    localparam integer DEGREE = 4;
    localparam integer DATA_WIDTH = 8;
    localparam integer DIGIT_IDX_WIDTH = $clog2(DATA_WIDTH);
    localparam integer ROW_ID_WIDTH = $clog2(NUM_ROWS);
    localparam integer TABLE_BITS = NUM_ROWS * DATA_WIDTH * DEGREE;

    reg i_req_valid;
    reg [ROW_ID_WIDTH - 1 : 0] i_req_row_id;
    reg [DIGIT_IDX_WIDTH - 1 : 0] i_req_digit_idx;
    reg [TABLE_BITS - 1 : 0] i_digit_p_table;
    reg [TABLE_BITS - 1 : 0] i_digit_n_table;
    wire o_resp_valid;
    wire [DEGREE - 1 : 0] o_state_digit_p_terms;
    wire [DEGREE - 1 : 0] o_state_digit_n_terms;

    iter_prefix_safe_digit_replay_source #(
        .num_rows(NUM_ROWS),
        .degree(DEGREE),
        .data_width(DATA_WIDTH)
    ) dut (
        .i_req_valid(i_req_valid),
        .i_req_row_id(i_req_row_id),
        .i_req_digit_idx(i_req_digit_idx),
        .i_digit_p_table(i_digit_p_table),
        .i_digit_n_table(i_digit_n_table),
        .o_resp_valid(o_resp_valid),
        .o_state_digit_p_terms(o_state_digit_p_terms),
        .o_state_digit_n_terms(o_state_digit_n_terms)
    );

    task set_digit;
        input integer row;
        input integer digit;
        input [DEGREE - 1 : 0] p_terms;
        input [DEGREE - 1 : 0] n_terms;
        integer base;
        begin
            base = ((row * DATA_WIDTH + digit) * DEGREE);
            i_digit_p_table[base +: DEGREE] = p_terms;
            i_digit_n_table[base +: DEGREE] = n_terms;
        end
    endtask

    task check_req;
        input integer row;
        input integer digit;
        input [DEGREE - 1 : 0] exp_p;
        input [DEGREE - 1 : 0] exp_n;
        begin
            i_req_valid = 1'b1;
            i_req_row_id = row[ROW_ID_WIDTH - 1 : 0];
            i_req_digit_idx = digit[DIGIT_IDX_WIDTH - 1 : 0];
            #1;
            if (!o_resp_valid ||
                o_state_digit_p_terms !== exp_p ||
                o_state_digit_n_terms !== exp_n) begin
                $display("ERROR replay row=%0d digit=%0d got p/n=%b/%b exp=%b/%b",
                    row,
                    digit,
                    o_state_digit_p_terms,
                    o_state_digit_n_terms,
                    exp_p,
                    exp_n);
                $fatal;
            end
        end
    endtask

    initial begin
        i_req_valid = 1'b0;
        i_req_row_id = {ROW_ID_WIDTH{1'b0}};
        i_req_digit_idx = {DIGIT_IDX_WIDTH{1'b0}};
        i_digit_p_table = {TABLE_BITS{1'b0}};
        i_digit_n_table = {TABLE_BITS{1'b0}};

        set_digit(0, 2, 4'b0101, 4'b0000);
        set_digit(1, 4, 4'b0011, 4'b0100);
        set_digit(2, 6, 4'b1110, 4'b0001);
        set_digit(3, 7, 4'b0000, 4'b1001);

        check_req(0, 2, 4'b0101, 4'b0000);
        check_req(1, 4, 4'b0011, 4'b0100);
        check_req(2, 6, 4'b1110, 4'b0001);
        check_req(3, 7, 4'b0000, 4'b1001);

        i_req_valid = 1'b0;
        #1;
        if (o_resp_valid ||
            o_state_digit_p_terms !== {DEGREE{1'b0}} ||
            o_state_digit_n_terms !== {DEGREE{1'b0}}) begin
            $display("ERROR replay did not zero output when invalid");
            $fatal;
        end

        $display("PASS tb_iter_prefix_safe_digit_replay_source");
        $finish;
    end
endmodule
