`timescale 1ns/1ps

module corev_min_soc_hello_tb (
  input  logic        clk_i,
  input  logic        rst_ni,
  input  logic        fetch_enable_i,
  output logic        uart_tx_valid_o,
  output logic [7:0]  uart_tx_data_o,
  output logic        exit_valid_o,
  output logic [31:0] exit_code_o,
  output logic        core_sleep_o
);
  corev_min_soc #(
    .ROM_INIT_FILE("work/hello/sap_vpu_hello.hex")
  ) dut (
    .clk_i(clk_i),
    .rst_ni(rst_ni),
    .fetch_enable_i(fetch_enable_i),
    .uart_tx_valid_o(uart_tx_valid_o),
    .uart_tx_data_o(uart_tx_data_o),
    .exit_valid_o(exit_valid_o),
    .exit_code_o(exit_code_o),
    .core_sleep_o(core_sleep_o)
  );
endmodule
