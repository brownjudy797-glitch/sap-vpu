if {$argc < 1} {
  puts "Usage: vivado -mode batch -source scripts/vivado_davinci_program.tcl -tclargs <bitstream>"
  exit 2
}

set bitstream [file normalize [lindex $argv 0]]
if {![file exists $bitstream]} {
  error "Bitstream not found: $bitstream"
}

open_hw_manager
connect_hw_server
open_hw_target

set device [lindex [get_hw_devices -quiet xc7a200t*] 0]
if {$device eq ""} {
  error "xc7a200t hardware device not found"
}

current_hw_device $device
refresh_hw_device $device
set_property PROGRAM.FILE $bitstream $device
program_hw_devices $device
puts "DAVINCI_JTAG_PROGRAM_PASS: $device"
close_hw_manager
