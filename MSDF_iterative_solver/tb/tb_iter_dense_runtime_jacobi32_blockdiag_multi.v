`timescale 1ns / 1ps

`ifdef PAGERANK32_GLOBAL
`ifdef PAGERANK32_PRIOR_FRACTIONAL
`define JACOBI32_TEMPLATE_MEMH "MSDF_iterative_solver/generated/rtl_vectors/pagerank32_global_prior_fractional/templates.memh"
`define JACOBI32_CERT_MEMH "MSDF_iterative_solver/generated/rtl_vectors/pagerank32_global_prior_fractional/cert_params.memh"
`define JACOBI32_GOLD_STATE_P_MEMH "MSDF_iterative_solver/generated/rtl_vectors/pagerank32_global_prior_fractional/gold_state_p_iters.memh"
`define JACOBI32_GOLD_STATE_N_MEMH "MSDF_iterative_solver/generated/rtl_vectors/pagerank32_global_prior_fractional/gold_state_n_iters.memh"
`define JACOBI32_GOLD_MAX_ERROR_MEMH "MSDF_iterative_solver/generated/rtl_vectors/pagerank32_global_prior_fractional/gold_max_error_iters.memh"
`define JACOBI32_GOLD_CERTIFIED_MEMH "MSDF_iterative_solver/generated/rtl_vectors/pagerank32_global_prior_fractional/gold_certified_iters.memh"
`define JACOBI32_GOLD_CONVERGED_MEMH "MSDF_iterative_solver/generated/rtl_vectors/pagerank32_global_prior_fractional/gold_iter_converged.memh"
`define JACOBI32_GOLD_CONTINUE_MEMH "MSDF_iterative_solver/generated/rtl_vectors/pagerank32_global_prior_fractional/gold_iter_continue.memh"
`else
`define JACOBI32_TEMPLATE_MEMH "MSDF_iterative_solver/generated/rtl_vectors/pagerank32_global_full_digit/templates.memh"
`define JACOBI32_CERT_MEMH "MSDF_iterative_solver/generated/rtl_vectors/pagerank32_global_full_digit/cert_params.memh"
`define JACOBI32_GOLD_STATE_P_MEMH "MSDF_iterative_solver/generated/rtl_vectors/pagerank32_global_full_digit/gold_state_p_iters.memh"
`define JACOBI32_GOLD_STATE_N_MEMH "MSDF_iterative_solver/generated/rtl_vectors/pagerank32_global_full_digit/gold_state_n_iters.memh"
`define JACOBI32_GOLD_MAX_ERROR_MEMH "MSDF_iterative_solver/generated/rtl_vectors/pagerank32_global_full_digit/gold_max_error_iters.memh"
`define JACOBI32_GOLD_CERTIFIED_MEMH "MSDF_iterative_solver/generated/rtl_vectors/pagerank32_global_full_digit/gold_certified_iters.memh"
`define JACOBI32_GOLD_CONVERGED_MEMH "MSDF_iterative_solver/generated/rtl_vectors/pagerank32_global_full_digit/gold_iter_converged.memh"
`define JACOBI32_GOLD_CONTINUE_MEMH "MSDF_iterative_solver/generated/rtl_vectors/pagerank32_global_full_digit/gold_iter_continue.memh"
`endif
`define JACOBI32_GLOBAL
`define JACOBI32_SIGNED_DIGIT_STATE_COMPARE
`define PAGERANK32_L1_CERT
`ifdef PAGERANK32_CONV_RUNTIME
`define JACOBI32_CONV_RUNTIME
`ifdef PAGERANK32_PRIOR_FRACTIONAL
`define JACOBI32_COUNTER_LABEL "pagerank32_global_conv_fractional_multi"
`define JACOBI32_PASS_LABEL "tb_iter_dense_runtime_pagerank32_global_conv_fractional_multi"
module tb_iter_dense_runtime_pagerank32_global_conv_fractional_multi;
`else
`define JACOBI32_COUNTER_LABEL "pagerank32_global_conv_multi"
`define JACOBI32_PASS_LABEL "tb_iter_dense_runtime_pagerank32_global_conv_multi"
module tb_iter_dense_runtime_pagerank32_global_conv_multi;
`endif
`elsif PAGERANK32_SOLVER_NATIVE_RUNTIME
`define JACOBI32_SOLVER_NATIVE_RUNTIME
`define JACOBI32_COUNTER_LABEL "pagerank32_global_solver_native_multi"
`define JACOBI32_PASS_LABEL "tb_iter_dense_runtime_pagerank32_global_solver_native_multi"
module tb_iter_dense_runtime_pagerank32_global_solver_native_multi;
`elsif PAGERANK32_WAVEFRONT_RUNTIME
`define JACOBI32_WAVEFRONT_RUNTIME
`define JACOBI32_COUNTER_LABEL "pagerank32_global_wavefront_superstep"
`define JACOBI32_PASS_LABEL "tb_iter_dense_runtime_pagerank32_global_wavefront_superstep"
module tb_iter_dense_runtime_pagerank32_global_wavefront_superstep;
`elsif PAGERANK32_PRIOR_RUNTIME
`define JACOBI32_PRIOR_RUNTIME
`ifdef PAGERANK32_PRIOR_FRACTIONAL
`define JACOBI32_COUNTER_LABEL "pagerank32_global_prior_fractional_multi"
`define JACOBI32_PASS_LABEL "tb_iter_dense_runtime_pagerank32_global_prior_fractional_multi"
module tb_iter_dense_runtime_pagerank32_global_prior_fractional_multi;
`else
`define JACOBI32_COUNTER_LABEL "pagerank32_global_prior_online_multi"
`define JACOBI32_PASS_LABEL "tb_iter_dense_runtime_pagerank32_global_prior_online_multi"
module tb_iter_dense_runtime_pagerank32_global_prior_online_multi;
`endif
`elsif PAGERANK32_PRIOR_DIGIT_STREAM_RUNTIME
`define JACOBI32_PRIOR_DIGIT_STREAM_RUNTIME
`define JACOBI32_COUNTER_LABEL "pagerank32_global_prior_digit_stream_fractional_multi"
`define JACOBI32_PASS_LABEL "tb_iter_dense_runtime_pagerank32_global_prior_digit_stream_fractional_multi"
module tb_iter_dense_runtime_pagerank32_global_prior_digit_stream_fractional_multi;
`elsif PAGERANK32_PRIOR_WAVEFRONT_RUNTIME
`define JACOBI32_PRIOR_WAVEFRONT_RUNTIME
`define JACOBI32_COUNTER_LABEL "pagerank32_global_prior_wavefront_fractional"
`define JACOBI32_PASS_LABEL "tb_iter_dense_runtime_pagerank32_global_prior_wavefront_fractional"
module tb_iter_dense_runtime_pagerank32_global_prior_wavefront_fractional;
`else
`define JACOBI32_FULL_DIGIT_RUNTIME
`ifdef PAGERANK32_PRIOR_FRACTIONAL
`define JACOBI32_COUNTER_LABEL "pagerank32_global_full_digit_fractional_multi"
`define JACOBI32_PASS_LABEL "tb_iter_dense_runtime_pagerank32_global_full_digit_fractional_multi"
module tb_iter_dense_runtime_pagerank32_global_full_digit_fractional_multi;
`else
`define JACOBI32_COUNTER_LABEL "pagerank32_global_full_digit_multi"
`define JACOBI32_PASS_LABEL "tb_iter_dense_runtime_pagerank32_global_full_digit_multi"
module tb_iter_dense_runtime_pagerank32_global_full_digit_multi;
`endif
`endif
`else
`ifdef JACOBI32_HALO
`ifdef JACOBI32_FULL_DIGIT_RUNTIME
`define JACOBI32_TEMPLATE_MEMH "MSDF_iterative_solver/generated/rtl_vectors/jacobi32_halo_conv/templates.memh"
`define JACOBI32_CERT_MEMH "MSDF_iterative_solver/generated/rtl_vectors/jacobi32_halo_conv/cert_params.memh"
`define JACOBI32_GOLD_STATE_P_MEMH "MSDF_iterative_solver/generated/rtl_vectors/jacobi32_halo_conv/gold_state_p_iters.memh"
`define JACOBI32_GOLD_STATE_N_MEMH "MSDF_iterative_solver/generated/rtl_vectors/jacobi32_halo_conv/gold_state_n_iters.memh"
`define JACOBI32_GOLD_MAX_ERROR_MEMH "MSDF_iterative_solver/generated/rtl_vectors/jacobi32_halo_conv/gold_max_error_iters.memh"
`define JACOBI32_GOLD_CERTIFIED_MEMH "MSDF_iterative_solver/generated/rtl_vectors/jacobi32_halo_conv/gold_certified_iters.memh"
`define JACOBI32_GOLD_CONVERGED_MEMH "MSDF_iterative_solver/generated/rtl_vectors/jacobi32_halo_conv/gold_iter_converged.memh"
`define JACOBI32_GOLD_CONTINUE_MEMH "MSDF_iterative_solver/generated/rtl_vectors/jacobi32_halo_conv/gold_iter_continue.memh"
`ifdef JACOBI32_PREFIX_GATING
`define JACOBI32_COUNTER_LABEL "jacobi32_halo_reg_full_digit_prefix_multi"
`define JACOBI32_PASS_LABEL "tb_iter_dense_runtime_jacobi32_halo_reg_full_digit_prefix_multi"
module tb_iter_dense_runtime_jacobi32_halo_reg_full_digit_prefix_multi;
`else
`define JACOBI32_COUNTER_LABEL "jacobi32_halo_reg_full_digit_multi"
`define JACOBI32_PASS_LABEL "tb_iter_dense_runtime_jacobi32_halo_reg_full_digit_multi"
module tb_iter_dense_runtime_jacobi32_halo_reg_full_digit_multi;
`endif
`elsif JACOBI32_CONV_RUNTIME
`define JACOBI32_TEMPLATE_MEMH "MSDF_iterative_solver/generated/rtl_vectors/jacobi32_halo_conv/templates.memh"
`define JACOBI32_CERT_MEMH "MSDF_iterative_solver/generated/rtl_vectors/jacobi32_halo_conv/cert_params.memh"
`define JACOBI32_GOLD_STATE_P_MEMH "MSDF_iterative_solver/generated/rtl_vectors/jacobi32_halo_conv/gold_state_p_iters.memh"
`define JACOBI32_GOLD_STATE_N_MEMH "MSDF_iterative_solver/generated/rtl_vectors/jacobi32_halo_conv/gold_state_n_iters.memh"
`define JACOBI32_GOLD_MAX_ERROR_MEMH "MSDF_iterative_solver/generated/rtl_vectors/jacobi32_halo_conv/gold_max_error_iters.memh"
`define JACOBI32_GOLD_CERTIFIED_MEMH "MSDF_iterative_solver/generated/rtl_vectors/jacobi32_halo_conv/gold_certified_iters.memh"
`define JACOBI32_GOLD_CONVERGED_MEMH "MSDF_iterative_solver/generated/rtl_vectors/jacobi32_halo_conv/gold_iter_converged.memh"
`define JACOBI32_GOLD_CONTINUE_MEMH "MSDF_iterative_solver/generated/rtl_vectors/jacobi32_halo_conv/gold_iter_continue.memh"
`define JACOBI32_COUNTER_LABEL "jacobi32_halo_reg_conv_multi"
`define JACOBI32_PASS_LABEL "tb_iter_dense_runtime_jacobi32_halo_reg_conv_multi"
module tb_iter_dense_runtime_jacobi32_halo_reg_conv_multi;
`elsif JACOBI32_WAVEFRONT_RUNTIME
`define JACOBI32_TEMPLATE_MEMH "MSDF_iterative_solver/generated/rtl_vectors/jacobi32_halo_conv_f2/templates.memh"
`define JACOBI32_CERT_MEMH "MSDF_iterative_solver/generated/rtl_vectors/jacobi32_halo_conv_f2/cert_params.memh"
`define JACOBI32_GOLD_STATE_P_MEMH "MSDF_iterative_solver/generated/rtl_vectors/jacobi32_halo_conv_f2/gold_state_p_iters.memh"
`define JACOBI32_GOLD_STATE_N_MEMH "MSDF_iterative_solver/generated/rtl_vectors/jacobi32_halo_conv_f2/gold_state_n_iters.memh"
`define JACOBI32_GOLD_MAX_ERROR_MEMH "MSDF_iterative_solver/generated/rtl_vectors/jacobi32_halo_conv_f2/gold_max_error_iters.memh"
`define JACOBI32_GOLD_CERTIFIED_MEMH "MSDF_iterative_solver/generated/rtl_vectors/jacobi32_halo_conv_f2/gold_certified_iters.memh"
`define JACOBI32_GOLD_CONVERGED_MEMH "MSDF_iterative_solver/generated/rtl_vectors/jacobi32_halo_conv_f2/gold_iter_converged.memh"
`define JACOBI32_GOLD_CONTINUE_MEMH "MSDF_iterative_solver/generated/rtl_vectors/jacobi32_halo_conv_f2/gold_iter_continue.memh"
`ifdef JACOBI32_HALO_REG
`define JACOBI32_COUNTER_LABEL "jacobi32_halo_reg_wavefront_superstep"
`define JACOBI32_PASS_LABEL "tb_iter_dense_runtime_jacobi32_halo_reg_wavefront_superstep"
module tb_iter_dense_runtime_jacobi32_halo_reg_wavefront_superstep;
`else
`define JACOBI32_COUNTER_LABEL "jacobi32_halo_wavefront_superstep"
`define JACOBI32_PASS_LABEL "tb_iter_dense_runtime_jacobi32_halo_wavefront_superstep"
module tb_iter_dense_runtime_jacobi32_halo_wavefront_superstep;
`endif
`define JACOBI32_SIGNED_DIGIT_STATE_COMPARE
`elsif JACOBI32_SOLVER_NATIVE_RUNTIME
`define JACOBI32_TEMPLATE_MEMH "MSDF_iterative_solver/generated/rtl_vectors/jacobi32_halo_conv_f2/templates.memh"
`define JACOBI32_CERT_MEMH "MSDF_iterative_solver/generated/rtl_vectors/jacobi32_halo_conv_f2/cert_params.memh"
`define JACOBI32_GOLD_STATE_P_MEMH "MSDF_iterative_solver/generated/rtl_vectors/jacobi32_halo_conv_f2/gold_state_p_iters.memh"
`define JACOBI32_GOLD_STATE_N_MEMH "MSDF_iterative_solver/generated/rtl_vectors/jacobi32_halo_conv_f2/gold_state_n_iters.memh"
`define JACOBI32_GOLD_MAX_ERROR_MEMH "MSDF_iterative_solver/generated/rtl_vectors/jacobi32_halo_conv_f2/gold_max_error_iters.memh"
`define JACOBI32_GOLD_CERTIFIED_MEMH "MSDF_iterative_solver/generated/rtl_vectors/jacobi32_halo_conv_f2/gold_certified_iters.memh"
`define JACOBI32_GOLD_CONVERGED_MEMH "MSDF_iterative_solver/generated/rtl_vectors/jacobi32_halo_conv_f2/gold_iter_converged.memh"
`define JACOBI32_GOLD_CONTINUE_MEMH "MSDF_iterative_solver/generated/rtl_vectors/jacobi32_halo_conv_f2/gold_iter_continue.memh"
`ifdef JACOBI32_FOUR_ITER_COMPARE
`define JACOBI32_COUNTER_LABEL "jacobi32_halo_reg_solver_native_four"
`define JACOBI32_PASS_LABEL "tb_iter_dense_runtime_jacobi32_halo_reg_solver_native_four"
module tb_iter_dense_runtime_jacobi32_halo_reg_solver_native_four;
`else
`define JACOBI32_COUNTER_LABEL "jacobi32_halo_reg_solver_native_multi"
`define JACOBI32_PASS_LABEL "tb_iter_dense_runtime_jacobi32_halo_reg_solver_native_multi"
module tb_iter_dense_runtime_jacobi32_halo_reg_solver_native_multi;
`endif
`else
`define JACOBI32_TEMPLATE_MEMH "MSDF_iterative_solver/generated/rtl_vectors/jacobi32_halo/templates.memh"
`define JACOBI32_CERT_MEMH "MSDF_iterative_solver/generated/rtl_vectors/jacobi32_halo/cert_params.memh"
`define JACOBI32_GOLD_STATE_P_MEMH "MSDF_iterative_solver/generated/rtl_vectors/jacobi32_halo/gold_state_p_iters.memh"
`define JACOBI32_GOLD_STATE_N_MEMH "MSDF_iterative_solver/generated/rtl_vectors/jacobi32_halo/gold_state_n_iters.memh"
`define JACOBI32_GOLD_MAX_ERROR_MEMH "MSDF_iterative_solver/generated/rtl_vectors/jacobi32_halo/gold_max_error_iters.memh"
`define JACOBI32_GOLD_CERTIFIED_MEMH "MSDF_iterative_solver/generated/rtl_vectors/jacobi32_halo/gold_certified_iters.memh"
`define JACOBI32_GOLD_CONVERGED_MEMH "MSDF_iterative_solver/generated/rtl_vectors/jacobi32_halo/gold_iter_converged.memh"
`define JACOBI32_GOLD_CONTINUE_MEMH "MSDF_iterative_solver/generated/rtl_vectors/jacobi32_halo/gold_iter_continue.memh"
`ifdef JACOBI32_HALO_REG
`ifdef JACOBI32_CERT_CMPIPE
`ifdef JACOBI32_CERT_OPIPE
`define JACOBI32_COUNTER_LABEL "jacobi32_halo_reg_opipe_cmpipe_multi"
`define JACOBI32_PASS_LABEL "tb_iter_dense_runtime_jacobi32_halo_reg_opipe_cmpipe_multi"
module tb_iter_dense_runtime_jacobi32_halo_reg_opipe_cmpipe_multi;
`else
`define JACOBI32_COUNTER_LABEL "jacobi32_halo_reg_cmpipe_multi"
`define JACOBI32_PASS_LABEL "tb_iter_dense_runtime_jacobi32_halo_reg_cmpipe_multi"
module tb_iter_dense_runtime_jacobi32_halo_reg_cmpipe_multi;
`endif
`elsif JACOBI32_CERT_PIPE
`ifdef JACOBI32_CERT_OPIPE
`define JACOBI32_COUNTER_LABEL "jacobi32_halo_reg_cpipe_opipe_multi"
`define JACOBI32_PASS_LABEL "tb_iter_dense_runtime_jacobi32_halo_reg_cpipe_opipe_multi"
module tb_iter_dense_runtime_jacobi32_halo_reg_cpipe_opipe_multi;
`else
`define JACOBI32_COUNTER_LABEL "jacobi32_halo_reg_cpipe_multi"
`define JACOBI32_PASS_LABEL "tb_iter_dense_runtime_jacobi32_halo_reg_cpipe_multi"
module tb_iter_dense_runtime_jacobi32_halo_reg_cpipe_multi;
`endif
`elsif JACOBI32_CERT_OPIPE
`define JACOBI32_COUNTER_LABEL "jacobi32_halo_reg_opipe_multi"
`define JACOBI32_PASS_LABEL "tb_iter_dense_runtime_jacobi32_halo_reg_opipe_multi"
module tb_iter_dense_runtime_jacobi32_halo_reg_opipe_multi;
`elsif JACOBI32_STENCIL_HALO_R1
`define JACOBI32_COUNTER_LABEL "jacobi32_halo_reg_stencil_r1_multi"
`define JACOBI32_PASS_LABEL "tb_iter_dense_runtime_jacobi32_halo_reg_stencil_r1_multi"
module tb_iter_dense_runtime_jacobi32_halo_reg_stencil_r1_multi;
`else
`define JACOBI32_COUNTER_LABEL "jacobi32_halo_reg_multi"
`define JACOBI32_PASS_LABEL "tb_iter_dense_runtime_jacobi32_halo_reg_multi"
module tb_iter_dense_runtime_jacobi32_halo_reg_multi;
`endif
`else
`define JACOBI32_COUNTER_LABEL "jacobi32_halo_multi"
`define JACOBI32_PASS_LABEL "tb_iter_dense_runtime_jacobi32_halo_multi"
module tb_iter_dense_runtime_jacobi32_halo_multi;
`endif
`endif
`elsif JACOBI32_GLOBAL
`define JACOBI32_TEMPLATE_MEMH "MSDF_iterative_solver/generated/rtl_vectors/jacobi32_global/templates.memh"
`define JACOBI32_CERT_MEMH "MSDF_iterative_solver/generated/rtl_vectors/jacobi32_global/cert_params.memh"
`define JACOBI32_GOLD_STATE_P_MEMH "MSDF_iterative_solver/generated/rtl_vectors/jacobi32_global/gold_state_p_iters.memh"
`define JACOBI32_GOLD_STATE_N_MEMH "MSDF_iterative_solver/generated/rtl_vectors/jacobi32_global/gold_state_n_iters.memh"
`define JACOBI32_GOLD_MAX_ERROR_MEMH "MSDF_iterative_solver/generated/rtl_vectors/jacobi32_global/gold_max_error_iters.memh"
`define JACOBI32_GOLD_CERTIFIED_MEMH "MSDF_iterative_solver/generated/rtl_vectors/jacobi32_global/gold_certified_iters.memh"
`define JACOBI32_GOLD_CONVERGED_MEMH "MSDF_iterative_solver/generated/rtl_vectors/jacobi32_global/gold_iter_converged.memh"
`define JACOBI32_GOLD_CONTINUE_MEMH "MSDF_iterative_solver/generated/rtl_vectors/jacobi32_global/gold_iter_continue.memh"
`define JACOBI32_COUNTER_LABEL "jacobi32_global_multi"
`define JACOBI32_PASS_LABEL "tb_iter_dense_runtime_jacobi32_global_multi"
module tb_iter_dense_runtime_jacobi32_global_multi;
`else
`ifdef JACOBI32_WAVEFRONT_RUNTIME
`define JACOBI32_TEMPLATE_MEMH "MSDF_iterative_solver/generated/rtl_vectors/jacobi32_blockdiag_full_digit_f4/templates.memh"
`define JACOBI32_CERT_MEMH "MSDF_iterative_solver/generated/rtl_vectors/jacobi32_blockdiag_full_digit_f4/cert_params.memh"
`define JACOBI32_GOLD_STATE_P_MEMH "MSDF_iterative_solver/generated/rtl_vectors/jacobi32_blockdiag_full_digit_f4/gold_state_p_iters.memh"
`define JACOBI32_GOLD_STATE_N_MEMH "MSDF_iterative_solver/generated/rtl_vectors/jacobi32_blockdiag_full_digit_f4/gold_state_n_iters.memh"
`define JACOBI32_GOLD_MAX_ERROR_MEMH "MSDF_iterative_solver/generated/rtl_vectors/jacobi32_blockdiag_full_digit_f4/gold_max_error_iters.memh"
`define JACOBI32_GOLD_CERTIFIED_MEMH "MSDF_iterative_solver/generated/rtl_vectors/jacobi32_blockdiag_full_digit_f4/gold_certified_iters.memh"
`define JACOBI32_GOLD_CONVERGED_MEMH "MSDF_iterative_solver/generated/rtl_vectors/jacobi32_blockdiag_full_digit_f4/gold_iter_converged.memh"
`define JACOBI32_GOLD_CONTINUE_MEMH "MSDF_iterative_solver/generated/rtl_vectors/jacobi32_blockdiag_full_digit_f4/gold_iter_continue.memh"
`define JACOBI32_COUNTER_LABEL "jacobi32_blockdiag_wavefront_superstep"
`define JACOBI32_PASS_LABEL "tb_iter_dense_runtime_jacobi32_blockdiag_wavefront_superstep"
`define JACOBI32_SIGNED_DIGIT_STATE_COMPARE
module tb_iter_dense_runtime_jacobi32_blockdiag_wavefront_superstep;
`elsif JACOBI32_SOLVER_NATIVE_RUNTIME
`define JACOBI32_TEMPLATE_MEMH "MSDF_iterative_solver/generated/rtl_vectors/jacobi32_blockdiag_full_digit_f4/templates.memh"
`define JACOBI32_CERT_MEMH "MSDF_iterative_solver/generated/rtl_vectors/jacobi32_blockdiag_full_digit_f4/cert_params.memh"
`define JACOBI32_GOLD_STATE_P_MEMH "MSDF_iterative_solver/generated/rtl_vectors/jacobi32_blockdiag_full_digit_f4/gold_state_p_iters.memh"
`define JACOBI32_GOLD_STATE_N_MEMH "MSDF_iterative_solver/generated/rtl_vectors/jacobi32_blockdiag_full_digit_f4/gold_state_n_iters.memh"
`define JACOBI32_GOLD_MAX_ERROR_MEMH "MSDF_iterative_solver/generated/rtl_vectors/jacobi32_blockdiag_full_digit_f4/gold_max_error_iters.memh"
`define JACOBI32_GOLD_CERTIFIED_MEMH "MSDF_iterative_solver/generated/rtl_vectors/jacobi32_blockdiag_full_digit_f4/gold_certified_iters.memh"
`define JACOBI32_GOLD_CONVERGED_MEMH "MSDF_iterative_solver/generated/rtl_vectors/jacobi32_blockdiag_full_digit_f4/gold_iter_converged.memh"
`define JACOBI32_GOLD_CONTINUE_MEMH "MSDF_iterative_solver/generated/rtl_vectors/jacobi32_blockdiag_full_digit_f4/gold_iter_continue.memh"
`define JACOBI32_COUNTER_LABEL "jacobi32_blockdiag_solver_native_multi"
`define JACOBI32_PASS_LABEL "tb_iter_dense_runtime_jacobi32_blockdiag_solver_native_multi"
`define JACOBI32_SIGNED_DIGIT_STATE_COMPARE
module tb_iter_dense_runtime_jacobi32_blockdiag_solver_native_multi;
`else
`define JACOBI32_TEMPLATE_MEMH "MSDF_iterative_solver/generated/rtl_vectors/jacobi32_blockdiag_multi/templates.memh"
`define JACOBI32_CERT_MEMH "MSDF_iterative_solver/generated/rtl_vectors/jacobi32_blockdiag_multi/cert_params.memh"
`define JACOBI32_GOLD_STATE_P_MEMH "MSDF_iterative_solver/generated/rtl_vectors/jacobi32_blockdiag_multi/gold_state_p_iters.memh"
`define JACOBI32_GOLD_STATE_N_MEMH "MSDF_iterative_solver/generated/rtl_vectors/jacobi32_blockdiag_multi/gold_state_n_iters.memh"
`define JACOBI32_GOLD_MAX_ERROR_MEMH "MSDF_iterative_solver/generated/rtl_vectors/jacobi32_blockdiag_multi/gold_max_error_iters.memh"
`define JACOBI32_GOLD_CERTIFIED_MEMH "MSDF_iterative_solver/generated/rtl_vectors/jacobi32_blockdiag_multi/gold_certified_iters.memh"
`define JACOBI32_GOLD_CONVERGED_MEMH "MSDF_iterative_solver/generated/rtl_vectors/jacobi32_blockdiag_multi/gold_iter_converged.memh"
`define JACOBI32_GOLD_CONTINUE_MEMH "MSDF_iterative_solver/generated/rtl_vectors/jacobi32_blockdiag_multi/gold_iter_continue.memh"
`define JACOBI32_COUNTER_LABEL "jacobi32_blockdiag_multi"
`define JACOBI32_PASS_LABEL "tb_iter_dense_runtime_jacobi32_blockdiag_multi"
module tb_iter_dense_runtime_jacobi32_blockdiag_multi;
`endif
`endif
`endif
    localparam integer NUM_TOTAL_CLUSTERS = 8;
    localparam integer NUM_CLUSTERS = 8;
    localparam integer NUM_ROWS = 4;
    localparam integer DEGREE = 4;
`ifdef WAVEFRONT_SUPERSTEP_STAGES_VALUE
    localparam integer WAVEFRONT_SUPERSTEP_STAGES = `WAVEFRONT_SUPERSTEP_STAGES_VALUE;
`else
    localparam integer WAVEFRONT_SUPERSTEP_STAGES = 4;
`endif
`ifdef JACOBI32_WAVEFRONT_RUNTIME
    localparam integer NUM_ITERS = 1;
`ifdef JACOBI32_NUM_GOLD_ITERS_VALUE
    localparam integer NUM_GOLD_ITERS = `JACOBI32_NUM_GOLD_ITERS_VALUE;
`else
    localparam integer NUM_GOLD_ITERS = 6;
`endif
`elsif JACOBI32_PRIOR_WAVEFRONT_RUNTIME
    localparam integer NUM_ITERS = 1;
`ifdef JACOBI32_NUM_GOLD_ITERS_VALUE
    localparam integer NUM_GOLD_ITERS = `JACOBI32_NUM_GOLD_ITERS_VALUE;
`else
    localparam integer NUM_GOLD_ITERS = 6;
`endif
`else
`ifdef JACOBI32_NUM_ITERS_VALUE
    localparam integer NUM_ITERS = `JACOBI32_NUM_ITERS_VALUE;
`else
    localparam integer NUM_ITERS = 6;
`endif
`ifdef JACOBI32_NUM_GOLD_ITERS_VALUE
    localparam integer NUM_GOLD_ITERS = `JACOBI32_NUM_GOLD_ITERS_VALUE;
`else
    localparam integer NUM_GOLD_ITERS = NUM_ITERS;
`endif
`endif
`ifdef JACOBI32_BIT_WIDTH_VALUE
    localparam integer BIT_WIDTH = `JACOBI32_BIT_WIDTH_VALUE;
`else
    localparam integer BIT_WIDTH = 8;
`endif
    localparam integer BOUND_WIDTH = BIT_WIDTH + 5;
`ifdef PAGERANK32_L1_CERT
    localparam integer BLOCK_SIZE = 1;
`else
    localparam integer BLOCK_SIZE = 2;
`endif
    localparam integer NUM_BLOCKS = (NUM_ROWS + BLOCK_SIZE - 1) / BLOCK_SIZE;
    localparam integer COEFF_WIDTH = 8;
    localparam integer ACC_WIDTH = 24;
    localparam integer DATA_WIDTH = BIT_WIDTH + 3;
`ifdef JACOBI32_CONV_PRODUCT_SHIFT_VALUE
    localparam integer CONV_PRODUCT_SHIFT = `JACOBI32_CONV_PRODUCT_SHIFT_VALUE;
`else
    localparam integer CONV_PRODUCT_SHIFT = 0;
`endif
`include "iter_tb_signed_digit_reconstruct.vh"
    localparam integer ROW_IDX_WIDTH = 2;
`ifdef JACOBI32_GLOBAL
    localparam integer SRC_IDX_WIDTH = 5;
    localparam integer GLOBAL_SOURCE_REPLAY = 1;
    localparam integer HALO_SOURCE_REPLAY = 0;
    localparam integer HALO_CLUSTER_RADIUS = 1;
`ifdef JACOBI32_GLOBAL_REG
    localparam integer HALO_REPLAY_OUTPUT_REGISTER = 1;
`else
    localparam integer HALO_REPLAY_OUTPUT_REGISTER = 0;
`endif
    localparam integer HALO_REPLAY_MODE = 0;
`elsif JACOBI32_HALO
    localparam integer SRC_IDX_WIDTH = 4;
    localparam integer GLOBAL_SOURCE_REPLAY = 0;
    localparam integer HALO_SOURCE_REPLAY = 1;
    localparam integer HALO_CLUSTER_RADIUS = 1;
`ifdef JACOBI32_HALO_REG
    localparam integer HALO_REPLAY_OUTPUT_REGISTER = 1;
`else
    localparam integer HALO_REPLAY_OUTPUT_REGISTER = 0;
`endif
`ifdef JACOBI32_STENCIL_HALO_R1
    localparam integer HALO_REPLAY_MODE = 1;
`else
    localparam integer HALO_REPLAY_MODE = 0;
`endif
`else
    localparam integer SRC_IDX_WIDTH = ROW_IDX_WIDTH;
    localparam integer GLOBAL_SOURCE_REPLAY = 0;
    localparam integer HALO_SOURCE_REPLAY = 0;
    localparam integer HALO_CLUSTER_RADIUS = 1;
    localparam integer HALO_REPLAY_OUTPUT_REGISTER = 0;
    localparam integer HALO_REPLAY_MODE = 0;
`endif
`ifdef JACOBI32_CERT_PIPE
    localparam integer CERT_PRODUCT_PIPELINE = 1;
`else
    localparam integer CERT_PRODUCT_PIPELINE = 0;
`endif
`ifdef JACOBI32_CERT_OPIPE
    localparam integer CERT_OPERAND_PIPELINE = 1;
`else
    localparam integer CERT_OPERAND_PIPELINE = 0;
`endif
`ifdef JACOBI32_CERT_CMPIPE
    localparam integer CERT_COMPARE_PIPELINE = 1;
`else
    localparam integer CERT_COMPARE_PIPELINE = 0;
`endif
`ifdef JACOBI32_FULL_DIGIT_RUNTIME
    localparam integer ROW_DATAPATH_MODE = 2;
    localparam integer CONV_MAC_PIPELINE = 0;
    localparam integer AUTO_FULL_DIGIT = 1;
`ifdef JACOBI32_PREFIX_GATING
    localparam integer AUTO_PREFIX_GATING = 1;
`else
    localparam integer AUTO_PREFIX_GATING = 0;
`endif
`elsif JACOBI32_CONV_RUNTIME
    localparam integer ROW_DATAPATH_MODE = 1;
    localparam integer CONV_MAC_PIPELINE = 1;
    localparam integer AUTO_FULL_DIGIT = 0;
    localparam integer AUTO_PREFIX_GATING = 0;
`elsif JACOBI32_SOLVER_NATIVE_RUNTIME
    localparam integer ROW_DATAPATH_MODE = 3;
    localparam integer CONV_MAC_PIPELINE = 0;
    localparam integer AUTO_FULL_DIGIT = 1;
    localparam integer AUTO_PREFIX_GATING = 0;
`elsif JACOBI32_WAVEFRONT_RUNTIME
    localparam integer ROW_DATAPATH_MODE = 4;
    localparam integer CONV_MAC_PIPELINE = 0;
    localparam integer AUTO_FULL_DIGIT = 1;
    localparam integer AUTO_PREFIX_GATING = 0;
`elsif JACOBI32_PRIOR_RUNTIME
    localparam integer ROW_DATAPATH_MODE = 5;
    localparam integer CONV_MAC_PIPELINE = 0;
    localparam integer AUTO_FULL_DIGIT = 0;
    localparam integer AUTO_PREFIX_GATING = 0;
`elsif JACOBI32_PRIOR_DIGIT_STREAM_RUNTIME
    localparam integer ROW_DATAPATH_MODE = 6;
    localparam integer CONV_MAC_PIPELINE = 0;
    localparam integer AUTO_FULL_DIGIT = 1;
    localparam integer AUTO_PREFIX_GATING = 0;
`elsif JACOBI32_PRIOR_WAVEFRONT_RUNTIME
    localparam integer ROW_DATAPATH_MODE = 7;
    localparam integer CONV_MAC_PIPELINE = 0;
    localparam integer AUTO_FULL_DIGIT = 1;
    localparam integer AUTO_PREFIX_GATING = 0;
`else
    localparam integer ROW_DATAPATH_MODE = 0;
    localparam integer CONV_MAC_PIPELINE = 0;
    localparam integer AUTO_FULL_DIGIT = 0;
    localparam integer AUTO_PREFIX_GATING = 0;
`endif
`ifdef JACOBI32_CONV_ROUND_PIPE
    localparam integer CONV_ROUND_PIPELINE = 1;
`else
    localparam integer CONV_ROUND_PIPELINE = 0;
`endif
`ifdef PAGERANK32_L1_CERT
    localparam integer GLOBAL_L1_CERT = 1;
`else
    localparam integer GLOBAL_L1_CERT = 0;
`endif
`ifdef PAGERANK32_PRIOR_FRACTIONAL_CAPTURE
    localparam integer PRIOR_CAPTURE_UNIT = 0;
`else
    localparam integer PRIOR_CAPTURE_UNIT = 1;
`endif
`ifndef SOLVER_NATIVE_SKIP_DIGITS_VALUE
`define SOLVER_NATIVE_SKIP_DIGITS_VALUE 4
`endif
`ifndef SOLVER_NATIVE_AFFINE_GUARD_SHIFT_VALUE
`define SOLVER_NATIVE_AFFINE_GUARD_SHIFT_VALUE 7
`endif
`ifndef SOLVER_NATIVE_SAMPLE_WIDTH_VALUE
`define SOLVER_NATIVE_SAMPLE_WIDTH_VALUE 5
`endif
    localparam integer SOLVER_NATIVE_SKIP_DIGITS = `SOLVER_NATIVE_SKIP_DIGITS_VALUE;
    localparam integer SOLVER_NATIVE_AFFINE_GUARD_SHIFT = `SOLVER_NATIVE_AFFINE_GUARD_SHIFT_VALUE;
    localparam integer SOLVER_NATIVE_SAMPLE_WIDTH = `SOLVER_NATIVE_SAMPLE_WIDTH_VALUE;
`ifdef PAGERANK32_PRIOR_TOLERANCE_VALUE
    localparam integer PRIOR_CHECK_TOLERANCE = `PAGERANK32_PRIOR_TOLERANCE_VALUE;
`else
    localparam integer PRIOR_CHECK_TOLERANCE = 0;
`endif
    localparam integer CLUSTER_ADDR_WIDTH = 3;
    localparam integer CLUSTER_SLOT_WIDTH = 3;
    localparam integer BIAS_WIDTH = BIT_WIDTH + 2;
    localparam integer VALID_WIDTH = NUM_ROWS * DEGREE;
    localparam integer SRC_WIDTH = NUM_ROWS * DEGREE * SRC_IDX_WIDTH;
    localparam integer COEFF_TERMS_WIDTH = NUM_ROWS * DEGREE * BIT_WIDTH;
    localparam integer BIAS_VEC_WIDTH = NUM_ROWS * BIAS_WIDTH;
    localparam integer TEMPLATE_PAYLOAD_WIDTH =
        VALID_WIDTH + SRC_WIDTH + 2 * COEFF_TERMS_WIDTH + 2 * BIAS_VEC_WIDTH;
    localparam integer BLOCK_WEIGHTS_WIDTH = NUM_ROWS * NUM_BLOCKS * COEFF_WIDTH;
    localparam integer CERT_PAYLOAD_WIDTH = BLOCK_WEIGHTS_WIDTH + ACC_WIDTH;
    localparam integer REPLAY_DIGIT_IDX = DATA_WIDTH - 1;

    reg i_clk;
    reg i_rst;
    reg i_cfg_template_we;
    reg i_cfg_cert_we;
    reg [CLUSTER_ADDR_WIDTH - 1 : 0] i_cfg_cluster_addr;
    reg [TEMPLATE_PAYLOAD_WIDTH - 1 : 0] i_cfg_template_word;
    reg [CERT_PAYLOAD_WIDTH - 1 : 0] i_cfg_cert_word;
    reg i_load_window;
    reg i_cfg_state_we;
    reg [CLUSTER_SLOT_WIDTH - 1 : 0] i_cfg_state_cluster_slot;
    reg i_cfg_state_bank_sel;
    reg [ROW_IDX_WIDTH - 1 : 0] i_cfg_state_row_idx;
    reg [DATA_WIDTH - 1 : 0] i_cfg_state_p;
    reg [DATA_WIDTH - 1 : 0] i_cfg_state_n;
    reg i_start_iter;
    reg i_commit_iter;
    reg [CLUSTER_ADDR_WIDTH - 1 : 0] i_base_cluster_idx;
    reg [NUM_CLUSTERS - 1 : 0] i_use_replay_clusters;
    reg [$clog2(DATA_WIDTH) - 1 : 0] i_replay_digit_idx;
    reg [NUM_CLUSTERS * NUM_ROWS - 1 : 0] i_issue_rows_clusters;
    reg [NUM_CLUSTERS * BOUND_WIDTH - 1 : 0] i_tail_bound_clusters;
    reg i_counter_clear;

    reg [TEMPLATE_PAYLOAD_WIDTH - 1 : 0] template_mem [0 : NUM_TOTAL_CLUSTERS - 1];
    reg [CERT_PAYLOAD_WIDTH - 1 : 0] cert_mem [0 : NUM_TOTAL_CLUSTERS - 1];
    reg [NUM_ROWS * DATA_WIDTH - 1 : 0] gold_state_p_mem [0 : NUM_GOLD_ITERS * NUM_CLUSTERS - 1];
    reg [NUM_ROWS * DATA_WIDTH - 1 : 0] gold_state_n_mem [0 : NUM_GOLD_ITERS * NUM_CLUSTERS - 1];
    reg [ACC_WIDTH - 1 : 0] gold_max_error_mem [0 : NUM_GOLD_ITERS * NUM_CLUSTERS - 1];
    reg [0 : 0] gold_certified_mem [0 : NUM_GOLD_ITERS * NUM_CLUSTERS - 1];
    reg [0 : 0] gold_iter_converged_mem [0 : NUM_GOLD_ITERS - 1];
    reg [0 : 0] gold_iter_continue_mem [0 : NUM_GOLD_ITERS - 1];

    reg [NUM_CLUSTERS * TEMPLATE_PAYLOAD_WIDTH - 1 : 0] expected_template_words;
    reg [NUM_CLUSTERS * CERT_PAYLOAD_WIDTH - 1 : 0] expected_cert_words;

    wire [NUM_CLUSTERS * TEMPLATE_PAYLOAD_WIDTH - 1 : 0] o_template_words_clusters;
    wire [NUM_CLUSTERS * CERT_PAYLOAD_WIDTH - 1 : 0] o_cert_param_words_clusters;
    wire [NUM_CLUSTERS * NUM_ROWS - 1 : 0] o_sched_row_active_clusters;
    wire [NUM_CLUSTERS - 1 : 0] o_cluster_valid;
    wire [NUM_CLUSTERS - 1 : 0] o_cluster_certified;
    wire [NUM_CLUSTERS * ACC_WIDTH - 1 : 0] o_cluster_max_error;
    wire [NUM_CLUSTERS * NUM_ROWS * DATA_WIDTH - 1 : 0] o_x_old_p_rows_clusters;
    wire [NUM_CLUSTERS * NUM_ROWS * DATA_WIDTH - 1 : 0] o_x_old_n_rows_clusters;
    wire [NUM_CLUSTERS - 1 : 0] o_read_bank_sel_clusters;
    wire o_window_valid;
    wire o_window_busy;
    wire [31 : 0] o_total_cycles;
    wire [31 : 0] o_issue_cycles;
    wire [31 : 0] o_cert_wait_cycles;
    wire [31 : 0] o_iter_count;
    wire [31 : 0] o_converged_iter;
    wire [31 : 0] o_cfg_template_write_count;
    wire [31 : 0] o_cfg_cert_write_count;
    wire [31 : 0] o_cfg_state_write_count;
    wire [31 : 0] o_window_load_count;
    wire [31 : 0] o_window_busy_cycles;
    wire [31 : 0] o_window_ready_cycles;
    wire [31 : 0] o_active_digit_cycles;
    wire [31 : 0] o_gated_digit_cycles;
    wire [31 : 0] o_cert_prefix_digit_sum;
    wire [31 : 0] o_certified_block_count;
    wire o_iter_done;
    wire o_iter_converged;
    wire o_iter_continue;
    wire [NUM_CLUSTERS - 1 : 0] o_seen_mask;

    iter_dense_small_runtime_top #(
        .num_total_clusters(NUM_TOTAL_CLUSTERS),
        .num_clusters(NUM_CLUSTERS),
        .num_rows(NUM_ROWS),
        .degree(DEGREE),
        .bit_width(BIT_WIDTH),
        .bound_width(BOUND_WIDTH),
        .coeff_width(COEFF_WIDTH),
        .acc_width(ACC_WIDTH),
        .block_size(BLOCK_SIZE),
        .num_blocks(NUM_BLOCKS),
        .data_width(DATA_WIDTH),
        .row_idx_width(ROW_IDX_WIDTH),
        .src_idx_width(SRC_IDX_WIDTH),
        .auto_full_digit(AUTO_FULL_DIGIT),
        .auto_prefix_gating(AUTO_PREFIX_GATING),
        .global_source_replay(GLOBAL_SOURCE_REPLAY),
        .halo_source_replay(HALO_SOURCE_REPLAY),
        .halo_cluster_radius(HALO_CLUSTER_RADIUS),
        .halo_replay_mode(HALO_REPLAY_MODE),
        .halo_replay_output_register(HALO_REPLAY_OUTPUT_REGISTER),
        .row_datapath_mode(ROW_DATAPATH_MODE),
        .mac_acc_width(32),
        .conv_mac_pipeline(CONV_MAC_PIPELINE),
        .conv_product_shift(CONV_PRODUCT_SHIFT),
        .conv_round_pipeline(CONV_ROUND_PIPELINE),
        .cert_product_pipeline(CERT_PRODUCT_PIPELINE),
        .cert_operand_pipeline(CERT_OPERAND_PIPELINE),
        .cert_compare_pipeline(CERT_COMPARE_PIPELINE),
        .global_l1_cert(GLOBAL_L1_CERT),
        .solver_native_skip_digits(SOLVER_NATIVE_SKIP_DIGITS),
        .solver_native_affine_guard_shift(SOLVER_NATIVE_AFFINE_GUARD_SHIFT),
        .solver_native_sample_width(SOLVER_NATIVE_SAMPLE_WIDTH),
        .wavefront_superstep_stages(WAVEFRONT_SUPERSTEP_STAGES),
        .prior_capture_unit(PRIOR_CAPTURE_UNIT),
        .cluster_addr_width(CLUSTER_ADDR_WIDTH),
        .cluster_slot_width(CLUSTER_SLOT_WIDTH),
        .runtime_mem_style(1)
    ) dut (
        .i_clk(i_clk),
        .i_rst(i_rst),
        .i_cfg_template_we(i_cfg_template_we),
        .i_cfg_cert_we(i_cfg_cert_we),
        .i_cfg_cluster_addr(i_cfg_cluster_addr),
        .i_cfg_template_word(i_cfg_template_word),
        .i_cfg_cert_word(i_cfg_cert_word),
        .i_load_window(i_load_window),
        .i_cfg_state_we(i_cfg_state_we),
        .i_cfg_state_cluster_slot(i_cfg_state_cluster_slot),
        .i_cfg_state_bank_sel(i_cfg_state_bank_sel),
        .i_cfg_state_row_idx(i_cfg_state_row_idx),
        .i_cfg_state_p(i_cfg_state_p),
        .i_cfg_state_n(i_cfg_state_n),
        .i_start_iter(i_start_iter),
        .i_commit_iter(i_commit_iter),
        .i_base_cluster_idx(i_base_cluster_idx),
        .i_use_replay_clusters(i_use_replay_clusters),
        .i_replay_digit_idx(i_replay_digit_idx),
        .i_issue_rows_clusters(i_issue_rows_clusters),
        .i_x0_p_rows_clusters({NUM_CLUSTERS * NUM_ROWS{1'b0}}),
        .i_x0_n_rows_clusters({NUM_CLUSTERS * NUM_ROWS{1'b0}}),
        .i_x1_p_rows_clusters({NUM_CLUSTERS * NUM_ROWS{1'b0}}),
        .i_x1_n_rows_clusters({NUM_CLUSTERS * NUM_ROWS{1'b0}}),
        .i_x2_p_rows_clusters({NUM_CLUSTERS * NUM_ROWS{1'b0}}),
        .i_x2_n_rows_clusters({NUM_CLUSTERS * NUM_ROWS{1'b0}}),
        .i_x3_p_rows_clusters({NUM_CLUSTERS * NUM_ROWS{1'b0}}),
        .i_x3_n_rows_clusters({NUM_CLUSTERS * NUM_ROWS{1'b0}}),
        .i_tail_bound_clusters(i_tail_bound_clusters),
        .i_counter_clear(i_counter_clear),
        .o_window_valid(o_window_valid),
        .o_window_busy(o_window_busy),
        .o_total_cycles(o_total_cycles),
        .o_issue_cycles(o_issue_cycles),
        .o_cert_wait_cycles(o_cert_wait_cycles),
        .o_iter_count(o_iter_count),
        .o_converged_iter(o_converged_iter),
        .o_cfg_template_write_count(o_cfg_template_write_count),
        .o_cfg_cert_write_count(o_cfg_cert_write_count),
        .o_cfg_state_write_count(o_cfg_state_write_count),
        .o_window_load_count(o_window_load_count),
        .o_window_busy_cycles(o_window_busy_cycles),
        .o_window_ready_cycles(o_window_ready_cycles),
        .o_active_digit_cycles(o_active_digit_cycles),
        .o_gated_digit_cycles(o_gated_digit_cycles),
        .o_cert_prefix_digit_sum(o_cert_prefix_digit_sum),
        .o_certified_block_count(o_certified_block_count),
        .o_template_words_clusters(o_template_words_clusters),
        .o_cert_param_words_clusters(o_cert_param_words_clusters),
        .o_sched_row_active_clusters(o_sched_row_active_clusters),
        .o_read_bank_sel_clusters(o_read_bank_sel_clusters),
        .o_drv_x0_p_rows_clusters(),
        .o_drv_x0_n_rows_clusters(),
        .o_drv_x1_p_rows_clusters(),
        .o_drv_x1_n_rows_clusters(),
        .o_drv_x2_p_rows_clusters(),
        .o_drv_x2_n_rows_clusters(),
        .o_drv_x3_p_rows_clusters(),
        .o_drv_x3_n_rows_clusters(),
        .o_cluster_valid(o_cluster_valid),
        .o_cluster_certified(o_cluster_certified),
        .o_cluster_max_error(o_cluster_max_error),
        .o_x_old_p_rows_clusters(o_x_old_p_rows_clusters),
        .o_x_old_n_rows_clusters(o_x_old_n_rows_clusters),
        .o_iter_done(o_iter_done),
        .o_iter_converged(o_iter_converged),
        .o_iter_continue(o_iter_continue),
        .o_seen_mask(o_seen_mask),
        .o_cert_mask()
    );

    always #5 i_clk = ~i_clk;

    task pack_expected_payloads;
        integer k;
        begin
            expected_template_words = {NUM_CLUSTERS * TEMPLATE_PAYLOAD_WIDTH{1'b0}};
            expected_cert_words = {NUM_CLUSTERS * CERT_PAYLOAD_WIDTH{1'b0}};
            for (k = 0; k < NUM_CLUSTERS; k = k + 1) begin
                expected_template_words[k * TEMPLATE_PAYLOAD_WIDTH +: TEMPLATE_PAYLOAD_WIDTH] = template_mem[k];
                expected_cert_words[k * CERT_PAYLOAD_WIDTH +: CERT_PAYLOAD_WIDTH] = cert_mem[k];
            end
        end
    endtask

    task cfg_write_cluster;
        input integer cluster_idx;
        begin
            @(negedge i_clk);
            i_cfg_cluster_addr <= cluster_idx[CLUSTER_ADDR_WIDTH - 1 : 0];
            i_cfg_template_word <= template_mem[cluster_idx];
            i_cfg_cert_word <= cert_mem[cluster_idx];
            i_cfg_template_we <= 1'b1;
            i_cfg_cert_we <= 1'b1;
            @(negedge i_clk);
            i_cfg_template_we <= 1'b0;
            i_cfg_cert_we <= 1'b0;
        end
    endtask

    task cfg_load_state;
        input integer cluster_slot;
        input [ROW_IDX_WIDTH - 1 : 0] row_idx;
        input [DATA_WIDTH - 1 : 0] state_p;
        input [DATA_WIDTH - 1 : 0] state_n;
        begin
            @(negedge i_clk);
            i_cfg_state_cluster_slot <= cluster_slot[CLUSTER_SLOT_WIDTH - 1 : 0];
            i_cfg_state_bank_sel <= 1'b0;
            i_cfg_state_row_idx <= row_idx;
            i_cfg_state_p <= state_p;
            i_cfg_state_n <= state_n;
            i_cfg_state_we <= 1'b1;
            @(negedge i_clk);
            i_cfg_state_we <= 1'b0;
            i_cfg_state_p <= {DATA_WIDTH{1'b0}};
            i_cfg_state_n <= {DATA_WIDTH{1'b0}};
        end
    endtask

    task load_window;
        integer wi;
        begin
            @(negedge i_clk);
            i_load_window <= 1'b1;
            @(negedge i_clk);
            i_load_window <= 1'b0;
            for (wi = 0; wi < 24; wi = wi + 1) begin
                @(posedge i_clk);
                if (o_window_valid) begin
                    wi = 24;
                end
            end
            if (!o_window_valid || o_window_busy) begin
                $display("ERROR multi window load did not finish");
                $fatal;
            end
        end
    endtask

    task pulse_start_iter;
        begin
            @(negedge i_clk);
            i_start_iter <= 1'b1;
            @(negedge i_clk);
            i_start_iter <= 1'b0;
        end
    endtask

    task pulse_commit_iter;
        begin
            @(negedge i_clk);
            i_commit_iter <= 1'b1;
            @(negedge i_clk);
            i_commit_iter <= 1'b0;
        end
    endtask

    task launch_once;
        begin
            @(posedge i_clk);
            i_issue_rows_clusters <= {NUM_CLUSTERS * NUM_ROWS{1'b1}};
            @(posedge i_clk);
            i_issue_rows_clusters <= {NUM_CLUSTERS * NUM_ROWS{1'b0}};
        end
    endtask

    integer ci;
    integer ri;
    integer iter_idx;
    integer check_iter_idx;
    integer cycles_waited;
    integer gold_idx;
    integer cert_wait_before;
    integer cert_wait_delta;
    integer expected_converged_count;
    integer expected_certified_block_count;
    integer expected_cert_prefix_digit_sum;
    integer expected_issue_cycles;
    integer expected_prefix_depth;
    integer conv_count_idx;
    reg [NUM_CLUSTERS - 1 : 0] expected_bank_sel;
    reg [DATA_WIDTH - 1 : 0] dut_state_p_word;
    reg [DATA_WIDTH - 1 : 0] dut_state_n_word;
    reg [DATA_WIDTH - 1 : 0] gold_state_p_word;
    reg [DATA_WIDTH - 1 : 0] gold_state_n_word;
    reg signed [31 : 0] dut_state_value;
    reg signed [31 : 0] gold_state_value;
    reg signed [31 : 0] compare_delta_value;
    reg [31 : 0] compare_abs_delta;

    task run_iteration;
        input integer iter_no;
        begin
`ifdef JACOBI32_WAVEFRONT_RUNTIME
            check_iter_idx = ((iter_no + 1) * WAVEFRONT_SUPERSTEP_STAGES) - 1;
`elsif JACOBI32_PRIOR_WAVEFRONT_RUNTIME
            check_iter_idx = ((iter_no + 1) * WAVEFRONT_SUPERSTEP_STAGES) - 1;
`else
            check_iter_idx = iter_no;
`endif
            cert_wait_before = o_cert_wait_cycles;
            i_use_replay_clusters <= {NUM_CLUSTERS{1'b1}};
            i_replay_digit_idx <= REPLAY_DIGIT_IDX[$clog2(DATA_WIDTH) - 1 : 0];

            pulse_start_iter();
            if (AUTO_FULL_DIGIT == 0) begin
                launch_once();
            end

            cycles_waited = 0;
            while (!o_iter_done && cycles_waited < 128) begin
                @(posedge i_clk);
                #1;
                cycles_waited = cycles_waited + 1;
            end
            if (!o_iter_done || o_seen_mask !== {NUM_CLUSTERS{1'b1}}) begin
                $display("ERROR multi iter=%0d did not finish seen=%b", iter_no, o_seen_mask);
                $fatal;
            end
`ifdef PAGERANK32_PRIOR_DEBUG_ACTUAL
            $display("DEBUG prior iter=%0d actual_maxerr0=%0d actual_cert0=%0d conv=%0d cont=%0d",
                iter_no,
                o_cluster_max_error[0 +: ACC_WIDTH],
                o_cluster_certified[0],
                o_iter_converged,
                o_iter_continue);
`ifdef PAGERANK32_PRIOR_FRACTIONAL
            $display("DEBUG prior cluster0 sum_p=%h sum_n=%h abs=%h",
                dut.core.gen_clusters[0].gen_prior_online_datapath.cluster_datapath.o_sum_p_rows,
                dut.core.gen_clusters[0].gen_prior_online_datapath.cluster_datapath.o_sum_n_rows,
                dut.core.gen_clusters[0].gen_prior_online_datapath.cluster_datapath.o_abs_upper_rows);
`endif
`endif
`ifndef PAGERANK32_PRIOR_RELAXED_CHECK
            if (o_iter_converged !== gold_iter_converged_mem[check_iter_idx][0] ||
                o_iter_continue !== gold_iter_continue_mem[check_iter_idx][0]) begin
                $display("ERROR multi iter decision iter=%0d conv=%0d/%0d cont=%0d/%0d",
                    iter_no,
                    o_iter_converged,
                    gold_iter_converged_mem[check_iter_idx][0],
                    o_iter_continue,
                    gold_iter_continue_mem[check_iter_idx][0]);
                $fatal;
            end
`endif

            for (ci = 0; ci < NUM_CLUSTERS; ci = ci + 1) begin
                gold_idx = check_iter_idx * NUM_CLUSTERS + ci;
`ifndef PAGERANK32_PRIOR_RELAXED_CHECK
`ifdef PAGERANK32_PRIOR_TOLERANT_CHECK
                compare_delta_value =
                    $signed({1'b0, o_cluster_max_error[ci * ACC_WIDTH +: ACC_WIDTH]}) -
                    $signed({1'b0, gold_max_error_mem[gold_idx]});
                compare_abs_delta = compare_delta_value[31]
                    ? (~compare_delta_value + 1'b1)
                    : compare_delta_value;
                if (compare_abs_delta > PRIOR_CHECK_TOLERANCE) begin
`else
                if (o_cluster_max_error[ci * ACC_WIDTH +: ACC_WIDTH] !== gold_max_error_mem[gold_idx]) begin
`endif
                    $display("ERROR multi max_error iter=%0d cluster=%0d got=%0d expected=%0d",
                        iter_no,
                        ci,
                        o_cluster_max_error[ci * ACC_WIDTH +: ACC_WIDTH],
                        gold_max_error_mem[gold_idx]);
                    $fatal;
                end
                if (o_cluster_certified[ci] !== gold_certified_mem[gold_idx][0]) begin
                    $display("ERROR multi certified iter=%0d cluster=%0d got=%0d expected=%0d",
                        iter_no,
                        ci,
                        o_cluster_certified[ci],
                        gold_certified_mem[gold_idx][0]);
                    $fatal;
                end
`endif
            end

            pulse_commit_iter();
            #1;
`ifdef PAGERANK32_PRIOR_DEBUG_ACTUAL
            $display("DEBUG prior iter=%0d actual_state0p=%h actual_state0n=%h bank=%b",
                iter_no,
                o_x_old_p_rows_clusters[0 +: NUM_ROWS * DATA_WIDTH],
                o_x_old_n_rows_clusters[0 +: NUM_ROWS * DATA_WIDTH],
                o_read_bank_sel_clusters);
`endif
`ifndef JACOBI32_SOLVER_NATIVE_RUNTIME
`ifndef JACOBI32_WAVEFRONT_RUNTIME
`ifndef JACOBI32_PRIOR_WAVEFRONT_RUNTIME
`ifndef JACOBI32_PRIOR_DIGIT_STREAM_RUNTIME
            expected_bank_sel = (iter_no[0]) ? {NUM_CLUSTERS{1'b0}} : {NUM_CLUSTERS{1'b1}};
            if (o_read_bank_sel_clusters !== expected_bank_sel) begin
                $display("ERROR multi read bank iter=%0d got=%b expected=%b",
                    iter_no, o_read_bank_sel_clusters, expected_bank_sel);
                $fatal;
            end
`endif
`endif
`endif
`endif

            for (ci = 0; ci < NUM_CLUSTERS; ci = ci + 1) begin
                gold_idx = check_iter_idx * NUM_CLUSTERS + ci;
`ifndef PAGERANK32_PRIOR_RELAXED_CHECK
`ifdef JACOBI32_SIGNED_DIGIT_STATE_COMPARE
                for (ri = 0; ri < NUM_ROWS; ri = ri + 1) begin
                    dut_state_p_word =
                        o_x_old_p_rows_clusters[ci * NUM_ROWS * DATA_WIDTH + ri * DATA_WIDTH +: DATA_WIDTH];
                    dut_state_n_word =
                        o_x_old_n_rows_clusters[ci * NUM_ROWS * DATA_WIDTH + ri * DATA_WIDTH +: DATA_WIDTH];
                    gold_state_p_word = gold_state_p_mem[gold_idx][ri * DATA_WIDTH +: DATA_WIDTH];
                    gold_state_n_word = gold_state_n_mem[gold_idx][ri * DATA_WIDTH +: DATA_WIDTH];
                    dut_state_value = iter_tb_signed_digit_value(dut_state_p_word, dut_state_n_word);
                    gold_state_value = iter_tb_magnitude_rail_value(gold_state_p_word, gold_state_n_word);
`ifdef PAGERANK32_PRIOR_TOLERANT_CHECK
                    compare_delta_value = dut_state_value - gold_state_value;
                    compare_abs_delta = compare_delta_value[31]
                        ? (~compare_delta_value + 1'b1)
                        : compare_delta_value;
                    if (compare_abs_delta > PRIOR_CHECK_TOLERANCE) begin
`else
                    if (dut_state_value !== gold_state_value) begin
`endif
                        $display("ERROR multi state_value iter=%0d cluster=%0d row=%0d got=%0d expected=%0d dut_p=%h dut_n=%h gold_p=%h gold_n=%h",
                            iter_no,
                            ci,
                            ri,
                            dut_state_value,
                            gold_state_value,
                            dut_state_p_word,
                            dut_state_n_word,
                            gold_state_p_word,
                            gold_state_n_word);
                        $fatal;
                    end
                end
`else
                if (o_x_old_p_rows_clusters[ci * NUM_ROWS * DATA_WIDTH +: NUM_ROWS * DATA_WIDTH]
                    !== gold_state_p_mem[gold_idx]) begin
                    $display("ERROR multi state_p iter=%0d cluster=%0d got=%h expected=%h",
                        iter_no,
                        ci,
                        o_x_old_p_rows_clusters[ci * NUM_ROWS * DATA_WIDTH +: NUM_ROWS * DATA_WIDTH],
                        gold_state_p_mem[gold_idx]);
                    $fatal;
                end
                if (o_x_old_n_rows_clusters[ci * NUM_ROWS * DATA_WIDTH +: NUM_ROWS * DATA_WIDTH]
                    !== gold_state_n_mem[gold_idx]) begin
                    $display("ERROR multi state_n iter=%0d cluster=%0d got=%h expected=%h",
                        iter_no,
                        ci,
                        o_x_old_n_rows_clusters[ci * NUM_ROWS * DATA_WIDTH +: NUM_ROWS * DATA_WIDTH],
                        gold_state_n_mem[gold_idx]);
                    $fatal;
                end
`endif
`endif
            end

            cert_wait_delta = o_cert_wait_cycles - cert_wait_before;
            if (cert_wait_delta <= 0) begin
                $display("ERROR multi cert_wait did not advance iter=%0d delta=%0d",
                    iter_no, cert_wait_delta);
                $fatal;
            end
            $display("ITER multi iter=%0d cert_wait_delta=%0d conv=%0d cont=%0d maxerr0=%0d state0p=%h state0n=%h",
                iter_no,
                cert_wait_delta,
                gold_iter_converged_mem[check_iter_idx][0],
                gold_iter_continue_mem[check_iter_idx][0],
                gold_max_error_mem[check_iter_idx * NUM_CLUSTERS],
                gold_state_p_mem[check_iter_idx * NUM_CLUSTERS],
                gold_state_n_mem[check_iter_idx * NUM_CLUSTERS]);
        end
    endtask

    initial begin
        $readmemh(`JACOBI32_TEMPLATE_MEMH, template_mem);
        $readmemh(`JACOBI32_CERT_MEMH, cert_mem);
        $readmemh(`JACOBI32_GOLD_STATE_P_MEMH, gold_state_p_mem);
        $readmemh(`JACOBI32_GOLD_STATE_N_MEMH, gold_state_n_mem);
        $readmemh(`JACOBI32_GOLD_MAX_ERROR_MEMH, gold_max_error_mem);
        $readmemh(`JACOBI32_GOLD_CERTIFIED_MEMH, gold_certified_mem);
        $readmemh(`JACOBI32_GOLD_CONVERGED_MEMH, gold_iter_converged_mem);
        $readmemh(`JACOBI32_GOLD_CONTINUE_MEMH, gold_iter_continue_mem);
        pack_expected_payloads();

        i_clk = 1'b0;
        i_rst = 1'b1;
        i_cfg_template_we = 1'b0;
        i_cfg_cert_we = 1'b0;
        i_cfg_cluster_addr = 0;
        i_cfg_template_word = 0;
        i_cfg_cert_word = 0;
        i_load_window = 1'b0;
        i_cfg_state_we = 1'b0;
        i_cfg_state_cluster_slot = 0;
        i_cfg_state_bank_sel = 1'b0;
        i_cfg_state_row_idx = 0;
        i_cfg_state_p = 0;
        i_cfg_state_n = 0;
        i_start_iter = 1'b0;
        i_commit_iter = 1'b0;
        i_base_cluster_idx = 0;
        i_use_replay_clusters = {NUM_CLUSTERS{1'b0}};
        i_replay_digit_idx = 0;
        i_issue_rows_clusters = 0;
        i_tail_bound_clusters = {NUM_CLUSTERS{{(BOUND_WIDTH - 1){1'b0}}, 1'b1}};
        i_counter_clear = 1'b0;

        repeat (2) @(posedge i_clk);
        i_rst <= 1'b0;

        for (ci = 0; ci < NUM_CLUSTERS; ci = ci + 1) begin
            cfg_write_cluster(ci);
        end
        load_window();
        for (ci = 0; ci < NUM_CLUSTERS; ci = ci + 1) begin
            for (ri = 0; ri < NUM_ROWS; ri = ri + 1) begin
                cfg_load_state(ci, ri[ROW_IDX_WIDTH - 1 : 0], {DATA_WIDTH{1'b0}}, {DATA_WIDTH{1'b0}});
            end
        end

        @(posedge i_clk);
        #1;
        if (o_template_words_clusters !== expected_template_words ||
            o_cert_param_words_clusters !== expected_cert_words) begin
            $display("ERROR multi runtime payload mismatch");
            $fatal;
        end
        if (o_sched_row_active_clusters !== {NUM_CLUSTERS * NUM_ROWS{1'b1}}) begin
            $display("ERROR multi row-active mask mismatch");
            $fatal;
        end
        if (o_cfg_template_write_count !== NUM_CLUSTERS ||
            o_cfg_cert_write_count !== NUM_CLUSTERS ||
            o_cfg_state_write_count !== (NUM_CLUSTERS * NUM_ROWS) ||
            o_window_load_count !== 32'd1 ||
            o_window_busy_cycles === 32'd0 ||
            o_window_ready_cycles === 32'd0) begin
            $display("ERROR multi loader counters tmpl=%0d cert=%0d state=%0d load=%0d busy=%0d ready=%0d",
                o_cfg_template_write_count,
                o_cfg_cert_write_count,
                o_cfg_state_write_count,
                o_window_load_count,
                o_window_busy_cycles,
                o_window_ready_cycles);
            $fatal;
        end

        for (iter_idx = 0; iter_idx < NUM_ITERS; iter_idx = iter_idx + 1) begin
            run_iteration(iter_idx);
        end

        expected_converged_count = 0;
        expected_certified_block_count = 0;
        expected_cert_prefix_digit_sum = 0;
        expected_issue_cycles = (AUTO_FULL_DIGIT == 0) ? NUM_ITERS : (NUM_ITERS * DATA_WIDTH);
        expected_prefix_depth = (AUTO_FULL_DIGIT == 0) ? (REPLAY_DIGIT_IDX + 1) : DATA_WIDTH;
        for (conv_count_idx = 0; conv_count_idx < NUM_ITERS; conv_count_idx = conv_count_idx + 1) begin
`ifdef JACOBI32_WAVEFRONT_RUNTIME
            check_iter_idx = ((conv_count_idx + 1) * WAVEFRONT_SUPERSTEP_STAGES) - 1;
`elsif JACOBI32_PRIOR_WAVEFRONT_RUNTIME
            check_iter_idx = ((conv_count_idx + 1) * WAVEFRONT_SUPERSTEP_STAGES) - 1;
`else
            check_iter_idx = conv_count_idx;
`endif
            expected_converged_count = expected_converged_count + gold_iter_converged_mem[check_iter_idx][0];
            for (ci = 0; ci < NUM_CLUSTERS; ci = ci + 1) begin
                gold_idx = check_iter_idx * NUM_CLUSTERS + ci;
                expected_certified_block_count =
                    expected_certified_block_count + gold_certified_mem[gold_idx][0];
                expected_cert_prefix_digit_sum =
                    expected_cert_prefix_digit_sum +
                    (gold_certified_mem[gold_idx][0] * expected_prefix_depth);
            end
        end

        if (o_iter_count !== NUM_ITERS ||
            o_issue_cycles !== expected_issue_cycles ||
`ifndef PAGERANK32_PRIOR_RELAXED_CHECK
`ifndef JACOBI32_SOLVER_NATIVE_RUNTIME
            o_converged_iter !== expected_converged_count ||
`endif
`endif
            o_active_digit_cycles !== expected_issue_cycles ||
            o_gated_digit_cycles !== 32'd0 ||
`ifndef PAGERANK32_PRIOR_RELAXED_CHECK
`ifndef JACOBI32_SOLVER_NATIVE_RUNTIME
            o_certified_block_count !== expected_certified_block_count ||
            o_cert_prefix_digit_sum !== expected_cert_prefix_digit_sum
`else
            1'b0
`endif
`else
            1'b0
`endif
        ) begin
            $display("ERROR multi final counters iter=%0d issue=%0d conv_iter=%0d total=%0d cert_wait=%0d active_digit=%0d gated_digit=%0d cert_blocks=%0d cert_sum=%0d",
                o_iter_count,
                o_issue_cycles,
                o_converged_iter,
                o_total_cycles,
                o_cert_wait_cycles,
                o_active_digit_cycles,
                o_gated_digit_cycles,
                o_certified_block_count,
                o_cert_prefix_digit_sum);
            $fatal;
        end

        $display("COUNTERS %s total=%0d issue=%0d cert_wait=%0d iter=%0d conv_iter=%0d cfg_template=%0d cfg_cert=%0d cfg_state=%0d window_load=%0d window_busy=%0d window_ready=%0d active_digit=%0d gated_digit=%0d cert_blocks=%0d cert_sum=%0d",
            `JACOBI32_COUNTER_LABEL,
            o_total_cycles,
            o_issue_cycles,
            o_cert_wait_cycles,
            o_iter_count,
            o_converged_iter,
            o_cfg_template_write_count,
            o_cfg_cert_write_count,
            o_cfg_state_write_count,
            o_window_load_count,
            o_window_busy_cycles,
            o_window_ready_cycles,
            o_active_digit_cycles,
            o_gated_digit_cycles,
            o_certified_block_count,
            o_cert_prefix_digit_sum);
        $display("PASS %s", `JACOBI32_PASS_LABEL);
        $finish;
    end
endmodule

`undef JACOBI32_TEMPLATE_MEMH
`undef JACOBI32_CERT_MEMH
`undef JACOBI32_GOLD_STATE_P_MEMH
`undef JACOBI32_GOLD_STATE_N_MEMH
`undef JACOBI32_GOLD_MAX_ERROR_MEMH
`undef JACOBI32_GOLD_CERTIFIED_MEMH
`undef JACOBI32_GOLD_CONVERGED_MEMH
`undef JACOBI32_GOLD_CONTINUE_MEMH
`undef JACOBI32_COUNTER_LABEL
`undef JACOBI32_PASS_LABEL
`undef JACOBI32_SIGNED_DIGIT_STATE_COMPARE
`undef JACOBI32_FOUR_ITER_COMPARE
`undef JACOBI32_NUM_ITERS_VALUE
`undef JACOBI32_NUM_GOLD_ITERS_VALUE
`undef WAVEFRONT_SUPERSTEP_STAGES_VALUE
`undef JACOBI32_CERT_PIPE
`undef JACOBI32_CERT_OPIPE
`undef JACOBI32_CERT_CMPIPE
`undef JACOBI32_CONV_RUNTIME
