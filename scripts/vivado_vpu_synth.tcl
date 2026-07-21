if {$argc < 3} {
  puts "Usage: vivado -mode batch -source scripts/vivado_vpu_synth.tcl -tclargs <part> <clock_mhz> <out_dir> ?top? ?out_of_context?"
  exit 2
}

set part [lindex $argv 0]
set clock_mhz [lindex $argv 1]
set out_dir [file normalize [lindex $argv 2]]
set top_name "sap_vpu_core"
if {$argc >= 4} {
  set top_name [lindex $argv 3]
}
set out_of_context 0
if {$argc >= 5} {
  set out_of_context [lindex $argv 4]
}
set repo_root [file normalize [file join [file dirname [info script]] ".."]]
set report_dir [file join $out_dir "reports"]
set checkpoint_dir [file join $out_dir "checkpoints"]

file mkdir $out_dir
file mkdir $report_dir
file mkdir $checkpoint_dir

set clock_period_ns [expr {1000.0 / double($clock_mhz)}]

puts "SAP-VPU FPGA synthesis"
puts "  top: $top_name"
puts "  out_of_context: $out_of_context"
puts "  part: $part"
puts "  clock_mhz: $clock_mhz"
puts "  clock_period_ns: $clock_period_ns"
puts "  out_dir: $out_dir"

read_verilog -sv [file join $repo_root "rtl/sap_vpu_pkg.sv"]
read_verilog -sv [file join $repo_root "rtl/sap_vpu_core.sv"]
read_verilog -sv [file join $repo_root "rtl/sap_vpu_tiled_gemm.sv"]
read_verilog -sv [file join $repo_root "rtl/sap_vpu_subsystem.sv"]

if {$out_of_context} {
  synth_design -top $top_name -part $part -mode out_of_context
} else {
  synth_design -top $top_name -part $part
}
create_clock -period $clock_period_ns -name clk_i [get_ports clk_i]

report_utilization -file [file join $report_dir "post_synth_utilization.rpt"]
report_timing_summary -file [file join $report_dir "post_synth_timing_summary.rpt"]
write_checkpoint -force [file join $checkpoint_dir "post_synth.dcp"]

opt_design
place_design
phys_opt_design
route_design

report_utilization -file [file join $report_dir "post_route_utilization.rpt"]
report_timing_summary -file [file join $report_dir "post_route_timing_summary.rpt"]
report_power -file [file join $report_dir "post_route_power.rpt"]
write_checkpoint -force [file join $checkpoint_dir "post_route.dcp"]

set timing_paths [get_timing_paths -max_paths 1 -quiet]
set worst_slack "NA"
if {[llength $timing_paths] > 0} {
  set worst_slack [get_property SLACK [lindex $timing_paths 0]]
}

set summary_file [file join $out_dir "fpga_vpu_summary.csv"]
set fd [open $summary_file "w"]
puts $fd "top,part,clock_mhz,clock_period_ns,out_of_context,worst_slack_ns"
puts $fd "$top_name,$part,$clock_mhz,$clock_period_ns,$out_of_context,$worst_slack"
close $fd

if {$worst_slack ne "NA" && [expr {double($worst_slack) < 0.0}]} {
  puts "ERROR: post-route timing failed with worst slack $worst_slack ns"
  exit 1
}

puts "SAP-VPU FPGA synthesis complete: $summary_file"
