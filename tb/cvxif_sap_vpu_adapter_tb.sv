`timescale 1ns/1ps

module cvxif_sap_vpu_adapter_tb;
  import sap_vpu_pkg::*;

  logic clk;
  logic rst_n;

  logic        issue_valid;
  logic        issue_ready;
  logic        issue_accept;
  logic        issue_writeback;
  logic [3:0]  issue_id;
  logic [31:0] issue_instr;
  logic [31:0] issue_rs1;
  logic [31:0] issue_rs2;
  logic        commit_valid;
  logic        commit_kill;
  logic        result_valid;
  logic        result_ready;
  logic [3:0]  result_id;
  logic [31:0] result_data;
  logic        result_we;
  logic [4:0]  result_rd;
  logic        result_exc;
  logic        vpu_cmd_valid;
  logic        vpu_cmd_ready;
  logic [3:0]  vpu_cmd_id;
  logic [6:0]  vpu_cmd_op;
  logic [31:0] vpu_cmd_rs1;
  logic [31:0] vpu_cmd_rs2;
  logic [31:0] vpu_cmd_instr;
  logic        vpu_rsp_valid;
  logic        vpu_rsp_ready;
  logic [3:0]  vpu_rsp_id;
  logic [31:0] vpu_rsp_data;
  logic        vpu_rsp_exc;

  cvxif_sap_vpu_adapter dut (
    .clk_i(clk),
    .rst_ni(rst_n),
    .issue_valid_i(issue_valid),
    .issue_ready_o(issue_ready),
    .issue_accept_o(issue_accept),
    .issue_writeback_o(issue_writeback),
    .issue_id_i(issue_id),
    .issue_instr_i(issue_instr),
    .issue_rs1_i(issue_rs1),
    .issue_rs2_i(issue_rs2),
    .commit_valid_i(commit_valid),
    .commit_kill_i(commit_kill),
    .result_valid_o(result_valid),
    .result_ready_i(result_ready),
    .result_id_o(result_id),
    .result_data_o(result_data),
    .result_we_o(result_we),
    .result_rd_o(result_rd),
    .result_exc_o(result_exc),
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

  function automatic logic [31:0] instr(input logic [6:0] funct7, input logic [2:0] funct3);
    instr = {funct7, 5'd0, 5'd0, funct3, 5'd0, SAP_OPCODE_CUSTOM0};
  endfunction

  function automatic logic [31:0] instr_rd(input logic [6:0] funct7, input logic [2:0] funct3, input logic [4:0] rd);
    instr_rd = {funct7, 5'd0, 5'd0, funct3, rd, SAP_OPCODE_CUSTOM0};
  endfunction

  task automatic tick;
    begin
      clk = 1'b1;
      clk = 1'b0;
    end
  endtask

  task automatic clear_inputs;
    begin
      issue_valid  = 1'b0;
      issue_id     = '0;
      issue_instr  = '0;
      issue_rs1    = '0;
      issue_rs2    = '0;
      commit_valid = 1'b0;
      commit_kill  = 1'b0;
      result_ready = 1'b1;
      vpu_cmd_ready = 1'b1;
      vpu_rsp_valid = 1'b0;
      vpu_rsp_id    = '0;
      vpu_rsp_data  = '0;
      vpu_rsp_exc   = 1'b0;
    end
  endtask

  initial begin
    clk = 1'b0;
    rst_n = 1'b0;
    clear_inputs();
    tick();
    rst_n = 1'b1;
    tick();

    issue_valid = 1'b1;
    issue_id = 4'h3;
    issue_instr = 32'h0000_0013;
    assert(issue_ready);
    assert(!issue_accept);
    assert(!issue_writeback);
    assert(!vpu_cmd_valid);
    tick();
    clear_inputs();

    issue_valid = 1'b1;
    issue_id = 4'h7;
    issue_instr = instr(SAP_FUNCT7_VTLOAD, 3'b000);
    issue_rs1 = 32'h0403_0201;
    issue_rs2 = 32'h0;
    assert(issue_ready);
    assert(issue_accept);
    assert(!issue_writeback);
    assert(vpu_cmd_valid);
    assert(vpu_cmd_op == SAP_OP_VTLOAD);
    tick();
    clear_inputs();
    vpu_rsp_valid = 1'b1;
    vpu_rsp_id = 4'h7;
    assert(result_valid);
    assert(!result_we);
    tick();
    clear_inputs();

    issue_valid = 1'b1;
    issue_id = 4'h9;
    issue_instr = instr_rd(SAP_FUNCT7_VREADCNT, 3'b000, 5'd11);
    issue_rs1 = 32'h0000_0002;
    assert(issue_ready);
    assert(issue_accept);
    assert(issue_writeback);
    assert(vpu_cmd_valid);
    assert(vpu_cmd_id == 4'h9);
    assert(vpu_cmd_op == SAP_OP_VREADCNT);
    tick();
    clear_inputs();

    result_ready = 1'b0;
    vpu_rsp_valid = 1'b1;
    vpu_rsp_id = 4'h9;
    vpu_rsp_data = 32'hcafe_f00d;
    vpu_rsp_exc = 1'b1;
    assert(result_valid);
    assert(!vpu_rsp_ready);
    assert(result_id == 4'h9);
    assert(result_data == 32'hcafe_f00d);
    assert(result_we);
    assert(result_rd == 5'd11);
    assert(result_exc);
    result_ready = 1'b1;
    assert(vpu_rsp_ready);
    tick();
    clear_inputs();

    issue_valid = 1'b1;
    issue_id = 4'ha;
    issue_instr = instr(SAP_FUNCT7_VDOT, 3'b000);
    assert(vpu_cmd_valid);
    assert(issue_accept);
    assert(issue_writeback);
    tick();
    clear_inputs();
    commit_valid = 1'b1;
    commit_kill = 1'b1;
    tick();
    clear_inputs();
    vpu_rsp_valid = 1'b1;
    vpu_rsp_id = 4'ha;
    vpu_rsp_data = 32'h1;
    assert(!result_valid);

    $finish;
  end
endmodule
