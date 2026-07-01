`timescale 1ns/1ps

module corev_min_soc #(
  parameter int unsigned ROM_WORDS = 1024,
  parameter int unsigned RAM_WORDS = 1024,
  parameter logic [31:0] BOOT_ADDR = 32'h0000_0000,
  parameter logic [31:0] RAM_BASE  = 32'h0001_0000,
  parameter logic [31:0] UART_ADDR = 32'h1000_0000,
  parameter logic [31:0] EXIT_ADDR = 32'h1000_0004,
  parameter string       ROM_INIT_FILE = ""
) (
  input  logic        clk_i,
  input  logic        rst_ni,
  input  logic        fetch_enable_i,
  output logic        uart_tx_valid_o,
  output logic [7:0]  uart_tx_data_o,
  output logic        exit_valid_o,
  output logic [31:0] exit_code_o,
  output logic        core_sleep_o
);
  import cv32e40x_pkg::*;

  logic instr_req;
  logic instr_gnt;
  logic instr_rvalid;
  logic [31:0] instr_addr;
  logic [31:0] instr_rdata;

  logic data_req;
  logic data_gnt;
  logic data_rvalid;
  logic [31:0] data_addr;
  logic [3:0]  data_be;
  logic        data_we;
  logic [31:0] data_wdata;
  logic [31:0] data_rdata;

  logic [1:0] unused_instr_memtype;
  logic [2:0] unused_instr_prot;
  logic       unused_instr_dbg;
  logic [1:0] unused_data_memtype;
  logic [2:0] unused_data_prot;
  logic       unused_data_dbg;
  logic [5:0] unused_data_atop;
  logic [63:0] unused_mcycle;
  logic        unused_fencei_flush_req;
  logic        unused_debug_havereset;
  logic        unused_debug_running;
  logic        unused_debug_halted;
  logic        unused_debug_pc_valid;
  logic [31:0] unused_debug_pc;

  logic [31:0] rom [0:ROM_WORDS-1];
  logic [31:0] ram [0:RAM_WORDS-1];

  cv32e40x_if_xif xif();

  assign xif.compressed_ready       = 1'b1;
  assign xif.compressed_resp        = '0;
  assign xif.issue_ready            = 1'b1;
  assign xif.issue_resp             = '0;
  assign xif.mem_valid              = 1'b0;
  assign xif.mem_req                = '0;
  assign xif.mem_result_valid       = 1'b0;
  assign xif.mem_result             = '0;
  assign xif.result_valid           = 1'b0;
  assign xif.result                 = '0;

  initial begin
    if (ROM_INIT_FILE != "") begin
      $readmemh(ROM_INIT_FILE, rom);
    end
  end

  assign instr_gnt    = instr_req;
  assign instr_rvalid = instr_req;

  always_comb begin
    instr_rdata = 32'h0000_0013;
    if ((instr_addr >= BOOT_ADDR) && (((instr_addr - BOOT_ADDR) >> 2) < ROM_WORDS)) begin
      instr_rdata = rom[(instr_addr - BOOT_ADDR) >> 2];
    end
  end

  assign data_gnt    = data_req;
  assign data_rvalid = data_req;

  always_comb begin
    data_rdata = 32'h0000_0000;
    if ((data_addr >= RAM_BASE) && (((data_addr - RAM_BASE) >> 2) < RAM_WORDS)) begin
      data_rdata = ram[(data_addr - RAM_BASE) >> 2];
    end
  end

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      uart_tx_valid_o <= 1'b0;
      uart_tx_data_o  <= 8'h00;
      exit_valid_o    <= 1'b0;
      exit_code_o     <= 32'h0000_0000;
    end else begin
      uart_tx_valid_o <= 1'b0;
      if (data_req && data_gnt && data_we) begin
        if ((data_addr >= RAM_BASE) && (((data_addr - RAM_BASE) >> 2) < RAM_WORDS)) begin
          for (int unsigned i = 0; i < 4; i++) begin
            if (data_be[i]) begin
              ram[(data_addr - RAM_BASE) >> 2][8*i +: 8] <= data_wdata[8*i +: 8];
            end
          end
        end else if (data_addr == UART_ADDR) begin
          uart_tx_valid_o <= 1'b1;
          uart_tx_data_o  <= data_wdata[7:0];
        end else if (data_addr == EXIT_ADDR) begin
          exit_valid_o <= 1'b1;
          exit_code_o  <= data_wdata;
        end
      end
    end
  end

  cv32e40x_core #(
    .DEBUG(0),
    .X_EXT(0)
  ) core_i (
    .clk_i(clk_i),
    .rst_ni(rst_ni),
    .scan_cg_en_i(1'b0),
    .boot_addr_i(BOOT_ADDR),
    .dm_exception_addr_i(32'hf000_0000),
    .dm_halt_addr_i(32'hf000_0800),
    .mhartid_i(32'h0),
    .mimpid_patch_i(4'h0),
    .mtvec_addr_i(BOOT_ADDR),
    .instr_req_o(instr_req),
    .instr_gnt_i(instr_gnt),
    .instr_rvalid_i(instr_rvalid),
    .instr_addr_o(instr_addr),
    .instr_memtype_o(unused_instr_memtype),
    .instr_prot_o(unused_instr_prot),
    .instr_dbg_o(unused_instr_dbg),
    .instr_rdata_i(instr_rdata),
    .instr_err_i(1'b0),
    .data_req_o(data_req),
    .data_gnt_i(data_gnt),
    .data_rvalid_i(data_rvalid),
    .data_addr_o(data_addr),
    .data_be_o(data_be),
    .data_we_o(data_we),
    .data_wdata_o(data_wdata),
    .data_memtype_o(unused_data_memtype),
    .data_prot_o(unused_data_prot),
    .data_dbg_o(unused_data_dbg),
    .data_atop_o(unused_data_atop),
    .data_rdata_i(data_rdata),
    .data_err_i(1'b0),
    .data_exokay_i(1'b0),
    .mcycle_o(unused_mcycle),
    .time_i(64'h0),
    .xif_compressed_if(xif.cpu_compressed),
    .xif_issue_if(xif.cpu_issue),
    .xif_commit_if(xif.cpu_commit),
    .xif_mem_if(xif.cpu_mem),
    .xif_mem_result_if(xif.cpu_mem_result),
    .xif_result_if(xif.cpu_result),
    .irq_i(32'h0),
    .wu_wfe_i(1'b0),
    .clic_irq_i(1'b0),
    .clic_irq_id_i('0),
    .clic_irq_level_i('0),
    .clic_irq_priv_i('0),
    .clic_irq_shv_i(1'b0),
    .fencei_flush_req_o(unused_fencei_flush_req),
    .fencei_flush_ack_i(unused_fencei_flush_req),
    .debug_req_i(1'b0),
    .debug_havereset_o(unused_debug_havereset),
    .debug_running_o(unused_debug_running),
    .debug_halted_o(unused_debug_halted),
    .debug_pc_valid_o(unused_debug_pc_valid),
    .debug_pc_o(unused_debug_pc),
    .fetch_enable_i(fetch_enable_i),
    .core_sleep_o(core_sleep_o)
  );
endmodule
