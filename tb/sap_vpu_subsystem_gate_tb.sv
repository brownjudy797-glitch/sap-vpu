`timescale 1ns/1ps

module sap_vpu_subsystem_gate_tb;
  import sap_vpu_pkg::*;

  localparam realtime DEFAULT_CLK_HALF_PERIOD_NS = 3.5715;
  localparam int unsigned DEFAULT_ITERATIONS = 128;
  localparam logic [31:0] LHS_BASE = 32'h0000_0100;
  localparam logic [31:0] RHS_BASE = 32'h0000_0200;
  localparam logic [31:0] OUT_BASE = 32'h0000_0300;

  logic        clk_i;
  logic        rst_ni;
  logic        cmd_valid_i;
  logic        cmd_ready_o;
  logic [3:0]  cmd_id_i;
  logic [6:0]  cmd_op_i;
  logic [31:0] cmd_rs1_i;
  logic [31:0] cmd_rs2_i;
  logic [31:0] cmd_instr_i;
  logic        rsp_valid_o;
  logic        rsp_ready_i;
  logic [3:0]  rsp_id_o;
  logic [31:0] rsp_data_o;
  logic        rsp_exc_o;
  logic        dma_req_o;
  logic        dma_gnt_i;
  logic [31:0] dma_addr_o;
  logic        dma_we_o;
  logic [3:0]  dma_be_o;
  logic [31:0] dma_wdata_o;
  logic        dma_rvalid_i;
  logic [31:0] dma_rdata_i;
  logic        dma_err_i;
  logic [31:0] result_mem [0:3];
  int unsigned read_transactions;
  int unsigned write_transactions;
  int unsigned iterations = DEFAULT_ITERATIONS;
  realtime     clk_half_period_ns = DEFAULT_CLK_HALF_PERIOD_NS;
  string       vcd_file = "sap_vpu_subsystem_gate.vcd";

  sap_vpu_subsystem dut (
    .clk_i(clk_i),
    .rst_ni(rst_ni),
    .cmd_valid_i(cmd_valid_i),
    .cmd_ready_o(cmd_ready_o),
    .cmd_id_i(cmd_id_i),
    .cmd_op_i(cmd_op_i),
    .cmd_rs1_i(cmd_rs1_i),
    .cmd_rs2_i(cmd_rs2_i),
    .cmd_instr_i(cmd_instr_i),
    .rsp_valid_o(rsp_valid_o),
    .rsp_ready_i(rsp_ready_i),
    .rsp_id_o(rsp_id_o),
    .rsp_data_o(rsp_data_o),
    .rsp_exc_o(rsp_exc_o),
    .dma_req_o(dma_req_o),
    .dma_gnt_i(dma_gnt_i),
    .dma_addr_o(dma_addr_o),
    .dma_we_o(dma_we_o),
    .dma_be_o(dma_be_o),
    .dma_wdata_o(dma_wdata_o),
    .dma_rvalid_i(dma_rvalid_i),
    .dma_rdata_i(dma_rdata_i),
    .dma_err_i(dma_err_i)
  );

  always #(clk_half_period_ns) clk_i = ~clk_i;
  assign dma_gnt_i = 1'b1;

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      dma_rvalid_i      <= 1'b0;
      dma_rdata_i       <= '0;
      dma_err_i         <= 1'b0;
      read_transactions <= 0;
      write_transactions <= 0;
      for (int i = 0; i < 4; i++) begin
        result_mem[i] <= '0;
      end
    end else begin
      dma_rvalid_i <= 1'b0;
      dma_err_i    <= 1'b0;
      if (dma_req_o && dma_gnt_i) begin
        dma_rvalid_i <= 1'b1;
        if (dma_we_o) begin
          write_transactions <= write_transactions + 1;
          if (dma_be_o !== 4'hf) begin
            dma_err_i <= 1'b1;
          end else begin
            case (dma_addr_o)
              OUT_BASE + 0:  result_mem[0] <= dma_wdata_o;
              OUT_BASE + 4:  result_mem[1] <= dma_wdata_o;
              OUT_BASE + 8:  result_mem[2] <= dma_wdata_o;
              OUT_BASE + 12: result_mem[3] <= dma_wdata_o;
              default:       dma_err_i <= 1'b1;
            endcase
          end
        end else begin
          read_transactions <= read_transactions + 1;
          case (dma_addr_o)
            LHS_BASE + 0: dma_rdata_i <= 32'h0403_0201;
            LHS_BASE + 4: dma_rdata_i <= 32'h0102_0304;
            RHS_BASE + 0: dma_rdata_i <= 32'h0101_0101;
            RHS_BASE + 4: dma_rdata_i <= 32'h0001_0001;
            default: begin
              dma_rdata_i <= '0;
              dma_err_i   <= 1'b1;
            end
          endcase
        end
      end
    end
  end

  task automatic gate_fail(input string message);
    begin
      $display("SUBSYSTEM_GATE_FAIL: %s", message);
      $finish;
    end
  endtask

  task automatic clear_cmd;
    begin
      cmd_valid_i = 1'b0;
      cmd_id_i    = '0;
      cmd_op_i    = '0;
      cmd_rs1_i   = '0;
      cmd_rs2_i   = '0;
      cmd_instr_i = '0;
    end
  endtask

  task automatic send_cmd(
    input logic [3:0]  id,
    input logic [6:0]  op,
    input logic [31:0] rs1,
    input logic [31:0] rs2
  );
    begin
      @(negedge clk_i);
      cmd_valid_i = 1'b1;
      cmd_id_i    = id;
      cmd_op_i    = op;
      cmd_rs1_i   = rs1;
      cmd_rs2_i   = rs2;
      for (int i = 0; i < 512; i++) begin
        @(posedge clk_i);
        if (cmd_ready_o === 1'b1) begin
          #1;
          clear_cmd();
          return;
        end
      end
      $display("SUBSYSTEM_GATE_CONTEXT: id=%0d op=0x%02x rsp_valid=%b dma_req=%b dma_rvalid=%b",
               id, op, rsp_valid_o, dma_req_o, dma_rvalid_i);
      gate_fail("command ready timeout");
    end
  endtask

  task automatic expect_rsp(
    input logic [3:0]  id,
    input logic [31:0] data
  );
    begin
      for (int i = 0; i < 4096; i++) begin
        if (rsp_valid_o === 1'b1) begin
          if (rsp_id_o !== id || rsp_exc_o !== 1'b0 || rsp_data_o !== data) begin
            gate_fail("response mismatch");
          end
          return;
        end
        @(negedge clk_i);
      end
      gate_fail("response timeout");
    end
  endtask

  task automatic run_tile(input int unsigned index);
    logic [3:0] id;
    begin
      id = index[3:0];
      send_cmd(id, SAP_OP_VTDMA, LHS_BASE, 32'd4);
      expect_rsp(id, 32'd2);
      send_cmd(id + 4'd1, SAP_OP_VTDMA, RHS_BASE, 32'd5);
      expect_rsp(id + 4'd1, 32'd2);
      send_cmd(id + 4'd2, SAP_OP_VTSTART, 32'h0000_0112, 32'h0);
      expect_rsp(id + 4'd2, 32'h0);
      send_cmd(id + 4'd3, SAP_OP_VTSTORE, OUT_BASE, 32'h0);
      expect_rsp(id + 4'd3, 32'h0);
      if (result_mem[0] !== 32'd10 || result_mem[1] !== 32'd4 ||
          result_mem[2] !== 32'd10 || result_mem[3] !== 32'd6) begin
        gate_fail("RAM writeback mismatch");
      end
    end
  endtask

  initial begin
    clk_i       = 1'b0;
    rst_ni      = 1'b0;
    rsp_ready_i = 1'b1;
    clear_cmd();

    if (!$value$plusargs("vcd=%s", vcd_file)) begin
      vcd_file = "sap_vpu_subsystem_gate.vcd";
    end
    if ($value$plusargs("iterations=%d", iterations) && iterations == 0) begin
      $fatal(1, "iterations must be positive");
    end
    if ($value$plusargs("clock_half_ns=%f", clk_half_period_ns) &&
        clk_half_period_ns <= 0.0) begin
      $fatal(1, "clock_half_ns must be positive");
    end

    #100;
    @(negedge clk_i);
    rst_ni = 1'b1;
    repeat (4) @(posedge clk_i);

    $dumpfile(vcd_file);
    $dumpvars(0, dut);
    for (int unsigned i = 0; i < iterations; i++) begin
      run_tile(i);
    end
    $dumpoff;

    send_cmd(4'he, SAP_OP_VREADCNT, 32'(SAP_CNT_MAC_ACTIVE), 32'h0);
    expect_rsp(4'he, 32'(iterations * 4));
    if (read_transactions != iterations * 4 ||
        write_transactions != iterations * 4) begin
      gate_fail("DMA transaction count mismatch");
    end

    $display("SUBSYSTEM_GATE_PASS: tiles=%0d reads=%0d writes=%0d",
             iterations, read_transactions, write_transactions);
    $finish;
  end

  initial begin
    repeat (1000000) @(posedge clk_i);
    gate_fail("simulation timeout");
  end
endmodule
