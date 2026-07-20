`timescale 1ns/1ps

module sap_vpu_tiled_gemm #(
  parameter int XLEN       = 32,
  parameter int X_ID_WIDTH = 4
) (
  input  logic                   clk_i,
  input  logic                   rst_ni,

  input  logic                   load_valid_i,
  output logic                   load_ready_o,
  input  logic                   load_weight_i,
  input  logic [1:0]             load_index_i,
  input  logic [31:0]            load_data_i,

  input  logic                   start_valid_i,
  output logic                   start_ready_o,
  input  logic [2:0]             start_m_i,
  input  logic [2:0]             start_n_i,
  input  logic [3:0]             start_k_i,

  output logic                   busy_o,
  output logic                   done_o,
  output logic                   error_o,
  output logic                   result_valid_o,
  input  logic                   result_ready_i,
  output logic [1:0]             result_row_o,
  output logic [1:0]             result_column_o,
  output logic [31:0]            result_data_o,

  output logic                   vpu_cmd_valid_o,
  input  logic                   vpu_cmd_ready_i,
  output logic [X_ID_WIDTH-1:0]  vpu_cmd_id_o,
  output logic [6:0]             vpu_cmd_op_o,
  output logic [XLEN-1:0]        vpu_cmd_rs1_o,
  output logic [XLEN-1:0]        vpu_cmd_rs2_o,
  output logic [31:0]            vpu_cmd_instr_o,

  input  logic                   vpu_rsp_valid_i,
  output logic                   vpu_rsp_ready_o,
  input  logic [XLEN-1:0]        vpu_rsp_data_i,
  input  logic                   vpu_rsp_exc_i
);
  import sap_vpu_pkg::*;

  typedef enum logic [3:0] {
    S_IDLE,
    S_SEND_PREC,
    S_WAIT_PREC,
    S_SEND_SPARSE,
    S_WAIT_SPARSE,
    S_SEND_LANE,
    S_WAIT_LANE,
    S_SEND_DOT,
    S_WAIT_DOT,
    S_RESULT
  } state_t;

  state_t state_q;
  logic [31:0] lhs_spad_q [0:3];
  logic [31:0] rhs_spad_q [0:3];
  logic [2:0] m_size_q;
  logic [2:0] n_size_q;
  logic [3:0] k_size_q;
  logic [1:0] row_q;
  logic [1:0] column_q;
  logic       k_block_q;
  logic signed [31:0] accumulator_q;
  logic [31:0] result_q;
  logic done_q;
  logic error_q;
  logic [3:0] remaining_lanes;
  logic [2:0] block_lanes;
  logic [1:0] lhs_spad_index;
  logic [1:0] rhs_spad_index;

  assign load_ready_o    = (state_q == S_IDLE) && !start_valid_i;
  assign start_ready_o   = (state_q == S_IDLE);
  assign busy_o          = (state_q != S_IDLE);
  assign done_o          = done_q;
  assign error_o         = error_q;
  assign result_valid_o  = (state_q == S_RESULT);
  assign result_row_o    = row_q;
  assign result_column_o = column_q;
  assign result_data_o   = result_q;
  assign remaining_lanes = k_size_q - (k_block_q ? 4 : 0);
  assign block_lanes     = (remaining_lanes >= 4) ? 3'd4 : remaining_lanes[2:0];
  assign lhs_spad_index  = (k_size_q > 4) ? {row_q[0], k_block_q} : {1'b0, row_q[0]};
  assign rhs_spad_index  = (k_size_q > 4) ? {column_q[0], k_block_q} : {1'b0, column_q[0]};

  always_comb begin
    vpu_cmd_valid_o = 1'b0;
    vpu_cmd_id_o    = '0;
    vpu_cmd_op_o    = '0;
    vpu_cmd_rs1_o   = '0;
    vpu_cmd_rs2_o   = '0;
    vpu_cmd_instr_o = '0;
    vpu_rsp_ready_o = 1'b0;

    unique case (state_q)
      S_SEND_PREC: begin
        vpu_cmd_valid_o = 1'b1;
        vpu_cmd_op_o    = SAP_OP_VSETPREC;
        vpu_cmd_rs1_o   = XLEN'(SAP_PREC_INT8);
      end
      S_SEND_SPARSE: begin
        vpu_cmd_valid_o = 1'b1;
        vpu_cmd_op_o    = SAP_OP_VSETSPARSE_BMP;
        vpu_cmd_rs1_o   = XLEN'((32'h1 << block_lanes) - 1);
      end
      S_SEND_LANE: begin
        vpu_cmd_valid_o = 1'b1;
        vpu_cmd_op_o    = SAP_OP_VSETLANE;
        vpu_cmd_rs1_o   = XLEN'(block_lanes);
      end
      S_SEND_DOT: begin
        vpu_cmd_valid_o = 1'b1;
        vpu_cmd_op_o    = SAP_OP_VDOT;
        vpu_cmd_rs1_o   = XLEN'(lhs_spad_q[lhs_spad_index]);
        vpu_cmd_rs2_o   = XLEN'(rhs_spad_q[rhs_spad_index]);
      end
      S_WAIT_PREC, S_WAIT_SPARSE, S_WAIT_LANE, S_WAIT_DOT: begin
        vpu_rsp_ready_o = 1'b1;
      end
      default: begin
      end
    endcase
  end

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      state_q   <= S_IDLE;
      m_size_q  <= '0;
      n_size_q  <= '0;
      k_size_q  <= '0;
      row_q     <= '0;
      column_q  <= '0;
      k_block_q <= 1'b0;
      accumulator_q <= '0;
      result_q  <= '0;
      done_q    <= 1'b0;
      error_q   <= 1'b0;
      for (int unsigned i = 0; i < 4; i++) begin
        lhs_spad_q[i] <= '0;
        rhs_spad_q[i] <= '0;
      end
    end else begin
      done_q <= 1'b0;

      unique case (state_q)
        S_IDLE: begin
          if (start_valid_i) begin
            if ((start_m_i >= 1) && (start_m_i <= 2) &&
                (start_n_i >= 1) && (start_n_i <= 2) &&
                (start_k_i >= 1) && (start_k_i <= 8)) begin
              m_size_q <= start_m_i;
              n_size_q <= start_n_i;
              k_size_q <= start_k_i;
              row_q    <= '0;
              column_q <= '0;
              k_block_q <= 1'b0;
              accumulator_q <= '0;
              error_q  <= 1'b0;
              state_q  <= S_SEND_PREC;
            end else begin
              error_q <= 1'b1;
              done_q  <= 1'b1;
            end
          end else if (load_valid_i && load_ready_o) begin
            if (load_weight_i) begin
              rhs_spad_q[load_index_i] <= load_data_i;
            end else begin
              lhs_spad_q[load_index_i] <= load_data_i;
            end
          end
        end

        S_SEND_PREC: begin
          if (vpu_cmd_valid_o && vpu_cmd_ready_i) state_q <= S_WAIT_PREC;
        end
        S_WAIT_PREC: begin
          if (vpu_rsp_valid_i) begin
            if (vpu_rsp_exc_i) begin
              error_q <= 1'b1;
              done_q  <= 1'b1;
              state_q <= S_IDLE;
            end else begin
              state_q <= S_SEND_SPARSE;
            end
          end
        end
        S_SEND_SPARSE: begin
          if (vpu_cmd_valid_o && vpu_cmd_ready_i) state_q <= S_WAIT_SPARSE;
        end
        S_WAIT_SPARSE: begin
          if (vpu_rsp_valid_i) begin
            if (vpu_rsp_exc_i) begin
              error_q <= 1'b1;
              done_q  <= 1'b1;
              state_q <= S_IDLE;
            end else begin
              state_q <= S_SEND_LANE;
            end
          end
        end
        S_SEND_LANE: begin
          if (vpu_cmd_valid_o && vpu_cmd_ready_i) state_q <= S_WAIT_LANE;
        end
        S_WAIT_LANE: begin
          if (vpu_rsp_valid_i) begin
            if (vpu_rsp_exc_i) begin
              error_q <= 1'b1;
              done_q  <= 1'b1;
              state_q <= S_IDLE;
            end else begin
              state_q <= S_SEND_DOT;
            end
          end
        end
        S_SEND_DOT: begin
          if (vpu_cmd_valid_o && vpu_cmd_ready_i) state_q <= S_WAIT_DOT;
        end
        S_WAIT_DOT: begin
          if (vpu_rsp_valid_i) begin
            if (vpu_rsp_exc_i) begin
              error_q <= 1'b1;
              done_q  <= 1'b1;
              state_q <= S_IDLE;
            end else if (!k_block_q && (k_size_q > 4)) begin
              accumulator_q <= $signed(vpu_rsp_data_i[31:0]);
              k_block_q     <= 1'b1;
              state_q       <= S_SEND_SPARSE;
            end else begin
              result_q <= accumulator_q + $signed(vpu_rsp_data_i[31:0]);
              state_q  <= S_RESULT;
            end
          end
        end
        S_RESULT: begin
          if (result_ready_i) begin
            if ((column_q + 1) < n_size_q) begin
              column_q <= column_q + 1'b1;
              k_block_q <= 1'b0;
              accumulator_q <= '0;
              state_q  <= S_SEND_SPARSE;
            end else if ((row_q + 1) < m_size_q) begin
              row_q    <= row_q + 1'b1;
              column_q <= '0;
              k_block_q <= 1'b0;
              accumulator_q <= '0;
              state_q  <= S_SEND_SPARSE;
            end else begin
              done_q  <= 1'b1;
              state_q <= S_IDLE;
            end
          end
        end
        default: state_q <= S_IDLE;
      endcase
    end
  end
endmodule
