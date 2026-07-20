`timescale 1ns/1ps

module sap_vpu_subsystem #(
  parameter int XLEN       = 32,
  parameter int X_ID_WIDTH = 4
) (
  input  logic                   clk_i,
  input  logic                   rst_ni,

  input  logic                   cmd_valid_i,
  output logic                   cmd_ready_o,
  input  logic [X_ID_WIDTH-1:0]  cmd_id_i,
  input  logic [6:0]             cmd_op_i,
  input  logic [XLEN-1:0]        cmd_rs1_i,
  input  logic [XLEN-1:0]        cmd_rs2_i,
  input  logic [31:0]            cmd_instr_i,

  output logic                   rsp_valid_o,
  input  logic                   rsp_ready_i,
  output logic [X_ID_WIDTH-1:0]  rsp_id_o,
  output logic [XLEN-1:0]        rsp_data_o,
  output logic                   rsp_exc_o
);
  import sap_vpu_pkg::*;

  logic is_tile_load;
  logic is_tile_start;
  logic is_tile_read;
  logic is_tile_op;
  logic load_args_valid;
  logic start_args_valid;

  logic                  local_rsp_valid_q;
  logic [X_ID_WIDTH-1:0] local_rsp_id_q;
  logic [XLEN-1:0]       local_rsp_data_q;
  logic                  local_rsp_exc_q;

  logic                  core_cmd_valid;
  logic                  core_cmd_ready;
  logic [X_ID_WIDTH-1:0] core_cmd_id;
  logic [6:0]            core_cmd_op;
  logic [XLEN-1:0]       core_cmd_rs1;
  logic [XLEN-1:0]       core_cmd_rs2;
  logic [31:0]           core_cmd_instr;
  logic                  core_rsp_valid;
  logic                  core_rsp_ready;
  logic [X_ID_WIDTH-1:0] core_rsp_id;
  logic [XLEN-1:0]       core_rsp_data;
  logic                  core_rsp_exc;

  logic                  tile_load_valid;
  logic                  tile_start_valid;
  logic                  tile_busy;
  logic                  tile_error;
  logic                  tile_result_valid;
  logic                  tile_result_ready;
  logic [31:0]           tile_result_data;
  logic                  tile_cmd_valid;
  logic                  tile_cmd_ready;
  logic [X_ID_WIDTH-1:0] tile_cmd_id;
  logic [6:0]            tile_cmd_op;
  logic [XLEN-1:0]       tile_cmd_rs1;
  logic [XLEN-1:0]       tile_cmd_rs2;
  logic [31:0]           tile_cmd_instr;
  logic                  tile_rsp_valid;
  logic                  tile_rsp_ready;
  logic [XLEN-1:0]       tile_rsp_data;
  logic                  tile_rsp_exc;

  assign is_tile_load  = cmd_op_i == SAP_OP_VTLOAD;
  assign is_tile_start = cmd_op_i == SAP_OP_VTSTART;
  assign is_tile_read  = cmd_op_i == SAP_OP_VTREAD;
  assign is_tile_op    = is_tile_load || is_tile_start || is_tile_read;

  assign load_args_valid = cmd_rs2_i[2:1] < 2;
  assign start_args_valid = (cmd_rs1_i[2:0] >= 1) && (cmd_rs1_i[2:0] <= 2) &&
                            (cmd_rs1_i[5:3] >= 1) && (cmd_rs1_i[5:3] <= 2) &&
                            (cmd_rs1_i[8:6] >= 1) && (cmd_rs1_i[8:6] <= 4);

  always_comb begin
    cmd_ready_o = 1'b0;
    if (!local_rsp_valid_q) begin
      if (is_tile_load) begin
        cmd_ready_o = !tile_busy;
      end else if (is_tile_start) begin
        cmd_ready_o = !tile_busy;
      end else if (is_tile_read) begin
        cmd_ready_o = tile_result_valid || (!tile_busy && tile_error);
      end else begin
        cmd_ready_o = !tile_busy && core_cmd_ready;
      end
    end
  end

  assign tile_load_valid  = cmd_valid_i && cmd_ready_o && is_tile_load && load_args_valid;
  assign tile_start_valid = cmd_valid_i && cmd_ready_o && is_tile_start && start_args_valid;
  assign tile_result_ready = cmd_valid_i && cmd_ready_o && is_tile_read && tile_result_valid;

  assign core_cmd_valid = tile_busy ? tile_cmd_valid :
                          (cmd_valid_i && cmd_ready_o && !is_tile_op);
  assign core_cmd_id    = tile_busy ? tile_cmd_id    : cmd_id_i;
  assign core_cmd_op    = tile_busy ? tile_cmd_op    : cmd_op_i;
  assign core_cmd_rs1   = tile_busy ? tile_cmd_rs1   : cmd_rs1_i;
  assign core_cmd_rs2   = tile_busy ? tile_cmd_rs2   : cmd_rs2_i;
  assign core_cmd_instr = tile_busy ? tile_cmd_instr : cmd_instr_i;
  assign tile_cmd_ready = tile_busy && core_cmd_ready;

  assign tile_rsp_valid = tile_busy && core_rsp_valid;
  assign tile_rsp_data  = core_rsp_data;
  assign tile_rsp_exc   = core_rsp_exc;
  assign core_rsp_ready = tile_busy ? tile_rsp_ready : (!local_rsp_valid_q && rsp_ready_i);

  assign rsp_valid_o = local_rsp_valid_q || (!tile_busy && core_rsp_valid);
  assign rsp_id_o    = local_rsp_valid_q ? local_rsp_id_q   : core_rsp_id;
  assign rsp_data_o  = local_rsp_valid_q ? local_rsp_data_q : core_rsp_data;
  assign rsp_exc_o   = local_rsp_valid_q ? local_rsp_exc_q  : core_rsp_exc;

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      local_rsp_valid_q <= 1'b0;
      local_rsp_id_q    <= '0;
      local_rsp_data_q  <= '0;
      local_rsp_exc_q   <= 1'b0;
    end else begin
      if (local_rsp_valid_q && rsp_ready_i) begin
        local_rsp_valid_q <= 1'b0;
      end
      if (cmd_valid_i && cmd_ready_o && is_tile_op) begin
        local_rsp_valid_q <= 1'b1;
        local_rsp_id_q    <= cmd_id_i;
        local_rsp_data_q  <= is_tile_read ? XLEN'(tile_result_data) : '0;
        local_rsp_exc_q   <= (is_tile_load && !load_args_valid) ||
                             (is_tile_start && !start_args_valid) ||
                             (is_tile_read && tile_error && !tile_result_valid);
      end
    end
  end

  sap_vpu_tiled_gemm #(
    .XLEN(XLEN),
    .X_ID_WIDTH(X_ID_WIDTH)
  ) tiled_gemm_i (
    .clk_i(clk_i),
    .rst_ni(rst_ni),
    .load_valid_i(tile_load_valid),
    .load_ready_o(),
    .load_weight_i(cmd_rs2_i[0]),
    .load_index_i(cmd_rs2_i[2:1]),
    .load_data_i(cmd_rs1_i[31:0]),
    .start_valid_i(tile_start_valid),
    .start_ready_o(),
    .start_m_i(cmd_rs1_i[2:0]),
    .start_n_i(cmd_rs1_i[5:3]),
    .start_k_i(cmd_rs1_i[8:6]),
    .busy_o(tile_busy),
    .done_o(),
    .error_o(tile_error),
    .result_valid_o(tile_result_valid),
    .result_ready_i(tile_result_ready),
    .result_row_o(),
    .result_column_o(),
    .result_data_o(tile_result_data),
    .vpu_cmd_valid_o(tile_cmd_valid),
    .vpu_cmd_ready_i(tile_cmd_ready),
    .vpu_cmd_id_o(tile_cmd_id),
    .vpu_cmd_op_o(tile_cmd_op),
    .vpu_cmd_rs1_o(tile_cmd_rs1),
    .vpu_cmd_rs2_o(tile_cmd_rs2),
    .vpu_cmd_instr_o(tile_cmd_instr),
    .vpu_rsp_valid_i(tile_rsp_valid),
    .vpu_rsp_ready_o(tile_rsp_ready),
    .vpu_rsp_data_i(tile_rsp_data),
    .vpu_rsp_exc_i(tile_rsp_exc)
  );

  sap_vpu_core #(
    .XLEN(XLEN),
    .X_ID_WIDTH(X_ID_WIDTH)
  ) core_i (
    .clk_i(clk_i),
    .rst_ni(rst_ni),
    .cmd_valid_i(core_cmd_valid),
    .cmd_ready_o(core_cmd_ready),
    .cmd_id_i(core_cmd_id),
    .cmd_op_i(core_cmd_op),
    .cmd_rs1_i(core_cmd_rs1),
    .cmd_rs2_i(core_cmd_rs2),
    .cmd_instr_i(core_cmd_instr),
    .rsp_valid_o(core_rsp_valid),
    .rsp_ready_i(core_rsp_ready),
    .rsp_id_o(core_rsp_id),
    .rsp_data_o(core_rsp_data),
    .rsp_exc_o(core_rsp_exc)
  );

endmodule
