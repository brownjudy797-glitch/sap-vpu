// Minimal flattened CV-X-IF to SAP-VPU adapter contract.
//
// The first slice keeps the upstream CV-X-IF package out of this repository.
// A later CV32E40X SoC wrapper should map real CV-X-IF structs to these flat
// signals.

module cvxif_sap_vpu_adapter #(
  parameter int XLEN       = 32,
  parameter int X_ID_WIDTH = 4
) (
  input  logic                    clk_i,
  input  logic                    rst_ni,

  input  logic                    issue_valid_i,
  output logic                    issue_ready_o,
  input  logic [X_ID_WIDTH-1:0]   issue_id_i,
  input  logic [31:0]             issue_instr_i,
  input  logic [XLEN-1:0]         issue_rs1_i,
  input  logic [XLEN-1:0]         issue_rs2_i,

  input  logic                    commit_valid_i,
  input  logic                    commit_kill_i,

  output logic                    result_valid_o,
  input  logic                    result_ready_i,
  output logic [X_ID_WIDTH-1:0]   result_id_o,
  output logic [XLEN-1:0]         result_data_o,
  output logic                    result_we_o,
  output logic                    result_exc_o,

  output logic                    vpu_cmd_valid_o,
  input  logic                    vpu_cmd_ready_i,
  output logic [X_ID_WIDTH-1:0]   vpu_cmd_id_o,
  output logic [6:0]              vpu_cmd_op_o,
  output logic [XLEN-1:0]         vpu_cmd_rs1_o,
  output logic [XLEN-1:0]         vpu_cmd_rs2_o,
  output logic [31:0]             vpu_cmd_instr_o,

  input  logic                    vpu_rsp_valid_i,
  output logic                    vpu_rsp_ready_o,
  input  logic [X_ID_WIDTH-1:0]   vpu_rsp_id_i,
  input  logic [XLEN-1:0]         vpu_rsp_data_i
  ,
  input  logic                    vpu_rsp_exc_i
);
  import sap_vpu_pkg::*;

  logic [X_ID_WIDTH-1:0] pending_id_q;
  logic                  pending_q;
  logic                  pending_we_q;

  logic [6:0] funct7;
  logic [2:0] funct3;
  logic [6:0] decoded_op;
  logic       is_custom0;
  logic       is_supported;
  logic       scalar_write;

  assign funct7     = issue_instr_i[31:25];
  assign funct3     = issue_instr_i[14:12];
  assign is_custom0 = issue_instr_i[6:0] == SAP_OPCODE_CUSTOM0;

  always_comb begin
    decoded_op   = 7'h00;
    is_supported = 1'b0;
    scalar_write = 1'b0;

    unique case ({funct7, funct3})
      {SAP_FUNCT7_VSET, SAP_FUNCT3_VSET}: begin
        decoded_op   = SAP_OP_VSET;
        is_supported = 1'b1;
      end
      {SAP_FUNCT7_VMOV, SAP_FUNCT3_VMOV}: begin
        decoded_op   = SAP_OP_VMOV;
        is_supported = 1'b1;
        scalar_write = 1'b1;
      end
      {SAP_FUNCT7_VDOT, 3'b000}: begin
        decoded_op   = SAP_OP_VDOT;
        is_supported = 1'b1;
      end
      {SAP_FUNCT7_VSETPREC, 3'b000}: begin
        decoded_op   = SAP_OP_VSETPREC;
        is_supported = 1'b1;
      end
      {SAP_FUNCT7_VREADCNT, 3'b000}: begin
        decoded_op   = SAP_OP_VREADCNT;
        is_supported = 1'b1;
        scalar_write = 1'b1;
      end
      {SAP_FUNCT7_VSETLANE, 3'b000}: begin
        decoded_op   = SAP_OP_VSETLANE;
        is_supported = 1'b1;
      end
      {SAP_FUNCT7_VSETSPARSE_BMP, 3'b000}: begin
        decoded_op   = SAP_OP_VSETSPARSE_BMP;
        is_supported = 1'b1;
      end
      {SAP_FUNCT7_VCLEARCNT, 3'b000}: begin
        decoded_op   = SAP_OP_VCLEARCNT;
        is_supported = 1'b1;
      end
      default: begin
      end
    endcase

    is_supported = is_supported && is_custom0;
  end

  // ponytail: one in-flight op; add an ID scoreboard only when tests need it.
  assign issue_ready_o   = !pending_q && (!is_supported || vpu_cmd_ready_i);
  assign vpu_cmd_valid_o = issue_valid_i && issue_ready_o && is_supported;
  assign vpu_cmd_id_o    = issue_id_i;
  assign vpu_cmd_op_o    = decoded_op;
  assign vpu_cmd_rs1_o   = issue_rs1_i;
  assign vpu_cmd_rs2_o   = issue_rs2_i;
  assign vpu_cmd_instr_o = issue_instr_i;

  assign result_valid_o  = pending_q && vpu_rsp_valid_i;
  assign result_id_o     = vpu_rsp_id_i;
  assign result_data_o   = vpu_rsp_data_i;
  assign result_we_o     = pending_we_q;
  assign result_exc_o    = vpu_rsp_exc_i;
  assign vpu_rsp_ready_o = pending_q && result_ready_i;

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      pending_q    <= 1'b0;
      pending_id_q <= '0;
      pending_we_q <= 1'b0;
    end else begin
      if (commit_valid_i && commit_kill_i) begin
        pending_q <= 1'b0;
      end else if (result_valid_o && result_ready_i) begin
        pending_q <= 1'b0;
      end else if (vpu_cmd_valid_o && vpu_cmd_ready_i) begin
        pending_q    <= 1'b1;
        pending_id_q <= issue_id_i;
        pending_we_q <= scalar_write;
      end
    end
  end

endmodule
