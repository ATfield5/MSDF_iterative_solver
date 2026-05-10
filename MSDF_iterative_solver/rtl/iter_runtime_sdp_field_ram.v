`timescale 1ns / 1ps

// Narrow synchronous 1-write/1-read RAM used by runtime field banks.
//
// This wrapper intentionally exposes a conventional RAM shape to synthesis:
// one registered write port, one registered read port, and no wide packed
// payload assembly inside the storage array. Window assembly is handled by the
// parent field-bank modules.

module iter_runtime_sdp_field_ram #(
    parameter integer data_width = 8,
    parameter integer depth = 2,
    parameter integer addr_width = (depth <= 2) ? 1 : $clog2(depth),
    // 0: distributed RAM, 1: block RAM, 2: UltraRAM.
    parameter integer mem_style = 1
) (
    input                           i_clk,
    input                           i_wr_en,
    input      [addr_width-1:0]     i_wr_addr,
    input      [data_width-1:0]     i_wr_data,
    input                           i_rd_en,
    input      [addr_width-1:0]     i_rd_addr,
    output reg [data_width-1:0]     o_rd_data
);

    generate
        if (mem_style == 0) begin : gen_distributed
            (* ram_style = "distributed" *) reg [data_width-1:0] r_mem [0:depth-1];

            always @(posedge i_clk) begin
                if (i_wr_en) begin
                    r_mem[i_wr_addr] <= i_wr_data;
                end

                if (i_rd_en) begin
                    o_rd_data <= r_mem[i_rd_addr];
                end
            end
        end else if (mem_style == 2) begin : gen_ultra
            (* ram_style = "ultra" *) reg [data_width-1:0] r_mem [0:depth-1];

            always @(posedge i_clk) begin
                if (i_wr_en) begin
                    r_mem[i_wr_addr] <= i_wr_data;
                end

                if (i_rd_en) begin
                    o_rd_data <= r_mem[i_rd_addr];
                end
            end
        end else begin : gen_block
            (* ram_style = "block" *) reg [data_width-1:0] r_mem [0:depth-1];

            always @(posedge i_clk) begin
                if (i_wr_en) begin
                    r_mem[i_wr_addr] <= i_wr_data;
                end

                if (i_rd_en) begin
                    o_rd_data <= r_mem[i_rd_addr];
                end
            end
        end
    endgenerate

endmodule
