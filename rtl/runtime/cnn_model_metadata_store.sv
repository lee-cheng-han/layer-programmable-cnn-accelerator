`timescale 1ns/1ps

module cnn_model_metadata_store #(
  parameter int MAX_LAYERS = 8,
  parameter int MAX_TENSORS = 32,
  parameter int MAX_QUANTIZATIONS = 32
)(
  input  logic        clk,
  input  logic        resetn,

  input  logic        begin_load,
  input  logic        finish_load,
  input  logic        validate_model,
  input  logic        activate_model,
  input  logic        retire_active,
  input  logic        clear_error,
  input  logic        job_busy,

  input  logic        metadata_write,
  input  logic        metadata_commit,
  input  logic [1:0]  metadata_kind,
  input  logic [5:0]  metadata_record_index,
  input  logic [5:0]  metadata_word_index,
  input  logic [31:0] metadata_write_data,
  output logic [31:0] metadata_read_data,

  input  logic [2:0]  execution_layer_index,
  output logic        execution_descriptor_valid,
  output logic [15:0] execution_layer_id,
  output logic [15:0] execution_opcode,
  output logic        execution_last_layer,
  output logic        execution_bias_enable,
  output logic [15:0] execution_input_tensor_id,
  output logic [15:0] execution_output_tensor_id,
  output logic [15:0] execution_residual_tensor_id,
  output logic [15:0] execution_quantization_id,
  output logic [31:0] execution_weight_size,
  output logic [31:0] execution_bias_size,
  output logic [31:0] execution_parameter_crc32,
  output logic [15:0] execution_input_width,
  output logic [15:0] execution_input_height,
  output logic [15:0] execution_input_channels,
  output logic [15:0] execution_output_width,
  output logic [15:0] execution_output_height,
  output logic [15:0] execution_output_channels,
  output logic [7:0]  execution_kernel_height,
  output logic [7:0]  execution_kernel_width,
  output logic [7:0]  execution_stride_y,
  output logic [7:0]  execution_stride_x,
  output logic [7:0]  execution_padding_top,
  output logic [7:0]  execution_padding_bottom,
  output logic [7:0]  execution_padding_left,
  output logic [7:0]  execution_padding_right,
  output logic [7:0]  execution_dilation_y,
  output logic [7:0]  execution_dilation_x,
  output logic [7:0]  execution_activation,
  output logic [7:0]  execution_residual_mode,
  output logic [15:0] execution_tile_height_hint,
  output logic [15:0] execution_tile_width_hint,
  output logic [63:0] execution_input_ddr_offset,
  output logic [31:0] execution_input_allocation_size,
  output logic [31:0] execution_input_row_stride,
  output logic [31:0] execution_input_pixel_stride,
  output logic [31:0] execution_input_channel_stride,
  output logic [63:0] execution_output_ddr_offset,
  output logic [31:0] execution_output_allocation_size,
  output logic [31:0] execution_output_row_stride,
  output logic [31:0] execution_output_pixel_stride,
  output logic [31:0] execution_output_channel_stride,

  output logic [2:0]  staging_state,
  output logic        staging_bank,
  output logic        active_valid,
  output logic        active_bank,
  output logic [31:0] staging_model_id,
  output logic [31:0] staging_generation_id,
  output logic [31:0] active_model_id,
  output logic [31:0] active_generation_id,
  output logic [15:0] active_layer_count,
  output logic [15:0] staging_layer_count,
  output logic [15:0] staging_tensor_count,
  output logic [15:0] staging_quantization_count,
  output logic [7:0]  lifecycle_error
);
  import cnn_accel_abi_pkg::*;

  localparam int HEADER_WORDS = MODEL_HEADER_BYTES / 4;
  localparam int LAYER_WORDS = LAYER_DESCRIPTOR_BYTES / 4;
  localparam int TENSOR_WORDS = TENSOR_DESCRIPTOR_BYTES / 4;
  localparam int QUANT_WORDS = QUANT_DESCRIPTOR_BYTES / 4;
  localparam int HEADER_DEPTH = 2 * HEADER_WORDS;
  localparam int LAYER_DEPTH = 2 * MAX_LAYERS * LAYER_WORDS;
  localparam int TENSOR_DEPTH = 2 * MAX_TENSORS * TENSOR_WORDS;
  localparam int QUANT_DEPTH = 2 * MAX_QUANTIZATIONS * QUANT_WORDS;
  localparam int LAYER_INDEX_W = (MAX_LAYERS <= 1) ? 1 : $clog2(MAX_LAYERS);
  localparam int TENSOR_INDEX_W = (MAX_TENSORS <= 1) ? 1 : $clog2(MAX_TENSORS);

  localparam logic [1:0] METADATA_HEADER = 2'd0;
  localparam logic [1:0] METADATA_LAYER = 2'd1;
  localparam logic [1:0] METADATA_TENSOR = 2'd2;
  localparam logic [1:0] METADATA_QUANTIZATION = 2'd3;

  logic [$clog2(HEADER_DEPTH)-1:0] header_address_value;
  logic [$clog2(LAYER_DEPTH)-1:0] layer_address_value;
  logic [$clog2(TENSOR_DEPTH)-1:0] tensor_address_value;
  logic [$clog2(QUANT_DEPTH)-1:0] quant_address_value;
  logic [$clog2(HEADER_DEPTH)-1:0] header_read_address_q;
  logic [$clog2(LAYER_DEPTH)-1:0] layer_read_address_q;
  logic [$clog2(TENSOR_DEPTH)-1:0] tensor_read_address_q;
  logic [$clog2(QUANT_DEPTH)-1:0] quant_read_address_q;
  logic [1:0] metadata_read_kind_q;
  logic [1:0] metadata_read_kind_qq;
  logic metadata_read_valid_q;
  logic metadata_read_valid_qq;
  logic [31:0] header_read_data;
  logic [31:0] layer_read_data;
  logic [31:0] tensor_read_data;
  logic [31:0] quant_read_data;

  logic [31:0] cached_magic [0:1];
  logic [31:0] cached_version_size [0:1];
  logic [31:0] cached_model_id [0:1];
  logic [31:0] cached_generation_id [0:1];
  logic [31:0] cached_counts0 [0:1];
  logic [31:0] cached_counts1 [0:1];

  logic [31:0] cached_layer_header [0:1][0:MAX_LAYERS-1];
  logic [31:0] cached_layer_identity [0:1][0:MAX_LAYERS-1];
  logic [31:0] cached_layer_flags [0:1][0:MAX_LAYERS-1];
  logic [31:0] cached_layer_tensor_ids [0:1][0:MAX_LAYERS-1];
  logic [31:0] cached_layer_residual_quant [0:1][0:MAX_LAYERS-1];
  logic [31:0] cached_layer_weight_size [0:1][0:MAX_LAYERS-1];
  logic [31:0] cached_layer_bias_size [0:1][0:MAX_LAYERS-1];
  logic [31:0] cached_layer_parameter_crc32 [0:1][0:MAX_LAYERS-1];
  logic [31:0] cached_layer_geometry [0:1][0:MAX_LAYERS-1];
  logic [31:0] cached_layer_padding [0:1][0:MAX_LAYERS-1];
  logic [31:0] cached_layer_postprocess [0:1][0:MAX_LAYERS-1];
  logic [31:0] cached_layer_tile_hints [0:1][0:MAX_LAYERS-1];

  logic [31:0] cached_tensor_header [0:1][0:MAX_TENSORS-1];
  logic [31:0] cached_tensor_identity [0:1][0:MAX_TENSORS-1];
  logic [63:0] cached_tensor_ddr_offset [0:1][0:MAX_TENSORS-1];
  logic [31:0] cached_tensor_allocation_size [0:1][0:MAX_TENSORS-1];
  logic [31:0] cached_tensor_geometry [0:1][0:MAX_TENSORS-1];
  logic [31:0] cached_tensor_channels [0:1][0:MAX_TENSORS-1];
  logic [31:0] cached_tensor_row_stride [0:1][0:MAX_TENSORS-1];
  logic [31:0] cached_tensor_pixel_stride [0:1][0:MAX_TENSORS-1];
  logic [31:0] cached_tensor_channel_stride [0:1][0:MAX_TENSORS-1];

  logic header_committed;
  logic [15:0] layer_committed_count;
  logic [15:0] tensor_committed_count;
  logic [15:0] quant_committed_count;
  logic layer_header_valid;
  logic layer_id_valid;
  logic tensor_header_valid;
  logic tensor_id_valid;
  logic quant_header_valid;
  logic quant_id_valid;

  logic metadata_address_valid;
  logic metadata_write_q;
  logic [1:0] metadata_write_kind_q;
  logic [31:0] metadata_write_data_q;
  logic validation_ok;
  logic [7:0] validation_error;

  typedef struct packed {
    logic valid;
    logic bank;
    logic [2:0] layer_index;
    logic [15:0] tensor_count;
    logic [31:0] identity;
    logic [31:0] flags;
    logic [31:0] tensor_ids;
    logic [31:0] residual_quant;
    logic [31:0] weight_size;
    logic [31:0] bias_size;
    logic [31:0] parameter_crc32;
    logic [31:0] geometry;
    logic [31:0] padding;
    logic [31:0] postprocess;
    logic [31:0] tile_hints;
  } execution_layer_lookup_t;

  typedef struct packed {
    logic valid;
    logic [31:0] geometry;
    logic [31:0] channels;
    logic [63:0] ddr_offset;
    logic [31:0] allocation_size;
    logic [31:0] row_stride;
    logic [31:0] pixel_stride;
    logic [31:0] channel_stride;
  } execution_tensor_lookup_t;

  execution_layer_lookup_t execution_layer_lookup_q;
  execution_layer_lookup_t execution_layer_lookup_qq;
  execution_tensor_lookup_t execution_input_tensor_lookup_q [0:1];
  execution_tensor_lookup_t execution_output_tensor_lookup_q [0:1];

  always_ff @(posedge clk or negedge resetn) begin
    int unsigned layer_slot;
    if (!resetn) begin
      execution_layer_lookup_q <= '0;
    end else begin
      execution_layer_lookup_q <= '0;
      layer_slot = int'(execution_layer_index);
      if (active_valid &&
          (layer_slot < MAX_LAYERS) &&
          (layer_slot < int'(cached_counts0[active_bank][15:0]))) begin
        execution_layer_lookup_q.valid <= 1'b1;
        execution_layer_lookup_q.bank <= active_bank;
        execution_layer_lookup_q.layer_index <= execution_layer_index;
        execution_layer_lookup_q.tensor_count <=
          cached_counts0[active_bank][31:16];
        execution_layer_lookup_q.identity <=
          cached_layer_identity[active_bank][layer_slot];
        execution_layer_lookup_q.flags <=
          cached_layer_flags[active_bank][layer_slot];
        execution_layer_lookup_q.tensor_ids <=
          cached_layer_tensor_ids[active_bank][layer_slot];
        execution_layer_lookup_q.residual_quant <=
          cached_layer_residual_quant[active_bank][layer_slot];
        execution_layer_lookup_q.weight_size <=
          cached_layer_weight_size[active_bank][layer_slot];
        execution_layer_lookup_q.bias_size <=
          cached_layer_bias_size[active_bank][layer_slot];
        execution_layer_lookup_q.parameter_crc32 <=
          cached_layer_parameter_crc32[active_bank][layer_slot];
        execution_layer_lookup_q.geometry <=
          cached_layer_geometry[active_bank][layer_slot];
        execution_layer_lookup_q.padding <=
          cached_layer_padding[active_bank][layer_slot];
        execution_layer_lookup_q.postprocess <=
          cached_layer_postprocess[active_bank][layer_slot];
        execution_layer_lookup_q.tile_hints <=
          cached_layer_tile_hints[active_bank][layer_slot];
      end
    end
  end

  always_ff @(posedge clk or negedge resetn) begin
    int unsigned input_slot;
    int unsigned output_slot;
    if (!resetn) begin
      execution_layer_lookup_qq <= '0;
      for (int bank = 0; bank < 2; bank++) begin
        execution_input_tensor_lookup_q[bank] <= '0;
        execution_output_tensor_lookup_q[bank] <= '0;
      end
    end else begin
      execution_layer_lookup_qq <= execution_layer_lookup_q;
      input_slot = int'(execution_layer_lookup_q.tensor_ids[15:0]);
      output_slot = int'(execution_layer_lookup_q.tensor_ids[31:16]);
      for (int bank = 0; bank < 2; bank++) begin
        execution_input_tensor_lookup_q[bank] <= '0;
        execution_output_tensor_lookup_q[bank] <= '0;
        if (execution_layer_lookup_q.valid &&
            (input_slot < MAX_TENSORS) &&
            (output_slot < MAX_TENSORS) &&
            (input_slot < int'(execution_layer_lookup_q.tensor_count)) &&
            (output_slot < int'(execution_layer_lookup_q.tensor_count))) begin
          execution_input_tensor_lookup_q[bank].valid <= 1'b1;
          execution_input_tensor_lookup_q[bank].geometry <=
            cached_tensor_geometry[bank][input_slot];
          execution_input_tensor_lookup_q[bank].channels <=
            cached_tensor_channels[bank][input_slot];
          execution_input_tensor_lookup_q[bank].ddr_offset <=
            cached_tensor_ddr_offset[bank][input_slot];
          execution_input_tensor_lookup_q[bank].allocation_size <=
            cached_tensor_allocation_size[bank][input_slot];
          execution_input_tensor_lookup_q[bank].row_stride <=
            cached_tensor_row_stride[bank][input_slot];
          execution_input_tensor_lookup_q[bank].pixel_stride <=
            cached_tensor_pixel_stride[bank][input_slot];
          execution_input_tensor_lookup_q[bank].channel_stride <=
            cached_tensor_channel_stride[bank][input_slot];
          execution_output_tensor_lookup_q[bank].valid <= 1'b1;
          execution_output_tensor_lookup_q[bank].geometry <=
            cached_tensor_geometry[bank][output_slot];
          execution_output_tensor_lookup_q[bank].channels <=
            cached_tensor_channels[bank][output_slot];
          execution_output_tensor_lookup_q[bank].ddr_offset <=
            cached_tensor_ddr_offset[bank][output_slot];
          execution_output_tensor_lookup_q[bank].allocation_size <=
            cached_tensor_allocation_size[bank][output_slot];
          execution_output_tensor_lookup_q[bank].row_stride <=
            cached_tensor_row_stride[bank][output_slot];
          execution_output_tensor_lookup_q[bank].pixel_stride <=
            cached_tensor_pixel_stride[bank][output_slot];
          execution_output_tensor_lookup_q[bank].channel_stride <=
            cached_tensor_channel_stride[bank][output_slot];
        end
      end
    end
  end

  always_ff @(posedge clk or negedge resetn) begin
    if (!resetn) begin
      execution_descriptor_valid <= 1'b0;
      execution_layer_id <= 16'd0;
      execution_opcode <= 16'd0;
      execution_last_layer <= 1'b0;
      execution_bias_enable <= 1'b0;
      execution_input_tensor_id <= 16'd0;
      execution_output_tensor_id <= 16'd0;
      execution_residual_tensor_id <= NO_TENSOR_ID;
      execution_quantization_id <= 16'd0;
      execution_weight_size <= 32'd0;
      execution_bias_size <= 32'd0;
      execution_parameter_crc32 <= 32'd0;
      execution_input_width <= 16'd0;
      execution_input_height <= 16'd0;
      execution_input_channels <= 16'd0;
      execution_output_width <= 16'd0;
      execution_output_height <= 16'd0;
      execution_output_channels <= 16'd0;
      execution_kernel_height <= 8'd0;
      execution_kernel_width <= 8'd0;
      execution_stride_y <= 8'd0;
      execution_stride_x <= 8'd0;
      execution_padding_top <= 8'd0;
      execution_padding_bottom <= 8'd0;
      execution_padding_left <= 8'd0;
      execution_padding_right <= 8'd0;
      execution_dilation_y <= 8'd0;
      execution_dilation_x <= 8'd0;
      execution_activation <= 8'd0;
      execution_residual_mode <= 8'd0;
      execution_tile_height_hint <= 16'd0;
      execution_tile_width_hint <= 16'd0;
      execution_input_ddr_offset <= 64'd0;
      execution_input_allocation_size <= 32'd0;
      execution_input_row_stride <= 32'd0;
      execution_input_pixel_stride <= 32'd0;
      execution_input_channel_stride <= 32'd0;
      execution_output_ddr_offset <= 64'd0;
      execution_output_allocation_size <= 32'd0;
      execution_output_row_stride <= 32'd0;
      execution_output_pixel_stride <= 32'd0;
      execution_output_channel_stride <= 32'd0;
    end else begin
      execution_descriptor_valid <= 1'b0;
      execution_layer_id <= execution_layer_lookup_qq.identity[15:0];
      execution_opcode <= execution_layer_lookup_qq.identity[31:16];
      execution_last_layer <=
        (execution_layer_lookup_qq.flags & LAYER_FLAG_LAST_LAYER) != 0;
      execution_bias_enable <=
        (execution_layer_lookup_qq.flags & LAYER_FLAG_BIAS_ENABLE) != 0;
      execution_input_tensor_id <= execution_layer_lookup_qq.tensor_ids[15:0];
      execution_output_tensor_id <= execution_layer_lookup_qq.tensor_ids[31:16];
      execution_residual_tensor_id <=
        execution_layer_lookup_qq.residual_quant[15:0];
      execution_quantization_id <=
        execution_layer_lookup_qq.residual_quant[31:16];
      execution_weight_size <= execution_layer_lookup_qq.weight_size;
      execution_bias_size <= execution_layer_lookup_qq.bias_size;
      execution_parameter_crc32 <= execution_layer_lookup_qq.parameter_crc32;
      execution_kernel_height <= execution_layer_lookup_qq.geometry[7:0];
      execution_kernel_width <= execution_layer_lookup_qq.geometry[15:8];
      execution_stride_y <= execution_layer_lookup_qq.geometry[23:16];
      execution_stride_x <= execution_layer_lookup_qq.geometry[31:24];
      execution_padding_top <= execution_layer_lookup_qq.padding[7:0];
      execution_padding_bottom <= execution_layer_lookup_qq.padding[15:8];
      execution_padding_left <= execution_layer_lookup_qq.padding[23:16];
      execution_padding_right <= execution_layer_lookup_qq.padding[31:24];
      execution_dilation_y <= execution_layer_lookup_qq.postprocess[7:0];
      execution_dilation_x <= execution_layer_lookup_qq.postprocess[15:8];
      execution_activation <= execution_layer_lookup_qq.postprocess[23:16];
      execution_residual_mode <= execution_layer_lookup_qq.postprocess[31:24];
      execution_tile_height_hint <= execution_layer_lookup_qq.tile_hints[15:0];
      execution_tile_width_hint <= execution_layer_lookup_qq.tile_hints[31:16];
      execution_input_width <= 16'd0;
      execution_input_height <= 16'd0;
      execution_input_channels <= 16'd0;
      execution_output_width <= 16'd0;
      execution_output_height <= 16'd0;
      execution_output_channels <= 16'd0;
      execution_input_ddr_offset <= 64'd0;
      execution_input_allocation_size <= 32'd0;
      execution_input_row_stride <= 32'd0;
      execution_input_pixel_stride <= 32'd0;
      execution_input_channel_stride <= 32'd0;
      execution_output_ddr_offset <= 64'd0;
      execution_output_allocation_size <= 32'd0;
      execution_output_row_stride <= 32'd0;
      execution_output_pixel_stride <= 32'd0;
      execution_output_channel_stride <= 32'd0;

      if (execution_layer_lookup_qq.valid &&
          active_valid &&
          (execution_layer_lookup_qq.bank == active_bank) &&
          (execution_layer_lookup_qq.layer_index == execution_layer_index) &&
          execution_input_tensor_lookup_q[execution_layer_lookup_qq.bank].valid &&
          execution_output_tensor_lookup_q[execution_layer_lookup_qq.bank].valid) begin
        execution_input_width <=
          execution_input_tensor_lookup_q[
            execution_layer_lookup_qq.bank].geometry[15:0];
        execution_input_height <=
          execution_input_tensor_lookup_q[
            execution_layer_lookup_qq.bank].geometry[31:16];
        execution_input_channels <=
          execution_input_tensor_lookup_q[
            execution_layer_lookup_qq.bank].channels[15:0];
        execution_output_width <=
          execution_output_tensor_lookup_q[
            execution_layer_lookup_qq.bank].geometry[15:0];
        execution_output_height <=
          execution_output_tensor_lookup_q[
            execution_layer_lookup_qq.bank].geometry[31:16];
        execution_output_channels <=
          execution_output_tensor_lookup_q[
            execution_layer_lookup_qq.bank].channels[15:0];
        execution_input_ddr_offset <=
          execution_input_tensor_lookup_q[
            execution_layer_lookup_qq.bank].ddr_offset;
        execution_input_allocation_size <=
          execution_input_tensor_lookup_q[
            execution_layer_lookup_qq.bank].allocation_size;
        execution_input_row_stride <=
          execution_input_tensor_lookup_q[
            execution_layer_lookup_qq.bank].row_stride;
        execution_input_pixel_stride <=
          execution_input_tensor_lookup_q[
            execution_layer_lookup_qq.bank].pixel_stride;
        execution_input_channel_stride <=
          execution_input_tensor_lookup_q[
            execution_layer_lookup_qq.bank].channel_stride;
        execution_output_ddr_offset <=
          execution_output_tensor_lookup_q[
            execution_layer_lookup_qq.bank].ddr_offset;
        execution_output_allocation_size <=
          execution_output_tensor_lookup_q[
            execution_layer_lookup_qq.bank].allocation_size;
        execution_output_row_stride <=
          execution_output_tensor_lookup_q[
            execution_layer_lookup_qq.bank].row_stride;
        execution_output_pixel_stride <=
          execution_output_tensor_lookup_q[
            execution_layer_lookup_qq.bank].pixel_stride;
        execution_output_channel_stride <=
          execution_output_tensor_lookup_q[
            execution_layer_lookup_qq.bank].channel_stride;
        execution_descriptor_valid <= 1'b1;
      end
    end
  end

  always_comb begin
    header_address_value = $clog2(HEADER_DEPTH)'(
      (int'(staging_bank) * HEADER_WORDS) + int'(metadata_word_index));
    layer_address_value = $clog2(LAYER_DEPTH)'(
      (int'(staging_bank) * MAX_LAYERS * LAYER_WORDS) +
      (int'(metadata_record_index) * LAYER_WORDS) + int'(metadata_word_index));
    tensor_address_value = $clog2(TENSOR_DEPTH)'(
      (int'(staging_bank) * MAX_TENSORS * TENSOR_WORDS) +
      (int'(metadata_record_index) * TENSOR_WORDS) + int'(metadata_word_index));
    quant_address_value = $clog2(QUANT_DEPTH)'(
      (int'(staging_bank) * MAX_QUANTIZATIONS * QUANT_WORDS) +
      (int'(metadata_record_index) * QUANT_WORDS) + int'(metadata_word_index));
  end

  always_ff @(posedge clk or negedge resetn) begin
    if (!resetn) begin
      header_read_address_q <= '0;
      layer_read_address_q <= '0;
      tensor_read_address_q <= '0;
      quant_read_address_q <= '0;
      metadata_read_kind_q <= '0;
      metadata_read_kind_qq <= '0;
      metadata_read_valid_q <= 1'b0;
      metadata_read_valid_qq <= 1'b0;
      metadata_write_q <= 1'b0;
      metadata_write_kind_q <= '0;
      metadata_write_data_q <= '0;
    end else begin
      header_read_address_q <= header_address_value;
      layer_read_address_q <= layer_address_value;
      tensor_read_address_q <= tensor_address_value;
      quant_read_address_q <= quant_address_value;
      metadata_read_kind_q <= metadata_kind;
      metadata_read_kind_qq <= metadata_read_kind_q;
      metadata_read_valid_q <= metadata_address_valid;
      metadata_read_valid_qq <= metadata_read_valid_q;
      metadata_write_q <= metadata_write && metadata_address_valid &&
                          (staging_state == MODEL_STAGING_LOADING);
      metadata_write_kind_q <= metadata_kind;
      metadata_write_data_q <= metadata_write_data;
    end
  end

  cnn_metadata_word_ram #(
    .DEPTH(HEADER_DEPTH)
  ) u_header_memory (
    .clk(clk),
    .write_enable(metadata_write_q &&
                  (metadata_write_kind_q == METADATA_HEADER)),
    .write_address(header_read_address_q),
    .write_data(metadata_write_data_q),
    .read_address(header_read_address_q),
    .read_data(header_read_data)
  );

  cnn_metadata_word_ram #(
    .DEPTH(LAYER_DEPTH)
  ) u_layer_memory (
    .clk(clk),
    .write_enable(metadata_write_q &&
                  (metadata_write_kind_q == METADATA_LAYER)),
    .write_address(layer_read_address_q),
    .write_data(metadata_write_data_q),
    .read_address(layer_read_address_q),
    .read_data(layer_read_data)
  );

  cnn_metadata_word_ram #(
    .DEPTH(TENSOR_DEPTH)
  ) u_tensor_memory (
    .clk(clk),
    .write_enable(metadata_write_q &&
                  (metadata_write_kind_q == METADATA_TENSOR)),
    .write_address(tensor_read_address_q),
    .write_data(metadata_write_data_q),
    .read_address(tensor_read_address_q),
    .read_data(tensor_read_data)
  );

  cnn_metadata_word_ram #(
    .DEPTH(QUANT_DEPTH)
  ) u_quant_memory (
    .clk(clk),
    .write_enable(metadata_write_q &&
                  (metadata_write_kind_q == METADATA_QUANTIZATION)),
    .write_address(quant_read_address_q),
    .write_data(metadata_write_data_q),
    .read_address(quant_read_address_q),
    .read_data(quant_read_data)
  );

  always_comb begin
    metadata_address_valid = 1'b0;
    unique case (metadata_kind)
      METADATA_HEADER: begin
        metadata_address_valid =
          (metadata_record_index == 0) && (int'(metadata_word_index) < HEADER_WORDS);
      end
      METADATA_LAYER: begin
        metadata_address_valid =
          (int'(metadata_record_index) < MAX_LAYERS) &&
          (int'(metadata_word_index) < LAYER_WORDS);
      end
      METADATA_TENSOR: begin
        metadata_address_valid =
          (int'(metadata_record_index) < MAX_TENSORS) &&
          (int'(metadata_word_index) < TENSOR_WORDS);
      end
      METADATA_QUANTIZATION: begin
        metadata_address_valid =
          (int'(metadata_record_index) < MAX_QUANTIZATIONS) &&
          (int'(metadata_word_index) < QUANT_WORDS);
      end
      default: metadata_address_valid = 1'b0;
    endcase
  end

  always_comb begin
    metadata_read_data = 32'd0;
    if (metadata_read_valid_qq) begin
      unique case (metadata_read_kind_qq)
        METADATA_HEADER: begin
          metadata_read_data = header_read_data;
        end
        METADATA_LAYER: begin
          metadata_read_data = layer_read_data;
        end
        METADATA_TENSOR: begin
          metadata_read_data = tensor_read_data;
        end
        METADATA_QUANTIZATION: begin
          metadata_read_data = quant_read_data;
        end
        default: metadata_read_data = 32'd0;
      endcase
    end
  end

  always_comb begin
    staging_model_id = cached_model_id[staging_bank];
    staging_generation_id = cached_generation_id[staging_bank];
    staging_layer_count = cached_counts0[staging_bank][15:0];
    staging_tensor_count = cached_counts0[staging_bank][31:16];
    staging_quantization_count = cached_counts1[staging_bank][15:0];

    if (active_valid) begin
      active_model_id = cached_model_id[active_bank];
      active_generation_id = cached_generation_id[active_bank];
      active_layer_count = cached_counts0[active_bank][15:0];
    end else begin
      active_model_id = 32'd0;
      active_generation_id = 32'd0;
      active_layer_count = 16'd0;
    end
  end

  always_comb begin
    validation_ok = 1'b1;
    validation_error = MODEL_LIFECYCLE_OK;

    if (!header_committed) begin
      validation_ok = 1'b0;
      validation_error = MODEL_LIFECYCLE_INCOMPLETE;
    end else if ((cached_magic[staging_bank] != MODEL_MAGIC) ||
                 (cached_version_size[staging_bank] !=
                  {16'(MODEL_HEADER_BYTES), 16'(ABI_VERSION)})) begin
      validation_ok = 1'b0;
      validation_error = MODEL_LIFECYCLE_BAD_HEADER;
    end else if ((staging_layer_count == 0) ||
                 (staging_layer_count > 16'(MAX_LAYERS)) ||
                 (staging_tensor_count < 2) ||
                 (staging_tensor_count > 16'(MAX_TENSORS)) ||
                 (staging_quantization_count == 0) ||
                 (staging_quantization_count > 16'(MAX_QUANTIZATIONS))) begin
      validation_ok = 1'b0;
      validation_error = MODEL_LIFECYCLE_LIMIT;
    end

    if (validation_ok &&
        ((layer_committed_count < staging_layer_count) ||
         (tensor_committed_count < staging_tensor_count) ||
         (quant_committed_count < staging_quantization_count))) begin
      validation_ok = 1'b0;
      validation_error = MODEL_LIFECYCLE_INCOMPLETE;
    end
  end

  always_ff @(posedge clk or negedge resetn) begin
    logic next_staging_bank;
    if (!resetn) begin
      staging_state <= MODEL_STAGING_UNLOADED;
      staging_bank <= 1'b1;
      active_valid <= 1'b0;
      active_bank <= 1'b0;
      lifecycle_error <= MODEL_LIFECYCLE_OK;
      header_committed <= 1'b0;
      layer_committed_count <= 16'd0;
      tensor_committed_count <= 16'd0;
      quant_committed_count <= 16'd0;
      layer_header_valid <= 1'b0;
      layer_id_valid <= 1'b0;
      tensor_header_valid <= 1'b0;
      tensor_id_valid <= 1'b0;
      quant_header_valid <= 1'b0;
      quant_id_valid <= 1'b0;
      cached_magic[0] <= 32'd0;
      cached_magic[1] <= 32'd0;
      cached_version_size[0] <= 32'd0;
      cached_version_size[1] <= 32'd0;
      cached_model_id[0] <= 32'd0;
      cached_model_id[1] <= 32'd0;
      cached_generation_id[0] <= 32'd0;
      cached_generation_id[1] <= 32'd0;
      cached_counts0[0] <= 32'd0;
      cached_counts0[1] <= 32'd0;
      cached_counts1[0] <= 32'd0;
      cached_counts1[1] <= 32'd0;
    end else begin
      if (clear_error) begin
        lifecycle_error <= MODEL_LIFECYCLE_OK;
      end

      if (begin_load) begin
        next_staging_bank = ~active_bank;
        if (staging_state == MODEL_STAGING_LOADING) begin
          lifecycle_error <= MODEL_LIFECYCLE_BAD_STATE;
        end else begin
          staging_bank <= next_staging_bank;
          staging_state <= MODEL_STAGING_LOADING;
          header_committed <= 1'b0;
          layer_committed_count <= 16'd0;
          tensor_committed_count <= 16'd0;
          quant_committed_count <= 16'd0;
          layer_header_valid <= 1'b0;
          layer_id_valid <= 1'b0;
          tensor_header_valid <= 1'b0;
          tensor_id_valid <= 1'b0;
          quant_header_valid <= 1'b0;
          quant_id_valid <= 1'b0;
          lifecycle_error <= MODEL_LIFECYCLE_OK;
        end
      end

      if (metadata_write) begin
        if (staging_state != MODEL_STAGING_LOADING) begin
          lifecycle_error <= MODEL_LIFECYCLE_BAD_STATE;
        end else if (!metadata_address_valid) begin
          lifecycle_error <= MODEL_LIFECYCLE_BAD_ADDRESS;
        end else begin
          unique case (metadata_kind)
            METADATA_HEADER: begin
              unique case (metadata_word_index)
                0: cached_magic[staging_bank] <= metadata_write_data;
                1: cached_version_size[staging_bank] <= metadata_write_data;
                4: cached_model_id[staging_bank] <= metadata_write_data;
                5: cached_generation_id[staging_bank] <= metadata_write_data;
                6: cached_counts0[staging_bank] <= metadata_write_data;
                7: cached_counts1[staging_bank] <= metadata_write_data;
                default: begin
                end
              endcase
            end
            METADATA_LAYER: begin
              unique case (metadata_word_index)
                0: cached_layer_header[staging_bank][LAYER_INDEX_W'(metadata_record_index)] <=
                     metadata_write_data;
                1: cached_layer_identity[staging_bank][LAYER_INDEX_W'(metadata_record_index)] <=
                     metadata_write_data;
                2: cached_layer_flags[staging_bank][LAYER_INDEX_W'(metadata_record_index)] <=
                     metadata_write_data;
                3: cached_layer_tensor_ids[staging_bank][LAYER_INDEX_W'(metadata_record_index)] <=
                     metadata_write_data;
                4: cached_layer_residual_quant[staging_bank][LAYER_INDEX_W'(metadata_record_index)] <=
                     metadata_write_data;
                6: cached_layer_weight_size[staging_bank][LAYER_INDEX_W'(metadata_record_index)] <=
                     metadata_write_data;
                8: cached_layer_bias_size[staging_bank][LAYER_INDEX_W'(metadata_record_index)] <=
                     metadata_write_data;
                9: cached_layer_parameter_crc32[staging_bank][LAYER_INDEX_W'(metadata_record_index)] <=
                     metadata_write_data;
                10: cached_layer_geometry[staging_bank][LAYER_INDEX_W'(metadata_record_index)] <=
                      metadata_write_data;
                11: cached_layer_padding[staging_bank][LAYER_INDEX_W'(metadata_record_index)] <=
                      metadata_write_data;
                12: cached_layer_postprocess[staging_bank][LAYER_INDEX_W'(metadata_record_index)] <=
                      metadata_write_data;
                13: cached_layer_tile_hints[staging_bank][LAYER_INDEX_W'(metadata_record_index)] <=
                      metadata_write_data;
                default: begin
                end
              endcase

              if ((metadata_record_index == layer_committed_count[5:0]) &&
                  (metadata_word_index == 0)) begin
                layer_header_valid <=
                  metadata_write_data ==
                  {16'(LAYER_DESCRIPTOR_BYTES), 16'(ABI_VERSION)};
              end
              if ((metadata_record_index == layer_committed_count[5:0]) &&
                  (metadata_word_index == 1)) begin
                layer_id_valid <=
                  metadata_write_data[15:0] == 16'(metadata_record_index);
              end
            end
            METADATA_TENSOR: begin
              unique case (metadata_word_index)
                0: cached_tensor_header[staging_bank][TENSOR_INDEX_W'(metadata_record_index)] <=
                     metadata_write_data;
                1: cached_tensor_identity[staging_bank][TENSOR_INDEX_W'(metadata_record_index)] <=
                     metadata_write_data;
                2: cached_tensor_ddr_offset[staging_bank][TENSOR_INDEX_W'(metadata_record_index)][31:0] <=
                     metadata_write_data;
                3: cached_tensor_ddr_offset[staging_bank][TENSOR_INDEX_W'(metadata_record_index)][63:32] <=
                     metadata_write_data;
                4: cached_tensor_allocation_size[staging_bank][TENSOR_INDEX_W'(metadata_record_index)] <=
                     metadata_write_data;
                5: cached_tensor_geometry[staging_bank][TENSOR_INDEX_W'(metadata_record_index)] <=
                     metadata_write_data;
                6: cached_tensor_channels[staging_bank][TENSOR_INDEX_W'(metadata_record_index)] <=
                     metadata_write_data;
                9: cached_tensor_row_stride[staging_bank][TENSOR_INDEX_W'(metadata_record_index)] <=
                     metadata_write_data;
                10: cached_tensor_pixel_stride[staging_bank][TENSOR_INDEX_W'(metadata_record_index)] <=
                      metadata_write_data;
                11: cached_tensor_channel_stride[staging_bank][TENSOR_INDEX_W'(metadata_record_index)] <=
                      metadata_write_data;
                default: begin
                end
              endcase

              if ((metadata_record_index == tensor_committed_count[5:0]) &&
                  (metadata_word_index == 0)) begin
                tensor_header_valid <=
                  metadata_write_data ==
                  {16'(TENSOR_DESCRIPTOR_BYTES), 16'(ABI_VERSION)};
              end
              if ((metadata_record_index == tensor_committed_count[5:0]) &&
                  (metadata_word_index == 1)) begin
                tensor_id_valid <=
                  metadata_write_data[15:0] == 16'(metadata_record_index);
              end
            end
            METADATA_QUANTIZATION: begin
              if ((metadata_record_index == quant_committed_count[5:0]) &&
                  (metadata_word_index == 0)) begin
                quant_header_valid <=
                  metadata_write_data ==
                  {16'(QUANT_DESCRIPTOR_BYTES), 16'(ABI_VERSION)};
              end
              if ((metadata_record_index == quant_committed_count[5:0]) &&
                  (metadata_word_index == 1)) begin
                quant_id_valid <=
                  metadata_write_data[15:0] == 16'(metadata_record_index);
              end
            end
            default: lifecycle_error <= MODEL_LIFECYCLE_BAD_ADDRESS;
          endcase
        end
      end

      if (metadata_commit) begin
        if (staging_state != MODEL_STAGING_LOADING) begin
          lifecycle_error <= MODEL_LIFECYCLE_BAD_STATE;
        end else if (!metadata_address_valid) begin
          lifecycle_error <= MODEL_LIFECYCLE_BAD_ADDRESS;
        end else begin
          unique case (metadata_kind)
            METADATA_HEADER: header_committed <= 1'b1;
            METADATA_LAYER: begin
              if ((metadata_record_index == layer_committed_count[5:0]) &&
                  layer_header_valid && layer_id_valid) begin
                layer_committed_count <= layer_committed_count + 16'd1;
                layer_header_valid <= 1'b0;
                layer_id_valid <= 1'b0;
              end else begin
                lifecycle_error <= MODEL_LIFECYCLE_BAD_DESCRIPTOR;
              end
            end
            METADATA_TENSOR: begin
              if ((metadata_record_index == tensor_committed_count[5:0]) &&
                  tensor_header_valid && tensor_id_valid) begin
                tensor_committed_count <= tensor_committed_count + 16'd1;
                tensor_header_valid <= 1'b0;
                tensor_id_valid <= 1'b0;
              end else begin
                lifecycle_error <= MODEL_LIFECYCLE_BAD_DESCRIPTOR;
              end
            end
            METADATA_QUANTIZATION: begin
              if ((metadata_record_index == quant_committed_count[5:0]) &&
                  quant_header_valid && quant_id_valid) begin
                quant_committed_count <= quant_committed_count + 16'd1;
                quant_header_valid <= 1'b0;
                quant_id_valid <= 1'b0;
              end else begin
                lifecycle_error <= MODEL_LIFECYCLE_BAD_DESCRIPTOR;
              end
            end
            default: lifecycle_error <= MODEL_LIFECYCLE_BAD_ADDRESS;
          endcase
        end
      end

      if (finish_load) begin
        if (staging_state != MODEL_STAGING_LOADING) begin
          lifecycle_error <= MODEL_LIFECYCLE_BAD_STATE;
        end else begin
          staging_state <= MODEL_STAGING_LOADED_UNVALIDATED;
        end
      end

      if (validate_model) begin
        if (staging_state != MODEL_STAGING_LOADED_UNVALIDATED) begin
          lifecycle_error <= MODEL_LIFECYCLE_BAD_STATE;
        end else if (lifecycle_error != MODEL_LIFECYCLE_OK) begin
          lifecycle_error <= lifecycle_error;
        end else if (!validation_ok) begin
          lifecycle_error <= validation_error;
        end else begin
          staging_state <= MODEL_STAGING_VALIDATED;
          lifecycle_error <= MODEL_LIFECYCLE_OK;
        end
      end

      if (activate_model) begin
        if (job_busy) begin
          lifecycle_error <= MODEL_LIFECYCLE_BUSY;
        end else if (staging_state != MODEL_STAGING_VALIDATED) begin
          lifecycle_error <= MODEL_LIFECYCLE_BAD_STATE;
        end else begin
          active_bank <= staging_bank;
          active_valid <= 1'b1;
          staging_state <= MODEL_STAGING_UNLOADED;
          lifecycle_error <= MODEL_LIFECYCLE_OK;
        end
      end

      if (retire_active) begin
        if (job_busy) begin
          lifecycle_error <= MODEL_LIFECYCLE_BUSY;
        end else if (!active_valid) begin
          lifecycle_error <= MODEL_LIFECYCLE_BAD_STATE;
        end else begin
          active_valid <= 1'b0;
          lifecycle_error <= MODEL_LIFECYCLE_OK;
        end
      end
    end
  end
endmodule
