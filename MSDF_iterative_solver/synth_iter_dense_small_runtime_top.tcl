proc getenv_default {name default_value} {
    if {[info exists ::env($name)]} {
        return $::env($name)
    }
    return $default_value
}

set origin_dir [file normalize [file dirname [info script]]]
set rtl_dir [file join $origin_dir rtl]
set prior_rtl_dir [file join $origin_dir prior_rtl]
set prior_src_dir [file normalize [file join $origin_dir .. MSDF_operator_srcs MSDF_Operators MSDF_Operators MSDF_Operators.srcs sources_1 new]]

set part [getenv_default MSDF_PART "xcu55c-fsvh2892-2L-e"]
set clk_period [getenv_default MSDF_CLK_PERIOD_NS 5.000]
set run_route [getenv_default MSDF_RUN_ROUTE 0]
set run_ooc [getenv_default MSDF_OOC 1]
set top_name [getenv_default MSDF_TOP "iter_dense_small_runtime_top"]

set num_total_clusters [getenv_default MSDF_NUM_TOTAL_CLUSTERS 2]
set num_clusters [getenv_default MSDF_NUM_CLUSTERS 2]
set num_rows [getenv_default MSDF_NUM_ROWS 4]
set degree [getenv_default MSDF_DEGREE 4]
set bit_width [getenv_default MSDF_BIT_WIDTH 8]
set bound_width [getenv_default MSDF_BOUND_WIDTH [expr {$bit_width + 5}]]
set coeff_width [getenv_default MSDF_COEFF_WIDTH 8]
set acc_width [getenv_default MSDF_ACC_WIDTH 24]
set block_size [getenv_default MSDF_BLOCK_SIZE 2]
set data_width [getenv_default MSDF_DATA_WIDTH [expr {$bit_width + 3}]]
set row_datapath_mode [getenv_default MSDF_ROW_DATAPATH_MODE 0]
set auto_full_digit [getenv_default MSDF_AUTO_FULL_DIGIT 0]
set auto_prefix_gating [getenv_default MSDF_AUTO_PREFIX_GATING 0]
set mac_acc_width [getenv_default MSDF_MAC_ACC_WIDTH 32]
set conv_mac_pipeline [getenv_default MSDF_CONV_MAC_PIPELINE 0]
set conv_product_shift [getenv_default MSDF_CONV_PRODUCT_SHIFT 0]
set conv_round_pipeline [getenv_default MSDF_CONV_ROUND_PIPELINE 0]
set conv_baseline_degree [getenv_default MSDF_CONV_BASELINE_DEGREE 8]
set runtime_mem_style [getenv_default MSDF_RUNTIME_MEM_STYLE 1]
set row_idx_width [getenv_default MSDF_ROW_IDX_WIDTH 2]
set src_idx_width [getenv_default MSDF_SRC_IDX_WIDTH $row_idx_width]
set global_source_replay [getenv_default MSDF_GLOBAL_SOURCE_REPLAY 0]
set halo_source_replay [getenv_default MSDF_HALO_SOURCE_REPLAY 0]
set halo_cluster_radius [getenv_default MSDF_HALO_CLUSTER_RADIUS 1]
set halo_replay_mode [getenv_default MSDF_HALO_REPLAY_MODE 0]
set halo_replay_output_register [getenv_default MSDF_HALO_REPLAY_OUTPUT_REGISTER 0]
set cert_product_pipeline [getenv_default MSDF_CERT_PRODUCT_PIPELINE 0]
set cert_operand_pipeline [getenv_default MSDF_CERT_OPERAND_PIPELINE 0]
set cert_compare_pipeline [getenv_default MSDF_CERT_COMPARE_PIPELINE 0]
set solver_native_skip_digits [getenv_default MSDF_SOLVER_NATIVE_SKIP_DIGITS 4]
set solver_native_affine_guard_shift [getenv_default MSDF_SOLVER_NATIVE_AFFINE_GUARD_SHIFT 7]
set solver_native_sample_width [getenv_default MSDF_SOLVER_NATIVE_SAMPLE_WIDTH 5]
set wavefront_superstep_stages [getenv_default MSDF_WAVEFRONT_SUPERSTEP_STAGES 4]
set wavefront_inter_stage_delay_cycles [getenv_default MSDF_WAVEFRONT_INTER_STAGE_DELAY_CYCLES 0]
set prior_capture_unit [getenv_default MSDF_PRIOR_CAPTURE_UNIT 1]

set tag [format "top%s_part%s_ntc%s_nc%s_nr%s_deg%s_bw%s_bound%s_cw%s_acc%s_blk%s_data%s_dpm%s_auto%s_agate%s_macc%s_macp%s_pshift%s_rpipe%s_cdeg%s_mem%s_src%s_global%s_halo%s_hr%s_hmode%s_hreg%s_cpipe%s_opipe%s_cmpipe%s_snskip%s_sng%s_snsmpl%s_wfk%s_wfd%s_pcap%s_ooc%s_clk%s_route%s" \
    $top_name $part $num_total_clusters $num_clusters $num_rows $degree $bit_width \
    $bound_width $coeff_width $acc_width $block_size $data_width \
    $row_datapath_mode $auto_full_digit $auto_prefix_gating $mac_acc_width $conv_mac_pipeline $conv_product_shift $conv_round_pipeline $conv_baseline_degree $runtime_mem_style $src_idx_width $global_source_replay $halo_source_replay \
    $halo_cluster_radius $halo_replay_mode $halo_replay_output_register $cert_product_pipeline \
    $cert_operand_pipeline $cert_compare_pipeline $solver_native_skip_digits $solver_native_affine_guard_shift $solver_native_sample_width \
    $wavefront_superstep_stages $wavefront_inter_stage_delay_cycles $prior_capture_unit $run_ooc $clk_period $run_route]
set tag [getenv_default MSDF_RUN_TAG $tag]
set out_dir [file join $origin_dir generated vivado_iter_dense_small_runtime_top_$tag]
file mkdir $out_dir

set xdc_file [file join $out_dir iter_dense_small_runtime_top_clock.xdc]
set xdc_fp [open $xdc_file w]
puts $xdc_fp [format {create_clock -name i_clk -period %.3f [get_ports i_clk]} $clk_period]
close $xdc_fp

set_part $part

read_verilog \
    [file join $prior_src_dir DFF.v] \
    [file join $prior_src_dir full_adder.v] \
    [file join $prior_src_dir parallel_online_adder_block.v] \
    [file join $prior_src_dir parallel_online_adder.v] \
    [file join $prior_src_dir parallel_online_adder_4.v] \
    [file join $prior_src_dir parallel_online_adder_4_with_obuf.v] \
    [file join $prior_src_dir vector_append.v] \
    [file join $prior_src_dir selector.v] \
    [file join $prior_src_dir append_and_select.v] \
    [file join $prior_src_dir output_and_update.v] \
    [file join $prior_src_dir MSDF_MUL_ADD_8.v] \
    [file join $rtl_dir iter_dff.v] \
    [file join $rtl_dir iter_full_adder.v] \
    [file join $rtl_dir iter_parallel_online_adder_block.v] \
    [file join $rtl_dir iter_parallel_online_adder.v] \
    [file join $rtl_dir iter_parallel_online_adder_4.v] \
    [file join $rtl_dir iter_parallel_online_adder_4_with_obuf.v] \
    [file join $rtl_dir online_const_coeff_contrib.v] \
    [file join $rtl_dir iter_const_coeff_digit_contrib_rail.v] \
    [file join $rtl_dir iter_streamed_bias_source.v] \
    [file join $rtl_dir iter_online_affine_no_bias_core.v] \
    [file join $rtl_dir iter_online_output_update.v] \
    [file join $rtl_dir iter_online_affine_digit_core.v] \
    [file join $rtl_dir iter_digit_stream_delta_bound.v] \
    [file join $rtl_dir iter_solver_native_row_digit_engine.v] \
    [file join $rtl_dir iter_solver_native_commit_adapter.v] \
    [file join $rtl_dir iter_digit_stream_state_ping_pong_bank.v] \
    [file join $rtl_dir iter_digit_stream_state_replay_top.v] \
    [file join $rtl_dir iter_solver_native_cluster_digit_stream_top.v] \
    [file join $rtl_dir iter_solver_native_cluster_delta_cert_top.v] \
    [file join $rtl_dir iter_wavefront_digit_delay_line.v] \
    [file join $rtl_dir iter_wavefront_commit_stage_cluster.v] \
    [file join $rtl_dir iter_wavefront_radius1_commit_multistage_cluster.v] \
    [file join $rtl_dir iter_wavefront_commit_last_delta_cert_top.v] \
    [file join $rtl_dir iter_wavefront_superstep_cluster_state_top.v] \
    [file join $rtl_dir online_affine_row_update_core.v] \
    [file join $rtl_dir iter_digit_serial_full_row_update_delta_slice.v] \
    [file join $rtl_dir iter_digit_serial_full_row_cluster_delta_cert.v] \
    [file join $rtl_dir online_delta_linf_cert_core.v] \
    [file join $rtl_dir online_row_update_delta_slice.v] \
    [file join $rtl_dir block_bound_max_pool.v] \
    [file join $rtl_dir block_h_cert_engine.v] \
    [file join $rtl_dir online_row_cluster_block_cert.v] \
    [file join $rtl_dir online_row_cluster_delta_cert.v] \
    [file join $rtl_dir iter_cluster_cert_controller.v] \
    [file join $rtl_dir iter_digit_prefix_scheduler.v] \
    [file join $rtl_dir iter_state_ping_pong_bank.v] \
    [file join $rtl_dir iter_fixed_degree_state_replay.v] \
    [file join $rtl_dir iter_fixed_degree_state_replay_halo_r1.v] \
    [file join $rtl_dir iter_fixed_degree_state_word_replay.v] \
    [file join $rtl_dir iter_fixed_degree_state_word_replay_halo_r1.v] \
    [file join $rtl_dir iter_signed_to_rail.v] \
    [file join $rtl_dir iter_rail_to_signed.v] \
    [file join $rtl_dir conv_reserved_mac_slots.v] \
    [file join $rtl_dir conv_signed_row_update_delta_slice.v] \
    [file join $rtl_dir conv_signed_row_update_delta_slice_pipe.v] \
    [file join $rtl_dir conv_row_cluster_delta_cert.v] \
    [file join $rtl_dir iter_fixed_degree_row_scheduler.v] \
    [file join $rtl_dir iter_dense_small_ping_pong_top.v] \
    [file join $rtl_dir iter_runtime_word_bank.v] \
    [file join $rtl_dir iter_runtime_sdp_field_ram.v] \
    [file join $rtl_dir iter_template_field_bank.v] \
    [file join $rtl_dir iter_cert_param_field_bank.v] \
    [file join $rtl_dir iter_fixed_degree_template_unpack.v] \
    [file join $rtl_dir iter_cert_param_unpack.v] \
    [file join $prior_rtl_dir iter_prior_online_mma8_row_kernel.v] \
    [file join $prior_rtl_dir iter_prior_online_mma8_word_assembler.v] \
    [file join $prior_rtl_dir iter_prior_online_mma8_row_cluster_delta_cert.v] \
    [file join $prior_rtl_dir iter_prior_online_mma8_digit_stream_cluster_delta_cert.v] \
    [file join $prior_rtl_dir iter_prior_online_mma8_stream_stage_cluster.v] \
    [file join $prior_rtl_dir iter_prior_online_mma8_global_wavefront_top.v] \
    [file join $rtl_dir iter_dense_small_runtime_top.v] \
    [file join $rtl_dir iter_dense_small_runtime_binary_io_top.v]

read_xdc $xdc_file

set generic_args [list \
    num_total_clusters=$num_total_clusters \
    num_clusters=$num_clusters \
    num_rows=$num_rows \
    degree=$degree \
    bit_width=$bit_width \
    bound_width=$bound_width \
    coeff_width=$coeff_width \
    acc_width=$acc_width \
    block_size=$block_size \
    data_width=$data_width \
    row_datapath_mode=$row_datapath_mode \
    auto_full_digit=$auto_full_digit \
    auto_prefix_gating=$auto_prefix_gating \
    mac_acc_width=$mac_acc_width \
    conv_mac_pipeline=$conv_mac_pipeline \
    conv_product_shift=$conv_product_shift \
    conv_round_pipeline=$conv_round_pipeline \
    conv_baseline_degree=$conv_baseline_degree \
    row_idx_width=$row_idx_width \
    src_idx_width=$src_idx_width \
    global_source_replay=$global_source_replay \
    halo_source_replay=$halo_source_replay \
    halo_cluster_radius=$halo_cluster_radius \
    halo_replay_mode=$halo_replay_mode \
    halo_replay_output_register=$halo_replay_output_register \
    cert_product_pipeline=$cert_product_pipeline \
    cert_operand_pipeline=$cert_operand_pipeline \
    cert_compare_pipeline=$cert_compare_pipeline \
    solver_native_skip_digits=$solver_native_skip_digits \
    solver_native_affine_guard_shift=$solver_native_affine_guard_shift \
    solver_native_sample_width=$solver_native_sample_width \
    wavefront_superstep_stages=$wavefront_superstep_stages \
    wavefront_inter_stage_delay_cycles=$wavefront_inter_stage_delay_cycles \
    prior_capture_unit=$prior_capture_unit \
    runtime_mem_style=$runtime_mem_style]

if {$run_ooc != 0} {
    synth_design \
        -top $top_name \
        -part $part \
        -mode out_of_context \
        -generic $generic_args
} else {
    synth_design \
        -top $top_name \
        -part $part \
        -generic $generic_args
}

opt_design

report_utilization -file [file join $out_dir utilization_synth.rpt]
report_timing_summary -file [file join $out_dir timing_summary_synth.rpt] -delay_type max -max_paths 20
report_power -file [file join $out_dir power_synth.rpt]
write_checkpoint -force [file join $out_dir iter_dense_small_runtime_top_synth.dcp]

if {$run_route != 0} {
    place_design
    phys_opt_design
    route_design
    report_utilization -file [file join $out_dir utilization_routed.rpt]
    report_timing_summary -file [file join $out_dir timing_summary_routed.rpt] -delay_type max -max_paths 20
    report_power -file [file join $out_dir power_routed.rpt]
    write_checkpoint -force [file join $out_dir iter_dense_small_runtime_top_routed.dcp]
}

puts "OUT_DIR=$out_dir"
exit
