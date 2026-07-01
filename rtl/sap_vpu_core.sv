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

  assign cmd_ready_o = !rsp_valid_q;
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

  function automatic int signed packed_elem(
    input logic [31:0] word,
    input int unsigned idx,
    input logic [1:0] precision
  );
    int unsigned width;
    int unsigned shift;
    int unsigned mask;
    int unsigned raw;
    begin
      unique case (precision)
        SAP_PREC_INT8: width = 8;
        SAP_PREC_INT4: width = 4;
        SAP_PREC_INT2: width = 2;
        default:       width = 8;
      endcase

      shift = idx * width;
      mask = (32'd1 << width) - 1;
      raw = (word >> shift) & mask;
      if (((raw >> (width - 1)) & 1) != 0) begin
        packed_elem = int'(raw) - int'(32'd1 << width);
      end else begin
        packed_elem = int'(raw);
      end
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
    end else begin
      int signed   dot_acc;
      int unsigned lanes;
      int unsigned skipped;
      int unsigned next_inst_count;

      cycle_count_q <= cycle_count_q + 32'd1;

      if (rsp_valid_q && rsp_ready_i) begin
        rsp_valid_q <= 1'b0;
      end

      if (cmd_valid_i && cmd_ready_o) begin
        dot_acc = 0;
        skipped = 0;
        lanes = lanes_for_precision(precision_q);
        next_inst_count = inst_count_q + 32'd1;

        rsp_valid_q <= 1'b1;
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
                  dot_acc += packed_elem(cmd_rs1_i[31:0], i, precision_q)
                           * packed_elem(cmd_rs2_i[31:0], i, precision_q);
                end else begin
                  skipped++;
                end
              end
            end
            rsp_data_q      <= XLEN'(dot_acc);
            mac_active_q    <= mac_active_q + 32'd1;
            skipped_count_q <= skipped_count_q + skipped[31:0];
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
