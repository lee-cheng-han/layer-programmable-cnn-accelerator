`timescale 1ns/1ps

module cnn_programmable_runtime_top #(
  parameter int PC = 2,
  parameter int PK = 4,
  parameter int MAX_CIN = 16,
  parameter int MAX_COUT = 16,
  parameter int MAX_LAYERS = 8,
  parameter int MAX_TENSORS = 32,
  parameter int MAX_QUANTIZATIONS = 32,
  parameter int MAX_TILE_WIDTH = 16,
  parameter int MAX_TILE_HEIGHT = 16,
  parameter int MAX_PAYLOAD_BYTES = 4 * 1024 * 1024,
  parameter int DATA_W = 8,
  parameter int ACC_W = 32,
  parameter int COUNT_W = 8
)(
  input  logic clk,
  input  logic rst_n,
  input  logic clear,
  input  logic start,
  input  logic [31:0] job_id,

  input  logic begin_model_load,
  input  logic finish_model_load,
  input  logic validate_model,
  input  logic activate_model,
  input  logic retire_active_model,
  input  logic clear_model_error,
  input  logic metadata_write,
  input  logic metadata_commit,
  input  logic [1:0] metadata_kind,
  input  logic [5:0] metadata_record_index,
  input  logic [5:0] metadata_word_index,
  input  logic [31:0] metadata_write_data,
  output logic [31:0] metadata_read_data,
  input  logic [2:0] parameter_layer_select,

  input  logic [31:0] s_axis_tdata,
  input  logic [3:0] s_axis_tkeep,
  input  logic s_axis_tvalid,
  output logic s_axis_tready,
  input  logic s_axis_tlast,
  output logic [31:0] m_axis_tdata,
  output logic [3:0] m_axis_tkeep,
  output logic m_axis_tvalid,
  input  logic m_axis_tready,
  output logic m_axis_tlast,

  output logic [2:0] staging_state,
  output logic model_active_valid,
  output logic [31:0] active_model_id,
  output logic [31:0] active_generation_id,
  output logic [15:0] active_layer_count,
  output logic [7:0] model_lifecycle_error,
  output logic [2:0] active_layer,
  output logic [15:0] active_input_tensor_id,
  output logic [15:0] active_output_tensor_id,
  output logic [63:0] active_input_ddr_offset,
  output logic [63:0] active_output_ddr_offset,
  output logic [15:0] current_tile_x,
  output logic [15:0] current_tile_y,
  output logic [31:0] completed_layer_count,
  output logic [31:0] completed_tile_count,
  output logic [31:0] saturation_event_count,
  output logic layer_done,
  output logic busy,
  output logic done,
  output logic error,
  output logic [7:0] error_code,
  output logic [2:0] error_layer,
  output logic [31:0] packet_error_count,
  output logic [1:0] parameter_bank_valid
);
  logic [2:0] execution_layer_index;
  logic [2:0] controller_descriptor_index;
  logic descriptor_valid;
  logic [15:0] descriptor_layer_id;
  logic [15:0] descriptor_opcode;
  logic descriptor_last_layer;
  logic descriptor_bias_enable;
  logic [15:0] descriptor_input_tensor_id;
  logic [15:0] descriptor_output_tensor_id;
  logic [15:0] descriptor_residual_tensor_id;
  logic [15:0] descriptor_quantization_id;
  logic [31:0] descriptor_weight_size;
  logic [31:0] descriptor_bias_size;
  logic [31:0] descriptor_parameter_crc32;
  logic [15:0] descriptor_input_width;
  logic [15:0] descriptor_input_height;
  logic [15:0] descriptor_input_channels;
  logic [15:0] descriptor_output_width;
  logic [15:0] descriptor_output_height;
  logic [15:0] descriptor_output_channels;
  logic [7:0] descriptor_kernel_height;
  logic [7:0] descriptor_kernel_width;
  logic [7:0] descriptor_stride_y;
  logic [7:0] descriptor_stride_x;
  logic [7:0] descriptor_padding_top;
  logic [7:0] descriptor_padding_bottom;
  logic [7:0] descriptor_padding_left;
  logic [7:0] descriptor_padding_right;
  logic [7:0] descriptor_dilation_y;
  logic [7:0] descriptor_dilation_x;
  logic [7:0] descriptor_activation;
  logic [7:0] descriptor_residual_mode;
  logic [15:0] descriptor_tile_height_hint;
  logic [15:0] descriptor_tile_width_hint;
  logic [63:0] descriptor_input_ddr_offset;
  logic [31:0] descriptor_input_allocation_size;
  logic [31:0] descriptor_input_row_stride;
  logic [31:0] descriptor_input_pixel_stride;
  logic [31:0] descriptor_input_channel_stride;
  logic [63:0] descriptor_output_ddr_offset;
  logic [31:0] descriptor_output_allocation_size;
  logic [31:0] descriptor_output_row_stride;
  logic [31:0] descriptor_output_pixel_stride;
  logic [31:0] descriptor_output_channel_stride;
  logic [15:0] descriptor_output_tensor_quantization_id;
  logic descriptor_residual_tensor_valid;
  logic [15:0] descriptor_residual_width;
  logic [15:0] descriptor_residual_height;
  logic [15:0] descriptor_residual_channels;
  logic [15:0] descriptor_residual_quantization_id;
  logic [63:0] descriptor_residual_ddr_offset;
  logic descriptor_quantization_valid;
  logic [15:0] descriptor_quantization_channel_count;
  logic [7:0] descriptor_rounding_mode;
  logic signed [7:0] descriptor_output_zero_point;
  logic signed [31:0] descriptor_quant_multiplier [MAX_COUT];
  logic [5:0] descriptor_quant_shift [MAX_COUT];

  logic packet_start;
  logic packet_ready;
  logic packet_done;
  logic [7:0] packet_type;
  logic [31:0] packet_job_id;
  logic [15:0] packet_tensor_id;
  logic [15:0] packet_layer_id;
  logic [15:0] packet_tile_x;
  logic [15:0] packet_tile_y;
  logic [15:0] packet_tile_width;
  logic [15:0] packet_tile_height;
  logic [15:0] packet_channel_offset;
  logic [15:0] packet_channel_count;
  logic [31:0] packet_payload_length;
  logic payload_valid;
  logic payload_ready;
  logic [31:0] payload_data;
  logic [3:0] payload_keep;
  logic payload_last;
  logic parser_error_valid;
  logic [7:0] parser_error_code;

  logic parameter_load_start;
  logic parameter_load_abort;
  logic parameter_load_ready;
  logic [2:0] parameter_load_layer_id;
  logic [1:0] parameter_load_kernel_size;
  logic [7:0] parameter_load_cin;
  logic [7:0] parameter_load_cout;
  logic parameter_load_bias_enable;
  logic parameter_load_quant_enable;
  logic [4:0] parameter_load_quant_shift;
  logic [15:0] parameter_load_weight_bytes;
  logic [15:0] parameter_load_bias_bytes;
  logic [31:0] parameter_load_expected_crc32;
  logic parameter_weight_valid;
  logic parameter_weight_ready;
  logic signed [DATA_W-1:0] parameter_weight_data;
  logic parameter_bias_valid;
  logic parameter_bias_ready;
  logic signed [ACC_W-1:0] parameter_bias_data;
  logic parameter_load_done;
  logic parameter_error;
  logic [7:0] parameter_error_code;
  logic parameter_config_valid_q;
  logic [2:0] parameter_config_layer_id_q;
  logic [1:0] parameter_config_kernel_size_q;
  logic [7:0] parameter_config_cin_q;
  logic [7:0] parameter_config_cout_q;
  logic parameter_config_bias_enable_q;
  logic [15:0] parameter_config_weight_bytes_q;
  logic [15:0] parameter_config_bias_bytes_q;
  logic [31:0] parameter_config_crc32_q;

  logic activation_packet_start;
  logic activation_packet_ready;
  logic [31:0] activation_job_id;
  logic [15:0] activation_tensor_id;
  logic [15:0] activation_layer_id;
  logic [15:0] activation_tile_x;
  logic [15:0] activation_tile_y;
  logic [15:0] activation_tile_width;
  logic [15:0] activation_tile_height;
  logic [15:0] activation_channel_offset;
  logic [15:0] activation_channel_count;
  logic [31:0] activation_payload_length;
  logic activation_valid;
  logic activation_ready;
  logic [31:0] activation_data;
  logic [3:0] activation_keep;
  logic activation_last;
  logic router_error;
  logic [7:0] router_error_code;

  logic parameter_request;
  logic [2:0] parameter_layer_id;
  logic parameter_ready;
  logic parameter_release;
  logic parameter_quant_enable;
  logic [4:0] parameter_quant_shift;
  logic signed [ACC_W-1:0] parameter_bias [MAX_COUT];
  logic [COUNT_W-1:0] weight_read_k_base;
  logic [COUNT_W-1:0] weight_read_c_base;
  logic [3:0] weight_read_kernel_idx;
  logic [PK-1:0] weight_out_lane_mask;
  logic [PC-1:0] weight_in_lane_mask;
  logic signed [DATA_W-1:0] weight_mat_data [PK][PC];
  logic controller_done;
  logic controller_error;
  logic [7:0] controller_error_code;

  assign execution_layer_index =
    busy ? controller_descriptor_index : parameter_layer_select;
  assign done = controller_done;
  assign error = controller_error || router_error || parameter_error;
  assign error_code = controller_error ? controller_error_code :
                      (router_error ? {1'b1, router_error_code[6:0]} :
                       (parameter_error ? {2'b11, parameter_error_code[5:0]} :
                        parser_error_code));

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      parameter_config_valid_q <= 1'b0;
      parameter_config_layer_id_q <= '0;
      parameter_config_kernel_size_q <= '0;
      parameter_config_cin_q <= '0;
      parameter_config_cout_q <= '0;
      parameter_config_bias_enable_q <= 1'b0;
      parameter_config_weight_bytes_q <= '0;
      parameter_config_bias_bytes_q <= '0;
      parameter_config_crc32_q <= '0;
    end else begin
      parameter_config_valid_q <=
        !clear && descriptor_valid &&
        (descriptor_layer_id == 16'(parameter_layer_select));
      parameter_config_layer_id_q <= parameter_layer_select;
      parameter_config_kernel_size_q <= descriptor_kernel_width[1:0];
      parameter_config_cin_q <= descriptor_input_channels[7:0];
      parameter_config_cout_q <= descriptor_output_channels[7:0];
      parameter_config_bias_enable_q <= descriptor_bias_enable;
      parameter_config_weight_bytes_q <= descriptor_weight_size[15:0];
      parameter_config_bias_bytes_q <= descriptor_bias_size[15:0];
      parameter_config_crc32_q <= descriptor_parameter_crc32;
    end
  end

  cnn_model_metadata_store #(
    .MAX_LAYERS(MAX_LAYERS),
    .MAX_TENSORS(MAX_TENSORS),
    .MAX_QUANTIZATIONS(MAX_QUANTIZATIONS),
    .MAX_CHANNELS(MAX_COUT)
  ) u_metadata (
    .clk(clk),
    .resetn(rst_n),
    .begin_load(begin_model_load),
    .finish_load(finish_model_load),
    .validate_model(validate_model),
    .activate_model(activate_model),
    .retire_active(retire_active_model),
    .clear_error(clear_model_error || clear),
    .job_busy(busy),
    .metadata_write(metadata_write),
    .metadata_commit(metadata_commit),
    .metadata_kind(metadata_kind),
    .metadata_record_index(metadata_record_index),
    .metadata_word_index(metadata_word_index),
    .metadata_write_data(metadata_write_data),
    .metadata_read_data(metadata_read_data),
    .execution_layer_index(execution_layer_index),
    .execution_descriptor_valid(descriptor_valid),
    .execution_layer_id(descriptor_layer_id),
    .execution_opcode(descriptor_opcode),
    .execution_last_layer(descriptor_last_layer),
    .execution_bias_enable(descriptor_bias_enable),
    .execution_input_tensor_id(descriptor_input_tensor_id),
    .execution_output_tensor_id(descriptor_output_tensor_id),
    .execution_residual_tensor_id(descriptor_residual_tensor_id),
    .execution_quantization_id(descriptor_quantization_id),
    .execution_weight_size(descriptor_weight_size),
    .execution_bias_size(descriptor_bias_size),
    .execution_parameter_crc32(descriptor_parameter_crc32),
    .execution_input_width(descriptor_input_width),
    .execution_input_height(descriptor_input_height),
    .execution_input_channels(descriptor_input_channels),
    .execution_output_width(descriptor_output_width),
    .execution_output_height(descriptor_output_height),
    .execution_output_channels(descriptor_output_channels),
    .execution_kernel_height(descriptor_kernel_height),
    .execution_kernel_width(descriptor_kernel_width),
    .execution_stride_y(descriptor_stride_y),
    .execution_stride_x(descriptor_stride_x),
    .execution_padding_top(descriptor_padding_top),
    .execution_padding_bottom(descriptor_padding_bottom),
    .execution_padding_left(descriptor_padding_left),
    .execution_padding_right(descriptor_padding_right),
    .execution_dilation_y(descriptor_dilation_y),
    .execution_dilation_x(descriptor_dilation_x),
    .execution_activation(descriptor_activation),
    .execution_residual_mode(descriptor_residual_mode),
    .execution_tile_height_hint(descriptor_tile_height_hint),
    .execution_tile_width_hint(descriptor_tile_width_hint),
    .execution_input_ddr_offset(descriptor_input_ddr_offset),
    .execution_input_allocation_size(descriptor_input_allocation_size),
    .execution_input_row_stride(descriptor_input_row_stride),
    .execution_input_pixel_stride(descriptor_input_pixel_stride),
    .execution_input_channel_stride(descriptor_input_channel_stride),
    .execution_output_ddr_offset(descriptor_output_ddr_offset),
    .execution_output_allocation_size(descriptor_output_allocation_size),
    .execution_output_row_stride(descriptor_output_row_stride),
    .execution_output_pixel_stride(descriptor_output_pixel_stride),
    .execution_output_channel_stride(descriptor_output_channel_stride),
    .execution_output_tensor_quantization_id(
      descriptor_output_tensor_quantization_id),
    .execution_residual_tensor_valid(descriptor_residual_tensor_valid),
    .execution_residual_width(descriptor_residual_width),
    .execution_residual_height(descriptor_residual_height),
    .execution_residual_channels(descriptor_residual_channels),
    .execution_residual_quantization_id(
      descriptor_residual_quantization_id),
    .execution_residual_ddr_offset(descriptor_residual_ddr_offset),
    .execution_quantization_valid(descriptor_quantization_valid),
    .execution_quantization_channel_count(
      descriptor_quantization_channel_count),
    .execution_rounding_mode(descriptor_rounding_mode),
    .execution_output_zero_point(descriptor_output_zero_point),
    .execution_quant_multiplier(descriptor_quant_multiplier),
    .execution_quant_shift(descriptor_quant_shift),
    .staging_state(staging_state),
    .staging_bank(),
    .active_valid(model_active_valid),
    .active_bank(),
    .staging_model_id(),
    .staging_generation_id(),
    .active_model_id(active_model_id),
    .active_generation_id(active_generation_id),
    .active_layer_count(active_layer_count),
    .staging_layer_count(),
    .staging_tensor_count(),
    .staging_quantization_count(),
    .lifecycle_error(model_lifecycle_error)
  );

  packed_dma_packet_parser #(
    .MAX_PAYLOAD_BYTES(MAX_PAYLOAD_BYTES)
  ) u_parser (
    .clk(clk), .rst_n(rst_n), .clear(clear),
    .s_axis_tdata(s_axis_tdata), .s_axis_tkeep(s_axis_tkeep),
    .s_axis_tvalid(s_axis_tvalid), .s_axis_tready(s_axis_tready),
    .s_axis_tlast(s_axis_tlast),
    .packet_start(packet_start), .packet_ready(packet_ready),
    .packet_done(packet_done), .packet_type(packet_type),
    .job_id(packet_job_id), .tensor_id(packet_tensor_id),
    .layer_id(packet_layer_id), .tile_x(packet_tile_x),
    .tile_y(packet_tile_y), .tile_width(packet_tile_width),
    .tile_height(packet_tile_height),
    .channel_offset(packet_channel_offset),
    .channel_count(packet_channel_count),
    .payload_length(packet_payload_length),
    .payload_valid(payload_valid), .payload_ready(payload_ready),
    .payload_data(payload_data), .payload_keep(payload_keep),
    .payload_last(payload_last), .packet_busy(), .recovering(),
    .error_valid(parser_error_valid), .error_code(parser_error_code),
    .error_count(packet_error_count)
  );

  packed_dma_runtime_router u_router (
    .clk(clk), .rst_n(rst_n), .clear(clear),
    .packet_start(packet_start), .packet_ready(packet_ready),
    .packet_type(packet_type), .packet_job_id(packet_job_id),
    .packet_tensor_id(packet_tensor_id), .packet_layer_id(packet_layer_id),
    .packet_tile_x(packet_tile_x), .packet_tile_y(packet_tile_y),
    .packet_tile_width(packet_tile_width),
    .packet_tile_height(packet_tile_height),
    .packet_channel_offset(packet_channel_offset),
    .packet_channel_count(packet_channel_count),
    .packet_payload_length(packet_payload_length),
    .packet_error_valid(parser_error_valid),
    .payload_valid(payload_valid), .payload_ready(payload_ready),
    .payload_data(payload_data), .payload_keep(payload_keep),
    .payload_last(payload_last),
    .parameter_config_valid(parameter_config_valid_q),
    .parameter_config_layer_id(parameter_config_layer_id_q),
    .parameter_config_kernel_size(parameter_config_kernel_size_q),
    .parameter_config_cin(parameter_config_cin_q),
    .parameter_config_cout(parameter_config_cout_q),
    .parameter_config_bias_enable(parameter_config_bias_enable_q),
    .parameter_config_quant_enable(1'b0),
    .parameter_config_quant_shift(5'd0),
    .parameter_config_weight_bytes(parameter_config_weight_bytes_q),
    .parameter_config_bias_bytes(parameter_config_bias_bytes_q),
    .parameter_config_crc32(parameter_config_crc32_q),
    .parameter_load_start(parameter_load_start),
    .parameter_load_abort(parameter_load_abort),
    .parameter_load_ready(parameter_load_ready),
    .parameter_load_layer_id(parameter_load_layer_id),
    .parameter_load_kernel_size(parameter_load_kernel_size),
    .parameter_load_cin(parameter_load_cin),
    .parameter_load_cout(parameter_load_cout),
    .parameter_load_bias_enable(parameter_load_bias_enable),
    .parameter_load_quant_enable(parameter_load_quant_enable),
    .parameter_load_quant_shift(parameter_load_quant_shift),
    .parameter_load_weight_bytes(parameter_load_weight_bytes),
    .parameter_load_bias_bytes(parameter_load_bias_bytes),
    .parameter_load_expected_crc32(parameter_load_expected_crc32),
    .parameter_weight_valid(parameter_weight_valid),
    .parameter_weight_ready(parameter_weight_ready),
    .parameter_weight_data(parameter_weight_data),
    .parameter_bias_valid(parameter_bias_valid),
    .parameter_bias_ready(parameter_bias_ready),
    .parameter_bias_data(parameter_bias_data),
    .activation_packet_start(activation_packet_start),
    .activation_packet_ready(activation_packet_ready),
    .activation_job_id(activation_job_id),
    .activation_tensor_id(activation_tensor_id),
    .activation_layer_id(activation_layer_id),
    .activation_tile_x(activation_tile_x),
    .activation_tile_y(activation_tile_y),
    .activation_tile_width(activation_tile_width),
    .activation_tile_height(activation_tile_height),
    .activation_channel_offset(activation_channel_offset),
    .activation_channel_count(activation_channel_count),
    .activation_payload_length(activation_payload_length),
    .activation_valid(activation_valid),
    .activation_ready(activation_ready),
    .activation_data(activation_data), .activation_keep(activation_keep),
    .activation_last(activation_last),
    .error(router_error), .error_code(router_error_code)
  );

  cnn_runtime_parameter_banks #(
    .PC(PC), .PK(PK), .MAX_CIN(MAX_CIN), .MAX_COUT(MAX_COUT),
    .DATA_W(DATA_W), .BIAS_W(ACC_W), .COUNT_W(COUNT_W)
  ) u_parameters (
    .clk(clk), .rst_n(rst_n), .clear_error(clear),
    .load_start(parameter_load_start), .load_abort(parameter_load_abort),
    .load_ready(parameter_load_ready),
    .load_layer_id(parameter_load_layer_id),
    .load_kernel_size(parameter_load_kernel_size),
    .load_cin(parameter_load_cin), .load_cout(parameter_load_cout),
    .load_bias_enable(parameter_load_bias_enable),
    .load_quant_enable(parameter_load_quant_enable),
    .load_quant_shift(parameter_load_quant_shift),
    .load_weight_bytes(parameter_load_weight_bytes),
    .load_bias_bytes(parameter_load_bias_bytes),
    .load_expected_crc32(parameter_load_expected_crc32),
    .weight_valid(parameter_weight_valid),
    .weight_ready(parameter_weight_ready),
    .weight_data(parameter_weight_data),
    .bias_valid(parameter_bias_valid), .bias_ready(parameter_bias_ready),
    .bias_data(parameter_bias_data), .load_busy(),
    .load_done(parameter_load_done), .error(parameter_error),
    .error_code(parameter_error_code),
    .parameter_request(parameter_request),
    .parameter_layer_id(parameter_layer_id),
    .parameter_ready(parameter_ready),
    .parameter_release(parameter_release),
    .parameter_use_scratchpad_weights(),
    .parameter_quant_enable(parameter_quant_enable),
    .parameter_quant_shift(parameter_quant_shift),
    .parameter_bias(parameter_bias),
    .weight_read_k_base(weight_read_k_base),
    .weight_read_c_base(weight_read_c_base),
    .weight_read_kernel_idx(weight_read_kernel_idx),
    .weight_out_lane_mask(weight_out_lane_mask),
    .weight_in_lane_mask(weight_in_lane_mask),
    .weight_mat_data(weight_mat_data),
    .bank_valid(parameter_bank_valid), .bank0_layer_id(),
    .bank1_layer_id(), .load_bank(), .compute_bank(),
    .compute_active(), .overlap_active()
  );

  cnn_tiled_multi_layer_controller #(
    .PC(PC), .PK(PK), .MAX_CIN(MAX_CIN), .MAX_COUT(MAX_COUT),
    .MAX_LAYERS(MAX_LAYERS), .MAX_TILE_WIDTH(MAX_TILE_WIDTH),
    .MAX_TILE_HEIGHT(MAX_TILE_HEIGHT), .DATA_W(DATA_W),
    .ACC_W(ACC_W), .COUNT_W(COUNT_W)
  ) u_controller (
    .clk(clk), .rst_n(rst_n), .clear(clear), .start(start),
    .job_id(job_id), .model_active_valid(model_active_valid),
    .model_layer_count(active_layer_count),
    .descriptor_layer_index(controller_descriptor_index),
    .descriptor_valid(descriptor_valid),
    .descriptor_layer_id(descriptor_layer_id),
    .descriptor_opcode(descriptor_opcode),
    .descriptor_last_layer(descriptor_last_layer),
    .descriptor_bias_enable(descriptor_bias_enable),
    .descriptor_input_tensor_id(descriptor_input_tensor_id),
    .descriptor_output_tensor_id(descriptor_output_tensor_id),
    .descriptor_residual_tensor_id(descriptor_residual_tensor_id),
    .descriptor_quantization_id(descriptor_quantization_id),
    .descriptor_input_width(descriptor_input_width),
    .descriptor_input_height(descriptor_input_height),
    .descriptor_input_channels(descriptor_input_channels),
    .descriptor_output_width(descriptor_output_width),
    .descriptor_output_height(descriptor_output_height),
    .descriptor_output_channels(descriptor_output_channels),
    .descriptor_kernel_height(descriptor_kernel_height),
    .descriptor_kernel_width(descriptor_kernel_width),
    .descriptor_stride_y(descriptor_stride_y),
    .descriptor_stride_x(descriptor_stride_x),
    .descriptor_padding_top(descriptor_padding_top),
    .descriptor_padding_bottom(descriptor_padding_bottom),
    .descriptor_padding_left(descriptor_padding_left),
    .descriptor_padding_right(descriptor_padding_right),
    .descriptor_dilation_y(descriptor_dilation_y),
    .descriptor_dilation_x(descriptor_dilation_x),
    .descriptor_activation(descriptor_activation),
    .descriptor_residual_mode(descriptor_residual_mode),
    .descriptor_tile_height_hint(descriptor_tile_height_hint),
    .descriptor_tile_width_hint(descriptor_tile_width_hint),
    .descriptor_input_ddr_offset(descriptor_input_ddr_offset),
    .descriptor_input_allocation_size(descriptor_input_allocation_size),
    .descriptor_input_row_stride(descriptor_input_row_stride),
    .descriptor_input_pixel_stride(descriptor_input_pixel_stride),
    .descriptor_input_channel_stride(descriptor_input_channel_stride),
    .descriptor_output_ddr_offset(descriptor_output_ddr_offset),
    .descriptor_output_allocation_size(descriptor_output_allocation_size),
    .descriptor_output_row_stride(descriptor_output_row_stride),
    .descriptor_output_pixel_stride(descriptor_output_pixel_stride),
    .descriptor_output_channel_stride(descriptor_output_channel_stride),
    .descriptor_output_tensor_quantization_id(
      descriptor_output_tensor_quantization_id),
    .descriptor_residual_tensor_valid(descriptor_residual_tensor_valid),
    .descriptor_residual_width(descriptor_residual_width),
    .descriptor_residual_height(descriptor_residual_height),
    .descriptor_residual_channels(descriptor_residual_channels),
    .descriptor_residual_quantization_id(
      descriptor_residual_quantization_id),
    .descriptor_residual_ddr_offset(descriptor_residual_ddr_offset),
    .descriptor_quantization_valid(descriptor_quantization_valid),
    .descriptor_quantization_channel_count(
      descriptor_quantization_channel_count),
    .descriptor_rounding_mode(descriptor_rounding_mode),
    .descriptor_output_zero_point(descriptor_output_zero_point),
    .descriptor_quant_multiplier(descriptor_quant_multiplier),
    .descriptor_quant_shift(descriptor_quant_shift),
    .parameter_request(parameter_request),
    .parameter_layer_id(parameter_layer_id),
    .parameter_ready(parameter_ready),
    .parameter_release(parameter_release),
    .parameter_quant_enable(parameter_quant_enable),
    .parameter_quant_shift(parameter_quant_shift),
    .parameter_bias(parameter_bias),
    .parameter_weight_read_k_base(weight_read_k_base),
    .parameter_weight_read_c_base(weight_read_c_base),
    .parameter_weight_read_kernel_idx(weight_read_kernel_idx),
    .parameter_weight_out_lane_mask(weight_out_lane_mask),
    .parameter_weight_in_lane_mask(weight_in_lane_mask),
    .parameter_weight_mat_data(weight_mat_data),
    .activation_packet_start(activation_packet_start),
    .activation_packet_ready(activation_packet_ready),
    .activation_job_id(activation_job_id),
    .activation_tensor_id(activation_tensor_id),
    .activation_layer_id(activation_layer_id),
    .activation_tile_x(activation_tile_x),
    .activation_tile_y(activation_tile_y),
    .activation_tile_width(activation_tile_width),
    .activation_tile_height(activation_tile_height),
    .activation_channel_offset(activation_channel_offset),
    .activation_channel_count(activation_channel_count),
    .activation_payload_length(activation_payload_length),
    .activation_valid(activation_valid),
    .activation_ready(activation_ready),
    .activation_data(activation_data), .activation_keep(activation_keep),
    .activation_last(activation_last),
    .m_axis_tdata(m_axis_tdata), .m_axis_tkeep(m_axis_tkeep),
    .m_axis_tvalid(m_axis_tvalid), .m_axis_tready(m_axis_tready),
    .m_axis_tlast(m_axis_tlast), .active_layer(active_layer),
    .active_input_tensor_id(active_input_tensor_id),
    .active_output_tensor_id(active_output_tensor_id),
    .active_input_ddr_offset(active_input_ddr_offset),
    .active_input_allocation_size(),
    .active_input_row_stride(), .active_input_pixel_stride(),
    .active_input_channel_stride(),
    .active_output_ddr_offset(active_output_ddr_offset),
    .active_output_allocation_size(),
    .active_output_row_stride(), .active_output_pixel_stride(),
    .active_output_channel_stride(), .current_tile_x(current_tile_x),
    .current_tile_y(current_tile_y),
    .completed_layer_count(completed_layer_count),
    .completed_tile_count(completed_tile_count),
    .saturation_event_count(saturation_event_count),
    .layer_done(layer_done), .busy(busy), .done(controller_done),
    .error(controller_error), .error_code(controller_error_code),
    .error_layer(error_layer)
  );

  logic unused;
  assign unused = &{1'b0, descriptor_quantization_id, packet_done,
                    parameter_load_done, parser_error_valid};
endmodule
