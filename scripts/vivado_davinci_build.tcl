if {$argc < 5} {
  puts "Usage: vivado -mode batch -source scripts/vivado_davinci_build.tcl -tclargs <part> <out_dir> <corev_flist> <image> <target_mhz>"
  exit 2
}

set part [lindex $argv 0]
set out_dir [file normalize [lindex $argv 1]]
set corev_flist [file normalize [lindex $argv 2]]
set image [lindex $argv 3]
set target_mhz [lindex $argv 4]
if {$target_mhz ni {50 60 70 80 100}} {
  puts "ERROR: target_mhz must be 50, 60, 70, 80, or 100"
  exit 2
}
set repo_root [file normalize [file join [file dirname [info script]] ".."]]
set design_rtl_dir [file join $repo_root "third_party/cv32e40x/rtl"]
set report_dir [file join $out_dir "reports"]
set checkpoint_dir [file join $out_dir "checkpoints"]
file mkdir $report_dir
file mkdir $checkpoint_dir

set include_dirs {}
set corev_files {}
set fd [open $corev_flist r]
foreach raw_line [split [read $fd] "\n"] {
  set line [string trim $raw_line]
  if {$line eq ""} { continue }
  set line [string map [list {${DESIGN_RTL_DIR}} $design_rtl_dir] $line]
  if {[string match "+incdir+*" $line]} {
    lappend include_dirs [string range $line 8 end]
  } elseif {![string match "*cv32e40x_sim_clock_gate.sv" $line]} {
    lappend corev_files [file normalize $line]
  }
}
close $fd

create_project -in_memory -part $part
set_property include_dirs $include_dirs [current_fileset]
read_verilog -sv $corev_files
read_verilog -sv [file join $repo_root "platforms/corev/rtl/cv32e40x_fpga_clock_gate.sv"]
read_verilog -sv [file join $repo_root "rtl/sap_vpu_pkg.sv"]
read_verilog -sv [file join $repo_root "rtl/sap_vpu_core.sv"]
read_verilog -sv [file join $repo_root "rtl/sap_vpu_tiled_gemm.sv"]
read_verilog -sv [file join $repo_root "rtl/sap_vpu_subsystem.sv"]
read_verilog -sv [file join $repo_root "platforms/corev/rtl/cvxif_sap_vpu_adapter.sv"]
read_verilog -sv [file join $repo_root "platforms/corev/rtl/corev_min_soc.sv"]
read_verilog -sv [file join $repo_root "platforms/davinci/rtl/sap_vpu_davinci_top.sv"]
read_xdc [file join $repo_root "platforms/davinci/constr/davinci_a7_200t.xdc"]

synth_design -top sap_vpu_davinci_top -part $part -generic [list TARGET_MHZ=$target_mhz]
report_utilization -file [file join $report_dir "post_synth_utilization.rpt"]
report_timing_summary -file [file join $report_dir "post_synth_timing_summary.rpt"]
write_checkpoint -force [file join $checkpoint_dir "post_synth.dcp"]

opt_design
place_design -directive Explore
phys_opt_design -directive Explore
route_design -directive Explore

set initial_paths [get_timing_paths -max_paths 1 -quiet]
if {[llength $initial_paths] > 0} {
  set initial_slack [get_property SLACK [lindex $initial_paths 0]]
  if {[expr {double($initial_slack) < 0.0}]} {
    puts "INFO: initial route slack is $initial_slack ns; running post-route physical optimization"
    phys_opt_design -directive AggressiveExplore
    route_design -directive Explore
  }
}

report_utilization -file [file join $report_dir "post_route_utilization.rpt"]
report_timing_summary -file [file join $report_dir "post_route_timing_summary.rpt"]
report_power -file [file join $report_dir "post_route_power.rpt"]
write_checkpoint -force [file join $checkpoint_dir "post_route.dcp"]

set timing_paths [get_timing_paths -max_paths 1 -quiet]
set worst_slack "NA"
if {[llength $timing_paths] > 0} {
  set worst_slack [get_property SLACK [lindex $timing_paths 0]]
}

set summary_file [file join $out_dir "fpga_davinci_summary.csv"]
set fd [open $summary_file "w"]
puts $fd "top,image,part,input_clock_mhz,core_clock_mhz,uart_baud,worst_slack_ns"
puts $fd "sap_vpu_davinci_top,$image,$part,50,$target_mhz,115200,$worst_slack"
close $fd

if {$worst_slack ne "NA" && [expr {double($worst_slack) < 0.0}]} {
  puts "ERROR: board timing failed with worst slack $worst_slack ns"
  exit 1
}
write_bitstream -force [file join $out_dir "sap_vpu_davinci_${image}.bit"]
puts "SAP-VPU Davinci bitstream complete: $summary_file"
