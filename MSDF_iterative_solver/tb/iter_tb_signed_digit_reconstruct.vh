// Testbench helper: reconstruct an MSB-first signed-digit rail word.
//
// The solver-native mode3 state bank stores signed-digit p/n traces.  Existing
// Jacobi fixtures store magnitude rail golden words, so mode3 tests must compare
// numerical values instead of raw p/n bit patterns.

function automatic signed [31:0] iter_tb_signed_digit_value;
    input [DATA_WIDTH-1:0] word_p;
    input [DATA_WIDTH-1:0] word_n;
    integer di;
    integer bit_sel;
    reg signed [31:0] value;
    begin
        value = 32'sd0;
        for (di = 0; di < DATA_WIDTH; di = di + 1) begin
            bit_sel = DATA_WIDTH - 1 - di;
            value = value <<< 1;
            if (word_p[bit_sel] && !word_n[bit_sel]) begin
                value = value + 1;
            end else if (!word_p[bit_sel] && word_n[bit_sel]) begin
                value = value - 1;
            end
        end
        iter_tb_signed_digit_value = value;
    end
endfunction

function automatic signed [31:0] iter_tb_magnitude_rail_value;
    input [DATA_WIDTH-1:0] word_p;
    input [DATA_WIDTH-1:0] word_n;
    begin
        iter_tb_magnitude_rail_value =
            $signed({1'b0, word_p}) - $signed({1'b0, word_n});
    end
endfunction
