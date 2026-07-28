`timescale 1ns/1ps

module tb_programmable_runtime_top;
  import cnn_dma_packet_pkg::*;

  localparam logic [1:0] METADATA_HEADER = 2'd0;
  localparam logic [1:0] METADATA_LAYER = 2'd1;
  localparam logic [1:0] METADATA_TENSOR = 2'd2;
  localparam logic [1:0] METADATA_QUANTIZATION = 2'd3;

  logic clk = 1'b0;
  logic rst_n = 1'b0;
  logic clear = 1'b0;
  logic start = 1'b0;
  logic [31:0] job_id = 32'd77;
  logic begin_model_load = 1'b0;
  logic finish_model_load = 1'b0;
  logic validate_model = 1'b0;
  logic activate_model = 1'b0;
  logic retire_active_model = 1'b0;
  logic clear_model_error = 1'b0;
  logic metadata_write = 1'b0;
  logic metadata_commit = 1'b0;
  logic [1:0] metadata_kind = '0;
  logic [5:0] metadata_record_index = '0;
  logic [5:0] metadata_word_index = '0;
  logic [31:0] metadata_write_data = '0;
  logic [31:0] metadata_read_data;
  logic [2:0] parameter_layer_select = '0;
  logic [31:0] s_axis_tdata = '0;
  logic [3:0] s_axis_tkeep = '0;
  logic s_axis_tvalid = 1'b0;
  logic s_axis_tready;
  logic s_axis_tlast = 1'b0;
  logic [31:0] m_axis_tdata;
  logic [3:0] m_axis_tkeep;
  logic m_axis_tvalid;
  logic m_axis_tready = 1'b1;
  logic m_axis_tlast;
  logic [2:0] staging_state;
  logic model_active_valid;
  logic [31:0] active_model_id;
  logic [31:0] active_generation_id;
  logic [15:0] active_layer_count;
  logic [7:0] model_lifecycle_error;
  logic [2:0] active_layer;
  logic [15:0] active_input_tensor_id;
  logic [15:0] active_output_tensor_id;
  logic [63:0] active_input_ddr_offset;
  logic [63:0] active_output_ddr_offset;
  logic [15:0] current_tile_x;
  logic [15:0] current_tile_y;
  logic [31:0] completed_layer_count;
  logic [31:0] completed_tile_count;
  logic layer_done;
  logic busy;
  logic done;
  logic error;
  logic [7:0] error_code;
  logic [2:0] error_layer;
  logic [31:0] packet_error_count;
  logic [1:0] parameter_bank_valid;

  logic [31:0] captured_data [0:31];
  logic [3:0] captured_keep [0:31];
  logic captured_last [0:31];
  int captured_count = 0;

  always #5 clk = ~clk;

  cnn_programmable_runtime_top #(
    .PC(2), .PK(2), .MAX_CIN(2), .MAX_COUT(2),
    .MAX_LAYERS(2), .MAX_TENSORS(4), .MAX_QUANTIZATIONS(2),
    .MAX_TILE_WIDTH(2), .MAX_TILE_HEIGHT(2),
    .MAX_PAYLOAD_BYTES(1024)
  ) dut (.*);

  always_ff @(posedge clk) begin
    if (m_axis_tvalid && m_axis_tready) begin
      captured_data[captured_count] <= m_axis_tdata;
      captured_keep[captured_count] <= m_axis_tkeep;
      captured_last[captured_count] <= m_axis_tlast;
      captured_count <= captured_count + 1;
    end
  end

  function automatic logic [31:0] crc32_byte(
    input logic [31:0] crc_in,
    input logic [7:0] data
  );
    logic [31:0] value;
    begin
      value = crc_in ^ {24'd0, data};
      for (int bit_index = 0; bit_index < 8; bit_index++) begin
        value = value[0] ? ((value >> 1) ^ 32'hEDB8_8320) : (value >> 1);
      end
      return value;
    end
  endfunction

  task automatic pulse(input int command);
    begin
      @(negedge clk);
      case (command)
        0: begin_model_load = 1'b1;
        1: finish_model_load = 1'b1;
        2: validate_model = 1'b1;
        3: activate_model = 1'b1;
        4: start = 1'b1;
        default: clear = 1'b1;
      endcase
      @(negedge clk);
      begin_model_load = 1'b0;
      finish_model_load = 1'b0;
      validate_model = 1'b0;
      activate_model = 1'b0;
      start = 1'b0;
      clear = 1'b0;
    end
  endtask

  task automatic write_word(
    input logic [1:0] kind,
    input int record_index,
    input int word_index,
    input logic [31:0] data
  );
    begin
      @(negedge clk);
      metadata_kind = kind;
      metadata_record_index = 6'(record_index);
      metadata_word_index = 6'(word_index);
      metadata_write_data = data;
      metadata_write = 1'b1;
      @(negedge clk);
      metadata_write = 1'b0;
    end
  endtask

  task automatic commit_record(input logic [1:0] kind, input int index);
    begin
      @(negedge clk);
      metadata_kind = kind;
      metadata_record_index = 6'(index);
      metadata_commit = 1'b1;
      @(negedge clk);
      metadata_commit = 1'b0;
    end
  endtask

  task automatic load_model;
    logic [31:0] parameter_crc;
    begin
      parameter_crc = crc32_byte(32'hFFFF_FFFF, 8'd1) ^ 32'hFFFF_FFFF;
      write_word(METADATA_HEADER, 0, 0, 32'h314E_4E43);
      write_word(METADATA_HEADER, 0, 1, 32'h0080_0001);
      write_word(METADATA_HEADER, 0, 4, 32'd101);
      write_word(METADATA_HEADER, 0, 5, 32'd9);
      write_word(METADATA_HEADER, 0, 6, 32'h0002_0001);
      write_word(METADATA_HEADER, 0, 7, 32'h0000_0001);
      commit_record(METADATA_HEADER, 0);

      write_word(METADATA_LAYER, 0, 0, 32'h0080_0001);
      write_word(METADATA_LAYER, 0, 1, 32'h0001_0000);
      write_word(METADATA_LAYER, 0, 2, 32'h0000_0002);
      write_word(METADATA_LAYER, 0, 3, 32'h0001_0000);
      write_word(METADATA_LAYER, 0, 4, 32'h0000_FFFF);
      write_word(METADATA_LAYER, 0, 6, 32'd1);
      write_word(METADATA_LAYER, 0, 8, 32'd0);
      write_word(METADATA_LAYER, 0, 9, parameter_crc);
      write_word(METADATA_LAYER, 0, 10, 32'h0101_0101);
      write_word(METADATA_LAYER, 0, 11, 32'd0);
      write_word(METADATA_LAYER, 0, 12, 32'h0000_0101);
      write_word(METADATA_LAYER, 0, 13, 32'h0002_0002);
      commit_record(METADATA_LAYER, 0);

      for (int tensor = 0; tensor < 2; tensor++) begin
        write_word(METADATA_TENSOR, tensor, 0, 32'h0040_0001);
        write_word(METADATA_TENSOR, tensor, 1, {16'd1, 16'(tensor)});
        write_word(METADATA_TENSOR, tensor, 2,
                   tensor == 0 ? 32'h0000_1000 : 32'h0000_2000);
        write_word(METADATA_TENSOR, tensor, 3, 32'd0);
        write_word(METADATA_TENSOR, tensor, 4, 32'd6);
        write_word(METADATA_TENSOR, tensor, 5, 32'h0002_0003);
        write_word(METADATA_TENSOR, tensor, 6, 32'h0101_0001);
        write_word(METADATA_TENSOR, tensor, 9, 32'd3);
        write_word(METADATA_TENSOR, tensor, 10, 32'd1);
        write_word(METADATA_TENSOR, tensor, 11, 32'd1);
        commit_record(METADATA_TENSOR, tensor);
      end

      write_word(METADATA_QUANTIZATION, 0, 0, 32'h00C0_0001);
      write_word(METADATA_QUANTIZATION, 0, 1, 32'd0);
      commit_record(METADATA_QUANTIZATION, 0);
    end
  endtask

  task automatic send_beat(
    input logic [31:0] data,
    input logic [3:0] keep,
    input logic last
  );
    begin
      @(negedge clk);
      s_axis_tdata = data;
      s_axis_tkeep = keep;
      s_axis_tlast = last;
      s_axis_tvalid = 1'b1;
      do @(posedge clk); while (!s_axis_tready);
      @(negedge clk);
      s_axis_tvalid = 1'b0;
      s_axis_tlast = 1'b0;
      s_axis_tkeep = '0;
    end
  endtask

  task automatic send_packet(
    input logic [7:0] type_id,
    input int tensor_id,
    input int layer_id,
    input int tile_x,
    input int tile_width,
    input logic [31:0] payload,
    input logic [3:0] payload_keep,
    input int payload_bytes
  );
    begin
      send_beat(DMA_PACKET_MAGIC, 4'hF, 1'b0);
      send_beat({8'd0, type_id, DMA_PACKET_HEADER_WORDS,
                 DMA_PACKET_VERSION}, 4'hF, 1'b0);
      send_beat(job_id, 4'hF, 1'b0);
      send_beat({16'(layer_id), 16'(tensor_id)}, 4'hF, 1'b0);
      send_beat({16'd0, 16'(tile_x)}, 4'hF, 1'b0);
      send_beat({16'd2, 16'(tile_width)}, 4'hF, 1'b0);
      send_beat({16'd1, 16'd0}, 4'hF, 1'b0);
      send_beat(32'(payload_bytes), 4'hF, 1'b0);
      send_beat(payload, payload_keep, 1'b1);
    end
  endtask

  initial begin
    repeat (4) @(posedge clk);
    rst_n = 1'b1;
    repeat (2) @(posedge clk);

    pulse(0);
    load_model();
    pulse(1);
    pulse(2);
    pulse(3);
    if (!model_active_valid || (active_model_id != 101) ||
        (active_generation_id != 9) || (active_layer_count != 1) ||
        (model_lifecycle_error != 0)) begin
      $fatal(1, "model activation failed state=%0d error=%0d",
             staging_state, model_lifecycle_error);
    end

    send_packet(DMA_PACKET_LAYER_WEIGHTS, 0, 0, 0, 0,
                32'd1, 4'b0001, 1);
    wait (parameter_bank_valid[0] || parameter_bank_valid[1]);

    pulse(4);
    wait (busy && (current_tile_x == 0));
    send_packet(DMA_PACKET_INPUT_TILE, 0, 0, 0, 2,
                32'h0504_0201, 4'b1111, 4);
    wait (busy && (current_tile_x == 2));
    send_packet(DMA_PACKET_INPUT_TILE, 0, 0, 2, 1,
                32'h0000_0603, 4'b0011, 2);

    fork
      wait (done);
      begin
        repeat (10000) @(posedge clk);
        $fatal(1, "integrated programmable runtime timed out");
      end
    join_any
    disable fork;
    repeat (2) @(posedge clk);

    if (error || (packet_error_count != 0) ||
        (completed_layer_count != 1) || (captured_count != 18)) begin
      $fatal(1, "runtime status error=%0d/%0d packet=%0d layers=%0d beats=%0d",
             error, error_code, packet_error_count,
             completed_layer_count, captured_count);
    end
    if ((captured_data[3] != {16'd0, 16'd1}) ||
        (captured_data[8] != 32'h0504_0201) ||
        (captured_data[12] != {16'd0, 16'd1}) ||
        (captured_data[17] != 32'h0000_0603) ||
        (captured_keep[17] != 4'b0011) || !captured_last[17]) begin
      $fatal(1, "integrated output packet mismatch");
    end

    $display("[PASS] active model to packed tiled output integration");
    $finish;
  end
endmodule
