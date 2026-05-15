proc getenv_default {name default_value} {
    if {[info exists ::env($name)]} {
        return $::env($name)
    }
    return $default_value
}

set origin_dir [file normalize [file dirname [info script]]]
set rtl_dir [file join $origin_dir rtl]
set prior_rtl_dir [file join $origin_dir prior_rtl]

set part [getenv_default MSDF_PART "xcu55c-fsvh2892-2L-e"]
set clk_period [getenv_default MSDF_CLK_PERIOD_NS 5.000]
set run_route [getenv_default MSDF_RUN_ROUTE 1]
set run_ooc [getenv_default MSDF_OOC 1]
set skip_synth_reports [getenv_default MSDF_SKIP_SYNTH_REPORTS 0]
set max_threads [getenv_default MSDF_VIVADO_MAX_THREADS ""]
set place_directive [getenv_default MSDF_PLACE_DIRECTIVE ""]
set route_directive [getenv_default MSDF_ROUTE_DIRECTIVE ""]
set post_route_phys_opt_directive [getenv_default MSDF_POST_ROUTE_PHYS_OPT_DIRECTIVE ""]
set top_name [getenv_default MSDF_TOP "iter_parallel_in_online_mma8_global_wavefront_top"]
set top_kind [getenv_default MSDF_TOP_KIND "p3sp"]

set num_stages [getenv_default MSDF_NUM_STAGES 4]
set num_rows [getenv_default MSDF_NUM_ROWS 32]
set degree [getenv_default MSDF_DEGREE 4]
set physical_degree [getenv_default MSDF_PHYSICAL_DEGREE 8]
set default_bit_width 30
set bit_width [getenv_default MSDF_BIT_WIDTH $default_bit_width]
set default_data_width 32
set data_width [getenv_default MSDF_DATA_WIDTH $default_data_width]
set default_bias_width 32
set bias_width [getenv_default MSDF_BIAS_WIDTH $default_bias_width]
set bound_width [getenv_default MSDF_BOUND_WIDTH 16]
set default_acc_width [expr {$top_kind eq "p3spfb" ? 64 : ($top_kind eq "p3sp" ? 36 : 40)}]
set acc_width [getenv_default MSDF_ACC_WIDTH $default_acc_width]
set core_acc_width [getenv_default MSDF_CORE_ACC_WIDTH 33]
set default_product_width [expr {$data_width + $bit_width + 4}]
set product_width [getenv_default MSDF_PRODUCT_WIDTH $default_product_width]
set online_delay [getenv_default MSDF_ONLINE_DELAY 2]
set fast2_core [getenv_default MSDF_FAST2_CORE 0]
set estimate_selector [getenv_default MSDF_EST_SELECTOR 0]
set estimate_frac_bits [getenv_default MSDF_EST_FRAC_BITS 6]
set estimate_guard_bits [getenv_default MSDF_EST_GUARD_BITS 2]
set split_estimate [getenv_default MSDF_SPLIT_ESTIMATE 1]
set redundant_residual [getenv_default MSDF_REDUNDANT_RESIDUAL 0]
set nonnegative_coeff [getenv_default MSDF_NONNEGATIVE_COEFF 0]
set nonnegative_bias [getenv_default MSDF_NONNEGATIVE_BIAS 0]
set grouped_stage_broadcast [getenv_default MSDF_GROUPED_STAGE_BROADCAST 0]
set source_onehot [getenv_default MSDF_SOURCE_ONEHOT 0]
set product_shift [getenv_default MSDF_PRODUCT_SHIFT $data_width]
set round_pipeline [getenv_default MSDF_ROUND_PIPELINE 1]
set src_idx_width [getenv_default MSDF_SRC_IDX_WIDTH 5]
set feedback_fifo_depth [getenv_default MSDF_FEEDBACK_FIFO_DEPTH 128]

set tag [format "kind%s_top%s_part%s_k%s_rows%s_deg%s_pdeg%s_bw%s_data%s_bias%s_bound%s_acc%s_pwidth%s_odelay%s_pshift%s_rpipe%s_ooc%s_clk%s_route%s" \
    $top_kind $top_name $part $num_stages $num_rows $degree $physical_degree \
    $bit_width $data_width $bias_width $bound_width $acc_width $product_width $online_delay \
    $product_shift $round_pipeline $run_ooc $clk_period $run_route]
set tag [getenv_default MSDF_RUN_TAG $tag]
set out_dir [file join $origin_dir generated vivado_parallel_in_wavefront_$tag]
file mkdir $out_dir

if {$max_threads ne ""} {
    set_param general.maxThreads $max_threads
}

set xdc_file [file join $out_dir parallel_in_wavefront_clock.xdc]
set xdc_fp [open $xdc_file w]
puts $xdc_fp [format {create_clock -name i_clk -period %.3f [get_ports i_clk]} $clk_period]
close $xdc_fp

set_part $part

read_verilog \
    [file join $rtl_dir conv_signed_row_update_delta_slice_pipe.v] \
    [file join $prior_rtl_dir iter_parallel_in_online_mma8_frac_core.v] \
    [file join $prior_rtl_dir iter_parallel_in_online_mma8_frac_core_fast2.v] \
    [file join $prior_rtl_dir iter_parallel_in_online_mma8_stage_cluster.v] \
    [file join $prior_rtl_dir iter_parallel_in_online_mma8_global_wavefront_top.v] \
    [file join $prior_rtl_dir iter_parallel_in_online_mma8_global_feedback_top.v] \
    [file join $prior_rtl_dir iter_parallel_in_conv_mma8_global_wavefront_top.v] \
    [file join $prior_rtl_dir iter_parallel_in_conv_mma8_parallel_rows_top.v]

read_xdc $xdc_file

if {$top_kind eq "p3sp"} {
    set generic_args [list \
        num_stages=$num_stages \
        num_rows=$num_rows \
        degree=$degree \
        physical_degree=$physical_degree \
        bit_width=$bit_width \
        data_width=$data_width \
        bias_width=$bias_width \
        online_delay=$online_delay \
        acc_width=$acc_width \
        fast2_core=$fast2_core \
        nonnegative_coeff=$nonnegative_coeff \
        nonnegative_bias=$nonnegative_bias \
        grouped_stage_broadcast=$grouped_stage_broadcast \
        src_idx_width=$src_idx_width]
} elseif {$top_kind eq "p3spfb"} {
    set generic_args [list \
        num_stages=$num_stages \
        num_rows=$num_rows \
        degree=$degree \
        physical_degree=$physical_degree \
        bit_width=$bit_width \
        data_width=$data_width \
        bias_width=$bias_width \
        online_delay=$online_delay \
        acc_width=$acc_width \
        core_acc_width=$core_acc_width \
        fast2_core=$fast2_core \
        estimate_selector=$estimate_selector \
        estimate_frac_bits=$estimate_frac_bits \
        estimate_guard_bits=$estimate_guard_bits \
        split_estimate=$split_estimate \
        redundant_residual=$redundant_residual \
        nonnegative_coeff=$nonnegative_coeff \
        nonnegative_bias=$nonnegative_bias \
        source_onehot=$source_onehot \
        src_idx_width=$src_idx_width \
        feedback_fifo_depth=$feedback_fifo_depth]
} elseif {$top_kind eq "p4sp"} {
    set generic_args [list \
        num_rows=$num_rows \
        physical_degree=$physical_degree \
        data_width=$data_width \
        coeff_width=$bit_width \
        bias_width=$bias_width \
        bound_width=$bound_width \
        acc_width=$acc_width \
        product_width=$product_width \
        product_shift=$product_shift \
        round_pipeline=$round_pipeline]
} else {
    error "Unknown MSDF_TOP_KIND=$top_kind"
}

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

if {$skip_synth_reports == 0} {
    report_utilization -file [file join $out_dir utilization_synth.rpt]
    report_timing_summary -file [file join $out_dir timing_summary_synth.rpt] -delay_type max -max_paths 20
    report_power -file [file join $out_dir power_synth.rpt]
    write_checkpoint -force [file join $out_dir parallel_in_wavefront_synth.dcp]
} else {
    report_utilization -file [file join $out_dir utilization_synth.rpt]
}

if {$run_route != 0} {
    if {$place_directive ne ""} {
        place_design -directive $place_directive
    } else {
        place_design
    }
    phys_opt_design
    if {$route_directive ne ""} {
        route_design -directive $route_directive
    } else {
        route_design
    }
    if {$post_route_phys_opt_directive ne ""} {
        phys_opt_design -directive $post_route_phys_opt_directive
        route_design
    }
    report_utilization -file [file join $out_dir utilization_routed.rpt]
    report_timing_summary -file [file join $out_dir timing_summary_routed.rpt] -delay_type max -max_paths 20
    report_power -file [file join $out_dir power_routed.rpt]
    report_route_status -file [file join $out_dir route_status_routed.rpt]
    catch {report_design_analysis -congestion -file [file join $out_dir congestion_routed.rpt]}
    write_checkpoint -force [file join $out_dir parallel_in_wavefront_routed.dcp]
}

puts "OUT_DIR=$out_dir"
exit
