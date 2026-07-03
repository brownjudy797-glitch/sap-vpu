`timescale 1ns/1ps

module corev_min_soc_tinyvit_tb;
  localparam int unsigned TIMEOUT_CYCLES = 30000;
  localparam logic [31:0] RESULT_MAGIC = 32'h5456_4954; // "TVIT"

  logic clk;
  logic rst_n;
  logic fetch_enable;
  logic uart_tx_valid;
  logic [7:0] uart_tx_data;
  logic exit_valid;
  logic [31:0] exit_code;
  logic core_sleep;
  int result_fd;

  corev_min_soc #(
    .ROM_INIT_FILE("work/tinyvit/sap_vpu_tinyvit.hex")
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
        $fatal(1, "TinyViT smoke exit code expected 1 got %0d", exit_code);
      end
      if (dut.ram[0] !== RESULT_MAGIC) begin
        $fatal(1, "TinyViT result magic expected 0x%08x got 0x%08x", RESULT_MAGIC, dut.ram[0]);
      end
      if ((dut.ram[4] == 32'd0) || (dut.ram[5] == 32'd0) ||
          (dut.ram[11] == 32'd0) || (dut.ram[12] == 32'd0) ||
          (dut.ram[18] == 32'd0) || (dut.ram[19] == 32'd0)) begin
        $fatal(1, "TinyViT cycle/inst counters must be nonzero");
      end
      result_fd = $fopen("work/tinyvit/tinyvit_smoke_counters.csv", "w");
      if (result_fd == 0) begin
        $fatal(1, "Could not open TinyViT counter CSV");
      end
      $fdisplay(result_fd, "kernel,precision,sparse,output,mac_active,skip,sparse_state,lane_state,cycle_delta,instret_delta");
      $fdisplay(result_fd, "dense,int8,none,%0d,%0d,%0d,0,4,%0d,%0d",
                dut.ram[1], dut.ram[2], dut.ram[3], dut.ram[4], dut.ram[5]);
      $fdisplay(result_fd, "static_lowbit,int4,none,%0d,%0d,%0d,%0d,%0d,%0d,%0d",
                dut.ram[6], dut.ram[7], dut.ram[8], dut.ram[9], dut.ram[10],
                dut.ram[11], dut.ram[12]);
      $fdisplay(result_fd, "adaptive,int4,bitmap,%0d,%0d,%0d,%0d,%0d,%0d,%0d",
                dut.ram[13], dut.ram[14], dut.ram[15], dut.ram[16], dut.ram[17],
                dut.ram[18], dut.ram[19]);
      $fclose(result_fd);
      $display("TinyViT smoke exit code: %0d", exit_code);
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
    $fatal(1, "Timed out waiting for TinyViT smoke exit");
  end
endmodule
