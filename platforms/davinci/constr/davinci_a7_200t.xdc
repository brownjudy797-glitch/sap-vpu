set_property CFGBVS VCCO [current_design]
set_property CONFIG_VOLTAGE 3.3 [current_design]

set_property PACKAGE_PIN R4 [get_ports sys_clk]
set_property IOSTANDARD LVCMOS15 [get_ports sys_clk]
create_clock -period 20.000 -name sys_clk [get_ports sys_clk]

set_property PACKAGE_PIN U7 [get_ports sys_rst_n]
set_property IOSTANDARD LVCMOS15 [get_ports sys_rst_n]

set_property PACKAGE_PIN V9 [get_ports {led[0]}]
set_property PACKAGE_PIN Y8 [get_ports {led[1]}]
set_property PACKAGE_PIN Y7 [get_ports {led[2]}]
set_property PACKAGE_PIN W7 [get_ports {led[3]}]
set_property IOSTANDARD LVCMOS15 [get_ports {led[*]}]

set_property PACKAGE_PIN E14 [get_ports uart_rxd]
set_property IOSTANDARD LVCMOS33 [get_ports uart_rxd]

set_property PACKAGE_PIN D17 [get_ports uart_txd]
set_property IOSTANDARD LVCMOS33 [get_ports uart_txd]
