`timescale 1ns/1ps

module corev_min_soc #(
  parameter int unsigned ROM_WORDS = 1024,
  parameter int unsigned RAM_WORDS = 1024,
  parameter logic [31:0] BOOT_ADDR = 32'h0000_0000,
  parameter logic [31:0] RAM_BASE  = 32'h0001_0000,
  parameter logic [31:0] UART_ADDR = 32'h1000_0000,
  parameter logic [31:0] EXIT_ADDR = 32'h1000_0004,
  parameter string       ROM_INIT_FILE = "",
  parameter string       RAM_INIT_FILE = ""
) (
  input  logic        clk_i,
  input  logic        rst_ni,
  input  logic        fetch_enable_i,
  output logic        uart_tx_valid_o,
  output logic [7:0]  uart_tx_data_o,
  output logic        exit_valid_o,
  output logic [31:0] exit_code_o,
  output logic        core_sleep_o,
  output logic        debug_instr_req_o,
  output logic        debug_data_req_o,
  output logic [31:0] debug_instr_addr_o,
  output logic [31:0] debug_instr_rdata_o
);
  import cv32e40x_pkg::*;

  localparam int unsigned X_ID_WIDTH = 4;

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

  logic [31:0] instr_rom [0:ROM_WORDS-1];
  logic [31:0] data_rom [0:ROM_WORDS-1];
  (* ram_style = "block" *) logic [31:0] ram [0:RAM_WORDS-1];
  logic        data_ram_req;
  logic        vpu_dma_ram_req;
  logic        data_ram_rsp;
  logic        vpu_dma_ram_rsp;
  logic [31:0] ram_req_addr;
  logic        ram_req_we;
  logic [3:0]  ram_req_be;
  logic [31:0] ram_req_wdata;
  logic [31:0] ram_rdata;
  logic [31:0] data_nonram_rdata;
  logic [31:0] vpu_dma_nonram_rdata;

  logic                  xif_issue_ready;
  logic                  xif_issue_accept;
  logic                  xif_issue_writeback;
  logic                  xif_result_valid;
  logic [X_ID_WIDTH-1:0] xif_result_id;
  logic [31:0]           xif_result_data;
  logic                  xif_result_we;
  logic [4:0]            xif_result_rd;
  logic                  xif_result_exc;

  logic                  vpu_cmd_valid;
  logic                  vpu_cmd_ready;
  logic [X_ID_WIDTH-1:0] vpu_cmd_id;
  logic [6:0]            vpu_cmd_op;
  logic [31:0]           vpu_cmd_rs1;
  logic [31:0]           vpu_cmd_rs2;
  logic [31:0]           vpu_cmd_instr;
  logic                  vpu_rsp_valid;
  logic                  vpu_rsp_ready;
  logic [X_ID_WIDTH-1:0] vpu_rsp_id;
  logic [31:0]           vpu_rsp_data;
  logic                  vpu_rsp_exc;
  logic                  vpu_dma_req;
  logic                  vpu_dma_gnt;
  logic [31:0]           vpu_dma_addr;
  logic                  vpu_dma_we;
  logic [3:0]            vpu_dma_be;
  logic [31:0]           vpu_dma_wdata;
  logic                  vpu_dma_rvalid;
  logic [31:0]           vpu_dma_rdata;
  logic                  vpu_dma_err;

  function automatic logic [31:0] read_instr_rom(input logic [31:0] addr);
    begin
      read_instr_rom = 32'h0000_0013;
      if ((addr >= BOOT_ADDR) && (((addr - BOOT_ADDR) >> 2) < ROM_WORDS)) begin
        read_instr_rom = instr_rom[(addr - BOOT_ADDR) >> 2];
      end
    end
  endfunction

  function automatic logic [31:0] read_data_rom(input logic [31:0] addr);
    begin
      read_data_rom = 32'h0000_0000;
      if ((addr >= BOOT_ADDR) && (((addr - BOOT_ADDR) >> 2) < ROM_WORDS)) begin
        read_data_rom = data_rom[(addr - BOOT_ADDR) >> 2];
      end
    end
  endfunction

  function automatic logic is_ram_addr(input logic [31:0] addr);
    begin
      is_ram_addr = (addr >= RAM_BASE) && (((addr - RAM_BASE) >> 2) < RAM_WORDS);
    end
  endfunction

  cv32e40x_if_xif xif();

  assign xif.compressed_ready        = 1'b1;
  assign xif.compressed_resp         = '0;
  assign xif.issue_ready             = xif_issue_ready;
  assign xif.issue_resp.accept       = xif_issue_accept;
  assign xif.issue_resp.writeback    = xif_issue_writeback;
  assign xif.issue_resp.dualwrite    = 1'b0;
  assign xif.issue_resp.dualread     = 3'b000;
  assign xif.issue_resp.loadstore    = 1'b0;
  assign xif.issue_resp.ecswrite     = 1'b0;
  assign xif.issue_resp.exc          = 1'b0;
  assign xif.mem_valid               = 1'b0;
  assign xif.mem_req                 = '0;
  assign xif.result_valid            = xif_result_valid;
  assign xif.result.id               = xif_result_id;
  assign xif.result.data             = xif_result_data;
  assign xif.result.rd               = xif_result_rd;
  assign xif.result.we               = xif_result_we;
  assign xif.result.ecsdata          = '0;
  assign xif.result.ecswe            = '0;
  assign xif.result.exc              = xif_result_exc;
  assign xif.result.exccode          = xif_result_exc ? 6'd2 : 6'd0;
  assign xif.result.err              = 1'b0;
  assign xif.result.dbg              = 1'b0;

  cvxif_sap_vpu_adapter #(
    .XLEN(32),
    .X_ID_WIDTH(X_ID_WIDTH)
  ) xif_adapter_i (
    .clk_i(clk_i),
    .rst_ni(rst_ni),
    .issue_valid_i(xif.issue_valid),
    .issue_ready_o(xif_issue_ready),
    .issue_accept_o(xif_issue_accept),
    .issue_writeback_o(xif_issue_writeback),
    .issue_id_i(xif.issue_req.id),
    .issue_instr_i(xif.issue_req.instr),
    .issue_rs1_i(xif.issue_req.rs[0]),
    .issue_rs2_i(xif.issue_req.rs[1]),
    .commit_valid_i(xif.commit_valid),
    .commit_kill_i(xif.commit.commit_kill),
    .result_valid_o(xif_result_valid),
    .result_ready_i(xif.result_ready),
    .result_id_o(xif_result_id),
    .result_data_o(xif_result_data),
    .result_we_o(xif_result_we),
    .result_rd_o(xif_result_rd),
    .result_exc_o(xif_result_exc),
    .vpu_cmd_valid_o(vpu_cmd_valid),
    .vpu_cmd_ready_i(vpu_cmd_ready),
    .vpu_cmd_id_o(vpu_cmd_id),
    .vpu_cmd_op_o(vpu_cmd_op),
    .vpu_cmd_rs1_o(vpu_cmd_rs1),
    .vpu_cmd_rs2_o(vpu_cmd_rs2),
    .vpu_cmd_instr_o(vpu_cmd_instr),
    .vpu_rsp_valid_i(vpu_rsp_valid),
    .vpu_rsp_ready_o(vpu_rsp_ready),
    .vpu_rsp_id_i(vpu_rsp_id),
    .vpu_rsp_data_i(vpu_rsp_data),
    .vpu_rsp_exc_i(vpu_rsp_exc)
  );

  sap_vpu_subsystem #(
    .XLEN(32),
    .X_ID_WIDTH(X_ID_WIDTH)
  ) vpu_i (
    .clk_i(clk_i),
    .rst_ni(rst_ni),
    .cmd_valid_i(vpu_cmd_valid),
    .cmd_ready_o(vpu_cmd_ready),
    .cmd_id_i(vpu_cmd_id),
    .cmd_op_i(vpu_cmd_op),
    .cmd_rs1_i(vpu_cmd_rs1),
    .cmd_rs2_i(vpu_cmd_rs2),
    .cmd_instr_i(vpu_cmd_instr),
    .rsp_valid_o(vpu_rsp_valid),
    .rsp_ready_i(vpu_rsp_ready),
    .rsp_id_o(vpu_rsp_id),
    .rsp_data_o(vpu_rsp_data),
    .rsp_exc_o(vpu_rsp_exc),
    .dma_req_o(vpu_dma_req),
    .dma_gnt_i(vpu_dma_gnt),
    .dma_addr_o(vpu_dma_addr),
    .dma_we_o(vpu_dma_we),
    .dma_be_o(vpu_dma_be),
    .dma_wdata_o(vpu_dma_wdata),
    .dma_rvalid_i(vpu_dma_rvalid),
    .dma_rdata_i(vpu_dma_rdata),
    .dma_err_i(vpu_dma_err)
  );

  initial begin
    if (ROM_INIT_FILE != "") begin
      $readmemh(ROM_INIT_FILE, instr_rom);
      $readmemh(ROM_INIT_FILE, data_rom);
    end
    if (RAM_INIT_FILE != "") begin
      $readmemh(RAM_INIT_FILE, ram);
    end
  end

  assign instr_gnt    = instr_req;
  assign debug_instr_req_o = instr_req;
  assign debug_data_req_o = data_req;
  assign debug_instr_addr_o = instr_addr;
  assign debug_instr_rdata_o = instr_rdata;

  assign data_gnt    = data_req && !vpu_dma_req;
  assign vpu_dma_gnt = vpu_dma_req;
  assign data_ram_req = data_req && data_gnt && is_ram_addr(data_addr);
  assign vpu_dma_ram_req = vpu_dma_req && vpu_dma_gnt && is_ram_addr(vpu_dma_addr);
  assign ram_req_addr = data_ram_req ? data_addr : vpu_dma_addr;
  assign ram_req_we = data_ram_req ? data_we : vpu_dma_we;
  assign ram_req_be = data_ram_req ? data_be : vpu_dma_be;
  assign ram_req_wdata = data_ram_req ? data_wdata : vpu_dma_wdata;
  assign data_rdata = data_ram_rsp ? ram_rdata : data_nonram_rdata;
  assign vpu_dma_rdata = vpu_dma_ram_rsp ? ram_rdata : vpu_dma_nonram_rdata;

  always_ff @(posedge clk_i) begin
    if (data_ram_req || vpu_dma_ram_req) begin
      ram_rdata <= ram[(ram_req_addr - RAM_BASE) >> 2];
      if (ram_req_we) begin
        for (int unsigned i = 0; i < 4; i++) begin
          if (ram_req_be[i]) begin
            ram[(ram_req_addr - RAM_BASE) >> 2][8*i +: 8] <= ram_req_wdata[8*i +: 8];
          end
        end
      end
    end
  end

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      instr_rvalid    <= 1'b0;
      instr_rdata     <= 32'h0000_0013;
      data_rvalid     <= 1'b0;
      data_ram_rsp    <= 1'b0;
      data_nonram_rdata <= 32'h0000_0000;
      vpu_dma_rvalid  <= 1'b0;
      vpu_dma_ram_rsp <= 1'b0;
      vpu_dma_nonram_rdata <= 32'h0000_0000;
      vpu_dma_err     <= 1'b0;
      uart_tx_valid_o <= 1'b0;
      uart_tx_data_o  <= 8'h00;
      exit_valid_o    <= 1'b0;
      exit_code_o     <= 32'h0000_0000;
    end else begin
      instr_rvalid    <= instr_req && instr_gnt;
      instr_rdata     <= read_instr_rom(instr_addr);
      data_rvalid     <= data_req && data_gnt;
      data_ram_rsp    <= data_ram_req;
      if (data_req && data_gnt && !data_ram_req) begin
        if ((data_addr >= BOOT_ADDR) && (((data_addr - BOOT_ADDR) >> 2) < ROM_WORDS)) begin
          data_nonram_rdata <= read_data_rom(data_addr);
        end else begin
          data_nonram_rdata <= 32'h0000_0000;
        end
      end
      vpu_dma_rvalid  <= vpu_dma_req && vpu_dma_gnt;
      vpu_dma_ram_rsp <= vpu_dma_ram_req;
      if (vpu_dma_req && vpu_dma_gnt && !vpu_dma_ram_req) begin
        vpu_dma_nonram_rdata <= 32'h0000_0000;
      end
      vpu_dma_err     <= vpu_dma_req && vpu_dma_gnt && !vpu_dma_ram_req;
      uart_tx_valid_o <= 1'b0;
      exit_valid_o    <= 1'b0;
      if (data_req && data_gnt && data_we) begin
        if (data_addr == UART_ADDR) begin
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
    .X_EXT(1)
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
