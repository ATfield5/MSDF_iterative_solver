proc getenv_required {name} {
    if {![info exists ::env($name)]} {
        error "missing required env var $name"
    }
    return $::env($name)
}

set dcp_path [getenv_required MSDF_DCP_PATH]
set out_path [getenv_required MSDF_HIER_UTIL_OUT]
set depth [expr {[info exists ::env(MSDF_HIER_DEPTH)] ? $::env(MSDF_HIER_DEPTH) : 6}]

open_checkpoint $dcp_path
report_utilization -hierarchical -hierarchical_depth $depth -file $out_path
puts "HIER_UTIL_OUT=$out_path"
exit
