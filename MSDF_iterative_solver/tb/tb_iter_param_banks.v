`timescale 1ns / 1ps

module tb_iter_param_banks;
    localparam integer NUM_TOTAL_CLUSTERS = 4;
    localparam integer NUM_CLUSTERS = 2;
    localparam integer PAYLOAD_WIDTH = 16;
    localparam integer ADDR_WIDTH = 2;

    reg [ADDR_WIDTH - 1 : 0] i_base_cluster_idx;
    wire [NUM_CLUSTERS * PAYLOAD_WIDTH - 1 : 0] template_words;
    wire [NUM_CLUSTERS * PAYLOAD_WIDTH - 1 : 0] cert_words;

    iter_fixed_degree_template_bank #(
        .num_total_clusters(NUM_TOTAL_CLUSTERS),
        .num_clusters(NUM_CLUSTERS),
        .payload_width(PAYLOAD_WIDTH),
        .cluster_addr_width(ADDR_WIDTH),
        .template_mem_init("MSDF_iterative_solver/testdata/template_bank_dummy.memh")
    ) template_bank (
        .i_base_cluster_idx(i_base_cluster_idx),
        .o_template_words_clusters(template_words)
    );

    iter_cert_param_bank #(
        .num_total_clusters(NUM_TOTAL_CLUSTERS),
        .num_clusters(NUM_CLUSTERS),
        .payload_width(PAYLOAD_WIDTH),
        .cluster_addr_width(ADDR_WIDTH),
        .cert_param_mem_init("MSDF_iterative_solver/testdata/cert_param_bank_dummy.memh")
    ) cert_bank (
        .i_base_cluster_idx(i_base_cluster_idx),
        .o_cert_param_words_clusters(cert_words)
    );

    initial begin
        i_base_cluster_idx = 0;
        #1;
        if (template_words !== {16'h2222, 16'h1111}) begin
            $display("ERROR template bank base0 mismatch: %h", template_words);
            $fatal;
        end
        if (cert_words !== {16'hbbbb, 16'haaaa}) begin
            $display("ERROR cert bank base0 mismatch: %h", cert_words);
            $fatal;
        end

        i_base_cluster_idx = 2;
        #1;
        if (template_words !== {16'h4444, 16'h3333}) begin
            $display("ERROR template bank base2 mismatch: %h", template_words);
            $fatal;
        end
        if (cert_words !== {16'hdddd, 16'hcccc}) begin
            $display("ERROR cert bank base2 mismatch: %h", cert_words);
            $fatal;
        end

        i_base_cluster_idx = 3;
        #1;
        if (template_words !== {16'h0000, 16'h4444}) begin
            $display("ERROR template bank edge-window mismatch: %h", template_words);
            $fatal;
        end
        if (cert_words !== {16'h0000, 16'hdddd}) begin
            $display("ERROR cert bank edge-window mismatch: %h", cert_words);
            $fatal;
        end

        $display("PASS tb_iter_param_banks");
        $finish;
    end
endmodule
