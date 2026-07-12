`timescale 1ns/1ps

module sap_vpu_core_gate_tb;
  import sap_vpu_pkg::*;

  localparam realtime DEFAULT_CLK_HALF_PERIOD_NS = 3.5715;

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
  string       policy_name;
  string       vcd_file;
  realtime     clk_half_period_ns = DEFAULT_CLK_HALF_PERIOD_NS;

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

  always #(clk_half_period_ns) clk_i = ~clk_i;

  initial begin
    if ($value$plusargs("clock_half_ns=%f", clk_half_period_ns) &&
        (clk_half_period_ns <= 0.0)) begin
      $fatal(1, "clock_half_ns must be positive");
    end
  end

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

  task automatic wait_rsp_retired;
    begin
      do begin
        @(negedge clk_i);
      end while (rsp_valid_o !== 1'b0);
    end
  endtask

  task automatic policy_config(
    input string        name,
    output logic [1:0]  precision,
    output logic [31:0] sparse,
    output logic [31:0] lanes,
    output logic [31:0] expected_skip,
    output logic [31:0] expected_total
  );
    begin
      if (name == "dense_int8") begin
        precision = SAP_PREC_INT8; sparse = 32'h0f; lanes = 4; expected_skip = 0; expected_total = 12096;
      end else if (name == "static_int4") begin
        precision = SAP_PREC_INT4; sparse = 32'hff; lanes = 8; expected_skip = 0; expected_total = 14592;
      end else if (name == "static_int2") begin
        precision = SAP_PREC_INT2; sparse = 32'hffff; lanes = 16; expected_skip = 0; expected_total = 5120;
      end else if (name == "adaptive_int4") begin
        precision = SAP_PREC_INT4; sparse = 32'h0f; lanes = 4; expected_skip = 2048; expected_total = 7296;
      end else if (name == "adaptive_sparse75") begin
        precision = SAP_PREC_INT4; sparse = 32'h03; lanes = 2; expected_skip = 3072; expected_total = 3648;
      end else if (name == "adaptive_unstructured") begin
        precision = SAP_PREC_INT4; sparse = 32'h55; lanes = 8; expected_skip = 2048; expected_total = 7296;
      end else if (name == "no_sparse") begin
        precision = SAP_PREC_INT4; sparse = 32'hff; lanes = 4; expected_skip = 2048; expected_total = 7296;
      end else if (name == "no_lane") begin
        precision = SAP_PREC_INT4; sparse = 32'h0f; lanes = 8; expected_skip = 2048; expected_total = 7296;
      end else if (name == "no_precision") begin
        precision = SAP_PREC_INT8; sparse = 32'h0f; lanes = 4; expected_skip = 0; expected_total = 7296;
      end else begin
        $fatal(1, "GATE_POLICY_FAIL: unknown policy %s", name);
      end
    end
  endtask

  task automatic policy_operands(
    input string name,
    input int unsigned index,
    output logic [31:0] rs1,
    output logic [31:0] rs2
  );
    int unsigned block;
    int unsigned op;
    logic [31:0] token0;
    logic [31:0] token1;
    logic [31:0] weight0;
    logic [31:0] weight1;
    begin
      block = (index / 4) % 4;
      op = index % 4;

      if (name == "dense_int8") begin
        case (block)
          0: begin token0 = 32'h04030201; token1 = 32'h01020304; weight0 = 32'h08070605; weight1 = 32'h01010101; end
          1: begin token0 = 32'h02020202; token1 = 32'h03010301; weight0 = 32'h08070605; weight1 = 32'h02020202; end
          2: begin token0 = 32'h01010101; token1 = 32'h02020202; weight0 = 32'h04030201; weight1 = 32'h01010101; end
          default: begin token0 = 32'h03030303; token1 = 32'h01010101; weight0 = 32'h02020202; weight1 = 32'h01010101; end
        endcase
      end else if (name == "static_int2") begin
        token0 = 32'h55555555; token1 = 32'h11111111;
        weight0 = 32'h55555555; weight1 = 32'h11111111;
      end else if (name == "no_precision") begin
        case (block)
          0: begin token0 = 32'h01010101; token1 = 32'h02020202; weight0 = 32'h01010101; weight1 = 32'h02020202; end
          1: begin token0 = 32'h03030303; token1 = 32'h04040404; weight0 = 32'h01010101; weight1 = 32'h02020202; end
          2: begin token0 = 32'h01010101; token1 = 32'h03030303; weight0 = 32'h01010101; weight1 = 32'h02020202; end
          default: begin token0 = 32'h01010101; token1 = 32'h02020202; weight0 = 32'h04040404; weight1 = 32'h01010101; end
        endcase
      end else begin
        case (block)
          0: begin token0 = 32'h11111111; token1 = 32'h22222222; weight0 = 32'h11111111; weight1 = 32'h22222222; end
          1: begin token0 = 32'h33333333; token1 = 32'h44444444; weight0 = 32'h11111111; weight1 = 32'h22222222; end
          2: begin token0 = 32'h11111111; token1 = 32'h33333333; weight0 = 32'h11111111; weight1 = 32'h22222222; end
          default: begin token0 = 32'h11111111; token1 = 32'h22222222; weight0 = 32'h44444444; weight1 = 32'h11111111; end
        endcase
      end

      rs1 = (op < 2) ? token0 : token1;
      rs2 = ((op % 2) == 0) ? weight0 : weight1;
    end
  endtask

  task automatic run_policy(input string name, input string activity_file);
    logic [1:0] precision;
    logic [31:0] sparse;
    logic [31:0] lanes;
    logic [31:0] expected_skip;
    logic [31:0] expected_total;
    logic [31:0] total_output;
    logic [31:0] rs1;
    logic [31:0] rs2;
    begin
      policy_config(name, precision, sparse, lanes, expected_skip, expected_total);
      total_output = '0;

      send_cmd(4'h0, SAP_OP_VSETPREC, 32'(precision), 32'h0);
      expect_rsp(4'h0, 1'b1, 32'(precision), 1'b0);
      send_cmd(4'h1, SAP_OP_VSETSPARSE_BMP, sparse, 32'h0);
      expect_rsp(4'h1, 1'b1, sparse, 1'b0);
      send_cmd(4'h2, SAP_OP_VSETLANE, lanes, 32'h0);
      expect_rsp(4'h2, 1'b1, lanes, 1'b0);
      send_cmd(4'h3, SAP_OP_VCLEARCNT, 32'h0, 32'h0);
      expect_rsp(4'h3, 1'b1, 32'h0, 1'b0);
      wait_rsp_retired();

      $dumpfile(activity_file);
      $dumpvars(0, sap_vpu_core_gate_tb);
      for (int unsigned i = 0; i < 512; i++) begin
        policy_operands(name, i, rs1, rs2);
        send_cmd(i[3:0], SAP_OP_VDOT, rs1, rs2);
        expect_rsp(i[3:0], 1'b0, 32'h0, 1'b0);
        total_output = total_output + rsp_data_o;
      end
      wait_rsp_retired();
      $dumpoff;
      if (total_output !== expected_total) begin
        $fatal(1, "GATE_POLICY_FAIL: %s output total mismatch: got %0d expected %0d",
               name, total_output, expected_total);
      end

      send_cmd(4'h4, SAP_OP_VREADCNT, 32'(SAP_CNT_MAC_ACTIVE), 32'h0);
      expect_rsp(4'h4, 1'b1, 32'd512, 1'b0);
      send_cmd(4'h5, SAP_OP_VREADCNT, 32'(SAP_CNT_SKIPPED), 32'h0);
      expect_rsp(4'h5, 1'b1, expected_skip, 1'b0);
      send_cmd(4'h6, SAP_OP_VREADCNT, 32'(SAP_CNT_SPARSE), 32'h0);
      expect_rsp(4'h6, 1'b1, sparse, 1'b0);
      send_cmd(4'h7, SAP_OP_VREADCNT, 32'(SAP_CNT_LANE), 32'h0);
      expect_rsp(4'h7, 1'b1, lanes, 1'b0);
      $display("GATE_POLICY_PASS: %s", name);
    end
  endtask

  initial begin
    clk_i = 1'b0;
    rst_ni = 1'b0;
    rsp_ready_i = 1'b1;
    clear_cmd();

    #100;
    @(negedge clk_i);
    rst_ni = 1'b1;
    repeat (4) @(posedge clk_i);

    if ($value$plusargs("policy=%s", policy_name)) begin
      if (!$value$plusargs("vcd=%s", vcd_file)) begin
        vcd_file = "sap_vpu_core_gate_policy.vcd";
      end
      run_policy(policy_name, vcd_file);
      $finish;
    end

    $dumpfile("sap_vpu_core_gate_tb.vcd");
    $dumpvars(0, sap_vpu_core_gate_tb);

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
