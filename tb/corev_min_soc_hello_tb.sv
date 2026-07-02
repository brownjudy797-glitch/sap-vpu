`timescale 1ns/1ps

module corev_min_soc_hello_tb;
  localparam int unsigned EXPECTED_LEN = 14;
  localparam int unsigned TIMEOUT_CYCLES = 20000;

  logic clk;
  logic rst_n;
  logic fetch_enable;
  logic uart_tx_valid;
  logic [7:0] uart_tx_data;
  logic exit_valid;
  logic [31:0] exit_code;
  logic core_sleep;

  int unsigned uart_count;

  corev_min_soc #(
    .ROM_INIT_FILE("work/hello/sap_vpu_hello.hex")
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

  function automatic logic [7:0] expected_byte(input int unsigned index);
    begin
      case (index)
        0:  expected_byte = "S";
        1:  expected_byte = "A";
        2:  expected_byte = "P";
        3:  expected_byte = "-";
        4:  expected_byte = "V";
        5:  expected_byte = "P";
        6:  expected_byte = "U";
        7:  expected_byte = " ";
        8:  expected_byte = "h";
        9:  expected_byte = "e";
        10: expected_byte = "l";
        11: expected_byte = "l";
        12: expected_byte = "o";
        13: expected_byte = 8'h0a;
        default: expected_byte = 8'h00;
      endcase
    end
  endfunction

  always #5 clk = ~clk;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      uart_count <= 0;
    end else begin
      if (uart_tx_valid) begin
        if (uart_count >= EXPECTED_LEN) begin
          $fatal(1, "Too many UART bytes; got extra 0x%02x", uart_tx_data);
        end
        if (uart_tx_data !== expected_byte(uart_count)) begin
          $fatal(1, "UART byte %0d expected 0x%02x got 0x%02x",
                 uart_count, expected_byte(uart_count), uart_tx_data);
        end
        uart_count <= uart_count + 1;
      end

      if (exit_valid) begin
        if (exit_code !== 32'd1) begin
          $fatal(1, "Exit code expected 1 got 0x%08x", exit_code);
        end
        if (uart_count != EXPECTED_LEN) begin
          $fatal(1, "UART length expected %0d got %0d", EXPECTED_LEN, uart_count);
        end
        $display("UART transcript: SAP-VPU hello");
        $display("Exit code: %0d", exit_code);
        $finish;
      end
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
    $fatal(1, "Timed out waiting for hello exit");
  end
endmodule
