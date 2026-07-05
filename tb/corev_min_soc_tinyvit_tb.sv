`timescale 1ns/1ps

module corev_min_soc_tinyvit_tb;
  localparam int unsigned TIMEOUT_CYCLES = 30000;
  localparam logic [31:0] RESULT_MAGIC = 32'h5456_4954; // "TVIT"
  localparam int unsigned TINYVIT_ITERS = 16;

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

  task automatic expect_result(input int unsigned index, input logic [31:0] expected);
    if (dut.ram[index] !== expected) begin
      $fatal(1, "TinyViT result ram[%0d] expected %0d got %0d", index, expected, dut.ram[index]);
    end
  endtask

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
      expect_result(1, 32'd150 * TINYVIT_ITERS);
      expect_result(2, 32'd4 * TINYVIT_ITERS);
      expect_result(3, 32'd0);
      expect_result(6, 32'd24 * TINYVIT_ITERS);
      expect_result(7, 32'd2 * TINYVIT_ITERS);
      expect_result(8, 32'd0);
      expect_result(13, 32'd12 * TINYVIT_ITERS);
      expect_result(14, 32'd2 * TINYVIT_ITERS);
      expect_result(15, 32'd8 * TINYVIT_ITERS);
      expect_result(20, 32'd12 * TINYVIT_ITERS);
      expect_result(21, 32'd2 * TINYVIT_ITERS);
      expect_result(22, 32'd8 * TINYVIT_ITERS);
      expect_result(27, 32'd12 * TINYVIT_ITERS);
      expect_result(28, 32'd2 * TINYVIT_ITERS);
      expect_result(29, 32'd8 * TINYVIT_ITERS);
      expect_result(34, 32'd12 * TINYVIT_ITERS);
      expect_result(35, 32'd2 * TINYVIT_ITERS);
      expect_result(36, 32'd0);
      if ((dut.ram[4] == 32'd0) || (dut.ram[5] == 32'd0) ||
          (dut.ram[11] == 32'd0) || (dut.ram[12] == 32'd0) ||
          (dut.ram[18] == 32'd0) || (dut.ram[19] == 32'd0) ||
          (dut.ram[25] == 32'd0) || (dut.ram[26] == 32'd0) ||
          (dut.ram[32] == 32'd0) || (dut.ram[33] == 32'd0) ||
          (dut.ram[39] == 32'd0) || (dut.ram[40] == 32'd0)) begin
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
      $fdisplay(result_fd, "no_sparse_skip,int4,none,%0d,%0d,%0d,%0d,%0d,%0d,%0d",
                dut.ram[20], dut.ram[21], dut.ram[22], dut.ram[23], dut.ram[24],
                dut.ram[25], dut.ram[26]);
      $fdisplay(result_fd, "no_lane_gating,int4,bitmap,%0d,%0d,%0d,%0d,%0d,%0d,%0d",
                dut.ram[27], dut.ram[28], dut.ram[29], dut.ram[30], dut.ram[31],
                dut.ram[32], dut.ram[33]);
      $fdisplay(result_fd, "no_precision_gating,int8,bitmap,%0d,%0d,%0d,%0d,%0d,%0d,%0d",
                dut.ram[34], dut.ram[35], dut.ram[36], dut.ram[37], dut.ram[38],
                dut.ram[39], dut.ram[40]);
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
