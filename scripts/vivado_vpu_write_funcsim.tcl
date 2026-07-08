if {$argc < 2} {
  puts "Usage: vivado -mode batch -source scripts/vivado_vpu_write_funcsim.tcl -tclargs <checkpoint.dcp> <out_dir>"
  exit 2
}

set dcp_file [file normalize [lindex $argv 0]]
set out_dir [file normalize [lindex $argv 1]]
file mkdir $out_dir

puts "SAP-VPU FPGA functional simulation netlist export"
puts "  dcp: $dcp_file"
puts "  out_dir: $out_dir"

if {![file exists $dcp_file]} {
  puts stderr "Missing checkpoint: $dcp_file"
  exit 3
}

open_checkpoint $dcp_file

set netlist_file [file join $out_dir "sap_vpu_core_funcsim.v"]
write_verilog -force -mode funcsim $netlist_file

set summary_file [file join $out_dir "fpga_vpu_funcsim_summary.csv"]
set fd [open $summary_file "w"]
puts $fd "top,dcp,netlist"
puts $fd "[current_design],$dcp_file,$netlist_file"
close $fd

puts "SAP-VPU FPGA functional simulation netlist complete: $netlist_file"
