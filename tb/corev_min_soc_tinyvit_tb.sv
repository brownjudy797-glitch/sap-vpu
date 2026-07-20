`timescale 1ns/1ps

module corev_min_soc_tinyvit_tb #(
  parameter string ROM_INIT_FILE = "work/tinyvit/sap_vpu_tinyvit.hex"
);
  localparam int unsigned TIMEOUT_CYCLES = 90000;
  localparam logic [31:0] RESULT_MAGIC = 32'h5456_4954; // "TVIT"
  localparam int unsigned TINYVIT_ITERS = 16;
  localparam logic [31:0] RESULT_BASE = 32'h0001_0000;
  localparam logic [31:0] TINYVIT_TILE_BASE = 32'h0001_0200;
  localparam logic [31:0] TINYVIT_MLP2_BASE = TINYVIT_TILE_BASE + 32'd512;
  localparam logic [31:0] TINYVIT_TILE_LIMIT = TINYVIT_MLP2_BASE + 32'd32;
  localparam int unsigned EXPECTED_TILE_READS = 11392;
  localparam int unsigned K_DENSE = 0;
  localparam int unsigned K_STATIC_LOWBIT = 1;
  localparam int unsigned K_STATIC_INT2 = 2;
  localparam int unsigned K_ADAPTIVE = 3;
  localparam int unsigned K_ADAPTIVE_UNSTRUCTURED = 4;
  localparam int unsigned K_NO_SPARSE = 5;
  localparam int unsigned K_NO_LANE = 6;
  localparam int unsigned K_NO_PRECISION = 7;
  localparam int unsigned K_DENSE_REUSE = 8;
  localparam int unsigned K_ADAPTIVE_REUSE = 9;
  localparam int unsigned K_ADAPTIVE_SPARSE75 = 10;
  localparam int unsigned K_DENSE_X4 = 11;
  localparam int unsigned K_ADAPTIVE_SPARSE75_SCHEDULE = 12;
  localparam int unsigned K_MLP2 = 13;
  localparam int unsigned K_DONE = 14;

`include "tinyvit_mlp2_fixture_tb.svh"

  logic clk;
  logic rst_n;
  logic fetch_enable;
  logic uart_tx_valid;
  logic [7:0] uart_tx_data;
  logic exit_valid;
  logic [31:0] exit_code;
  logic core_sleep;
  int result_fd;
  int unsigned current_kernel;
  int unsigned tile_read_count;
  int unsigned operand_read_count [0:13];
  int unsigned weight_read_count [0:13];
  int unsigned kernel_tile_read_count [0:13];
  string vcd_file;

  corev_min_soc #(
    .ROM_WORDS(2048),
    .ROM_INIT_FILE(ROM_INIT_FILE)
  ) dut (
    .clk_i(clk),
    .rst_ni(rst_n),
    .fetch_enable_i(fetch_enable),
    .uart_tx_valid_o(uart_tx_valid),
    .uart_tx_data_o(uart_tx_data),
    .exit_valid_o(exit_valid),
    .exit_code_o(exit_code),
    .core_sleep_o(core_sleep)
  );

  always #5 clk = ~clk;

  initial begin
    if ($value$plusargs("vcd=%s", vcd_file)) begin
      $dumpfile(vcd_file);
      $dumpvars(0, dut.vpu_i);
    end
  end

  task automatic expect_result(input int unsigned index, input logic [31:0] expected);
    if (dut.ram[index] !== expected) begin
      $fatal(1, "TinyViT result ram[%0d] expected %0d got %0d", index, expected, dut.ram[index]);
    end
  endtask

  task automatic expect_traffic(
    input int unsigned index,
    input int unsigned expected_operand_reads,
    input int unsigned expected_weight_reads
  );
    if (operand_read_count[index] != expected_operand_reads) begin
      $fatal(1, "TinyViT kernel[%0d] operand reads expected %0d got %0d",
             index, expected_operand_reads, operand_read_count[index]);
    end
    if (weight_read_count[index] != expected_weight_reads) begin
      $fatal(1, "TinyViT kernel[%0d] weight reads expected %0d got %0d",
             index, expected_weight_reads, weight_read_count[index]);
    end
    if (kernel_tile_read_count[index] != (expected_operand_reads + expected_weight_reads)) begin
      $fatal(1, "TinyViT kernel[%0d] tile reads expected %0d got %0d",
             index, expected_operand_reads + expected_weight_reads, kernel_tile_read_count[index]);
    end
  endtask

  function automatic bit is_operand_addr(input logic [31:0] addr);
    logic [31:0] block_offset;
    begin
      if (addr >= TINYVIT_MLP2_BASE) begin
        block_offset = addr - TINYVIT_MLP2_BASE;
        is_operand_addr = (block_offset == 32'd0) || (block_offset == 32'd4);
      end else begin
        block_offset = (addr - TINYVIT_TILE_BASE) & 32'hf;
        is_operand_addr = (block_offset == 32'd0) || (block_offset == 32'd4);
      end
    end
  endfunction

  function automatic bit is_weight_addr(input logic [31:0] addr);
    logic [31:0] block_offset;
    begin
      if (addr >= TINYVIT_MLP2_BASE) begin
        block_offset = addr - TINYVIT_MLP2_BASE;
        is_weight_addr = (block_offset >= 32'd8) && (block_offset < 32'd32);
      end else begin
        block_offset = (addr - TINYVIT_TILE_BASE) & 32'hf;
        is_weight_addr = (block_offset == 32'd8) || (block_offset == 32'd12);
      end
    end
  endfunction

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      current_kernel <= K_DENSE;
      tile_read_count <= 0;
      for (int unsigned i = 0; i < 14; i++) begin
        operand_read_count[i] <= 0;
        weight_read_count[i] <= 0;
        kernel_tile_read_count[i] <= 0;
      end
    end else begin
      if (dut.data_req && dut.data_gnt && !dut.data_we &&
          (dut.data_addr >= TINYVIT_TILE_BASE) && (dut.data_addr < TINYVIT_TILE_LIMIT)) begin
        tile_read_count <= tile_read_count + 1;
        if (current_kernel < K_DONE) begin
          kernel_tile_read_count[current_kernel] <= kernel_tile_read_count[current_kernel] + 1;
          if (is_operand_addr(dut.data_addr)) begin
            operand_read_count[current_kernel] <= operand_read_count[current_kernel] + 1;
          end else if (is_weight_addr(dut.data_addr)) begin
            weight_read_count[current_kernel] <= weight_read_count[current_kernel] + 1;
          end else begin
            $fatal(1, "Unexpected TinyViT tile read address 0x%08x", dut.data_addr);
          end
        end else begin
          $fatal(1, "Unexpected TinyViT tile read after all kernels");
        end
      end

      if (dut.data_req && dut.data_gnt && dut.data_we) begin
        unique case (dut.data_addr)
          RESULT_BASE + 32'd20:  current_kernel <= K_DENSE_X4;
          RESULT_BASE + 32'd312: current_kernel <= K_STATIC_LOWBIT;
          RESULT_BASE + 32'd48:  current_kernel <= K_STATIC_INT2;
          RESULT_BASE + 32'd188: current_kernel <= K_ADAPTIVE;
          RESULT_BASE + 32'd76:  current_kernel <= K_ADAPTIVE_SPARSE75;
          RESULT_BASE + 32'd292: current_kernel <= K_ADAPTIVE_UNSTRUCTURED;
          RESULT_BASE + 32'd216: current_kernel <= K_NO_SPARSE;
          RESULT_BASE + 32'd104: current_kernel <= K_NO_LANE;
          RESULT_BASE + 32'd132: current_kernel <= K_NO_PRECISION;
          RESULT_BASE + 32'd160: current_kernel <= K_DENSE_REUSE;
          RESULT_BASE + 32'd236: current_kernel <= K_ADAPTIVE_REUSE;
          RESULT_BASE + 32'd264: current_kernel <= K_ADAPTIVE_SPARSE75_SCHEDULE;
          RESULT_BASE + 32'd344: current_kernel <= K_MLP2;
          RESULT_BASE + 32'd364: current_kernel <= K_DONE;
          default: begin
          end
        endcase
      end

      if (uart_tx_valid) begin
        $fatal(1, "Unexpected UART byte 0x%02x", uart_tx_data);
      end

      if (exit_valid) begin
        if (exit_code !== 32'd1) begin
          $fatal(1, "TinyViT smoke exit code expected 1 got %0d", exit_code);
        end
        if (tile_read_count != EXPECTED_TILE_READS) begin
          $fatal(1, "TinyViT RAM tile reads expected %0d got %0d", EXPECTED_TILE_READS, tile_read_count);
        end
        expect_traffic(K_DENSE, 256, 512);
        expect_traffic(K_DENSE_X4, 1024, 2048);
        expect_traffic(K_STATIC_LOWBIT, 256, 512);
        expect_traffic(K_STATIC_INT2, 256, 512);
        expect_traffic(K_ADAPTIVE, 256, 512);
        expect_traffic(K_ADAPTIVE_SPARSE75, 256, 512);
        expect_traffic(K_ADAPTIVE_UNSTRUCTURED, 256, 512);
        expect_traffic(K_NO_SPARSE, 256, 512);
        expect_traffic(K_NO_LANE, 256, 512);
        expect_traffic(K_NO_PRECISION, 256, 512);
        expect_traffic(K_DENSE_REUSE, 256, 256);
        expect_traffic(K_ADAPTIVE_REUSE, 256, 256);
        expect_traffic(K_ADAPTIVE_SPARSE75_SCHEDULE, 128, 128);
        expect_traffic(K_MLP2, 32, 96);
        if (dut.ram[0] !== RESULT_MAGIC) begin
          $fatal(1, "TinyViT result magic expected 0x%08x got 0x%08x", RESULT_MAGIC, dut.ram[0]);
        end
        expect_result(1, 32'd756 * TINYVIT_ITERS);
        expect_result(2, 32'd32 * TINYVIT_ITERS);
        expect_result(3, 32'd0);
        expect_result(74, 32'd756 * 64);
        expect_result(75, 32'd32 * 64);
        expect_result(76, 32'd0);
        expect_result(6, 32'd912 * TINYVIT_ITERS);
        expect_result(7, 32'd32 * TINYVIT_ITERS);
        expect_result(8, 32'd0);
        expect_result(13, 32'd456 * TINYVIT_ITERS);
        expect_result(14, 32'd32 * TINYVIT_ITERS);
        expect_result(15, 32'd128 * TINYVIT_ITERS);
        expect_result(48, 32'd456 * TINYVIT_ITERS);
        expect_result(49, 32'd32 * TINYVIT_ITERS);
        expect_result(50, 32'd128 * TINYVIT_ITERS);
        expect_result(20, 32'd456 * TINYVIT_ITERS);
        expect_result(21, 32'd32 * TINYVIT_ITERS);
        expect_result(22, 32'd128 * TINYVIT_ITERS);
        expect_result(67, 32'd228 * TINYVIT_ITERS);
        expect_result(68, 32'd32 * TINYVIT_ITERS);
        expect_result(69, 32'd192 * TINYVIT_ITERS);
        expect_result(27, 32'd456 * TINYVIT_ITERS);
        expect_result(28, 32'd32 * TINYVIT_ITERS);
        expect_result(29, 32'd128 * TINYVIT_ITERS);
        expect_result(34, 32'd456 * TINYVIT_ITERS);
        expect_result(35, 32'd32 * TINYVIT_ITERS);
        expect_result(36, 32'd0);
        expect_result(41, 32'd320 * TINYVIT_ITERS);
        expect_result(42, 32'd32 * TINYVIT_ITERS);
        expect_result(43, 32'd0);
        expect_result(55, 32'd756 * TINYVIT_ITERS);
        expect_result(56, 32'd32 * TINYVIT_ITERS);
        expect_result(57, 32'd0);
        expect_result(60, 32'd456 * TINYVIT_ITERS);
        expect_result(61, 32'd32 * TINYVIT_ITERS);
        expect_result(62, 32'd128 * TINYVIT_ITERS);
        expect_result(80, 32'd1024);
        expect_result(81, 32'd128);
        expect_result(82, 32'd0);
        expect_result(83, 32'd255);
        expect_result(84, 32'd8);
        expect_result(87, TINYVIT_MLP2_EXPECTED_OUTPUT);
        expect_result(88, 32'd192);
        expect_result(89, 32'd0);
        if ((dut.ram[4] == 32'd0) || (dut.ram[5] == 32'd0) ||
            (dut.ram[11] == 32'd0) || (dut.ram[12] == 32'd0) ||
            (dut.ram[18] == 32'd0) || (dut.ram[19] == 32'd0) ||
            (dut.ram[25] == 32'd0) || (dut.ram[26] == 32'd0) ||
            (dut.ram[32] == 32'd0) || (dut.ram[33] == 32'd0) ||
            (dut.ram[39] == 32'd0) || (dut.ram[40] == 32'd0) ||
            (dut.ram[46] == 32'd0) || (dut.ram[47] == 32'd0) ||
            (dut.ram[53] == 32'd0) || (dut.ram[54] == 32'd0) ||
            (dut.ram[58] == 32'd0) || (dut.ram[59] == 32'd0) ||
            (dut.ram[65] == 32'd0) || (dut.ram[66] == 32'd0) ||
            (dut.ram[72] == 32'd0) || (dut.ram[73] == 32'd0) ||
            (dut.ram[85] == 32'd0) || (dut.ram[86] == 32'd0) ||
            (dut.ram[90] == 32'd0) || (dut.ram[91] == 32'd0) ||
            (dut.ram[77] == 32'd0) || (dut.ram[78] == 32'd0)) begin
          $fatal(1, "TinyViT cycle/inst counters must be nonzero");
        end
        result_fd = $fopen("work/tinyvit/tinyvit_smoke_counters.csv", "w");
        if (result_fd == 0) begin
          $fatal(1, "Could not open TinyViT counter CSV");
        end
        $fdisplay(result_fd, "kernel,precision,sparse,output,mac_active,skip,sparse_state,lane_state,cycle_delta,instret_delta,operand_reads,weight_reads,ram_tile_reads,scheduled_skip");
        $fdisplay(result_fd, "dense,int8,none,%0d,%0d,%0d,0,4,%0d,%0d,%0d,%0d,%0d,0",
                  dut.ram[1], dut.ram[2], dut.ram[3], dut.ram[4], dut.ram[5],
                  operand_read_count[K_DENSE], weight_read_count[K_DENSE],
                  kernel_tile_read_count[K_DENSE]);
        $fdisplay(result_fd, "dense_x4,int8,none,%0d,%0d,%0d,0,4,%0d,%0d,%0d,%0d,%0d,0",
                  dut.ram[74], dut.ram[75], dut.ram[76], dut.ram[77], dut.ram[78],
                  operand_read_count[K_DENSE_X4], weight_read_count[K_DENSE_X4],
                  kernel_tile_read_count[K_DENSE_X4]);
        $fdisplay(result_fd, "dense_reuse,int8,none,%0d,%0d,%0d,0,4,%0d,%0d,%0d,%0d,%0d,0",
                  dut.ram[55], dut.ram[56], dut.ram[57], dut.ram[58], dut.ram[59],
                  operand_read_count[K_DENSE_REUSE], weight_read_count[K_DENSE_REUSE],
                  kernel_tile_read_count[K_DENSE_REUSE]);
        $fdisplay(result_fd, "static_lowbit,int4,none,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,0",
                  dut.ram[6], dut.ram[7], dut.ram[8], dut.ram[9], dut.ram[10],
                  dut.ram[11], dut.ram[12], operand_read_count[K_STATIC_LOWBIT],
                  weight_read_count[K_STATIC_LOWBIT], kernel_tile_read_count[K_STATIC_LOWBIT]);
        $fdisplay(result_fd, "static_int2,int2,none,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,0",
                  dut.ram[41], dut.ram[42], dut.ram[43], dut.ram[44], dut.ram[45],
                  dut.ram[46], dut.ram[47], operand_read_count[K_STATIC_INT2],
                  weight_read_count[K_STATIC_INT2], kernel_tile_read_count[K_STATIC_INT2]);
        $fdisplay(result_fd, "adaptive,int4,bitmap,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,0",
                  dut.ram[13], dut.ram[14], dut.ram[15], dut.ram[16], dut.ram[17],
                  dut.ram[18], dut.ram[19], operand_read_count[K_ADAPTIVE],
                  weight_read_count[K_ADAPTIVE], kernel_tile_read_count[K_ADAPTIVE]);
        $fdisplay(result_fd, "adaptive_sparse75,int4,bitmap_sparse75,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,0",
                  dut.ram[67], dut.ram[68], dut.ram[69], dut.ram[70], dut.ram[71],
                  dut.ram[72], dut.ram[73], operand_read_count[K_ADAPTIVE_SPARSE75],
                  weight_read_count[K_ADAPTIVE_SPARSE75],
                  kernel_tile_read_count[K_ADAPTIVE_SPARSE75]);
        $fdisplay(result_fd, "adaptive_reuse,int4,bitmap_reuse,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,0",
                  dut.ram[60], dut.ram[61], dut.ram[62], dut.ram[63], dut.ram[64],
                  dut.ram[65], dut.ram[66], operand_read_count[K_ADAPTIVE_REUSE],
                  weight_read_count[K_ADAPTIVE_REUSE],
                  kernel_tile_read_count[K_ADAPTIVE_REUSE]);
        $fdisplay(result_fd, "adaptive_sparse75_schedule,int4,vector_skip75,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d",
                  dut.ram[80], dut.ram[81], dut.ram[82], dut.ram[83], dut.ram[84],
                  dut.ram[85], dut.ram[86], operand_read_count[K_ADAPTIVE_SPARSE75_SCHEDULE],
                  weight_read_count[K_ADAPTIVE_SPARSE75_SCHEDULE],
                  kernel_tile_read_count[K_ADAPTIVE_SPARSE75_SCHEDULE], 32'd3072);
        $fdisplay(result_fd, "tinyvit_mlp2,int8,none,%0d,%0d,%0d,15,4,%0d,%0d,%0d,%0d,%0d,0",
                  dut.ram[87], dut.ram[88], dut.ram[89], dut.ram[90], dut.ram[91],
                  operand_read_count[K_MLP2], weight_read_count[K_MLP2],
                  kernel_tile_read_count[K_MLP2]);
        $fdisplay(result_fd, "adaptive_unstructured,int4,bitmap_unstructured,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,0",
                  dut.ram[48], dut.ram[49], dut.ram[50], dut.ram[51], dut.ram[52],
                  dut.ram[53], dut.ram[54], operand_read_count[K_ADAPTIVE_UNSTRUCTURED],
                  weight_read_count[K_ADAPTIVE_UNSTRUCTURED],
                  kernel_tile_read_count[K_ADAPTIVE_UNSTRUCTURED]);
        $fdisplay(result_fd, "no_sparse_skip,int4,none,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,0",
                  dut.ram[20], dut.ram[21], dut.ram[22], dut.ram[23], dut.ram[24],
                  dut.ram[25], dut.ram[26], operand_read_count[K_NO_SPARSE],
                  weight_read_count[K_NO_SPARSE], kernel_tile_read_count[K_NO_SPARSE]);
        $fdisplay(result_fd, "no_lane_gating,int4,bitmap,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,0",
                  dut.ram[27], dut.ram[28], dut.ram[29], dut.ram[30], dut.ram[31],
                  dut.ram[32], dut.ram[33], operand_read_count[K_NO_LANE],
                  weight_read_count[K_NO_LANE], kernel_tile_read_count[K_NO_LANE]);
        $fdisplay(result_fd, "no_precision_gating,int8,bitmap,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,0",
                  dut.ram[34], dut.ram[35], dut.ram[36], dut.ram[37], dut.ram[38],
                  dut.ram[39], dut.ram[40], operand_read_count[K_NO_PRECISION],
                  weight_read_count[K_NO_PRECISION], kernel_tile_read_count[K_NO_PRECISION]);
        $fclose(result_fd);
        $display("TinyViT smoke exit code: %0d", exit_code);
        $finish;
      end
    end
  end

  initial begin
    clk = 1'b0;
    rst_n = 1'b0;
    fetch_enable = 1'b0;

    repeat (5) @(posedge clk);
    rst_n = 1'b1;
    fetch_enable = 1'b1;

    repeat (TIMEOUT_CYCLES) @(posedge clk);
    $fatal(1, "Timed out waiting for TinyViT smoke exit");
  end
endmodule
