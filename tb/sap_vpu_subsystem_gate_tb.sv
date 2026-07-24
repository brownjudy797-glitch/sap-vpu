`timescale 1ns/1ps

module sap_vpu_subsystem_gate_tb;
  import sap_vpu_pkg::*;

`include "tinyvit_mlp2_fixture_tb.svh"
`include "tinyvit_fc2_k128_policy_tb.svh"
`include "tinyvit_fc2_k512_policy_tb.svh"

  localparam realtime DEFAULT_CLK_HALF_PERIOD_NS = 3.5715;
  localparam int unsigned DEFAULT_ITERATIONS = 128;
  localparam logic [31:0] TOKEN_BASE = 32'h0000_0100;
  localparam logic [31:0] FC1_WEIGHT_BASE = 32'h0000_0200;
  localparam logic [31:0] FC1_OUT0_BASE = 32'h0000_0300;
  localparam logic [31:0] FC1_OUT1_BASE = 32'h0000_0320;
  localparam logic [31:0] HIDDEN_BASE = 32'h0000_0400;
  localparam logic [31:0] FC2_WEIGHT_BASE = 32'h0000_0500;
  localparam logic [31:0] FC2_OUT_BASE = 32'h0000_0600;
  localparam logic [31:0] FC2_K128_INPUT_BASE = 32'h0000_0800;
  localparam logic [31:0] FC2_K128_WEIGHT_BASE = 32'h0000_0900;
  localparam logic [31:0] FC2_K128_OUT_BASE = 32'h0000_0a00;
  localparam logic [31:0] FC2_K512_INPUT_BASE = 32'h0000_1000;
  localparam logic [31:0] FC2_K512_WEIGHT_BASE = 32'h0000_1800;
  localparam logic [31:0] FC2_K512_OUT_BASE = 32'h0000_2000;
  localparam logic [31:0] FC2_K512_PAIR_WEIGHT_BASE = 32'h0000_2400;
  localparam int unsigned POLICY_MLP2_DENSE = 0;
  localparam int unsigned POLICY_FC2_DENSE = 1;
  localparam int unsigned POLICY_FC2_GLOBAL = 2;
  localparam int unsigned POLICY_FC2_BUDGET = 3;
  localparam int unsigned POLICY_FC2_K512_DENSE = 4;
  localparam int unsigned POLICY_FC2_K512_GLOBAL = 5;
  localparam int unsigned POLICY_FC2_K512_BUDGET = 6;
  localparam int unsigned POLICY_FC2_K512_PAIR_DENSE = 7;
  localparam int unsigned POLICY_FC2_K512_PAIR_GLOBAL = 8;
  localparam int unsigned POLICY_FC2_K512_PAIR_BUDGET = 9;

  logic        clk_i;
  logic        rst_ni;
  logic        cmd_valid_i;
  logic        cmd_ready_o;
  logic [3:0]  cmd_id_i;
  logic [6:0]  cmd_op_i;
  logic [31:0] cmd_rs1_i;
  logic [31:0] cmd_rs2_i;
  logic [31:0] cmd_instr_i;
  logic        rsp_valid_o;
  logic        rsp_ready_i;
  logic [3:0]  rsp_id_o;
  logic [31:0] rsp_data_o;
  logic        rsp_exc_o;
  logic        dma_req_o;
  logic        dma_gnt_i;
  logic [31:0] dma_addr_o;
  logic        dma_we_o;
  logic [3:0]  dma_be_o;
  logic [31:0] dma_wdata_o;
  logic        dma_rvalid_i;
  logic [31:0] dma_rdata_i;
  logic        dma_err_i;
  logic [31:0] fc1_output_0 [0:3];
  logic [31:0] fc1_output_1 [0:3];
  logic [31:0] fc2_output [0:3];
  logic [31:0] fc2_k128_output [0:3];
  logic [31:0] fc2_k512_output [0:3];
  logic [31:0] hidden_words [0:1];
  int unsigned read_transactions;
  int unsigned write_transactions;
  int unsigned iterations = DEFAULT_ITERATIONS;
  realtime     clk_half_period_ns = DEFAULT_CLK_HALF_PERIOD_NS;
  string       vcd_file = "sap_vpu_subsystem_gate.vcd";
  string       activity_policy = "mlp2_dense";
  int unsigned policy_id = POLICY_MLP2_DENSE;
  int unsigned expected_vdots;
  int unsigned expected_reads;
  int unsigned expected_writes;

  sap_vpu_subsystem dut (
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
    .rsp_exc_o(rsp_exc_o),
    .dma_req_o(dma_req_o),
    .dma_gnt_i(dma_gnt_i),
    .dma_addr_o(dma_addr_o),
    .dma_we_o(dma_we_o),
    .dma_be_o(dma_be_o),
    .dma_wdata_o(dma_wdata_o),
    .dma_rvalid_i(dma_rvalid_i),
    .dma_rdata_i(dma_rdata_i),
    .dma_err_i(dma_err_i)
  );

  always #(clk_half_period_ns) clk_i = ~clk_i;
  assign dma_gnt_i = 1'b1;

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      dma_rvalid_i      <= 1'b0;
      dma_rdata_i       <= '0;
      dma_err_i         <= 1'b0;
      read_transactions <= 0;
      write_transactions <= 0;
      for (int i = 0; i < 4; i++) begin
        fc1_output_0[i] <= '0;
        fc1_output_1[i] <= '0;
        fc2_output[i]   <= '0;
        fc2_k128_output[i] <= '0;
        fc2_k512_output[i] <= '0;
      end
    end else begin
      dma_rvalid_i <= 1'b0;
      dma_err_i    <= 1'b0;
      if (dma_req_o && dma_gnt_i) begin
        dma_rvalid_i <= 1'b1;
        if (dma_we_o) begin
          write_transactions <= write_transactions + 1;
          if (dma_be_o !== 4'hf) begin
            dma_err_i <= 1'b1;
          end else begin
            case (dma_addr_o)
              FC1_OUT0_BASE + 0:  fc1_output_0[0] <= dma_wdata_o;
              FC1_OUT0_BASE + 4:  fc1_output_0[1] <= dma_wdata_o;
              FC1_OUT0_BASE + 8:  fc1_output_0[2] <= dma_wdata_o;
              FC1_OUT0_BASE + 12: fc1_output_0[3] <= dma_wdata_o;
              FC1_OUT1_BASE + 0:  fc1_output_1[0] <= dma_wdata_o;
              FC1_OUT1_BASE + 4:  fc1_output_1[1] <= dma_wdata_o;
              FC1_OUT1_BASE + 8:  fc1_output_1[2] <= dma_wdata_o;
              FC1_OUT1_BASE + 12: fc1_output_1[3] <= dma_wdata_o;
              FC2_OUT_BASE + 0:   fc2_output[0] <= dma_wdata_o;
              FC2_OUT_BASE + 4:   fc2_output[1] <= dma_wdata_o;
              FC2_OUT_BASE + 8:   fc2_output[2] <= dma_wdata_o;
              FC2_OUT_BASE + 12:  fc2_output[3] <= dma_wdata_o;
              FC2_K128_OUT_BASE + 0:  fc2_k128_output[0] <= dma_wdata_o;
              FC2_K128_OUT_BASE + 4:  fc2_k128_output[1] <= dma_wdata_o;
              FC2_K128_OUT_BASE + 8:  fc2_k128_output[2] <= dma_wdata_o;
              FC2_K128_OUT_BASE + 12: fc2_k128_output[3] <= dma_wdata_o;
              FC2_K512_OUT_BASE + 0:  fc2_k512_output[0] <= dma_wdata_o;
              FC2_K512_OUT_BASE + 4:  fc2_k512_output[1] <= dma_wdata_o;
              FC2_K512_OUT_BASE + 8:  fc2_k512_output[2] <= dma_wdata_o;
              FC2_K512_OUT_BASE + 12: fc2_k512_output[3] <= dma_wdata_o;
              default:            dma_err_i <= 1'b1;
            endcase
          end
        end else begin
          read_transactions <= read_transactions + 1;
          if (dma_addr_o >= FC2_K128_INPUT_BASE && dma_addr_o < FC2_K128_INPUT_BASE + 256) begin
            dma_rdata_i <= TINYVIT_FC2_K128_INPUT_WORDS[(dma_addr_o - FC2_K128_INPUT_BASE) >> 2];
          end else if (dma_addr_o >= FC2_K128_WEIGHT_BASE &&
                       dma_addr_o < FC2_K128_WEIGHT_BASE + 256) begin
            dma_rdata_i <= TINYVIT_FC2_K128_WEIGHT_WORDS[(dma_addr_o - FC2_K128_WEIGHT_BASE) >> 2];
          end else if (dma_addr_o >= FC2_K512_INPUT_BASE &&
                       dma_addr_o < FC2_K512_INPUT_BASE + 1024) begin
            dma_rdata_i <= TINYVIT_FC2_K512_INPUT_WORDS[(dma_addr_o - FC2_K512_INPUT_BASE) >> 2];
          end else if (dma_addr_o >= FC2_K512_WEIGHT_BASE &&
                       dma_addr_o < FC2_K512_WEIGHT_BASE + 1024) begin
            dma_rdata_i <= TINYVIT_FC2_K512_WEIGHT_WORDS[(dma_addr_o - FC2_K512_WEIGHT_BASE) >> 2];
          end else if (dma_addr_o >= FC2_K512_PAIR_WEIGHT_BASE &&
                       dma_addr_o < FC2_K512_PAIR_WEIGHT_BASE + 4096) begin
            dma_rdata_i <= TINYVIT_FC2_K512_PAIR_WEIGHT_WORDS[
              (dma_addr_o - FC2_K512_PAIR_WEIGHT_BASE) >> 2
            ];
          end else begin
            case (dma_addr_o)
              TOKEN_BASE + 0:      dma_rdata_i <= TINYVIT_MLP2_WORDS[0];
              TOKEN_BASE + 4:      dma_rdata_i <= TINYVIT_MLP2_WORDS[1];
              FC1_WEIGHT_BASE + 0: dma_rdata_i <= TINYVIT_MLP2_WORDS[2];
              FC1_WEIGHT_BASE + 4: dma_rdata_i <= TINYVIT_MLP2_WORDS[3];
              FC1_WEIGHT_BASE + 8: dma_rdata_i <= TINYVIT_MLP2_WORDS[4];
              FC1_WEIGHT_BASE + 12: dma_rdata_i <= TINYVIT_MLP2_WORDS[5];
              HIDDEN_BASE + 0:     dma_rdata_i <= hidden_words[0];
              HIDDEN_BASE + 4:     dma_rdata_i <= hidden_words[1];
              FC2_WEIGHT_BASE + 0: dma_rdata_i <= TINYVIT_MLP2_WORDS[6];
              FC2_WEIGHT_BASE + 4: dma_rdata_i <= TINYVIT_MLP2_WORDS[7];
              default: begin
                dma_rdata_i <= '0;
                dma_err_i   <= 1'b1;
              end
            endcase
          end
        end
      end
    end
  end

  task automatic gate_fail(input string message);
    begin
      $display("SUBSYSTEM_GATE_FAIL: %s", message);
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

  task automatic send_cmd(
    input logic [3:0]  id,
    input logic [6:0]  op,
    input logic [31:0] rs1,
    input logic [31:0] rs2
  );
    begin
      @(negedge clk_i);
      cmd_valid_i = 1'b1;
      cmd_id_i    = id;
      cmd_op_i    = op;
      cmd_rs1_i   = rs1;
      cmd_rs2_i   = rs2;
      for (int i = 0; i < 512; i++) begin
        @(posedge clk_i);
        if (cmd_ready_o === 1'b1) begin
          #1;
          clear_cmd();
          return;
        end
      end
      $display("SUBSYSTEM_GATE_CONTEXT: id=%0d op=0x%02x rsp_valid=%b dma_req=%b dma_rvalid=%b",
               id, op, rsp_valid_o, dma_req_o, dma_rvalid_i);
      gate_fail("command ready timeout");
    end
  endtask

  task automatic expect_rsp(
    input logic [3:0]  id,
    input logic [31:0] data
  );
    begin
      for (int i = 0; i < 4096; i++) begin
        if (rsp_valid_o === 1'b1) begin
          if (rsp_id_o !== id || rsp_exc_o !== 1'b0 || rsp_data_o !== data) begin
            gate_fail("response mismatch");
          end
          return;
        end
        @(negedge clk_i);
      end
      gate_fail("response timeout");
    end
  endtask

  function automatic logic [31:0] output_word(
    input logic [31:0] base,
    input int unsigned index
  );
    begin
      case (base)
        FC1_OUT0_BASE: output_word = fc1_output_0[index];
        FC1_OUT1_BASE: output_word = fc1_output_1[index];
        FC2_OUT_BASE:  output_word = fc2_output[index];
        FC2_K128_OUT_BASE: output_word = fc2_k128_output[index];
        FC2_K512_OUT_BASE: output_word = fc2_k512_output[index];
        default:       output_word = 'x;
      endcase
    end
  endfunction

  function automatic logic [7:0] relu_byte(input logic [31:0] value);
    logic [31:0] requantized;
    begin
      if ($signed(value) < 0) begin
        relu_byte = 8'h00;
      end else begin
        requantized = (value + TINYVIT_MLP2_FC1_REQUANT_ROUNDING) >>
                      TINYVIT_MLP2_FC1_REQUANT_SHIFT;
        relu_byte = requantized[7:0];
      end
    end
  endfunction

  task automatic expect_tile(
    input logic [31:0] base,
    input logic [31:0] expected_0,
    input logic [31:0] expected_1,
    input logic [31:0] expected_2,
    input logic [31:0] expected_3
  );
    begin
      if (output_word(base, 0) !== expected_0 || output_word(base, 1) !== expected_1 ||
          output_word(base, 2) !== expected_2 || output_word(base, 3) !== expected_3) begin
        gate_fail("RAM writeback mismatch");
      end
    end
  endtask

  task automatic run_tile_descriptors(
    input int unsigned index,
    input logic [31:0] lhs_base,
    input logic [31:0] lhs_descriptor,
    input logic [31:0] rhs_base,
    input logic [31:0] rhs_descriptor,
    input logic [31:0] out_base
  );
    logic [3:0] id;
    begin
      id = index[3:0];
      send_cmd(id, SAP_OP_VTDMA, lhs_base, lhs_descriptor);
      expect_rsp(id, 32'(lhs_descriptor[3:1]));
      send_cmd(id + 4'd1, SAP_OP_VTDMA, rhs_base, rhs_descriptor);
      expect_rsp(id + 4'd1, 32'(rhs_descriptor[3:1]));
      send_cmd(id + 4'd2, SAP_OP_VTSTART,
               lhs_descriptor[3:1] == 3'd2 ? 32'h0000_0112 : 32'h0000_0212, 32'h0);
      expect_rsp(id + 4'd2, 32'h0);
      send_cmd(id + 4'd3, SAP_OP_VTSTORE, out_base, 32'h0);
      expect_rsp(id + 4'd3, 32'h0);
    end
  endtask

  task automatic run_tile(
    input int unsigned index,
    input logic [31:0] lhs_base,
    input logic [31:0] rhs_base,
    input logic [31:0] out_base
  );
    begin
      run_tile_descriptors(index, lhs_base, 32'd4, rhs_base, 32'd5, out_base);
    end
  endtask

  function automatic logic [3:0] fc2_policy_mask(
    input int unsigned policy,
    input int unsigned chunk
  );
    begin
      case (policy)
        POLICY_FC2_GLOBAL: fc2_policy_mask = TINYVIT_FC2_GLOBAL_L1_6P25_MASKS[chunk];
        POLICY_FC2_BUDGET: fc2_policy_mask = TINYVIT_FC2_L1_BUDGET_2PCT_MASKS[chunk];
        default:           fc2_policy_mask = 4'hf;
      endcase
    end
  endfunction

  function automatic logic [31:0] fc2_policy_expected(
    input int unsigned policy,
    input int unsigned index
  );
    begin
      case (policy)
        POLICY_FC2_GLOBAL: fc2_policy_expected = TINYVIT_FC2_GLOBAL_L1_6P25_EXPECTED[index];
        POLICY_FC2_BUDGET: fc2_policy_expected = TINYVIT_FC2_L1_BUDGET_2PCT_EXPECTED[index];
        default:           fc2_policy_expected = TINYVIT_FC2_DENSE_EXPECTED[index];
      endcase
    end
  endfunction

  function automatic logic [3:0] fc2_k512_policy_mask(
    input int unsigned policy,
    input int unsigned chunk
  );
    begin
      case (policy)
        POLICY_FC2_K512_GLOBAL:
          fc2_k512_policy_mask = TINYVIT_FC2_K512_GLOBAL_L1_6P25_MASKS[chunk];
        POLICY_FC2_K512_BUDGET:
          fc2_k512_policy_mask = TINYVIT_FC2_K512_L1_BUDGET_2PCT_MASKS[chunk];
        default: fc2_k512_policy_mask = 4'hf;
      endcase
    end
  endfunction

  function automatic logic [31:0] fc2_k512_policy_expected(
    input int unsigned policy,
    input int unsigned index
  );
    begin
      case (policy)
        POLICY_FC2_K512_GLOBAL:
          fc2_k512_policy_expected = TINYVIT_FC2_K512_GLOBAL_L1_6P25_EXPECTED[index];
        POLICY_FC2_K512_BUDGET:
          fc2_k512_policy_expected = TINYVIT_FC2_K512_L1_BUDGET_2PCT_EXPECTED[index];
        default: fc2_k512_policy_expected = TINYVIT_FC2_K512_DENSE_EXPECTED[index];
      endcase
    end
  endfunction

  function automatic int unsigned fc2_k512_active_groups(input int unsigned policy);
    int unsigned groups;
    logic [3:0] mask;
    begin
      groups = 0;
      for (int unsigned chunk = 0; chunk < 64; chunk++) begin
        mask = fc2_k512_policy_mask(policy, chunk);
        for (int unsigned group = 0; group < 4; group++) begin
          groups += mask[group] ? 1 : 0;
        end
      end
      return groups;
    end
  endfunction

  function automatic logic [3:0] fc2_k512_pair_policy_mask(
    input int unsigned policy,
    input int unsigned pair,
    input int unsigned chunk
  );
    int unsigned index;
    begin
      index = pair * 64 + chunk;
      case (policy)
        POLICY_FC2_K512_PAIR_GLOBAL:
          fc2_k512_pair_policy_mask =
            TINYVIT_FC2_K512_PAIR_LAYER_GLOBAL_L1_6P25_MASKS[index];
        POLICY_FC2_K512_PAIR_BUDGET:
          fc2_k512_pair_policy_mask =
            TINYVIT_FC2_K512_PAIR_LAYER_L1_BUDGET_1PCT_MASKS[index];
        default: fc2_k512_pair_policy_mask = 4'hf;
      endcase
    end
  endfunction

  function automatic logic [3:0] fc2_k512_pair_input_mask(input logic [3:0] weight_mask);
    logic [3:0] input_mask;
    begin
      input_mask = '0;
      for (int unsigned group = 0; group < 2; group++) begin
        if (weight_mask[group] || weight_mask[group + 2]) begin
          input_mask[group] = 1'b1;
          input_mask[group + 2] = 1'b1;
        end
      end
      return input_mask;
    end
  endfunction

  function automatic logic [31:0] fc2_k512_pair_policy_expected(
    input int unsigned policy,
    input int unsigned pair,
    input int unsigned index
  );
    int unsigned expected_index;
    begin
      expected_index = pair * 4 + index;
      case (policy)
        POLICY_FC2_K512_PAIR_GLOBAL:
          fc2_k512_pair_policy_expected =
            TINYVIT_FC2_K512_PAIR_LAYER_GLOBAL_L1_6P25_EXPECTED[expected_index];
        POLICY_FC2_K512_PAIR_BUDGET:
          fc2_k512_pair_policy_expected =
            TINYVIT_FC2_K512_PAIR_LAYER_L1_BUDGET_1PCT_EXPECTED[expected_index];
        default:
          fc2_k512_pair_policy_expected =
            TINYVIT_FC2_K512_PAIR_DENSE_EXPECTED[expected_index];
      endcase
    end
  endfunction

  function automatic int unsigned fc2_k512_pair_weight_reads(input int unsigned policy);
    int unsigned reads;
    logic [3:0] mask;
    begin
      reads = 0;
      for (int unsigned pair = 0; pair < TINYVIT_FC2_K512_PAIR_COUNT; pair++) begin
        for (int unsigned chunk = 0; chunk < 64; chunk++) begin
          mask = fc2_k512_pair_policy_mask(policy, pair, chunk);
          for (int unsigned group = 0; group < 4; group++) begin
            reads += mask[group] ? 1 : 0;
          end
        end
      end
      return reads;
    end
  endfunction

  function automatic int unsigned fc2_k512_pair_input_reads(input int unsigned policy);
    int unsigned reads;
    logic [3:0] mask;
    begin
      reads = 0;
      for (int unsigned pair = 0; pair < TINYVIT_FC2_K512_PAIR_COUNT; pair++) begin
        for (int unsigned chunk = 0; chunk < 64; chunk++) begin
          mask = fc2_k512_pair_input_mask(
            fc2_k512_pair_policy_mask(policy, pair, chunk)
          );
          for (int unsigned group = 0; group < 4; group++) begin
            reads += mask[group] ? 1 : 0;
          end
        end
      end
      return reads;
    end
  endfunction

  task automatic run_fc2_k128(
    input int unsigned iteration,
    input int unsigned policy
  );
    logic signed [31:0] sums [0:3];
    logic [3:0] mask;
    logic [31:0] lhs_descriptor;
    logic [31:0] rhs_descriptor;
    begin
      for (int output_index = 0; output_index < 4; output_index++) begin
        sums[output_index] = '0;
      end
      for (int unsigned chunk = 0; chunk < 16; chunk++) begin
        mask = fc2_policy_mask(policy, chunk);
        lhs_descriptor = policy == POLICY_FC2_DENSE ? 32'd8 : 32'h0000_01f8;
        rhs_descriptor = policy == POLICY_FC2_DENSE ? 32'd9 : {23'd0, 1'b1, mask, 4'h9};
        run_tile_descriptors(
          (iteration * 16) + chunk,
          FC2_K128_INPUT_BASE + (chunk * 16), lhs_descriptor,
          FC2_K128_WEIGHT_BASE + (chunk * 16), rhs_descriptor,
          FC2_K128_OUT_BASE
        );
        for (int output_index = 0; output_index < 4; output_index++) begin
          sums[output_index] += $signed(fc2_k128_output[output_index]);
        end
      end
      for (int output_index = 0; output_index < 4; output_index++) begin
        if (sums[output_index] !== $signed(fc2_policy_expected(policy, output_index))) begin
          gate_fail("K=128 FC2 aggregate mismatch");
        end
      end
    end
  endtask

  task automatic run_fc2_k512(
    input int unsigned iteration,
    input int unsigned policy
  );
    logic signed [31:0] sums [0:3];
    logic [3:0] mask;
    logic [31:0] lhs_descriptor;
    logic [31:0] rhs_descriptor;
    begin
      for (int output_index = 0; output_index < 4; output_index++) begin
        sums[output_index] = '0;
      end
      for (int unsigned chunk = 0; chunk < 64; chunk++) begin
        mask = fc2_k512_policy_mask(policy, chunk);
        lhs_descriptor = policy == POLICY_FC2_K512_DENSE ? 32'd8 : 32'h0000_01f8;
        rhs_descriptor = policy == POLICY_FC2_K512_DENSE ? 32'd9 : {23'd0, 1'b1, mask, 4'h9};
        run_tile_descriptors(
          (iteration * 64) + chunk,
          FC2_K512_INPUT_BASE + (chunk * 16), lhs_descriptor,
          FC2_K512_WEIGHT_BASE + (chunk * 16), rhs_descriptor,
          FC2_K512_OUT_BASE
        );
        for (int output_index = 0; output_index < 4; output_index++) begin
          sums[output_index] += $signed(fc2_k512_output[output_index]);
        end
      end
      for (int output_index = 0; output_index < 4; output_index++) begin
        if (sums[output_index] !== $signed(fc2_k512_policy_expected(policy, output_index))) begin
          gate_fail("K=512 FC2 aggregate mismatch");
        end
      end
    end
  endtask

  task automatic run_fc2_k512_pairs(
    input int unsigned iteration,
    input int unsigned policy
  );
    logic signed [31:0] sums [0:3];
    logic [3:0] input_mask;
    logic [3:0] weight_mask;
    logic [31:0] lhs_descriptor;
    logic [31:0] rhs_descriptor;
    begin
      for (int unsigned pair = 0; pair < TINYVIT_FC2_K512_PAIR_COUNT; pair++) begin
        for (int output_index = 0; output_index < 4; output_index++) begin
          sums[output_index] = '0;
        end
        for (int unsigned chunk = 0; chunk < 64; chunk++) begin
          weight_mask = fc2_k512_pair_policy_mask(policy, pair, chunk);
          input_mask = fc2_k512_pair_input_mask(weight_mask);
          if (policy == POLICY_FC2_K512_PAIR_DENSE) begin
            lhs_descriptor = 32'd8;
            rhs_descriptor = 32'd9;
          end else begin
            lhs_descriptor = {23'd0, 1'b1, input_mask, 4'h8};
            rhs_descriptor = {23'd0, 1'b1, weight_mask, 4'h9};
          end
          run_tile_descriptors(
            (iteration * TINYVIT_FC2_K512_PAIR_COUNT * 64) + (pair * 64) + chunk,
            FC2_K512_INPUT_BASE + (chunk * 16), lhs_descriptor,
            FC2_K512_PAIR_WEIGHT_BASE + (pair * 1024) + (chunk * 16), rhs_descriptor,
            FC2_K512_OUT_BASE
          );
          for (int output_index = 0; output_index < 4; output_index++) begin
            sums[output_index] += $signed(fc2_k512_output[output_index]);
          end
        end
        for (int output_index = 0; output_index < 4; output_index++) begin
          if (sums[output_index] !==
              $signed(fc2_k512_pair_policy_expected(policy, pair, output_index))) begin
            gate_fail("representative K=512 FC2 aggregate mismatch");
          end
        end
      end
    end
  endtask

  task automatic run_mlp2(input int unsigned index);
    begin
      run_tile(index * 3, TOKEN_BASE, FC1_WEIGHT_BASE, FC1_OUT0_BASE);
      expect_tile(FC1_OUT0_BASE,
                  TINYVIT_MLP2_FC1_OUTPUTS[0], TINYVIT_MLP2_FC1_OUTPUTS[1],
                  TINYVIT_MLP2_FC1_OUTPUTS[4], TINYVIT_MLP2_FC1_OUTPUTS[5]);
      run_tile((index * 3) + 1, TOKEN_BASE, FC1_WEIGHT_BASE + 8, FC1_OUT1_BASE);
      expect_tile(FC1_OUT1_BASE,
                  TINYVIT_MLP2_FC1_OUTPUTS[2], TINYVIT_MLP2_FC1_OUTPUTS[3],
                  TINYVIT_MLP2_FC1_OUTPUTS[6], TINYVIT_MLP2_FC1_OUTPUTS[7]);

      hidden_words[0] = {relu_byte(fc1_output_1[1]), relu_byte(fc1_output_1[0]),
                         relu_byte(fc1_output_0[1]), relu_byte(fc1_output_0[0])};
      hidden_words[1] = {relu_byte(fc1_output_1[3]), relu_byte(fc1_output_1[2]),
                         relu_byte(fc1_output_0[3]), relu_byte(fc1_output_0[2])};
      if (hidden_words[0] !== TINYVIT_MLP2_HIDDEN_WORDS[0] ||
          hidden_words[1] !== TINYVIT_MLP2_HIDDEN_WORDS[1]) begin
        gate_fail("ReLU hidden activation mismatch");
      end

      run_tile((index * 3) + 2, HIDDEN_BASE, FC2_WEIGHT_BASE, FC2_OUT_BASE);
      expect_tile(FC2_OUT_BASE,
                  TINYVIT_MLP2_FC2_OUTPUTS[0], TINYVIT_MLP2_FC2_OUTPUTS[1],
                  TINYVIT_MLP2_FC2_OUTPUTS[2], TINYVIT_MLP2_FC2_OUTPUTS[3]);
    end
  endtask

  initial begin
    clk_i       = 1'b0;
    rst_ni      = 1'b0;
    rsp_ready_i = 1'b1;
    hidden_words[0] = '0;
    hidden_words[1] = '0;
    clear_cmd();

    if (!$value$plusargs("vcd=%s", vcd_file)) begin
      vcd_file = "sap_vpu_subsystem_gate.vcd";
    end
    if ($value$plusargs("iterations=%d", iterations) && iterations == 0) begin
      $fatal(1, "iterations must be positive");
    end
    if ($value$plusargs("clock_half_ns=%f", clk_half_period_ns) &&
        clk_half_period_ns <= 0.0) begin
      $fatal(1, "clock_half_ns must be positive");
    end
    void'($value$plusargs("policy=%s", activity_policy));
    case (activity_policy)
      "mlp2_dense": begin
        policy_id = POLICY_MLP2_DENSE;
        expected_vdots = iterations * 12;
        expected_reads = iterations * 12;
        expected_writes = iterations * 12;
      end
      "fc2_dense": begin
        policy_id = POLICY_FC2_DENSE;
        expected_vdots = iterations * 128;
        expected_reads = iterations * 128;
        expected_writes = iterations * 64;
      end
      "fc2_global_l1_6p25": begin
        policy_id = POLICY_FC2_GLOBAL;
        expected_vdots = iterations * 120;
        expected_reads = iterations * 124;
        expected_writes = iterations * 64;
      end
      "fc2_l1_budget_2pct": begin
        policy_id = POLICY_FC2_BUDGET;
        expected_vdots = iterations * 122;
        expected_reads = iterations * 125;
        expected_writes = iterations * 64;
      end
      "fc2_k512_dense": begin
        policy_id = POLICY_FC2_K512_DENSE;
        expected_vdots = iterations * 512;
        expected_reads = iterations * 512;
        expected_writes = iterations * 256;
      end
      "fc2_k512_global_l1_6p25": begin
        policy_id = POLICY_FC2_K512_GLOBAL;
        expected_vdots = iterations * fc2_k512_active_groups(policy_id) * 2;
        expected_reads = iterations * (256 + fc2_k512_active_groups(policy_id));
        expected_writes = iterations * 256;
      end
      "fc2_k512_l1_budget_2pct": begin
        policy_id = POLICY_FC2_K512_BUDGET;
        expected_vdots = iterations * fc2_k512_active_groups(policy_id) * 2;
        expected_reads = iterations * (256 + fc2_k512_active_groups(policy_id));
        expected_writes = iterations * 256;
      end
      "fc2_k512_pairs_dense": begin
        policy_id = POLICY_FC2_K512_PAIR_DENSE;
        expected_vdots = iterations * fc2_k512_pair_weight_reads(policy_id) * 2;
        expected_reads = iterations * (
          fc2_k512_pair_input_reads(policy_id) + fc2_k512_pair_weight_reads(policy_id)
        );
        expected_writes = iterations * TINYVIT_FC2_K512_PAIR_COUNT * 256;
      end
      "fc2_k512_pairs_global_l1_6p25": begin
        policy_id = POLICY_FC2_K512_PAIR_GLOBAL;
        expected_vdots = iterations * fc2_k512_pair_weight_reads(policy_id) * 2;
        expected_reads = iterations * (
          fc2_k512_pair_input_reads(policy_id) + fc2_k512_pair_weight_reads(policy_id)
        );
        expected_writes = iterations * TINYVIT_FC2_K512_PAIR_COUNT * 256;
      end
      "fc2_k512_pairs_l1_budget_1pct": begin
        policy_id = POLICY_FC2_K512_PAIR_BUDGET;
        expected_vdots = iterations * fc2_k512_pair_weight_reads(policy_id) * 2;
        expected_reads = iterations * (
          fc2_k512_pair_input_reads(policy_id) + fc2_k512_pair_weight_reads(policy_id)
        );
        expected_writes = iterations * TINYVIT_FC2_K512_PAIR_COUNT * 256;
      end
      default: $fatal(1, "unsupported policy: %s", activity_policy);
    endcase

    #100;
    @(negedge clk_i);
    rst_ni = 1'b1;
    repeat (4) @(posedge clk_i);

    $dumpfile(vcd_file);
    $dumpvars(0, dut);
    for (int unsigned i = 0; i < iterations; i++) begin
      if (policy_id == POLICY_MLP2_DENSE) begin
        run_mlp2(i);
      end else if (policy_id >= POLICY_FC2_K512_PAIR_DENSE) begin
        run_fc2_k512_pairs(i, policy_id);
      end else if (policy_id >= POLICY_FC2_K512_DENSE) begin
        run_fc2_k512(i, policy_id);
      end else begin
        run_fc2_k128(i, policy_id);
      end
    end
    $dumpoff;

    send_cmd(4'he, SAP_OP_VREADCNT, 32'(SAP_CNT_MAC_ACTIVE), 32'h0);
    expect_rsp(4'he, 32'(expected_vdots));
    if (read_transactions != expected_reads || write_transactions != expected_writes) begin
      gate_fail("DMA transaction count mismatch");
    end

    $display("SUBSYSTEM_GATE_PASS: policy=%s iterations=%0d vdots=%0d reads=%0d writes=%0d",
             activity_policy, iterations, expected_vdots, read_transactions, write_transactions);
    $finish;
  end

  initial begin
    repeat (1000000) @(posedge clk_i);
    gate_fail("simulation timeout");
  end
endmodule
