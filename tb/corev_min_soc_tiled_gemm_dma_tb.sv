`timescale 1ns/1ps

module corev_min_soc_tiled_gemm_dma_tb #(
  parameter string ROM_INIT_FILE = "work/tiled_gemm_dma_soc/sap_vpu_tiled_gemm_dma_soc.hex",
  parameter string RAM_INIT_FILE = "",
  parameter int unsigned EXPECTED_DMA_READS = 24,
  parameter bit EXPECT_POLICY_UART = 1'b0,
  parameter int unsigned EXPECTED_DENSE_MAC_ACTIVE = 192,
  parameter int unsigned EXPECTED_GLOBAL_MAC_ACTIVE = 154,
  parameter int unsigned EXPECTED_BUDGET_MAC_ACTIVE = 158,
  parameter int unsigned EXPECTED_DENSE_DMA_SAVED = 0,
  parameter int unsigned EXPECTED_GLOBAL_DMA_SAVED = 21,
  parameter int unsigned EXPECTED_BUDGET_DMA_SAVED = 19
);
  localparam int unsigned TIMEOUT_CYCLES = EXPECT_POLICY_UART ? 3000000 : 30000;
  localparam int unsigned FC2_SUM_RAM_WORD = 12;
  localparam int unsigned FC2_GLOBAL_SUM_RAM_WORD = 16;
  localparam int unsigned FC2_BUDGET_SUM_RAM_WORD = 24;
  localparam int unsigned WINDOW_ID_RAM_WORD = 60;

  logic clk;
  logic rst_n;
  logic fetch_enable;
  logic uart_tx_valid;
  logic [7:0] uart_tx_data;
  logic exit_valid;
  logic [31:0] exit_code;
  logic core_sleep;
  logic debug_instr_req;
  logic debug_data_req;
  logic [31:0] debug_instr_addr;
  logic [31:0] debug_instr_rdata;
  logic report_fc2_window;
  int unsigned dma_read_transactions;
  int parsed_fields;
  logic [31:0] dense_cycles;
  logic [31:0] dense_mac_active;
  logic [31:0] dense_dma_saved;
  logic [31:0] global_cycles;
  logic [31:0] global_mac_active;
  logic [31:0] global_dma_saved;
  logic [31:0] budget_cycles;
  logic [31:0] budget_mac_active;
  logic [31:0] budget_dma_saved;
  string ram_init_file;
  string uart_transcript;

  corev_min_soc #(
    .ROM_INIT_FILE(ROM_INIT_FILE),
    .RAM_INIT_FILE(RAM_INIT_FILE)
  ) dut (
    .clk_i(clk),
    .rst_ni(rst_n),
    .fetch_enable_i(fetch_enable),
    .uart_tx_valid_o(uart_tx_valid),
    .uart_tx_data_o(uart_tx_data),
    .exit_valid_o(exit_valid),
    .exit_code_o(exit_code),
    .core_sleep_o(core_sleep),
    .debug_instr_req_o(debug_instr_req),
    .debug_data_req_o(debug_data_req),
    .debug_instr_addr_o(debug_instr_addr),
    .debug_instr_rdata_o(debug_instr_rdata)
  );

  always #5 clk = ~clk;

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      dma_read_transactions <= 0;
    end else if (dut.vpu_dma_req && dut.vpu_dma_gnt && !dut.vpu_dma_we) begin
      dma_read_transactions <= dma_read_transactions + 1;
    end
    if (rst_n && uart_tx_valid) begin
      if (!EXPECT_POLICY_UART) begin
        $fatal(1, "Unexpected UART byte 0x%02x", uart_tx_data);
      end
      uart_transcript = {uart_transcript, uart_tx_data};
    end
    if (rst_n && exit_valid) begin
      if (exit_code !== 32'd1) begin
        $fatal(1, "Tiled GEMM DMA SoC smoke exit code expected 1 got %0d", exit_code);
      end
      if (!report_fc2_window && dma_read_transactions != EXPECTED_DMA_READS) begin
        $fatal(1, "Tiled GEMM DMA reads expected %0d got %0d",
               EXPECTED_DMA_READS, dma_read_transactions);
      end
      if (EXPECT_POLICY_UART) begin
        parsed_fields = $sscanf(uart_transcript,
            "D,%h,%h,%h\nG,%h,%h,%h\nB,%h,%h,%h\n",
            dense_cycles, dense_mac_active, dense_dma_saved,
            global_cycles, global_mac_active, global_dma_saved,
            budget_cycles, budget_mac_active, budget_dma_saved);
        if (parsed_fields != 9) begin
          $fatal(1, "Policy UART parse expected 9 fields got %0d: %s",
                 parsed_fields, uart_transcript);
        end
        if (dense_mac_active != EXPECTED_DENSE_MAC_ACTIVE ||
            global_mac_active != EXPECTED_GLOBAL_MAC_ACTIVE ||
            budget_mac_active != EXPECTED_BUDGET_MAC_ACTIVE ||
            dense_dma_saved != EXPECTED_DENSE_DMA_SAVED ||
            global_dma_saved != EXPECTED_GLOBAL_DMA_SAVED ||
            budget_dma_saved != EXPECTED_BUDGET_DMA_SAVED) begin
          $fatal(1, "Policy UART counters mismatch: %s", uart_transcript);
        end
        if (!(global_cycles < dense_cycles && budget_cycles < dense_cycles)) begin
          $fatal(1, "Policy UART cycle ordering mismatch: dense=%0d global=%0d budget=%0d",
                 dense_cycles, global_cycles, budget_cycles);
        end
        $display("Tile policy cycles: dense=%0d global=%0d budget=%0d",
                 dense_cycles, global_cycles, budget_cycles);
      end
      if (report_fc2_window) begin
        if (dma_read_transactions !=
            1072 - dut.ram[FC2_GLOBAL_SUM_RAM_WORD + 5] - dut.ram[FC2_BUDGET_SUM_RAM_WORD + 5]) begin
          $fatal(1, "TinyViT dense+policy DMA reads mismatch: got %0d", dma_read_transactions);
        end
        $display("TinyViT FC2 window %0d: %0d %0d %0d %0d",
                 dut.ram[WINDOW_ID_RAM_WORD],
                 $signed(dut.ram[FC2_SUM_RAM_WORD]),
                 $signed(dut.ram[FC2_SUM_RAM_WORD + 1]),
                 $signed(dut.ram[FC2_SUM_RAM_WORD + 2]),
                 $signed(dut.ram[FC2_SUM_RAM_WORD + 3]));
        $display("TinyViT FC2 global-l1-6p25 window %0d: %0d %0d %0d %0d",
                 dut.ram[WINDOW_ID_RAM_WORD],
                 $signed(dut.ram[FC2_GLOBAL_SUM_RAM_WORD]),
                 $signed(dut.ram[FC2_GLOBAL_SUM_RAM_WORD + 1]),
                 $signed(dut.ram[FC2_GLOBAL_SUM_RAM_WORD + 2]),
                 $signed(dut.ram[FC2_GLOBAL_SUM_RAM_WORD + 3]));
        $display("TinyViT FC2 l1-budget-2pct window %0d: %0d %0d %0d %0d",
                 dut.ram[WINDOW_ID_RAM_WORD],
                 $signed(dut.ram[FC2_BUDGET_SUM_RAM_WORD]),
                 $signed(dut.ram[FC2_BUDGET_SUM_RAM_WORD + 1]),
                 $signed(dut.ram[FC2_BUDGET_SUM_RAM_WORD + 2]),
                 $signed(dut.ram[FC2_BUDGET_SUM_RAM_WORD + 3]));
      end
      $display("Tiled GEMM DMA SoC smoke exit code: %0d", exit_code);
      $finish;
    end
  end

  initial begin
    clk = 1'b0;
    rst_n = 1'b0;
    fetch_enable = 1'b0;
    report_fc2_window = 1'b0;
    uart_transcript = "";
    if ($value$plusargs("ram_init=%s", ram_init_file)) begin
      $readmemh(ram_init_file, dut.ram);
      report_fc2_window = 1'b1;
    end

    repeat (5) @(posedge clk);
    rst_n = 1'b1;
    fetch_enable = 1'b1;

    repeat (TIMEOUT_CYCLES) @(posedge clk);
    $display("Timeout state: pc=0x%08x instr=0x%08x dma_reads=%0d data_req=%0b",
             debug_instr_addr, debug_instr_rdata, dma_read_transactions, debug_data_req);
    $display("CPU data: addr=0x%08x we=%0b rvalid=%0b ram_rsp=%0b; VPU DMA: req=%0b gnt=%0b addr=0x%08x we=%0b",
             dut.data_addr, dut.data_we, dut.data_rvalid, dut.data_ram_rsp,
             dut.vpu_dma_req, dut.vpu_dma_gnt, dut.vpu_dma_addr, dut.vpu_dma_we);
    $display("Output RAM: %0d %0d %0d %0d",
             $signed(dut.ram[16]), $signed(dut.ram[17]),
             $signed(dut.ram[18]), $signed(dut.ram[19]));
    $fatal(1, "Timed out waiting for tiled GEMM DMA SoC smoke exit");
  end
endmodule
