if {$argc < 3} {
  puts "Usage: vivado -mode batch -source scripts/vivado_vpu_saif_power.tcl -tclargs <routed_dcp> <saif_file> <out_dir> [saif_strip_path]"
  exit 2
}

set dcp_file [file normalize [lindex $argv 0]]
set saif_file [file normalize [lindex $argv 1]]
set out_dir [file normalize [lindex $argv 2]]
set saif_strip_path ""
if {$argc >= 4} {
  set saif_strip_path [lindex $argv 3]
}

set report_dir [file join $out_dir "reports"]
file mkdir $out_dir
file mkdir $report_dir

puts "SAP-VPU FPGA SAIF power"
puts "  dcp: $dcp_file"
puts "  saif: $saif_file"
puts "  saif_strip_path: $saif_strip_path"
puts "  out_dir: $out_dir"

if {![file exists $dcp_file]} {
  puts stderr "Missing routed checkpoint: $dcp_file"
  exit 3
}
if {![file exists $saif_file]} {
  puts stderr "Missing SAIF file: $saif_file"
  exit 4
}

open_checkpoint $dcp_file
set unmatched_file [file join $report_dir "post_route_saif_unmatched.rpt"]
if {$saif_strip_path eq ""} {
  read_saif -out_file $unmatched_file $saif_file
} else {
  read_saif -strip_path $saif_strip_path -out_file $unmatched_file $saif_file
}

set power_report [file join $report_dir "post_route_saif_power.rpt"]
report_power -file $power_report

set summary_file [file join $out_dir "fpga_vpu_saif_power_summary.csv"]
set fd [open $summary_file "w"]
puts $fd "top,dcp,saif,saif_strip_path,power_report,unmatched_report"
puts $fd "[current_design],$dcp_file,$saif_file,$saif_strip_path,$power_report,$unmatched_file"
close $fd

puts "SAP-VPU FPGA SAIF power complete: $power_report"
