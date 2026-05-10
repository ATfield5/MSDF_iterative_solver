proc getenv_default {name default_value} {
    if {[info exists ::env($name)]} {
        return $::env($name)
    }
    return $default_value
}

set origin_dir [file normalize [file dirname [info script]]]
set rtl_dir [file join $origin_dir rtl]

set part [getenv_default MSDF_PART "xcu55c-fsvh2892-2L-e"]
set clk_period [getenv_default MSDF_CLK_PERIOD_NS 5.000]
set run_route [getenv_default MSDF_RUN_ROUTE 0]
set run_ooc [getenv_default MSDF_OOC 1]

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
set template_mem_init [getenv_default MSDF_TEMPLATE_MEM_INIT "MSDF_iterative_solver/generated/rtl_vectors/blockdiag8/templates.memh"]
set cert_param_mem_init [getenv_default MSDF_CERT_PARAM_MEM_INIT "MSDF_iterative_solver/generated/rtl_vectors/blockdiag8/cert_params.memh"]

set tag [format "part%s_ntc%s_nc%s_nr%s_deg%s_bw%s_bound%s_cw%s_acc%s_blk%s_data%s_ooc%s_clk%s_route%s" \
    $part $num_total_clusters $num_clusters $num_rows $degree $bit_width \
    $bound_width $coeff_width $acc_width $block_size $data_width $run_ooc \
    $clk_period $run_route]
set out_dir [file join $origin_dir generated vivado_iter_dense_small_param_bank_top_$tag]
file mkdir $out_dir

set xdc_file [file join $out_dir iter_dense_small_param_bank_top_clock.xdc]
set xdc_fp [open $xdc_file w]
puts $xdc_fp [format {create_clock -name i_clk -period %.3f [get_ports i_clk]} $clk_period]
close $xdc_fp

set_part $part

read_verilog \
    [file join $rtl_dir iter_dff.v] \
    [file join $rtl_dir iter_full_adder.v] \
    [file join $rtl_dir iter_parallel_online_adder_block.v] \
    [file join $rtl_dir iter_parallel_online_adder.v] \
    [file join $rtl_dir iter_parallel_online_adder_4.v] \
    [file join $rtl_dir iter_parallel_online_adder_4_with_obuf.v] \
    [file join $rtl_dir online_const_coeff_contrib.v] \
    [file join $rtl_dir online_affine_row_update_core.v] \
    [file join $rtl_dir online_delta_linf_cert_core.v] \
    [file join $rtl_dir online_row_update_delta_slice.v] \
    [file join $rtl_dir block_bound_max_pool.v] \
    [file join $rtl_dir block_h_cert_engine.v] \
    [file join $rtl_dir online_row_cluster_block_cert.v] \
    [file join $rtl_dir online_row_cluster_delta_cert.v] \
    [file join $rtl_dir iter_cluster_cert_controller.v] \
    [file join $rtl_dir iter_state_ping_pong_bank.v] \
    [file join $rtl_dir iter_fixed_degree_state_replay.v] \
    [file join $rtl_dir iter_fixed_degree_row_scheduler.v] \
    [file join $rtl_dir iter_dense_small_ping_pong_top.v] \
    [file join $rtl_dir iter_dense_small_sched_top.v] \
    [file join $rtl_dir iter_fixed_degree_template_unpack.v] \
    [file join $rtl_dir iter_fixed_degree_template_bank.v] \
    [file join $rtl_dir iter_cert_param_unpack.v] \
    [file join $rtl_dir iter_cert_param_bank.v] \
    [file join $rtl_dir iter_dense_small_param_bank_top.v]

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
    template_mem_init=$template_mem_init \
    cert_param_mem_init=$cert_param_mem_init]

if {$run_ooc != 0} {
    synth_design \
        -top iter_dense_small_param_bank_top \
        -part $part \
        -mode out_of_context \
        -generic $generic_args
} else {
    synth_design \
        -top iter_dense_small_param_bank_top \
        -part $part \
        -generic $generic_args
}

opt_design

report_utilization -file [file join $out_dir utilization_synth.rpt]
report_timing_summary -file [file join $out_dir timing_summary_synth.rpt] -delay_type max -max_paths 20
report_power -file [file join $out_dir power_synth.rpt]
write_checkpoint -force [file join $out_dir iter_dense_small_param_bank_top_synth.dcp]

if {$run_route != 0} {
    place_design
    phys_opt_design
    route_design
    report_utilization -file [file join $out_dir utilization_routed.rpt]
    report_timing_summary -file [file join $out_dir timing_summary_routed.rpt] -delay_type max -max_paths 20
    report_power -file [file join $out_dir power_routed.rpt]
    write_checkpoint -force [file join $out_dir iter_dense_small_param_bank_top_routed.dcp]
}

puts "OUT_DIR=$out_dir"
exit
