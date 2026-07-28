`timescale 1ns/1ps

module sap_vpu_davinci_top #(
  parameter int unsigned TARGET_MHZ = 50,
  parameter int unsigned CLK_HZ = TARGET_MHZ * 1_000_000,
  parameter int unsigned UART_BAUD = 115_200,
  parameter string ROM_INIT_FILE = "sap_vpu_hello.hex"
) (
  input  logic       sys_clk,
  input  logic       sys_rst_n,
  input  logic       uart_rxd,
  output logic       uart_txd,
  output logic [3:0] led
);
  localparam int unsigned UART_FIFO_DEPTH = 32;
  localparam int unsigned UART_CLKS_PER_BIT = (CLK_HZ + UART_BAUD / 2) / UART_BAUD;
  localparam int unsigned UART_COUNTER_WIDTH = $clog2(UART_CLKS_PER_BIT);
  localparam int unsigned STATUS_COUNTER_WIDTH = $clog2(CLK_HZ);
  localparam int unsigned STATUS_PACKET_LAST = 20;

  logic [3:0] reset_sync;
  logic       core_clk;
  logic       clock_locked;
  logic       board_reset_n;
  logic       rst_ni;
  logic       soc_uart_valid;
  logic [7:0] soc_uart_data;
  logic       soc_exit_valid;
  logic [31:0] soc_exit_code;
  logic       core_sleep;
  logic       debug_instr_req;
  logic       debug_data_req;
  logic [31:0] debug_instr_addr;
  logic [31:0] debug_instr_rdata;
  logic       unused_uart_rxd;

  logic [7:0] uart_fifo [0:UART_FIFO_DEPTH-1];
  logic [4:0] fifo_write_ptr;
  logic [4:0] fifo_read_ptr;
  logic [5:0] fifo_count;
  logic       fifo_overflow;
  logic       fifo_push;
  logic       fifo_pop;
  logic       status_push;
  logic       status_active;
  logic [4:0] status_index;
  logic [STATUS_COUNTER_WIDTH-1:0] status_count;
  logic [31:0] status_instr_addr;
  logic [31:0] status_instr_rdata;
  logic [3:0] status_progress;
  logic [7:0] fifo_write_data;
  logic       tx_busy;
  logic [9:0] tx_shift;
  logic [3:0] tx_bit_index;
  logic [UART_COUNTER_WIDTH-1:0] tx_baud_count;
  logic       instr_seen;
  logic       data_seen;
  logic       exit_seen;
  logic       exit_pass;

  assign unused_uart_rxd = uart_rxd;
  assign rst_ni = reset_sync[3];
  assign board_reset_n = sys_rst_n && clock_locked;

  generate
    if (TARGET_MHZ == 50) begin : gen_clock_bypass
      assign core_clk = sys_clk;
      assign clock_locked = 1'b1;
    end else begin : gen_clock_mmcm
`ifdef VERILATOR
      assign core_clk = sys_clk;
      assign clock_locked = sys_rst_n;
`else
      logic clkfb;
      logic clkfb_buf;
      logic core_clk_raw;

      MMCME2_BASE #(
        .BANDWIDTH("OPTIMIZED"),
        .CLKIN1_PERIOD(20.000),
        .DIVCLK_DIVIDE(1),
        .CLKFBOUT_MULT_F(TARGET_MHZ == 70 ? 21.000 : 24.000),
        .CLKOUT0_DIVIDE_F(TARGET_MHZ == 60 ? 20.000 :
                          TARGET_MHZ == 70 ? 15.000 :
                          TARGET_MHZ == 80 ? 15.000 : 12.000)
      ) mmcm_i (
        .CLKIN1(sys_clk),
        .CLKFBIN(clkfb_buf),
        .RST(!sys_rst_n),
        .PWRDWN(1'b0),
        .CLKFBOUT(clkfb),
        .CLKFBOUTB(),
        .CLKOUT0(core_clk_raw),
        .CLKOUT0B(),
        .CLKOUT1(),
        .CLKOUT1B(),
        .CLKOUT2(),
        .CLKOUT2B(),
        .CLKOUT3(),
        .CLKOUT3B(),
        .CLKOUT4(),
        .CLKOUT5(),
        .CLKOUT6(),
        .LOCKED(clock_locked)
      );

      BUFG clkfb_buf_i (
        .I(clkfb),
        .O(clkfb_buf)
      );

      BUFG core_clk_buf_i (
        .I(core_clk_raw),
        .O(core_clk)
      );
`endif
    end
  endgenerate

  function automatic logic [7:0] hex_char(input logic [3:0] value);
    hex_char = value < 10 ? 8'h30 + value : 8'h41 + value - 10;
  endfunction

  function automatic logic [7:0] status_byte(input logic [4:0] index);
    if (index == 0) begin
      status_byte = "P";
    end else if (index <= 8) begin
      status_byte = hex_char(status_instr_addr >> ((8 - index) * 4));
    end else if (index == 9) begin
      status_byte = "I";
    end else if (index <= 17) begin
      status_byte = hex_char(status_instr_rdata >> ((17 - index) * 4));
    end else if (index == 18) begin
      status_byte = "S";
    end else if (index == 19) begin
      status_byte = hex_char(status_progress);
    end else begin
      status_byte = 8'h0a;
    end
  endfunction

  assign status_push = status_active && !soc_uart_valid;
  assign fifo_push = (soc_uart_valid || status_push) && (fifo_count < UART_FIFO_DEPTH);
  assign fifo_pop = !tx_busy && (fifo_count != 0);
  assign led = {exit_pass && !fifo_overflow, exit_seen, data_seen, instr_seen};
  assign fifo_write_data = soc_uart_valid ? soc_uart_data : status_byte(status_index);

  always_ff @(posedge core_clk or negedge board_reset_n) begin
    if (!board_reset_n) begin
      reset_sync <= '0;
    end else begin
      reset_sync <= {reset_sync[2:0], 1'b1};
    end
  end

  corev_min_soc #(
    .ROM_INIT_FILE(ROM_INIT_FILE)
  ) soc_i (
    .clk_i(core_clk),
    .rst_ni(rst_ni),
    .fetch_enable_i(rst_ni),
    .uart_tx_valid_o(soc_uart_valid),
    .uart_tx_data_o(soc_uart_data),
    .exit_valid_o(soc_exit_valid),
    .exit_code_o(soc_exit_code),
    .core_sleep_o(core_sleep),
    .debug_instr_req_o(debug_instr_req),
    .debug_data_req_o(debug_data_req),
    .debug_instr_addr_o(debug_instr_addr),
    .debug_instr_rdata_o(debug_instr_rdata)
  );

  always_ff @(posedge core_clk or negedge rst_ni) begin
    if (!rst_ni) begin
      fifo_write_ptr <= '0;
      fifo_read_ptr  <= '0;
      fifo_count     <= '0;
      fifo_overflow  <= 1'b0;
      status_count   <= '0;
      status_active  <= 1'b0;
      status_index   <= '0;
      status_instr_addr <= '0;
      status_instr_rdata <= '0;
      status_progress <= '0;
      tx_busy        <= 1'b0;
      tx_shift       <= 10'h3ff;
      tx_bit_index   <= '0;
      tx_baud_count  <= '0;
      uart_txd       <= 1'b1;
      instr_seen     <= 1'b0;
      data_seen      <= 1'b0;
      exit_seen      <= 1'b0;
      exit_pass      <= 1'b0;
    end else begin
      if (fifo_push) begin
        uart_fifo[fifo_write_ptr] <= fifo_write_data;
        fifo_write_ptr <= fifo_write_ptr + 1'b1;
      end else if (soc_uart_valid || status_push) begin
        fifo_overflow <= 1'b1;
      end

      if (!status_active) begin
        if (status_count == CLK_HZ - 1) begin
          status_count <= '0;
          status_active <= 1'b1;
          status_index <= '0;
          status_instr_addr <= debug_instr_addr;
          status_instr_rdata <= debug_instr_rdata;
          status_progress <= {exit_pass, exit_seen, data_seen, instr_seen};
        end else begin
          status_count <= status_count + 1'b1;
        end
      end else if (status_push && (fifo_count < UART_FIFO_DEPTH)) begin
        if (status_index == STATUS_PACKET_LAST) begin
          status_active <= 1'b0;
        end else begin
          status_index <= status_index + 1'b1;
        end
      end

      if (fifo_pop) begin
        fifo_read_ptr <= fifo_read_ptr + 1'b1;
      end

      case ({fifo_push, fifo_pop})
        2'b10: fifo_count <= fifo_count + 1'b1;
        2'b01: fifo_count <= fifo_count - 1'b1;
        default: fifo_count <= fifo_count;
      endcase

      if (fifo_pop) begin
        tx_shift      <= {1'b1, uart_fifo[fifo_read_ptr], 1'b0};
        tx_bit_index  <= 4'd0;
        tx_baud_count <= UART_CLKS_PER_BIT - 1;
        tx_busy       <= 1'b1;
        uart_txd      <= 1'b0;
      end else if (tx_busy) begin
        if (tx_baud_count == 0) begin
          tx_baud_count <= UART_CLKS_PER_BIT - 1;
          if (tx_bit_index == 9) begin
            tx_busy  <= 1'b0;
            uart_txd <= 1'b1;
          end else begin
            tx_bit_index <= tx_bit_index + 1'b1;
            uart_txd <= tx_shift[tx_bit_index + 1'b1];
          end
        end else begin
          tx_baud_count <= tx_baud_count - 1'b1;
        end
      end

      if (soc_exit_valid) begin
        exit_seen <= 1'b1;
        exit_pass <= (soc_exit_code == 32'd1);
      end
      if (debug_instr_req) instr_seen <= 1'b1;
      if (debug_data_req) data_seen <= 1'b1;
    end
  end
endmodule
