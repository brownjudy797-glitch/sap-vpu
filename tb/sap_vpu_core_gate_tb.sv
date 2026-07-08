`timescale 1ns/1ps

module sap_vpu_core_gate_tb;
  import sap_vpu_pkg::*;

  logic       clk_i;
  logic       rst_ni;
  logic       cmd_valid_i;
  logic       cmd_ready_o;
  logic [3:0] cmd_id_i;
  logic [6:0] cmd_op_i;
  logic [31:0] cmd_rs1_i;
  logic [31:0] cmd_rs2_i;
  logic [31:0] cmd_instr_i;
  logic        rsp_valid_o;
  logic        rsp_ready_i;
  logic [3:0]  rsp_id_o;
  logic [31:0] rsp_data_o;
  logic        rsp_exc_o;

  sap_vpu_core dut (
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
    .rsp_exc_o(rsp_exc_o)
  );

  always #5 clk_i = ~clk_i;

  task automatic gate_fail(input string message);
    begin
      $display("GATE_SMOKE_FAIL: %s", message);
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

  task automatic wait_ready;
    begin
      for (int i = 0; i < 64; i++) begin
        @(negedge clk_i);
        if (cmd_ready_o === 1'b1) begin
          return;
        end
      end
      gate_fail("cmd_ready timeout");
    end
  endtask

  task automatic send_cmd(
    input logic [3:0]  id,
    input logic [6:0]  op,
    input logic [31:0] rs1,
    input logic [31:0] rs2
  );
    begin
      wait_ready();
      cmd_valid_i = 1'b1;
      cmd_id_i    = id;
      cmd_op_i    = op;
      cmd_rs1_i   = rs1;
      cmd_rs2_i   = rs2;
      @(posedge clk_i);
      #1;
      clear_cmd();
    end
  endtask

  task automatic expect_rsp(
    input logic [3:0]  id,
    input bit          check_data,
    input logic [31:0] data,
    input logic        exc
  );
    begin
      if (rsp_valid_o === 1'b1) begin
        if (rsp_id_o !== id) begin
          gate_fail("response id mismatch");
        end
        if (rsp_exc_o !== exc) begin
          gate_fail("response exception mismatch");
        end
        if (check_data && rsp_data_o !== data) begin
          gate_fail("response data mismatch");
        end
        return;
      end
      for (int i = 0; i < 128; i++) begin
        @(negedge clk_i);
        if (rsp_valid_o === 1'b1) begin
          if (rsp_id_o !== id) begin
            gate_fail("response id mismatch");
          end
          if (rsp_exc_o !== exc) begin
            gate_fail("response exception mismatch");
          end
          if (check_data && rsp_data_o !== data) begin
            gate_fail("response data mismatch");
          end
          return;
        end
      end
      gate_fail("response timeout");
    end
  endtask

  initial begin
    $dumpfile("sap_vpu_core_gate_tb.vcd");
    $dumpvars(0, sap_vpu_core_gate_tb);

    clk_i = 1'b0;
    rst_ni = 1'b0;
    rsp_ready_i = 1'b1;
    clear_cmd();

    repeat (6) @(posedge clk_i);
    rst_ni = 1'b1;
    repeat (4) @(posedge clk_i);

    send_cmd(4'h1, SAP_OP_VDOT, 32'h0102_0304, 32'h0101_0101);
    expect_rsp(4'h1, 1'b1, 32'd10, 1'b0);

    send_cmd(4'h2, SAP_OP_VSETPREC, 32'(SAP_PREC_INT4), 32'h0);
    expect_rsp(4'h2, 1'b1, 32'(SAP_PREC_INT4), 1'b0);

    send_cmd(4'h3, SAP_OP_VSETSPARSE_BMP, 32'h0000_000f, 32'h0);
    expect_rsp(4'h3, 1'b1, 32'h0000_000f, 1'b0);

    send_cmd(4'h4, SAP_OP_VDOT, 32'h1111_1111, 32'h1111_1111);
    expect_rsp(4'h4, 1'b1, 32'd4, 1'b0);

    send_cmd(4'h5, SAP_OP_VREADCNT, 32'(SAP_CNT_SKIPPED), 32'h0);
    expect_rsp(4'h5, 1'b1, 32'd4, 1'b0);

    send_cmd(4'h6, 7'h7f, 32'h0, 32'h0);
    expect_rsp(4'h6, 1'b0, 32'h0, 1'b1);

    repeat (4) @(posedge clk_i);
    $display("GATE_SMOKE_PASS");
    $finish;
  end
endmodule
