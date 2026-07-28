`timescale 1ns/1ps

module sap_vpu_davinci_top_tb;
  localparam int unsigned CLKS_PER_BIT = 10;
  localparam int unsigned EXPECTED_LEN = 14;

  logic sys_clk;
  logic sys_rst_n;
  logic uart_rxd;
  logic uart_txd;
  logic [3:0] led;

  sap_vpu_davinci_top #(
    .CLK_HZ(1_000_000),
    .UART_BAUD(100_000),
    .ROM_INIT_FILE("work/hello/sap_vpu_hello.hex")
  ) dut (
    .sys_clk(sys_clk),
    .sys_rst_n(sys_rst_n),
    .uart_rxd(uart_rxd),
    .uart_txd(uart_txd),
    .led(led)
  );

  always #5 sys_clk = ~sys_clk;

  function automatic logic [7:0] expected_byte(input int unsigned index);
    case (index)
      0: expected_byte = "S";
      1: expected_byte = "A";
      2: expected_byte = "P";
      3: expected_byte = "-";
      4: expected_byte = "V";
      5: expected_byte = "P";
      6: expected_byte = "U";
      7: expected_byte = " ";
      8: expected_byte = "h";
      9: expected_byte = "e";
      10: expected_byte = "l";
      11: expected_byte = "l";
      12: expected_byte = "o";
      13: expected_byte = 8'h0a;
      default: expected_byte = 8'h00;
    endcase
  endfunction

  task automatic receive_uart(output logic [7:0] data);
    begin
      @(negedge uart_txd);
      repeat (CLKS_PER_BIT / 2) @(posedge sys_clk);
      if (uart_txd !== 1'b0) $fatal(1, "UART start bit mismatch");
      for (int unsigned bit_index = 0; bit_index < 8; bit_index++) begin
        repeat (CLKS_PER_BIT) @(posedge sys_clk);
        data[bit_index] = uart_txd;
      end
      repeat (CLKS_PER_BIT) @(posedge sys_clk);
      if (uart_txd !== 1'b1) $fatal(1, "UART stop bit mismatch");
    end
  endtask

  initial begin
    logic [7:0] received;

    sys_clk = 1'b0;
    sys_rst_n = 1'b0;
    uart_rxd = 1'b1;
    repeat (10) @(posedge sys_clk);
    sys_rst_n = 1'b1;

    for (int unsigned index = 0; index < EXPECTED_LEN; index++) begin
      receive_uart(received);
      if (received !== expected_byte(index)) begin
        $fatal(1, "UART byte %0d expected 0x%02x got 0x%02x",
               index, expected_byte(index), received);
      end
    end

    wait (led[2]);
    if (led !== 4'b1111) $fatal(1, "Board status LEDs expected 1111 got %04b", led);
    $display("DAVINCI_HELLO_PASS: SAP-VPU hello, leds=%04b", led);
    $finish;
  end

  initial begin
    repeat (100000) @(posedge sys_clk);
    $fatal(1, "Timed out waiting for Davinci hello");
  end
endmodule
