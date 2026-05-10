set origin_dir [file normalize [file dirname [info script]]]
set rtl_dir [file join $origin_dir rtl]
set tb_dir  [file join $origin_dir tb]

if {[info exists ::env(TB_NAME)]} {
    set tb_name $::env(TB_NAME)
} else {
    set tb_name "tb_online_const_coeff_contrib"
}

set common_files [list \
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
    [file join $rtl_dir online_affine_row_update_core.v] \
    [file join $rtl_dir online_delta_linf_cert_core.v] \
    [file join $rtl_dir online_row_update_delta_slice.v] \
    [file join $rtl_dir block_bound_max_pool.v] \
    [file join $rtl_dir block_h_cert_engine.v] \
    [file join $rtl_dir online_row_cluster_block_cert.v] \
    [file join $rtl_dir online_row_cluster_delta_cert.v] \
    [file join $rtl_dir iter_cluster_cert_controller.v] \
    [file join $rtl_dir iter_dense_small_closed_loop_top.v] \
    [file join $rtl_dir iter_row_state_handoff_buffer.v] \
    [file join $rtl_dir iter_state_ping_pong_bank.v] \
    [file join $rtl_dir iter_dense_small_handoff_top.v] \
    [file join $rtl_dir iter_fixed_degree_state_replay.v] \
    [file join $rtl_dir iter_dense_small_replay_top.v] \
    [file join $rtl_dir iter_dense_small_ping_pong_top.v] \
    [file join $rtl_dir iter_fixed_degree_row_scheduler.v] \
    [file join $rtl_dir iter_dense_small_sched_top.v] \
    [file join $rtl_dir iter_fixed_degree_template_unpack.v] \
    [file join $rtl_dir iter_fixed_degree_template_rom.v] \
    [file join $rtl_dir iter_dense_small_template_top.v] \
    [file join $rtl_dir iter_fixed_degree_template_bank.v] \
    [file join $rtl_dir iter_runtime_word_bank.v] \
    [file join $rtl_dir iter_runtime_sdp_field_ram.v] \
    [file join $rtl_dir iter_template_field_bank.v] \
    [file join $rtl_dir iter_cert_param_field_bank.v] \
    [file join $rtl_dir iter_cert_param_unpack.v] \
    [file join $rtl_dir iter_cert_param_bank.v] \
    [file join $rtl_dir iter_dense_small_param_bank_top.v] \
    [file join $rtl_dir iter_dense_small_runtime_top.v] \
]

set tb_file [file join $tb_dir "${tb_name}.v"]

foreach f [concat $common_files [list $tb_file]] {
    if {![file exists $f]} {
        error "missing file: $f"
    }
}

exec xvlog -nolog -i $tb_dir {*}$common_files $tb_file
exec xelab -nolog $tb_name -s ${tb_name}_sim
exec xsim ${tb_name}_sim -runall
