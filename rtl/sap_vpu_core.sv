`timescale 1ns/1ps

module sap_vpu_core #(
  parameter int XLEN       = 32,
  parameter int X_ID_WIDTH = 4
) (
  input  logic                    clk_i,
  input  logic                    rst_ni,

  input  logic                    cmd_valid_i,
  output logic                    cmd_ready_o,
  input  logic [X_ID_WIDTH-1:0]   cmd_id_i,
  input  logic [6:0]              cmd_op_i,
  input  logic [XLEN-1:0]         cmd_rs1_i,
  input  logic [XLEN-1:0]         cmd_rs2_i,
  input  logic [31:0]             cmd_instr_i,

  output logic                    rsp_valid_o,
  input  logic                    rsp_ready_i,
  output logic [X_ID_WIDTH-1:0]   rsp_id_o,
  output logic [XLEN-1:0]         rsp_data_o,
  output logic                    rsp_exc_o
);
  import sap_vpu_pkg::*;

  logic [1:0]  precision_q;
  logic [31:0] sparse_bitmap_q;
  logic [4:0]  active_lanes_q;
  logic [31:0] control_q;

  logic [31:0] cycle_count_q;
  logic [31:0] inst_count_q;
  logic [31:0] mac_active_q;
  logic [31:0] skipped_count_q;

  logic                  rsp_valid_q;
  logic [X_ID_WIDTH-1:0] rsp_id_q;
  logic [XLEN-1:0]       rsp_data_q;
  logic                  rsp_exc_q;

  localparam int unsigned VDOT_SUM_GROUPS = (SAP_FRONT_MAX_LANES + 3) / 4;

  logic                  vdot_pending_q;
  logic                  vdot_sum_pending_q;
  logic                  vdot_elem_pending_q;
  logic [X_ID_WIDTH-1:0] vdot_id_q;
  logic signed [31:0]    vdot_lhs_q [0:SAP_FRONT_MAX_LANES-1];
  logic signed [31:0]    vdot_rhs_q [0:SAP_FRONT_MAX_LANES-1];
  logic signed [31:0]    vdot_product_q [0:SAP_FRONT_MAX_LANES-1];
  logic signed [31:0]    vdot_sum_q [0:VDOT_SUM_GROUPS-1];
  logic [4:0]            vdot_skipped_q;

  assign cmd_ready_o = !rsp_valid_q && !vdot_elem_pending_q && !vdot_pending_q && !vdot_sum_pending_q;
  assign rsp_valid_o = rsp_valid_q;
  assign rsp_id_o    = rsp_id_q;
  assign rsp_data_o  = rsp_data_q;
  assign rsp_exc_o   = rsp_exc_q;

  function automatic int unsigned lanes_for_precision(input logic [1:0] precision);
    begin
      unique case (precision)
        SAP_PREC_INT8: lanes_for_precision = 4;
        SAP_PREC_INT4: lanes_for_precision = 8;
        SAP_PREC_INT2: lanes_for_precision = 16;
        default:       lanes_for_precision = 4;
      endcase
    end
  endfunction

  function automatic logic signed [31:0] packed_elem(
    input logic [31:0] word,
    input int unsigned idx,
    input logic [1:0] precision
  );
    begin
      packed_elem = '0;
      unique case (precision)
        SAP_PREC_INT8: begin
          unique case (idx[1:0])
            2'd0: packed_elem = $signed({{24{word[7]}},  word[7:0]});
            2'd1: packed_elem = $signed({{24{word[15]}}, word[15:8]});
            2'd2: packed_elem = $signed({{24{word[23]}}, word[23:16]});
            2'd3: packed_elem = $signed({{24{word[31]}}, word[31:24]});
          endcase
        end
        SAP_PREC_INT4: begin
          unique case (idx[2:0])
            3'd0: packed_elem = $signed({{28{word[3]}},  word[3:0]});
            3'd1: packed_elem = $signed({{28{word[7]}},  word[7:4]});
            3'd2: packed_elem = $signed({{28{word[11]}}, word[11:8]});
            3'd3: packed_elem = $signed({{28{word[15]}}, word[15:12]});
            3'd4: packed_elem = $signed({{28{word[19]}}, word[19:16]});
            3'd5: packed_elem = $signed({{28{word[23]}}, word[23:20]});
            3'd6: packed_elem = $signed({{28{word[27]}}, word[27:24]});
            3'd7: packed_elem = $signed({{28{word[31]}}, word[31:28]});
          endcase
        end
        SAP_PREC_INT2: begin
          unique case (idx[3:0])
            4'd0:  packed_elem = $signed({{30{word[1]}},  word[1:0]});
            4'd1:  packed_elem = $signed({{30{word[3]}},  word[3:2]});
            4'd2:  packed_elem = $signed({{30{word[5]}},  word[5:4]});
            4'd3:  packed_elem = $signed({{30{word[7]}},  word[7:6]});
            4'd4:  packed_elem = $signed({{30{word[9]}},  word[9:8]});
            4'd5:  packed_elem = $signed({{30{word[11]}}, word[11:10]});
            4'd6:  packed_elem = $signed({{30{word[13]}}, word[13:12]});
            4'd7:  packed_elem = $signed({{30{word[15]}}, word[15:14]});
            4'd8:  packed_elem = $signed({{30{word[17]}}, word[17:16]});
            4'd9:  packed_elem = $signed({{30{word[19]}}, word[19:18]});
            4'd10: packed_elem = $signed({{30{word[21]}}, word[21:20]});
            4'd11: packed_elem = $signed({{30{word[23]}}, word[23:22]});
            4'd12: packed_elem = $signed({{30{word[25]}}, word[25:24]});
            4'd13: packed_elem = $signed({{30{word[27]}}, word[27:26]});
            4'd14: packed_elem = $signed({{30{word[29]}}, word[29:28]});
            4'd15: packed_elem = $signed({{30{word[31]}}, word[31:30]});
          endcase
        end
        default: begin
          unique case (idx[1:0])
            2'd0: packed_elem = $signed({{24{word[7]}},  word[7:0]});
            2'd1: packed_elem = $signed({{24{word[15]}}, word[15:8]});
            2'd2: packed_elem = $signed({{24{word[23]}}, word[23:16]});
            2'd3: packed_elem = $signed({{24{word[31]}}, word[31:24]});
          endcase
        end
      endcase
    end
  endfunction

  function automatic logic [XLEN-1:0] counter_value(
    input logic [2:0] selector,
    input logic [31:0] next_inst_count
  );
    begin
      unique case (selector)
        SAP_CNT_CYCLE:      counter_value = XLEN'(cycle_count_q);
        SAP_CNT_INST:       counter_value = XLEN'(next_inst_count);
        SAP_CNT_MAC_ACTIVE: counter_value = XLEN'(mac_active_q);
        SAP_CNT_SKIPPED:    counter_value = XLEN'(skipped_count_q);
        SAP_CNT_SPARSE:     counter_value = XLEN'(sparse_bitmap_q);
        SAP_CNT_LANE:       counter_value = XLEN'(active_lanes_q);
        default:            counter_value = '0;
      endcase
    end
  endfunction

  function automatic logic signed [31:0] precision_product(
    input logic signed [31:0] lhs,
    input logic signed [31:0] rhs,
    input logic [1:0] precision
  );
    logic signed [7:0]  lhs8;
    logic signed [7:0]  rhs8;
    logic signed [15:0] prod8;
    logic signed [3:0]  lhs4;
    logic signed [3:0]  rhs4;
    logic signed [7:0]  prod4;
    logic signed [1:0]  lhs2;
    logic signed [1:0]  rhs2;
    logic signed [3:0]  prod2;
    begin
      lhs8 = $signed(lhs[7:0]);
      rhs8 = $signed(rhs[7:0]);
      prod8 = lhs8 * rhs8;
      lhs4 = $signed(lhs[3:0]);
      rhs4 = $signed(rhs[3:0]);
      prod4 = lhs4 * rhs4;
      lhs2 = $signed(lhs[1:0]);
      rhs2 = $signed(rhs[1:0]);
      prod2 = lhs2 * rhs2;

      unique case (precision)
        SAP_PREC_INT8: precision_product = $signed({{16{prod8[15]}}, prod8});
        SAP_PREC_INT4: precision_product = $signed({{24{prod4[7]}}, prod4});
        SAP_PREC_INT2: precision_product = $signed({{28{prod2[3]}}, prod2});
        default:       precision_product = $signed({{16{prod8[15]}}, prod8});
      endcase
    end
  endfunction

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      precision_q     <= SAP_PREC_INT8;
      sparse_bitmap_q <= 32'hffff_ffff;
      active_lanes_q  <= SAP_FRONT_MAX_LANES[4:0];
      control_q       <= '0;
      cycle_count_q   <= '0;
      inst_count_q    <= '0;
      mac_active_q    <= '0;
      skipped_count_q <= '0;
      rsp_valid_q     <= 1'b0;
      rsp_id_q        <= '0;
      rsp_data_q      <= '0;
      rsp_exc_q       <= 1'b0;
      vdot_pending_q  <= 1'b0;
      vdot_sum_pending_q <= 1'b0;
      vdot_elem_pending_q <= 1'b0;
      vdot_id_q       <= '0;
      vdot_skipped_q  <= '0;
      for (int unsigned i = 0; i < SAP_FRONT_MAX_LANES; i++) begin
        vdot_lhs_q[i]     <= '0;
        vdot_rhs_q[i]     <= '0;
        vdot_product_q[i] <= '0;
      end
      for (int unsigned i = 0; i < VDOT_SUM_GROUPS; i++) begin
        vdot_sum_q[i] <= '0;
      end
    end else begin
      int signed   dot_acc;
      int signed   dot_product;
      int unsigned lanes;
      int unsigned skipped;
      int unsigned next_inst_count;

      cycle_count_q <= cycle_count_q + 32'd1;

      if (rsp_valid_q && rsp_ready_i) begin
        rsp_valid_q <= 1'b0;
      end

      if (vdot_sum_pending_q && !rsp_valid_q) begin
        dot_acc = 0;
        for (int unsigned i = 0; i < VDOT_SUM_GROUPS; i++) begin
          dot_acc += vdot_sum_q[i];
        end
        rsp_valid_q     <= 1'b1;
        rsp_id_q        <= vdot_id_q;
        rsp_data_q      <= XLEN'(dot_acc);
        rsp_exc_q       <= 1'b0;
        mac_active_q    <= mac_active_q + 32'd1;
        skipped_count_q <= skipped_count_q + 32'(vdot_skipped_q);
        vdot_sum_pending_q <= 1'b0;
      end else if (vdot_pending_q && !rsp_valid_q) begin
        for (int unsigned group = 0; group < VDOT_SUM_GROUPS; group++) begin
          dot_acc = 0;
          for (int unsigned lane = 0; lane < 4; lane++) begin
            if (((group * 4) + lane) < SAP_FRONT_MAX_LANES) begin
              dot_acc += vdot_product_q[(group * 4) + lane];
            end
          end
          vdot_sum_q[group] <= dot_acc;
        end
        vdot_pending_q     <= 1'b0;
        vdot_sum_pending_q <= 1'b1;
      end else if (vdot_elem_pending_q && !rsp_valid_q) begin
        for (int unsigned i = 0; i < SAP_FRONT_MAX_LANES; i++) begin
          dot_product = precision_product(vdot_lhs_q[i], vdot_rhs_q[i], precision_q);
          vdot_product_q[i] <= dot_product;
        end
        vdot_elem_pending_q <= 1'b0;
        vdot_pending_q      <= 1'b1;
      end

      if (cmd_valid_i && cmd_ready_o) begin
        dot_acc = 0;
        skipped = 0;
        lanes = lanes_for_precision(precision_q);
        next_inst_count = inst_count_q + 32'd1;

        rsp_valid_q <= (cmd_op_i != SAP_OP_VDOT);
        rsp_id_q    <= cmd_id_i;
        rsp_data_q  <= '0;
        rsp_exc_q   <= 1'b0;
        inst_count_q <= next_inst_count[31:0];

        unique case (cmd_op_i)
          SAP_OP_VSET: begin
            control_q  <= cmd_rs1_i[31:0];
            rsp_data_q <= cmd_rs1_i;
          end

          SAP_OP_VMOV: begin
            rsp_data_q <= cmd_rs1_i;
          end

          SAP_OP_VSETPREC: begin
            if (cmd_rs1_i[1:0] <= SAP_PREC_INT2) begin
              precision_q <= cmd_rs1_i[1:0];
              rsp_data_q  <= XLEN'(cmd_rs1_i[1:0]);
            end else begin
              rsp_exc_q <= 1'b1;
            end
          end

          SAP_OP_VSETSPARSE_BMP: begin
            sparse_bitmap_q <= cmd_rs1_i[31:0];
            rsp_data_q      <= cmd_rs1_i;
          end

          SAP_OP_VSETLANE: begin
            active_lanes_q <= cmd_rs1_i[4:0];
            rsp_data_q     <= XLEN'(cmd_rs1_i[4:0]);
          end

          SAP_OP_VDOT: begin
            for (int unsigned i = 0; i < SAP_FRONT_MAX_LANES; i++) begin
              if (i < lanes) begin
                if ((i < active_lanes_q) && sparse_bitmap_q[i]) begin
                  vdot_lhs_q[i] <= packed_elem(cmd_rs1_i[31:0], i, precision_q);
                  vdot_rhs_q[i] <= packed_elem(cmd_rs2_i[31:0], i, precision_q);
                end else begin
                  skipped++;
                  vdot_lhs_q[i] <= '0;
                  vdot_rhs_q[i] <= '0;
                end
              end else begin
                vdot_lhs_q[i] <= '0;
                vdot_rhs_q[i] <= '0;
              end
            end
            vdot_id_q           <= cmd_id_i;
            vdot_skipped_q      <= skipped[4:0];
            vdot_elem_pending_q <= 1'b1;
          end

          SAP_OP_VREADCNT: begin
            rsp_data_q <= counter_value(cmd_rs1_i[2:0], next_inst_count[31:0]);
          end

          SAP_OP_VCLEARCNT: begin
            cycle_count_q   <= '0;
            inst_count_q    <= '0;
            mac_active_q    <= '0;
            skipped_count_q <= '0;
            rsp_data_q      <= '0;
          end

          default: begin
            rsp_exc_q <= 1'b1;
          end
        endcase
      end
    end
  end
endmodule
