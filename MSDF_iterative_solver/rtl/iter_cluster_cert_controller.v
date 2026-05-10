`timescale 1ns / 1ps

// Minimal iteration controller for cluster-level certification results.
//
// This controller does not schedule matrix streaming or state ping-pong yet.
// It only closes the first control loop:
//
//   cluster cert results -> iteration done / converged / continue
//
// Expected use:
// - pulse i_start_iter to clear state for a new iteration
// - each cluster asserts its valid bit for one cycle when its certification
//   result is ready
// - the controller latches which clusters have reported and whether they
//   certified
// - once all clusters have reported, it emits one-cycle done/converged/continue
//   outputs

module iter_cluster_cert_controller #(
    parameter integer num_clusters = 2,
    // When enabled, expose the final all-cluster decision combinationally in the
    // same cycle that the last cluster_valid arrives.  The registered masks are
    // still updated on the next clock; the output masks are bypassed with the
    // current valid bits so external control can safely observe done/seen/cert
    // together.
    parameter integer fast_done = 1
) (
    input                           i_clk,
    input                           i_rst,
    input                           i_start_iter,
    input      [num_clusters-1:0]   i_cluster_valid,
    input      [num_clusters-1:0]   i_cluster_certified,
    output                          o_iter_done,
    output                          o_iter_converged,
    output                          o_iter_continue,
    output     [num_clusters-1:0]   o_seen_mask,
    output     [num_clusters-1:0]   o_cert_mask
);

    reg  [num_clusters-1:0] r_seen_mask;
    reg  [num_clusters-1:0] r_cert_mask;
    reg                     r_iter_done;
    reg                     r_iter_converged;
    reg                     r_iter_continue;
    wire [num_clusters-1:0] w_seen_next;
    wire [num_clusters-1:0] w_cert_next;
    wire                    w_all_seen;
    wire                    w_all_cert;
    wire                    w_fast_done;
    reg                     r_iter_reported;

    assign w_seen_next = r_seen_mask | i_cluster_valid;
    assign w_cert_next = r_cert_mask | (i_cluster_valid & i_cluster_certified);
    assign w_all_seen = &w_seen_next;
    assign w_all_cert = &w_cert_next;
    assign w_fast_done = (fast_done != 0) && !i_start_iter && w_all_seen && !r_iter_reported;

    assign o_iter_done = (fast_done != 0) ? w_fast_done : r_iter_done;
    assign o_iter_converged = (fast_done != 0) ? (w_fast_done && w_all_cert) : r_iter_converged;
    assign o_iter_continue = (fast_done != 0) ? (w_fast_done && !w_all_cert) : r_iter_continue;
    assign o_seen_mask = ((fast_done != 0) && !i_start_iter && !r_iter_reported)
        ? w_seen_next : r_seen_mask;
    assign o_cert_mask = ((fast_done != 0) && !i_start_iter && !r_iter_reported)
        ? w_cert_next : r_cert_mask;

    always @(posedge i_clk) begin
        if (i_rst) begin
            r_seen_mask <= {num_clusters{1'b0}};
            r_cert_mask <= {num_clusters{1'b0}};
            r_iter_done <= 1'b0;
            r_iter_converged <= 1'b0;
            r_iter_continue <= 1'b0;
            r_iter_reported <= 1'b0;
        end else begin
            r_iter_done <= 1'b0;
            r_iter_converged <= 1'b0;
            r_iter_continue <= 1'b0;

            if (i_start_iter) begin
                r_seen_mask <= {num_clusters{1'b0}};
                r_cert_mask <= {num_clusters{1'b0}};
                r_iter_reported <= 1'b0;
            end else begin
                r_seen_mask <= w_seen_next;
                r_cert_mask <= w_cert_next;

                if (w_all_seen && !r_iter_reported) begin
                    r_iter_done <= 1'b1;
                    r_iter_reported <= 1'b1;
                    if (w_all_cert) begin
                        r_iter_converged <= 1'b1;
                    end else begin
                        r_iter_continue <= 1'b1;
                    end
                end
            end
        end
    end

endmodule
