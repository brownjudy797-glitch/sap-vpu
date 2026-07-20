`timescale 1ns/1ps

package sap_vpu_pkg;
  localparam logic [6:0] SAP_OPCODE_CUSTOM0 = 7'h0b;

  localparam logic [6:0] SAP_FUNCT7_VSET          = 7'h09;
  localparam logic [6:0] SAP_FUNCT7_VMOV          = 7'h09;
  localparam logic [6:0] SAP_FUNCT7_VDOT          = 7'h10;
  localparam logic [6:0] SAP_FUNCT7_VSETPREC      = 7'h18;
  localparam logic [6:0] SAP_FUNCT7_VREADCNT      = 7'h1a;
  localparam logic [6:0] SAP_FUNCT7_VSETLANE      = 7'h1b;
  localparam logic [6:0] SAP_FUNCT7_VSETSPARSE_BMP = 7'h1c;
  localparam logic [6:0] SAP_FUNCT7_VCLEARCNT     = 7'h1d;
  localparam logic [6:0] SAP_FUNCT7_VTLOAD        = 7'h20;
  localparam logic [6:0] SAP_FUNCT7_VTSTART       = 7'h21;
  localparam logic [6:0] SAP_FUNCT7_VTREAD        = 7'h22;
  localparam logic [6:0] SAP_FUNCT7_VTDMA         = 7'h23;

  localparam logic [2:0] SAP_FUNCT3_VSET = 3'b000;
  localparam logic [2:0] SAP_FUNCT3_VMOV = 3'b001;

  localparam logic [6:0] SAP_OP_VDOT          = 7'h10;
  localparam logic [6:0] SAP_OP_VSET          = 7'h11;
  localparam logic [6:0] SAP_OP_VMOV          = 7'h12;
  localparam logic [6:0] SAP_OP_VSETPREC      = 7'h18;
  localparam logic [6:0] SAP_OP_VREADCNT      = 7'h1a;
  localparam logic [6:0] SAP_OP_VSETLANE      = 7'h1b;
  localparam logic [6:0] SAP_OP_VSETSPARSE_BMP = 7'h1c;
  localparam logic [6:0] SAP_OP_VCLEARCNT     = 7'h1d;
  localparam logic [6:0] SAP_OP_VTLOAD        = 7'h20;
  localparam logic [6:0] SAP_OP_VTSTART       = 7'h21;
  localparam logic [6:0] SAP_OP_VTREAD        = 7'h22;
  localparam logic [6:0] SAP_OP_VTDMA         = 7'h23;

  localparam logic [1:0] SAP_PREC_INT8 = 2'd0;
  localparam logic [1:0] SAP_PREC_INT4 = 2'd1;
  localparam logic [1:0] SAP_PREC_INT2 = 2'd2;

  localparam logic [2:0] SAP_CNT_CYCLE      = 3'd0;
  localparam logic [2:0] SAP_CNT_INST       = 3'd1;
  localparam logic [2:0] SAP_CNT_MAC_ACTIVE = 3'd2;
  localparam logic [2:0] SAP_CNT_SKIPPED    = 3'd3;
  localparam logic [2:0] SAP_CNT_SPARSE     = 3'd4;
  localparam logic [2:0] SAP_CNT_LANE       = 3'd5;

  localparam int unsigned SAP_FRONT_MAX_LANES = 16;
endpackage
