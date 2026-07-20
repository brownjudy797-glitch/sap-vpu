`timescale 1ns/1ps

module sap_vpu_tiled_gemm_tb;
  logic clk;
  logic rst_n;
  logic load_valid;
  logic load_ready;
  logic load_weight;
  logic [1:0] load_index;
  logic [31:0] load_data;
  logic start_valid;
  logic start_ready;
  logic [2:0] start_m;
  logic [2:0] start_n;
  logic [3:0] start_k;
  logic busy;
  logic done;
  logic error;
  logic result_valid;
  logic result_ready;
  logic [1:0] result_row;
  logic [1:0] result_column;
  logic [31:0] result_data;
  logic cmd_valid;
  logic cmd_ready;
  logic [3:0] cmd_id;
  logic [6:0] cmd_op;
  logic [31:0] cmd_rs1;
  logic [31:0] cmd_rs2;
  logic [31:0] cmd_instr;
  logic rsp_valid;
  logic rsp_ready;
  logic [3:0] rsp_id;
  logic [31:0] rsp_data;
  logic rsp_exc;

  sap_vpu_tiled_gemm dut (
    .clk_i(clk),
    .rst_ni(rst_n),
    .load_valid_i(load_valid),
    .load_ready_o(load_ready),
    .load_weight_i(load_weight),
    .load_index_i(load_index),
    .load_data_i(load_data),
    .start_valid_i(start_valid),
    .start_ready_o(start_ready),
    .start_m_i(start_m),
    .start_n_i(start_n),
    .start_k_i(start_k),
    .busy_o(busy),
    .done_o(done),
    .error_o(error),
    .result_valid_o(result_valid),
    .result_ready_i(result_ready),
    .result_row_o(result_row),
    .result_column_o(result_column),
    .result_data_o(result_data),
    .vpu_cmd_valid_o(cmd_valid),
    .vpu_cmd_ready_i(cmd_ready),
    .vpu_cmd_id_o(cmd_id),
    .vpu_cmd_op_o(cmd_op),
    .vpu_cmd_rs1_o(cmd_rs1),
    .vpu_cmd_rs2_o(cmd_rs2),
    .vpu_cmd_instr_o(cmd_instr),
    .vpu_rsp_valid_i(rsp_valid),
    .vpu_rsp_ready_o(rsp_ready),
    .vpu_rsp_data_i(rsp_data),
    .vpu_rsp_exc_i(rsp_exc)
  );

  sap_vpu_core vpu_i (
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

  always #5 clk = ~clk;

  task automatic load_word(input logic weight, input logic [1:0] index, input logic [31:0] data);
    @(negedge clk);
    if (!load_ready) $fatal(1, "tiled GEMM load interface not ready");
    load_valid  = 1'b1;
    load_weight = weight;
    load_index  = index;
    load_data   = data;
    @(negedge clk);
    load_valid = 1'b0;
  endtask

  task automatic start_tile(input logic [2:0] m_size, input logic [2:0] n_size, input logic [3:0] k_size);
    @(negedge clk);
    if (!start_ready) $fatal(1, "tiled GEMM start interface not ready");
    start_valid = 1'b1;
    start_m = m_size;
    start_n = n_size;
    start_k = k_size;
    @(negedge clk);
    start_valid = 1'b0;
  endtask

  task automatic expect_result(
    input logic [1:0] expected_row,
    input logic [1:0] expected_column,
    input logic [31:0] expected_data
  );
    do @(negedge clk); while (!result_valid);
    if ((result_row != expected_row) || (result_column != expected_column) ||
        (result_data !== expected_data)) begin
      $fatal(1, "result [%0d,%0d] expected %0d, got [%0d,%0d]=%0d",
             expected_row, expected_column, expected_data,
             result_row, result_column, result_data);
    end
  endtask

  task automatic expect_done;
    while (!done) @(negedge clk);
    if (error) $fatal(1, "tiled GEMM completed with error");
  endtask

  task automatic expect_error;
    while (!done) @(negedge clk);
    if (!error || busy) $fatal(1, "invalid tiled GEMM dimensions were not rejected");
  endtask

  initial begin
    clk = 1'b0;
    rst_n = 1'b0;
    load_valid = 1'b0;
    load_weight = 1'b0;
    load_index = '0;
    load_data = '0;
    start_valid = 1'b0;
    start_m = '0;
    start_n = '0;
    start_k = '0;
    result_ready = 1'b1;

    repeat (4) @(posedge clk);
    rst_n = 1'b1;

    load_word(1'b0, 0, 32'h0403_0201);
    load_word(1'b0, 1, 32'h0102_0304);
    load_word(1'b1, 0, 32'h0101_0101);
    load_word(1'b1, 1, 32'h0001_0001);
    start_tile(2, 2, 4);
    expect_result(0, 0, 10);
    expect_result(0, 1, 4);
    expect_result(1, 0, 10);
    expect_result(1, 1, 6);
    expect_done();

    load_word(1'b0, 0, 32'h7f03_0201);
    load_word(1'b1, 0, 32'h7f06_0504);
    start_tile(1, 1, 3);
    expect_result(0, 0, 32);
    expect_done();

    load_word(1'b0, 0, 32'h0403_0201);
    load_word(1'b0, 1, 32'h0807_0605);
    load_word(1'b0, 2, 32'h0506_0708);
    load_word(1'b0, 3, 32'h0102_0304);
    load_word(1'b1, 0, 32'h0101_0101);
    load_word(1'b1, 1, 32'h0101_0101);
    load_word(1'b1, 2, 32'h0001_0001);
    load_word(1'b1, 3, 32'h0001_0001);
    start_tile(2, 2, 8);
    expect_result(0, 0, 36);
    expect_result(0, 1, 16);
    expect_result(1, 0, 36);
    expect_result(1, 1, 20);
    expect_done();

    load_word(1'b0, 0, 32'h0403_0201);
    load_word(1'b0, 1, 32'h7f7f_7f05);
    load_word(1'b1, 0, 32'h0203_0405);
    load_word(1'b1, 1, 32'h7f7f_7f01);
    start_tile(1, 1, 5);
    expect_result(0, 0, 35);
    expect_done();

    start_tile(1, 1, 0);
    expect_error();
    start_tile(1, 1, 9);
    expect_error();

    $display("tiled GEMM RTL smoke: PASS");
    $finish;
  end

  initial begin
    repeat (1200) @(posedge clk);
    $fatal(1, "tiled GEMM RTL smoke timed out");
  end
endmodule
