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
  output logic                   rsp_exc_o,

  output logic                   dma_req_o,
  input  logic                   dma_gnt_i,
  output logic [31:0]            dma_addr_o,
  output logic                   dma_we_o,
  output logic [3:0]             dma_be_o,
  output logic [31:0]            dma_wdata_o,
  input  logic                   dma_rvalid_i,
  input  logic [31:0]            dma_rdata_i,
  input  logic                   dma_err_i
);
  import sap_vpu_pkg::*;

  typedef enum logic [2:0] {
    STREAM_DESC_REQ,
    STREAM_DESC_WAIT,
    STREAM_LOAD_REQ,
    STREAM_LOAD_WAIT,
    STREAM_START,
    STREAM_COLLECT,
    STREAM_STORE_REQ,
    STREAM_STORE_WAIT
  } stream_state_t;

  logic is_tile_load;
  logic is_tile_start;
  logic is_tile_read;
  logic is_tile_dma;
  logic is_tile_store;
  logic is_tile_stream;
  logic is_dma_counter_read;
  logic is_tile_op;
  logic start_args_valid;
  logic dma_args_valid;
  logic store_args_valid;
  logic stream_args_valid;

  logic                  dma_active_q;
  logic                  dma_wait_q;
  logic [X_ID_WIDTH-1:0] dma_cmd_id_q;
  logic [31:0]           dma_addr_q;
  logic [2:0]            dma_count_q;
  logic [1:0]            dma_index_q;
  logic                  dma_weight_q;
  logic                  dma_metadata_q;
  logic [3:0]            dma_group_mask_q;
  logic                  dma_group_valid;
  logic                  dma_skip_load;
  logic [31:0]           dma_read_saved_q;

  logic                  store_active_q;
  logic                  store_wait_q;
  logic [X_ID_WIDTH-1:0] store_cmd_id_q;
  logic [31:0]           store_addr_q;

  logic                  stream_active_q;
  stream_state_t         stream_state_q;
  logic [X_ID_WIDTH-1:0] stream_cmd_id_q;
  logic [31:0]           stream_desc_addr_q;
  logic [1:0]            stream_desc_index_q;
  logic [31:0]           stream_lhs_base_q;
  logic [31:0]           stream_rhs_base_q;
  logic [31:0]           stream_out_base_q;
  logic [6:0]            stream_block_count_q;
  logic [5:0]            stream_chunk_q;
  logic [3:0]            stream_load_index_q;
  logic [1:0]            stream_result_index_q;
  logic [1:0]            stream_store_index_q;
  logic signed [31:0]    stream_accumulator_q [0:3];
  logic                  stream_dma_req;
  logic [31:0]           stream_dma_addr;
  logic                  stream_dma_we;
  logic [31:0]           stream_dma_wdata;
  logic                  stream_load_response;

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
  logic                  tile_load_ready;
  logic                  tile_load_weight;
  logic [1:0]            tile_load_index;
  logic [31:0]           tile_load_data;
  logic                  tile_load_group_valid;
  logic                  tile_start_valid;
  logic                  tile_start_ready;
  logic [2:0]            tile_start_m;
  logic [2:0]            tile_start_n;
  logic [3:0]            tile_start_k;
  logic                  tile_busy;
  logic                  tile_done;
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
  assign is_tile_dma   = cmd_op_i == SAP_OP_VTDMA;
  assign is_tile_store = cmd_op_i == SAP_OP_VTSTORE;
  assign is_tile_stream = cmd_op_i == SAP_OP_VTSTREAM;
  assign is_dma_counter_read = (cmd_op_i == SAP_OP_VREADCNT) &&
                               (cmd_rs1_i[2:0] == SAP_CNT_DMA_READ_SAVED);
  assign is_tile_op    = is_tile_load || is_tile_start || is_tile_read ||
                         is_tile_dma || is_tile_store || is_tile_stream ||
                         is_dma_counter_read;

  assign start_args_valid = (cmd_rs1_i[2:0] >= 1) && (cmd_rs1_i[2:0] <= 2) &&
                            (cmd_rs1_i[5:3] >= 1) && (cmd_rs1_i[5:3] <= 2) &&
                            (cmd_rs1_i[9:6] >= 1) && (cmd_rs1_i[9:6] <= 8);
  assign dma_args_valid = (cmd_rs1_i[1:0] == 2'b00) &&
                          (cmd_rs2_i[3:1] >= 1) && (cmd_rs2_i[3:1] <= 4);
  assign store_args_valid = (cmd_rs1_i[1:0] == 2'b00) && tile_busy;
  assign stream_args_valid = (cmd_rs1_i[1:0] == 2'b00) && (cmd_rs2_i == '0);

  always_comb begin
    cmd_ready_o = 1'b0;
    if (!local_rsp_valid_q && !dma_active_q && !store_active_q && !stream_active_q) begin
      if (is_tile_load) begin
        cmd_ready_o = !tile_busy;
      end else if (is_tile_start) begin
        cmd_ready_o = !tile_busy;
      end else if (is_tile_read) begin
        cmd_ready_o = tile_result_valid || (!tile_busy && tile_error);
      end else if (is_tile_dma) begin
        cmd_ready_o = !tile_busy;
      end else if (is_tile_store) begin
        cmd_ready_o = 1'b1;
      end else if (is_tile_stream) begin
        cmd_ready_o = !tile_busy;
      end else if (is_dma_counter_read) begin
        cmd_ready_o = !tile_busy;
      end else begin
        cmd_ready_o = !tile_busy && core_cmd_ready;
      end
    end
  end

  assign dma_group_valid = !dma_metadata_q || dma_group_mask_q[dma_index_q];
  assign dma_skip_load = dma_active_q && !dma_wait_q && !dma_group_valid;
  assign stream_load_response = stream_active_q &&
                                (stream_state_q == STREAM_LOAD_WAIT) &&
                                dma_rvalid_i && !dma_err_i;
  assign tile_load_valid  = (cmd_valid_i && cmd_ready_o && is_tile_load) ||
                            (dma_active_q && dma_wait_q && dma_rvalid_i && !dma_err_i) ||
                            dma_skip_load || stream_load_response;
  assign tile_load_weight = stream_active_q ? stream_load_index_q[2] :
                            dma_active_q ? dma_weight_q : cmd_rs2_i[0];
  assign tile_load_index  = stream_active_q ? stream_load_index_q[1:0] :
                            dma_active_q ? dma_index_q : cmd_rs2_i[2:1];
  assign tile_load_data   = stream_active_q ? dma_rdata_i :
                            dma_active_q && !dma_group_valid ? '0 :
                            dma_active_q ? dma_rdata_i : cmd_rs1_i[31:0];
  assign tile_load_group_valid = stream_active_q ? 1'b1 :
                                 dma_active_q ? dma_group_valid : 1'b1;
  assign tile_start_valid = (cmd_valid_i && cmd_ready_o && is_tile_start && start_args_valid) ||
                            (stream_active_q && (stream_state_q == STREAM_START));
  assign tile_start_m = stream_active_q ? 3'd2 : cmd_rs1_i[2:0];
  assign tile_start_n = stream_active_q ? 3'd2 : cmd_rs1_i[5:3];
  assign tile_start_k = stream_active_q ? 4'd8 : cmd_rs1_i[9:6];
  assign tile_result_ready = (cmd_valid_i && cmd_ready_o && is_tile_read && tile_result_valid) ||
                             (store_active_q && store_wait_q && dma_rvalid_i && !dma_err_i) ||
                             (stream_active_q && (stream_state_q == STREAM_COLLECT));

  assign stream_dma_req = stream_active_q &&
                          ((stream_state_q == STREAM_DESC_REQ) ||
                           (stream_state_q == STREAM_LOAD_REQ) ||
                           (stream_state_q == STREAM_STORE_REQ));
  assign stream_dma_addr = (stream_state_q == STREAM_DESC_REQ) ?
                           stream_desc_addr_q + {28'd0, stream_desc_index_q, 2'b00} :
                           (stream_state_q == STREAM_LOAD_REQ) ?
                           (stream_load_index_q[2] ? stream_rhs_base_q : stream_lhs_base_q) +
                           ({26'd0, stream_chunk_q} << 4) +
                           ({28'd0, stream_load_index_q[1:0]} << 2) :
                           stream_out_base_q + {28'd0, stream_store_index_q, 2'b00};
  assign stream_dma_we = stream_state_q == STREAM_STORE_REQ;
  assign stream_dma_wdata = stream_accumulator_q[stream_store_index_q];

  assign dma_req_o   = stream_active_q ? stream_dma_req :
                       (dma_active_q && !dma_wait_q && dma_group_valid) ||
                       (store_active_q && !store_wait_q && tile_result_valid);
  assign dma_addr_o  = stream_active_q ? stream_dma_addr :
                       store_active_q ? store_addr_q : dma_addr_q;
  assign dma_we_o    = stream_active_q ? stream_dma_we : store_active_q;
  assign dma_be_o    = dma_we_o ? 4'hf : 4'h0;
  assign dma_wdata_o = stream_active_q ? stream_dma_wdata : tile_result_data;

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
      dma_active_q      <= 1'b0;
      dma_wait_q        <= 1'b0;
      dma_cmd_id_q      <= '0;
      dma_addr_q        <= '0;
      dma_count_q       <= '0;
      dma_index_q       <= '0;
      dma_weight_q      <= 1'b0;
      dma_metadata_q    <= 1'b0;
      dma_group_mask_q  <= '0;
      dma_read_saved_q  <= '0;
      store_active_q    <= 1'b0;
      store_wait_q      <= 1'b0;
      store_cmd_id_q    <= '0;
      store_addr_q      <= '0;
      stream_active_q     <= 1'b0;
      stream_state_q      <= STREAM_DESC_REQ;
      stream_cmd_id_q     <= '0;
      stream_desc_addr_q  <= '0;
      stream_desc_index_q <= '0;
      stream_lhs_base_q   <= '0;
      stream_rhs_base_q   <= '0;
      stream_out_base_q   <= '0;
      stream_block_count_q <= '0;
      stream_chunk_q      <= '0;
      stream_load_index_q <= '0;
      stream_result_index_q <= '0;
      stream_store_index_q <= '0;
      for (int unsigned i = 0; i < 4; i++) begin
        stream_accumulator_q[i] <= '0;
      end
    end else begin
      if (local_rsp_valid_q && rsp_ready_i) begin
        local_rsp_valid_q <= 1'b0;
      end
      if (cmd_valid_i && cmd_ready_o && is_tile_op) begin
        if (is_tile_stream && stream_args_valid) begin
          stream_active_q     <= 1'b1;
          stream_state_q      <= STREAM_DESC_REQ;
          stream_cmd_id_q     <= cmd_id_i;
          stream_desc_addr_q  <= cmd_rs1_i[31:0];
          stream_desc_index_q <= '0;
          stream_chunk_q      <= '0;
          stream_load_index_q <= '0;
          stream_result_index_q <= '0;
          stream_store_index_q <= '0;
          for (int unsigned i = 0; i < 4; i++) begin
            stream_accumulator_q[i] <= '0;
          end
        end else if (is_tile_dma && dma_args_valid) begin
          dma_active_q <= 1'b1;
          dma_wait_q   <= 1'b0;
          dma_cmd_id_q <= cmd_id_i;
          dma_addr_q   <= cmd_rs1_i[31:0];
          dma_count_q  <= cmd_rs2_i[3:1];
          dma_index_q  <= '0;
          dma_weight_q <= cmd_rs2_i[0];
          dma_metadata_q   <= cmd_rs2_i[8];
          dma_group_mask_q <= cmd_rs2_i[7:4];
        end else if (is_tile_store && store_args_valid) begin
          store_active_q <= 1'b1;
          store_wait_q   <= 1'b0;
          store_cmd_id_q <= cmd_id_i;
          store_addr_q   <= cmd_rs1_i[31:0];
        end else begin
          local_rsp_valid_q <= 1'b1;
          local_rsp_id_q    <= cmd_id_i;
          local_rsp_data_q  <= is_tile_read ? XLEN'(tile_result_data) :
                               is_dma_counter_read ? XLEN'(dma_read_saved_q) : '0;
          local_rsp_exc_q   <= (is_tile_start && !start_args_valid) ||
                               (is_tile_read && tile_error && !tile_result_valid) ||
                               (is_tile_dma && !dma_args_valid) ||
                               (is_tile_store && !store_args_valid) ||
                               (is_tile_stream && !stream_args_valid);
        end
      end

      if (cmd_valid_i && cmd_ready_o && (cmd_op_i == SAP_OP_VCLEARCNT)) begin
        dma_read_saved_q <= '0;
      end

      if (dma_req_o && dma_gnt_i && !stream_active_q) begin
        if (store_active_q) begin
          store_wait_q <= 1'b1;
        end else begin
          dma_wait_q <= 1'b1;
        end
      end

      if (dma_active_q && dma_wait_q && dma_rvalid_i) begin
        dma_wait_q <= 1'b0;
        if (dma_err_i || !tile_load_ready) begin
          dma_active_q      <= 1'b0;
          local_rsp_valid_q <= 1'b1;
          local_rsp_id_q    <= dma_cmd_id_q;
          local_rsp_data_q  <= '0;
          local_rsp_exc_q   <= 1'b1;
        end else if (({1'b0, dma_index_q} + 3'd1) >= dma_count_q) begin
          dma_active_q      <= 1'b0;
          local_rsp_valid_q <= 1'b1;
          local_rsp_id_q    <= dma_cmd_id_q;
          local_rsp_data_q  <= XLEN'(dma_count_q);
          local_rsp_exc_q   <= 1'b0;
        end else begin
          dma_addr_q  <= dma_addr_q + 32'd4;
          dma_index_q <= dma_index_q + 1'b1;
        end
      end

      if (dma_skip_load) begin
        if (!tile_load_ready) begin
          dma_active_q      <= 1'b0;
          local_rsp_valid_q <= 1'b1;
          local_rsp_id_q    <= dma_cmd_id_q;
          local_rsp_data_q  <= '0;
          local_rsp_exc_q   <= 1'b1;
        end else begin
          dma_read_saved_q <= dma_read_saved_q + 32'd1;
          if (({1'b0, dma_index_q} + 3'd1) >= dma_count_q) begin
            dma_active_q      <= 1'b0;
            local_rsp_valid_q <= 1'b1;
            local_rsp_id_q    <= dma_cmd_id_q;
            local_rsp_data_q  <= XLEN'(dma_count_q);
            local_rsp_exc_q   <= 1'b0;
          end else begin
            dma_addr_q  <= dma_addr_q + 32'd4;
            dma_index_q <= dma_index_q + 1'b1;
          end
        end
      end

      if (store_active_q && store_wait_q && dma_rvalid_i) begin
        store_wait_q <= 1'b0;
        if (dma_err_i) begin
          store_active_q    <= 1'b0;
          local_rsp_valid_q <= 1'b1;
          local_rsp_id_q    <= store_cmd_id_q;
          local_rsp_data_q  <= '0;
          local_rsp_exc_q   <= 1'b1;
        end else begin
          store_addr_q <= store_addr_q + 32'd4;
        end
      end

      if (store_active_q && !store_wait_q && tile_done) begin
        store_active_q    <= 1'b0;
        local_rsp_valid_q <= 1'b1;
        local_rsp_id_q    <= store_cmd_id_q;
        local_rsp_data_q  <= '0;
        local_rsp_exc_q   <= 1'b0;
      end

      if (stream_active_q) begin
        unique case (stream_state_q)
          STREAM_DESC_REQ: begin
            if (stream_dma_req && dma_gnt_i) begin
              stream_state_q <= STREAM_DESC_WAIT;
            end
          end
          STREAM_DESC_WAIT: begin
            if (dma_rvalid_i) begin
              if (dma_err_i) begin
                stream_active_q     <= 1'b0;
                local_rsp_valid_q   <= 1'b1;
                local_rsp_id_q      <= stream_cmd_id_q;
                local_rsp_data_q    <= '0;
                local_rsp_exc_q     <= 1'b1;
              end else begin
                unique case (stream_desc_index_q)
                  2'd0: stream_lhs_base_q <= dma_rdata_i;
                  2'd1: stream_rhs_base_q <= dma_rdata_i;
                  2'd2: stream_out_base_q <= dma_rdata_i;
                  default: stream_block_count_q <= dma_rdata_i[6:0];
                endcase
                if (stream_desc_index_q == 2'd3) begin
                  if ((stream_lhs_base_q[1:0] != 2'b00) ||
                      (stream_rhs_base_q[1:0] != 2'b00) ||
                      (stream_out_base_q[1:0] != 2'b00) ||
                      (dma_rdata_i[31:7] != '0) ||
                      (dma_rdata_i[6:0] < 7'd1) ||
                      (dma_rdata_i[6:0] > 7'd64)) begin
                    stream_active_q     <= 1'b0;
                    local_rsp_valid_q   <= 1'b1;
                    local_rsp_id_q      <= stream_cmd_id_q;
                    local_rsp_data_q    <= '0;
                    local_rsp_exc_q     <= 1'b1;
                  end else begin
                    stream_chunk_q      <= '0;
                    stream_load_index_q <= '0;
                    stream_state_q      <= STREAM_LOAD_REQ;
                  end
                end else begin
                  stream_desc_index_q <= stream_desc_index_q + 1'b1;
                  stream_state_q      <= STREAM_DESC_REQ;
                end
              end
            end
          end
          STREAM_LOAD_REQ: begin
            if (stream_dma_req && dma_gnt_i) begin
              stream_state_q <= STREAM_LOAD_WAIT;
            end
          end
          STREAM_LOAD_WAIT: begin
            if (dma_rvalid_i) begin
              if (dma_err_i || !tile_load_ready) begin
                stream_active_q     <= 1'b0;
                local_rsp_valid_q   <= 1'b1;
                local_rsp_id_q      <= stream_cmd_id_q;
                local_rsp_data_q    <= '0;
                local_rsp_exc_q     <= 1'b1;
              end else if (stream_load_index_q == 4'd7) begin
                stream_load_index_q <= '0;
                stream_state_q      <= STREAM_START;
              end else begin
                stream_load_index_q <= stream_load_index_q + 1'b1;
                stream_state_q      <= STREAM_LOAD_REQ;
              end
            end
          end
          STREAM_START: begin
            if (tile_start_valid && tile_start_ready) begin
              stream_result_index_q <= '0;
              stream_state_q        <= STREAM_COLLECT;
            end
          end
          STREAM_COLLECT: begin
            if (tile_done && tile_error) begin
              stream_active_q     <= 1'b0;
              local_rsp_valid_q   <= 1'b1;
              local_rsp_id_q      <= stream_cmd_id_q;
              local_rsp_data_q    <= '0;
              local_rsp_exc_q     <= 1'b1;
            end else if (tile_result_valid) begin
              stream_accumulator_q[stream_result_index_q] <=
                stream_accumulator_q[stream_result_index_q] + $signed(tile_result_data);
              if (stream_result_index_q == 2'd3) begin
                stream_result_index_q <= '0;
                if (({1'b0, stream_chunk_q} + 7'd1) >= stream_block_count_q) begin
                  stream_store_index_q <= '0;
                  stream_state_q       <= STREAM_STORE_REQ;
                end else begin
                  stream_chunk_q      <= stream_chunk_q + 1'b1;
                  stream_load_index_q <= '0;
                  stream_state_q      <= STREAM_LOAD_REQ;
                end
              end else begin
                stream_result_index_q <= stream_result_index_q + 1'b1;
              end
            end
          end
          STREAM_STORE_REQ: begin
            if (stream_dma_req && dma_gnt_i) begin
              stream_state_q <= STREAM_STORE_WAIT;
            end
          end
          STREAM_STORE_WAIT: begin
            if (dma_rvalid_i) begin
              if (dma_err_i) begin
                stream_active_q     <= 1'b0;
                local_rsp_valid_q   <= 1'b1;
                local_rsp_id_q      <= stream_cmd_id_q;
                local_rsp_data_q    <= '0;
                local_rsp_exc_q     <= 1'b1;
              end else if (stream_store_index_q == 2'd3) begin
                stream_active_q     <= 1'b0;
                local_rsp_valid_q   <= 1'b1;
                local_rsp_id_q      <= stream_cmd_id_q;
                local_rsp_data_q    <= XLEN'(stream_block_count_q);
                local_rsp_exc_q     <= 1'b0;
              end else begin
                stream_store_index_q <= stream_store_index_q + 1'b1;
                stream_state_q       <= STREAM_STORE_REQ;
              end
            end
          end
          default: stream_state_q <= STREAM_DESC_REQ;
        endcase
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
    .load_ready_o(tile_load_ready),
    .load_weight_i(tile_load_weight),
    .load_index_i(tile_load_index),
    .load_data_i(tile_load_data),
    .load_group_valid_i(tile_load_group_valid),
    .start_valid_i(tile_start_valid),
    .start_ready_o(tile_start_ready),
    .start_m_i(tile_start_m),
    .start_n_i(tile_start_n),
    .start_k_i(tile_start_k),
    .busy_o(tile_busy),
    .done_o(tile_done),
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
