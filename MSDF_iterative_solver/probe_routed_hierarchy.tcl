# Probe a routed checkpoint with hierarchical utilization and timing reports.
#
# Required environment variables:
#   MSDF_DCP      absolute or repo-relative routed checkpoint path
#   MSDF_OUT_DIR  output directory for generated reports
#
# Optional environment variables:
#   MSDF_HIER_DEPTH  hierarchy depth for report_utilization, default 8

if {![info exists ::env(MSDF_DCP)]} {
    error "MSDF_DCP is required"
}
if {![info exists ::env(MSDF_OUT_DIR)]} {
    error "MSDF_OUT_DIR is required"
}

set dcp_path $::env(MSDF_DCP)
set out_dir  $::env(MSDF_OUT_DIR)

if {[info exists ::env(MSDF_HIER_DEPTH)]} {
    set hier_depth $::env(MSDF_HIER_DEPTH)
} else {
    set hier_depth 8
}

file mkdir $out_dir

open_checkpoint $dcp_path

report_utilization \
    -hierarchical \
    -hierarchical_depth $hier_depth \
    -file [file join $out_dir utilization_hier_routed.rpt]

report_timing_summary \
    -delay_type max \
    -max_paths 20 \
    -file [file join $out_dir timing_summary_hier_probe.rpt]

report_route_status \
    -file [file join $out_dir route_status_probe.rpt]

close_project
exit
