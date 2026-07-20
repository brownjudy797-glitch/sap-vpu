`timescale 1ns/1ps

module corev_min_soc_tiled_gemm_tb;
  localparam int unsigned TIMEOUT_CYCLES = 30000;

  logic clk;
  logic rst_n;
  logic fetch_enable;
  logic uart_tx_valid;
  logic [7:0] uart_tx_data;
  logic exit_valid;
  logic [31:0] exit_code;
  logic core_sleep;

  corev_min_soc #(
    .ROM_INIT_FILE("work/tiled_gemm_soc/sap_vpu_tiled_gemm_soc.hex")
  ) dut (
    .clk_i(clk),
    .rst_ni(rst_n),
    .fetch_enable_i(fetch_enable),
    .uart_tx_valid_o(uart_tx_valid),
    .uart_tx_data_o(uart_tx_data),
    .exit_valid_o(exit_valid),
    .exit_code_o(exit_code),
    .core_sleep_o(core_sleep)
  );

  always #5 clk = ~clk;

  always_ff @(posedge clk or negedge rst_n) begin
    if (rst_n && uart_tx_valid) begin
      $fatal(1, "Unexpected UART byte 0x%02x", uart_tx_data);
    end
    if (rst_n && exit_valid) begin
      if (exit_code !== 32'd1) begin
        $fatal(1, "Tiled GEMM SoC smoke exit code expected 1 got %0d", exit_code);
      end
      $display("Tiled GEMM SoC smoke exit code: %0d", exit_code);
      $finish;
    end
  end

  initial begin
    clk = 1'b0;
    rst_n = 1'b0;
    fetch_enable = 1'b0;

    repeat (5) @(posedge clk);
    rst_n = 1'b1;
    fetch_enable = 1'b1;

    repeat (TIMEOUT_CYCLES) @(posedge clk);
    $fatal(1, "Timed out waiting for tiled GEMM SoC smoke exit");
  end
endmodule
