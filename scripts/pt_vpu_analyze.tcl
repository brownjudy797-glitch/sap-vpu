# SAP-VPU post-synthesis timing and power analysis for PrimeTime.

proc require_env {name} {
  if {![info exists ::env($name)] || $::env($name) eq ""} {
    puts stderr "Missing required environment variable: $name"
    exit 2
  }
  return $::env($name)
}

proc env_or_default {name default_value} {
  if {[info exists ::env($name)] && $::env($name) ne ""} {
    return $::env($name)
  }
  return $default_value
}

set top_name [env_or_default DESIGN_NAME "sap_vpu_subsystem"]
set db_file [file normalize [require_env STD_CELL_DB]]
set netlist_file [file normalize [require_env NETLIST_FILE]]
set sdc_file [file normalize [require_env SDC_FILE]]
set report_dir [file normalize [require_env REPORT_DIR]]
set process_corner [env_or_default PROCESS_CORNER "unknown"]
set saif_file_raw [env_or_default SAIF_FILE ""]
set saif_strip_path [env_or_default SAIF_STRIP_PATH ""]

foreach path [list $db_file $netlist_file $sdc_file] {
  if {![file exists $path]} {
    puts stderr "Required input does not exist: $path"
    exit 3
  }
}

file mkdir $report_dir
set_app_var link_path [concat "*" [list $db_file]]
set_app_var power_enable_analysis true
set_app_var power_analysis_mode averaged

read_verilog $netlist_file
current_design $top_name
link_design $top_name
read_sdc $sdc_file
check_timing
update_timing -full

if {$saif_file_raw ne ""} {
  set saif_file [file normalize $saif_file_raw]
  if {![file exists $saif_file]} {
    puts stderr "SAIF input does not exist: $saif_file"
    exit 4
  }
  if {$saif_strip_path eq ""} {
    read_saif $saif_file
  } else {
    read_saif -strip_path $saif_strip_path $saif_file
  }
}

update_power
redirect [file join $report_dir "check_timing.rpt"] {check_timing}
redirect [file join $report_dir "qor.rpt"] {report_qor}
redirect [file join $report_dir "timing_max.rpt"] {
  report_timing -delay_type max -slack_lesser_than 1000.0 -max_paths 20 -nworst 5
}
redirect [file join $report_dir "timing_min.rpt"] {
  report_timing -delay_type min -slack_lesser_than 1000.0 -max_paths 10 -nworst 3
}
redirect [file join $report_dir "constraints.rpt"] {
  report_constraint -all_violators
}
redirect [file join $report_dir "power.rpt"] {report_power}

set worst_max_slack "NA"
set worst_min_slack "NA"
set max_paths [get_timing_paths -delay_type max -max_paths 1]
if {[sizeof_collection $max_paths] > 0} {
  set worst_max_slack [get_attribute $max_paths slack]
}
set min_paths [get_timing_paths -delay_type min -max_paths 1]
if {[sizeof_collection $min_paths] > 0} {
  set worst_min_slack [get_attribute $min_paths slack]
}

set summary_file [file join $report_dir "pt_vpu_summary.csv"]
set fd [open $summary_file "w"]
puts $fd "top,library,corner,worst_max_slack_ns,worst_min_slack_ns,saif_file"
puts $fd "$top_name,$db_file,$process_corner,$worst_max_slack,$worst_min_slack,$saif_file_raw"
close $fd

puts "SAP-VPU PrimeTime analysis complete: $summary_file"
exit
