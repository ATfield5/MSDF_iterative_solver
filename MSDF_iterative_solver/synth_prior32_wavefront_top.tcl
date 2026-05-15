proc getenv_default {name default_value} {
    if {[info exists ::env($name)]} {
        return $::env($name)
    }
    return $default_value
}

set origin_dir [file normalize [file dirname [info script]]]
set root_dir [file normalize [file join $origin_dir ..]]
set prior_rtl_dir [file join $origin_dir prior_rtl]
set orig_src_dir [file join $root_dir MSDF_operator_srcs MSDF_Operators MSDF_Operators MSDF_Operators.srcs sources_1 new]

set part [getenv_default MSDF_PART "xcu55c-fsvh2892-2L-e"]
set clk_period [getenv_default MSDF_CLK_PERIOD_NS 5.000]
set run_ooc [getenv_default MSDF_OOC 1]
set run_route [getenv_default MSDF_RUN_ROUTE 0]
set max_threads [getenv_default MSDF_VIVADO_MAX_THREADS ""]

set top_name [getenv_default MSDF_TOP "iter_prior_online_mma8_global_wavefront_top"]
set num_stages [getenv_default MSDF_NUM_STAGES 4]
set num_rows [getenv_default MSDF_NUM_ROWS 32]
set degree [getenv_default MSDF_DEGREE 32]
set bit_width [getenv_default MSDF_BIT_WIDTH 29]
set data_width [getenv_default MSDF_DATA_WIDTH 32]
set bias_width [getenv_default MSDF_BIAS_WIDTH 31]
set src_idx_width [getenv_default MSDF_SRC_IDX_WIDTH 5]
set capture_unit [getenv_default MSDF_CAPTURE_UNIT 0]
set use_mma4_frac_core [getenv_default MSDF_USE_MMA4_FRAC_CORE 0]

set tag [format "prior32_top%s_part%s_k%s_rows%s_deg%s_bw%s_data%s_bias%s_ooc%s_clk%s_route%s" \
    $top_name $part $num_stages $num_rows $degree $bit_width $data_width \
    $bias_width $run_ooc $clk_period $run_route]
set tag [getenv_default MSDF_RUN_TAG $tag]
set out_dir [file join $origin_dir generated vivado_$tag]
file mkdir $out_dir

if {$max_threads ne ""} {
    set_param general.maxThreads $max_threads
}

set xdc_file [file join $out_dir prior32_wavefront_clock.xdc]
set xdc_fp [open $xdc_file w]
puts $xdc_fp [format {create_clock -name i_clk -period %.3f [get_ports i_clk]} $clk_period]
close $xdc_fp

set_part $part

read_verilog \
    [file join $orig_src_dir DFF.v] \
    [file join $orig_src_dir full_adder.v] \
    [file join $orig_src_dir serial_online_adder_block.v] \
    [file join $orig_src_dir parallel_online_adder_block.v] \
    [file join $orig_src_dir parallel_online_adder.v] \
    [file join $orig_src_dir parallel_online_adder_4.v] \
    [file join $orig_src_dir parallel_online_adder_4_with_obuf.v] \
    [file join $orig_src_dir vector_append.v] \
    [file join $orig_src_dir selector.v] \
    [file join $orig_src_dir append_and_select.v] \
    [file join $orig_src_dir output_and_update.v] \
    [file join $orig_src_dir MSDF_ADD.v] \
    [file join $orig_src_dir MSDF_MUL_ADD_8.v] \
    [file join $prior_rtl_dir MSDF_MUL_ADD_32_NATIVE.v] \
    [file join $prior_rtl_dir iter_pagerank_online_mma4_frac_core.v] \
    [file join $prior_rtl_dir iter_pagerank_online_mma4_frac_stage_cluster.v] \
    [file join $prior_rtl_dir iter_prior_online_mma8_row_kernel.v] \
    [file join $prior_rtl_dir iter_prior_online_mma32_row_kernel.v] \
    [file join $prior_rtl_dir iter_prior_online_mma32_native_row_kernel.v] \
    [file join $prior_rtl_dir iter_prior_online_mma8_stream_stage_cluster.v] \
    [file join $prior_rtl_dir iter_prior_online_mma8_global_wavefront_top.v]

read_xdc $xdc_file

set generic_args [list \
    num_stages=$num_stages \
    num_rows=$num_rows \
    degree=$degree \
    bit_width=$bit_width \
    data_width=$data_width \
    bias_width=$bias_width \
    src_idx_width=$src_idx_width \
    capture_unit=$capture_unit \
    use_mma4_frac_core=$use_mma4_frac_core]

if {$run_ooc != 0} {
    synth_design -top $top_name -part $part -mode out_of_context -generic $generic_args
} else {
    synth_design -top $top_name -part $part -generic $generic_args
}

opt_design

report_utilization -file [file join $out_dir utilization_synth.rpt]
report_timing_summary -file [file join $out_dir timing_summary_synth.rpt] -delay_type max -max_paths 20
report_power -file [file join $out_dir power_synth.rpt]
write_checkpoint -force [file join $out_dir prior32_wavefront_synth.dcp]

if {$run_route != 0} {
    place_design
    phys_opt_design
    route_design
    report_utilization -file [file join $out_dir utilization_routed.rpt]
    report_timing_summary -file [file join $out_dir timing_summary_routed.rpt] -delay_type max -max_paths 20
    report_power -file [file join $out_dir power_routed.rpt]
    report_route_status -file [file join $out_dir route_status_routed.rpt]
    write_checkpoint -force [file join $out_dir prior32_wavefront_routed.dcp]
}

puts "OUT_DIR=$out_dir"
exit
