`timescale 1ns/1ps

module sap_vpu_core_tb;
  import sap_vpu_pkg::*;

  logic clk;
  logic rst_n;
  logic        cmd_valid;
  logic        cmd_ready;
  logic [3:0]  cmd_id;
  logic [6:0]  cmd_op;
  logic [31:0] cmd_rs1;
  logic [31:0] cmd_rs2;
  logic [31:0] cmd_instr;
  logic        rsp_valid;
  logic        rsp_ready;
  logic [3:0]  rsp_id;
  logic [31:0] rsp_data;
  logic        rsp_exc;

  sap_vpu_core dut (
    .clk_i(clk),
    .rst_ni(rst_n),
    .cmd_valid_i(cmd_valid),
    .cmd_ready_o(cmd_ready),
    .cmd_id_i(cmd_id),
    .cmd_op_i(cmd_op),
    .cmd_rs1_i(cmd_rs1),
    .cmd_rs2_i(cmd_rs2),
    .cmd_instr_i(cmd_instr),
    .rsp_valid_o(rsp_valid),
    .rsp_ready_i(rsp_ready),
    .rsp_id_o(rsp_id),
    .rsp_data_o(rsp_data),
    .rsp_exc_o(rsp_exc)
  );

  task automatic tick;
    begin
      clk = 1'b1;
      clk = 1'b0;
    end
  endtask

  task automatic clear_inputs;
    begin
      cmd_valid = 1'b0;
      cmd_id    = '0;
      cmd_op    = '0;
      cmd_rs1   = '0;
      cmd_rs2   = '0;
      cmd_instr = '0;
      rsp_ready = 1'b1;
    end
  endtask

  task automatic send_cmd(
    input logic [3:0] id,
    input logic [6:0] op,
    input logic [31:0] rs1,
    input logic [31:0] rs2
  );
    begin
      cmd_valid = 1'b1;
      cmd_id = id;
      cmd_op = op;
      cmd_rs1 = rs1;
      cmd_rs2 = rs2;
      assert(cmd_ready);
      tick();
      cmd_valid = 1'b0;
      assert(rsp_valid);
      assert(rsp_id == id);
      assert(!rsp_exc);
      tick();
    end
  endtask

  initial begin
    clk = 1'b0;
    rst_n = 1'b0;
    clear_inputs();
    tick();
    rst_n = 1'b1;
    tick();

    send_cmd(4'h1, SAP_OP_VDOT, 32'h0102_0304, 32'h0101_0101);
    assert(rsp_data == 32'd10);

    send_cmd(4'h2, SAP_OP_VSETPREC, 32'(SAP_PREC_INT4), 32'h0);
    assert(rsp_data == 32'(SAP_PREC_INT4));

    send_cmd(4'h3, SAP_OP_VSETSPARSE_BMP, 32'h0000_000f, 32'h0);
    assert(rsp_data == 32'h0000_000f);

    send_cmd(4'h4, SAP_OP_VDOT, 32'h1111_1111, 32'h1111_1111);
    assert(rsp_data == 32'd4);

    send_cmd(4'h5, SAP_OP_VREADCNT, 32'(SAP_CNT_SKIPPED), 32'h0);
    assert(rsp_data == 32'd4);

    send_cmd(4'h6, SAP_OP_VCLEARCNT, 32'h0, 32'h0);
    assert(rsp_data == 32'h0);

    send_cmd(4'h7, SAP_OP_VREADCNT, 32'(SAP_CNT_INST), 32'h0);
    assert(rsp_data == 32'd1);

    cmd_valid = 1'b1;
    cmd_id = 4'h8;
    cmd_op = 7'h7f;
    assert(cmd_ready);
    tick();
    cmd_valid = 1'b0;
    assert(rsp_valid);
    assert(rsp_exc);

    $finish;
  end
endmodule
