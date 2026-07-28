# SAP-VPU core or subsystem synthesis for Synopsys Design Compiler.

proc env_or_default {name default_value} {
  if {[info exists ::env($name)] && $::env($name) ne ""} {
    return $::env($name)
  }
  return $default_value
}

set repo_root [file normalize [env_or_default REPO_ROOT "."]]
set top_name [env_or_default DESIGN_NAME "sap_vpu_core"]
set work_dir [file normalize [env_or_default WORK_DIR [file join $repo_root "work/dc/vpu_core"]]]
set report_dir [file normalize [env_or_default REPORT_DIR [file join $repo_root "reports/dc/vpu_core"]]]
set netlist_dir [file normalize [env_or_default NETLIST_DIR [file join $repo_root "netlist/dc/vpu_core"]]]
set ddc_file [file normalize [env_or_default DDC_FILE [file join $netlist_dir "${top_name}.ddc"]]]
set db_file [file normalize [env_or_default STD_CELL_DB ""]]
set process_corner [env_or_default PROCESS_CORNER [env_or_default TSMC28_CORNER "unknown"]]
set clock_period [env_or_default CLOCK_PERIOD "10.0"]
set clock_uncertainty [env_or_default CLOCK_UNCERTAINTY "0.20"]
set input_delay [env_or_default INPUT_DELAY "1.0"]
set output_delay [env_or_default OUTPUT_DELAY "1.0"]
set compile_ultra [env_or_default COMPILE_ULTRA "1"]
set map_effort [env_or_default MAP_EFFORT "medium"]
set area_effort [env_or_default AREA_EFFORT "none"]
set exact_map [env_or_default EXACT_MAP "0"]
set use_dw [env_or_default USE_DW "1"]
set precheck_only [env_or_default PRECHECK_ONLY "0"]
set skip_power_report [env_or_default SKIP_POWER_REPORT "0"]
set power_only [env_or_default POWER_ONLY "0"]
set saif_file_raw [env_or_default SAIF_FILE ""]
if {$saif_file_raw eq ""} {
  set saif_file ""
} else {
  set saif_file [file normalize $saif_file_raw]
}
set saif_instance [env_or_default SAIF_INSTANCE ""]
set power_report [file join $report_dir "power.rpt"]

foreach dir [list $work_dir $report_dir $netlist_dir] {
  file mkdir $dir
}
file mkdir [file join $work_dir "alib"]

if {$db_file eq "" || ![file exists $db_file]} {
  puts stderr "STD_CELL_DB is missing or does not exist: $db_file"
  exit 2
}

set_app_var search_path [concat $search_path [list $repo_root [file join $repo_root rtl]]]
set_app_var target_library [list $db_file]
if {$use_dw eq "0"} {
  set_app_var synthetic_library [list]
} else {
  set_app_var synthetic_library [list dw_foundation.sldb]
}
set_app_var link_library [concat "*" $target_library $synthetic_library]
set_app_var hdlin_check_no_latch true
set_app_var verilogout_no_tri true
set_app_var alib_library_analysis_path [file join $work_dir "alib"]

define_design_lib WORK -path [file join $work_dir "dc_work"]

set rtl_files [list \
  [file join $repo_root "rtl/sap_vpu_pkg.sv"] \
  [file join $repo_root "rtl/sap_vpu_core.sv"] \
  [file join $repo_root "rtl/sap_vpu_tiled_gemm.sv"] \
  [file join $repo_root "rtl/sap_vpu_subsystem.sv"] \
]

puts "SAP-VPU DC synthesis"
puts "  top: $top_name"
puts "  db: $db_file"
puts "  corner: $process_corner"
puts "  clock_period: $clock_period ns"
puts "  compile_ultra: $compile_ultra"
puts "  map_effort: $map_effort"
puts "  area_effort: $area_effort"
puts "  exact_map: $exact_map"
puts "  use_dw: $use_dw"
puts "  precheck_only: $precheck_only"
puts "  skip_power_report: $skip_power_report"
puts "  power_only: $power_only"
puts "  saif_file: $saif_file"
puts "  saif_instance: $saif_instance"
puts "  work_dir: $work_dir"

if {$power_only eq "1"} {
  if {![file exists $ddc_file]} {
    puts stderr "DDC_FILE is missing or does not exist: $ddc_file"
    exit 3
  }
  read_ddc $ddc_file
  current_design $top_name
  link
  if {$saif_file ne ""} {
    if {![file exists $saif_file]} {
      puts stderr "SAIF_FILE is missing or does not exist: $saif_file"
      exit 4
    }
    if {$saif_instance eq ""} {
      read_saif -input $saif_file
    } else {
      read_saif -input $saif_file -instance_name $saif_instance
    }
  }
  if {$skip_power_report eq "1"} {
    puts "Skipping power report"
  } else {
    redirect $power_report {
      report_power -analysis_effort low
    }
  }
  puts "SAP-VPU DC power report complete: $power_report"
  exit
}

analyze -format sverilog -define SYNTHESIS -library WORK $rtl_files
elaborate $top_name -library WORK
current_design $top_name
link
uniquify

create_clock -name clk_i -period $clock_period [get_ports clk_i]
set_clock_uncertainty $clock_uncertainty [get_clocks clk_i]
set_false_path -from [get_ports rst_ni]
set_input_delay $input_delay -clock clk_i [remove_from_collection [all_inputs] [get_ports clk_i]]
set_output_delay $output_delay -clock clk_i [all_outputs]

redirect -tee [file join $report_dir "check_design.rpt"] {check_design}
redirect [file join $report_dir "check_timing.rpt"] {check_timing}

if {$precheck_only eq "1"} {
  set summary_file [file join $work_dir "dc_vpu_precheck.csv"]
  set fd [open $summary_file "w"]
  puts $fd "top,library,corner,clock_period_ns,status"
  puts $fd "$top_name,$db_file,$process_corner,$clock_period,precheck_pass"
  close $fd
  puts "SAP-VPU DC precheck complete: $summary_file"
  exit
}

set_fix_multiple_port_nets -all -buffer_constants
if {$compile_ultra eq "0"} {
  if {$exact_map eq "0"} {
    compile -map_effort $map_effort -area_effort $area_effort
  } else {
    compile -exact_map
  }
} else {
  compile_ultra -no_autoungroup
}

change_names -rules verilog -hierarchy

redirect [file join $report_dir "qor.rpt"] {
  report_qor
}
redirect [file join $report_dir "area.rpt"] {
  report_area -hierarchy
}
redirect [file join $report_dir "timing_max.rpt"] {
  report_timing -delay_type max -max_paths 20 -nworst 5
}
redirect [file join $report_dir "timing_min.rpt"] {
  report_timing -delay_type min -max_paths 10 -nworst 3
}
redirect [file join $report_dir "constraints.rpt"] {
  report_constraint -all_violators
}
if {$skip_power_report eq "1"} {
  puts "Skipping power report"
} else {
  if {[catch {
    if {$saif_file ne ""} {
      if {![file exists $saif_file]} {
        puts stderr "SAIF_FILE is missing or does not exist: $saif_file"
        exit 4
      }
      if {$saif_instance eq ""} {
        read_saif -input $saif_file
      } else {
        read_saif -input $saif_file -instance_name $saif_instance
      }
    }
    redirect $power_report {
      report_power -analysis_effort low
    }
  } power_error]} {
    puts stderr "Power report unavailable: $power_error"
  }
}

write -format ddc -hierarchy -output [file join $netlist_dir "${top_name}.ddc"]
write -format verilog -hierarchy -output [file join $netlist_dir "${top_name}.v"]
write_sdc [file join $netlist_dir "${top_name}.sdc"]

set worst_slack "NA"
if {![catch {set timing_paths [get_timing_paths -max_paths 1]} timing_error]} {
  if {[sizeof_collection $timing_paths] > 0} {
    set worst_slack [get_attribute $timing_paths slack]
  }
} else {
  puts stderr "Timing path query unavailable: $timing_error"
}

set summary_file [file join $work_dir "dc_vpu_summary.csv"]
set fd [open $summary_file "w"]
puts $fd "top,library,corner,clock_period_ns,worst_slack_ns"
puts $fd "$top_name,$db_file,$process_corner,$clock_period,$worst_slack"
close $fd

puts "SAP-VPU DC synthesis complete: $summary_file"
exit
