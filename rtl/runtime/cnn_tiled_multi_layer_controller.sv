`timescale 1ns/1ps

module cnn_tiled_multi_layer_controller #(
  parameter int PC = 2,
  parameter int PK = 4,
  parameter int MAX_CIN = 16,
  parameter int MAX_COUT = 16,
  parameter int MAX_LAYERS = 8,
  parameter int MAX_TILE_WIDTH = 16,
  parameter int MAX_TILE_HEIGHT = 16,
  parameter int DATA_W = 8,
  parameter int ACC_W = 32,
  parameter int COUNT_W = 8
)(
  input  logic clk,
  input  logic rst_n,
  input  logic clear,

  input  logic start,
  input  logic [31:0] job_id,
  input  logic model_active_valid,
  input  logic [15:0] model_layer_count,

  output logic [2:0] descriptor_layer_index,
  input  logic descriptor_valid,
  input  logic [15:0] descriptor_layer_id,
  input  logic [15:0] descriptor_opcode,
  input  logic descriptor_last_layer,
  input  logic descriptor_bias_enable,
  input  logic [15:0] descriptor_input_tensor_id,
  input  logic [15:0] descriptor_output_tensor_id,
  input  logic [15:0] descriptor_residual_tensor_id,
  input  logic [15:0] descriptor_quantization_id,
  input  logic [15:0] descriptor_input_width,
  input  logic [15:0] descriptor_input_height,
  input  logic [15:0] descriptor_input_channels,
  input  logic [15:0] descriptor_output_width,
  input  logic [15:0] descriptor_output_height,
  input  logic [15:0] descriptor_output_channels,
  input  logic [7:0] descriptor_kernel_height,
  input  logic [7:0] descriptor_kernel_width,
  input  logic [7:0] descriptor_stride_y,
  input  logic [7:0] descriptor_stride_x,
  input  logic [7:0] descriptor_padding_top,
  input  logic [7:0] descriptor_padding_bottom,
  input  logic [7:0] descriptor_padding_left,
  input  logic [7:0] descriptor_padding_right,
  input  logic [7:0] descriptor_dilation_y,
  input  logic [7:0] descriptor_dilation_x,
  input  logic [7:0] descriptor_activation,
  input  logic [7:0] descriptor_residual_mode,
  input  logic [15:0] descriptor_tile_height_hint,
  input  logic [15:0] descriptor_tile_width_hint,
  input  logic [63:0] descriptor_input_ddr_offset,
  input  logic [31:0] descriptor_input_allocation_size,
  input  logic [31:0] descriptor_input_row_stride,
  input  logic [31:0] descriptor_input_pixel_stride,
  input  logic [31:0] descriptor_input_channel_stride,
  input  logic [63:0] descriptor_output_ddr_offset,
  input  logic [31:0] descriptor_output_allocation_size,
  input  logic [31:0] descriptor_output_row_stride,
  input  logic [31:0] descriptor_output_pixel_stride,
  input  logic [31:0] descriptor_output_channel_stride,
  input  logic [15:0] descriptor_output_tensor_quantization_id,
  input  logic descriptor_residual_tensor_valid,
  input  logic [15:0] descriptor_residual_width,
  input  logic [15:0] descriptor_residual_height,
  input  logic [15:0] descriptor_residual_channels,
  input  logic [15:0] descriptor_residual_quantization_id,
  input  logic [63:0] descriptor_residual_ddr_offset,
  input  logic descriptor_quantization_valid,
  input  logic [15:0] descriptor_quantization_channel_count,
  input  logic [7:0] descriptor_rounding_mode,
  input  logic signed [7:0] descriptor_output_zero_point,
  input  logic signed [31:0] descriptor_quant_multiplier [MAX_COUT],
  input  logic [5:0] descriptor_quant_shift [MAX_COUT],

  output logic parameter_request,
  output logic [2:0] parameter_layer_id,
  input  logic parameter_ready,
  output logic parameter_release,
  input  logic parameter_quant_enable,
  input  logic [4:0] parameter_quant_shift,
  input  logic signed [ACC_W-1:0] parameter_bias [MAX_COUT],
  output logic [COUNT_W-1:0] parameter_weight_read_k_base,
  output logic [COUNT_W-1:0] parameter_weight_read_c_base,
  output logic [3:0] parameter_weight_read_kernel_idx,
  output logic [PK-1:0] parameter_weight_out_lane_mask,
  output logic [PC-1:0] parameter_weight_in_lane_mask,
  input  logic signed [DATA_W-1:0] parameter_weight_mat_data [PK][PC],

  input  logic activation_packet_start,
  output logic activation_packet_ready,
  input  logic [31:0] activation_job_id,
  input  logic [15:0] activation_tensor_id,
  input  logic [15:0] activation_layer_id,
  input  logic [15:0] activation_tile_x,
  input  logic [15:0] activation_tile_y,
  input  logic [15:0] activation_tile_width,
  input  logic [15:0] activation_tile_height,
  input  logic [15:0] activation_channel_offset,
  input  logic [15:0] activation_channel_count,
  input  logic [31:0] activation_payload_length,
  input  logic activation_valid,
  output logic activation_ready,
  input  logic [31:0] activation_data,
  input  logic [3:0] activation_keep,
  input  logic activation_last,

  output logic [31:0] m_axis_tdata,
  output logic [3:0] m_axis_tkeep,
  output logic m_axis_tvalid,
  input  logic m_axis_tready,
  output logic m_axis_tlast,

  output logic [2:0] active_layer,
  output logic [15:0] active_input_tensor_id,
  output logic [15:0] active_output_tensor_id,
  output logic [63:0] active_input_ddr_offset,
  output logic [31:0] active_input_allocation_size,
  output logic [31:0] active_input_row_stride,
  output logic [31:0] active_input_pixel_stride,
  output logic [31:0] active_input_channel_stride,
  output logic [63:0] active_output_ddr_offset,
  output logic [31:0] active_output_allocation_size,
  output logic [31:0] active_output_row_stride,
  output logic [31:0] active_output_pixel_stride,
  output logic [31:0] active_output_channel_stride,
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
  output logic [2:0] error_layer
);
  import cnn_accel_abi_pkg::*;

  localparam logic [7:0] MULTI_ERROR_NONE = 8'd0;
  localparam logic [7:0] MULTI_ERROR_NO_MODEL = 8'd1;
  localparam logic [7:0] MULTI_ERROR_LAYER_COUNT = 8'd2;
  localparam logic [7:0] MULTI_ERROR_DESCRIPTOR = 8'd3;
  localparam logic [7:0] MULTI_ERROR_UNSUPPORTED = 8'd4;
  localparam logic [7:0] MULTI_ERROR_GEOMETRY = 8'd5;
  localparam logic [7:0] MULTI_ERROR_CHAIN = 8'd6;
  localparam logic [7:0] MULTI_ERROR_DDR_LAYOUT = 8'd7;
  localparam logic [7:0] MULTI_ERROR_RUNTIME = 8'd8;
  localparam logic [7:0] MULTI_ERROR_BUSY = 8'd9;

  typedef enum logic [3:0] {
    S_IDLE,
    S_FETCH_DESCRIPTOR,
    S_WAIT_DESCRIPTOR,
    S_CAPTURE_DESCRIPTOR,
    S_LATCH_DESCRIPTOR,
    S_CALCULATE_DESCRIPTOR,
    S_MULTIPLY_DESCRIPTOR_SPANS,
    S_COMBINE_DESCRIPTOR_SPANS,
    S_SUM_ALLOCATION,
    S_FINALIZE_ALLOCATION,
    S_CHECK_DESCRIPTOR,
    S_START_LAYER,
    S_WAIT_LAYER,
    S_ADVANCE_LAYER,
    S_DONE,
    S_ERROR
  } state_t;

  state_t state;
  typedef struct packed {
    logic valid;
    logic [15:0] layer_id;
    logic [15:0] opcode;
    logic last_layer;
    logic [15:0] input_channels;
    logic [15:0] output_channels;
    logic [7:0] kernel_height;
    logic [7:0] kernel_width;
    logic [7:0] stride_y;
    logic [7:0] stride_x;
    logic [7:0] padding_top;
    logic [7:0] padding_bottom;
    logic [7:0] padding_left;
    logic [7:0] padding_right;
    logic [7:0] dilation_y;
    logic [7:0] dilation_x;
    logic [7:0] activation;
    logic [7:0] residual_mode;
    logic bias_enable;
    logic [15:0] input_tensor_id;
    logic [15:0] output_tensor_id;
    logic [15:0] residual_tensor_id;
    logic [15:0] quantization_id;
    logic [63:0] input_ddr_offset;
    logic [31:0] input_allocation_size;
    logic [31:0] input_row_stride;
    logic [31:0] input_pixel_stride;
    logic [31:0] input_channel_stride;
    logic [63:0] output_ddr_offset;
    logic [31:0] output_allocation_size;
    logic [31:0] output_row_stride;
    logic [31:0] output_pixel_stride;
    logic [31:0] output_channel_stride;
    logic quantization_valid;
    logic [15:0] quantization_channel_count;
    logic [7:0] rounding_mode;
    logic signed [7:0] output_zero_point;
    logic [15:0] output_tensor_quantization_id;
    logic residual_tensor_valid;
    logic [15:0] residual_width;
    logic [15:0] residual_height;
    logic [15:0] residual_channels;
    logic [15:0] residual_quantization_id;
    logic [63:0] residual_ddr_offset;
    logic [15:0] input_width;
    logic [15:0] input_height;
    logic [15:0] output_width;
    logic [15:0] output_height;
    logic [15:0] tile_width_hint;
    logic [15:0] tile_height_hint;
  } descriptor_snapshot_t;

  descriptor_snapshot_t descriptor_snapshot;
  logic capture_active_q;
  logic [2:0] layer_index;
  logic [3:0] layer_count_q;
  logic runtime_start;
  logic runtime_done;
  logic runtime_error;
  logic [7:0] runtime_error_code;
  logic [31:0] runtime_saturation_event_count;
  logic descriptor_semantic_valid;
  logic [7:0] descriptor_error_code;
  logic descriptor_is_final;
  logic captured_descriptor_valid;
  logic [15:0] captured_layer_id;
  logic [15:0] captured_opcode;
  logic captured_last_layer;
  logic [15:0] captured_input_channels;
  logic [15:0] captured_output_channels;
  logic [7:0] captured_kernel_height;
  logic [7:0] captured_kernel_width;
  logic [7:0] captured_stride_y;
  logic [7:0] captured_stride_x;
  logic [7:0] captured_padding_top;
  logic [7:0] captured_padding_bottom;
  logic [7:0] captured_padding_left;
  logic [7:0] captured_padding_right;
  logic [7:0] captured_dilation_y;
  logic [7:0] captured_dilation_x;
  logic [7:0] captured_activation;
  logic [7:0] captured_residual_mode;
  logic captured_quantization_valid;
  logic [15:0] captured_quantization_channel_count;
  logic [7:0] captured_rounding_mode;
  logic signed [7:0] captured_output_zero_point;
  logic [31:0] expected_output_width_q;
  logic [31:0] expected_output_height_q;
  logic [31:0] output_width_numerator_q;
  logic [31:0] output_height_numerator_q;
  logic output_width_geometry_valid_q;
  logic output_height_geometry_valid_q;
  logic [63:0] minimum_input_allocation_q;
  logic [63:0] minimum_output_allocation_q;
  logic [63:0] minimum_input_row_stride_q;
  logic [63:0] minimum_output_row_stride_q;
  logic [63:0] input_row_span_q;
  logic [63:0] input_pixel_span_q;
  logic [63:0] input_channel_span_q;
  logic [63:0] output_row_span_q;
  logic [63:0] output_pixel_span_q;
  logic [63:0] output_channel_span_q;
  logic [31:0] minimum_input_row_stride_high_q;
  logic [31:0] minimum_output_row_stride_high_q;
  logic [31:0] input_row_span_high_q;
  logic [31:0] input_pixel_span_high_q;
  logic [31:0] input_channel_span_high_q;
  logic [31:0] output_row_span_high_q;
  logic [31:0] output_pixel_span_high_q;
  logic [31:0] output_channel_span_high_q;
  logic [63:0] input_allocation_partial_q;
  logic [63:0] output_allocation_partial_q;
  logic [15:0] input_width_extent_q;
  logic [15:0] input_height_extent_q;
  logic [15:0] input_channel_extent_q;
  logic [15:0] output_width_extent_q;
  logic [15:0] output_height_extent_q;
  logic [15:0] output_channel_extent_q;
  logic quantization_parameters_valid;

  function automatic logic [31:0] multiply_16x16(
    input logic [15:0] lhs,
    input logic [15:0] rhs
  );
    multiply_16x16 = 32'(lhs) * 32'(rhs);
  endfunction

  function automatic logic [63:0] combine_stride_product(
    input logic [31:0] low_product,
    input logic [31:0] high_product
  );
    combine_stride_product =
      64'({16'd0, low_product}) + 64'({high_product, 16'd0});
  endfunction

  logic [15:0] previous_output_tensor_id;
  logic [15:0] previous_output_width;
  logic [15:0] previous_output_height;
  logic [15:0] previous_output_channels;
  logic [63:0] previous_output_ddr_offset;

  logic [15:0] active_input_width;
  logic [15:0] active_input_height;
  logic [15:0] active_output_width;
  logic [15:0] active_output_height;
  logic [7:0] active_input_channels;
  logic [7:0] active_output_channels;
  logic [1:0] active_kernel_size;
  logic [1:0] active_stride;
  logic active_padding_left;
  logic active_padding_right;
  logic active_padding_top;
  logic active_padding_bottom;
  logic active_bias_enable;
  logic active_relu_enable;
  logic [15:0] active_tile_width_hint;
  logic [15:0] active_tile_height_hint;
  logic [15:0] active_residual_tensor_id;
  logic [15:0] active_quantization_id;
  logic [15:0] active_output_tensor_quantization_id;
  logic active_residual_tensor_valid;
  logic [15:0] active_residual_width;
  logic [15:0] active_residual_height;
  logic [15:0] active_residual_channels;
  logic [15:0] active_residual_quantization_id;
  logic [63:0] active_residual_ddr_offset;
  logic signed [31:0] active_quant_multiplier [MAX_COUT];
  logic [5:0] active_quant_shift [MAX_COUT];

  assign descriptor_layer_index = layer_index;
  assign active_layer = layer_index;
  assign busy = (state != S_IDLE) && (state != S_DONE);
  assign runtime_start = state == S_START_LAYER;
  assign descriptor_is_final =
    (4'(layer_index) + 4'd1) == layer_count_q;

  always_comb begin
    quantization_parameters_valid = captured_quantization_valid &&
      (captured_quantization_channel_count == captured_output_channels) &&
      (captured_rounding_mode == ROUND_HALF_TO_EVEN) &&
      (captured_output_zero_point == 0) &&
      (active_quantization_id == active_output_tensor_quantization_id);
    for (int channel = 0; channel < MAX_COUT; channel++) begin
      if ((channel < captured_output_channels) &&
          ((active_quant_multiplier[channel] <= 0) ||
           (active_quant_shift[channel] > 6'd62))) begin
        quantization_parameters_valid = 1'b0;
      end
    end
  end

  always_comb begin
    descriptor_semantic_valid = 1'b0;
    descriptor_error_code = MULTI_ERROR_DESCRIPTOR;

    if (!captured_descriptor_valid ||
        (captured_layer_id != 16'(layer_index)) ||
        (captured_last_layer != descriptor_is_final)) begin
      descriptor_error_code = MULTI_ERROR_DESCRIPTOR;
    end else if (!quantization_parameters_valid) begin
      descriptor_error_code = MULTI_ERROR_UNSUPPORTED;
    end else if ((captured_opcode != OPCODE_CONV2D) ||
                 !((captured_kernel_width == 1) ||
                   (captured_kernel_width == 3)) ||
                 (captured_kernel_height != captured_kernel_width) ||
                 !((captured_stride_x == 1) ||
                   (captured_stride_x == 2)) ||
                 (captured_stride_y != captured_stride_x) ||
                 (captured_padding_top > 1) ||
                 (captured_padding_bottom > 1) ||
                 (captured_padding_left > 1) ||
                 (captured_padding_right > 1) ||
                 (captured_dilation_x != 1) ||
                 (captured_dilation_y != 1) ||
                 (captured_activation > ACTIVATION_RELU) ||
                 (captured_residual_mode > RESIDUAL_POST_QUANT_SUBTRACT) ||
                 ((captured_residual_mode == RESIDUAL_NONE) &&
                  (active_residual_tensor_id != NO_TENSOR_ID)) ||
                 ((captured_residual_mode != RESIDUAL_NONE) &&
                  ((active_residual_tensor_id == NO_TENSOR_ID) ||
                   !active_residual_tensor_valid ||
                   (active_residual_width != active_output_width) ||
                   (active_residual_height != active_output_height) ||
                   (active_residual_channels != captured_output_channels) ||
                   (active_residual_quantization_id !=
                    active_output_tensor_quantization_id)))) begin
      descriptor_error_code = MULTI_ERROR_UNSUPPORTED;
    end else if ((active_input_width == 0) ||
                 (active_input_height == 0) ||
                 (active_output_width == 0) ||
                 (active_output_height == 0) ||
                 (active_input_width > 16'(MAX_TENSOR_WIDTH)) ||
                 (active_input_height > 16'(MAX_TENSOR_HEIGHT)) ||
                 (active_output_width > 16'(MAX_TENSOR_WIDTH)) ||
                 (active_output_height > 16'(MAX_TENSOR_HEIGHT)) ||
                 (captured_input_channels == 0) ||
                 (captured_input_channels > 16'(MAX_CIN)) ||
                 (captured_output_channels == 0) ||
                 (captured_output_channels > 16'(MAX_COUT)) ||
                 (expected_output_width_q != 32'(active_output_width)) ||
                 (expected_output_height_q != 32'(active_output_height)) ||
                 (active_tile_width_hint > 16'(MAX_TILE_WIDTH)) ||
                 (active_tile_height_hint > 16'(MAX_TILE_HEIGHT))) begin
      descriptor_error_code = MULTI_ERROR_GEOMETRY;
    end else if ((layer_index != 0) &&
                 ((active_input_tensor_id != previous_output_tensor_id) ||
                  (active_input_width != previous_output_width) ||
                  (active_input_height != previous_output_height) ||
                  (captured_input_channels != previous_output_channels) ||
                  (active_input_ddr_offset !=
                   previous_output_ddr_offset))) begin
      descriptor_error_code = MULTI_ERROR_CHAIN;
    end else if ((active_input_channel_stride != 1) ||
                 (active_output_channel_stride != 1) ||
                 (active_input_pixel_stride < captured_input_channels) ||
                 (active_output_pixel_stride < captured_output_channels) ||
                 (64'(active_input_row_stride) <
                  minimum_input_row_stride_q) ||
                 (64'(active_output_row_stride) <
                  minimum_output_row_stride_q) ||
                 (64'(active_input_allocation_size) <
                  minimum_input_allocation_q) ||
                 (64'(active_output_allocation_size) <
                  minimum_output_allocation_q)) begin
      descriptor_error_code = MULTI_ERROR_DDR_LAYOUT;
    end else begin
      descriptor_semantic_valid = 1'b1;
      descriptor_error_code = MULTI_ERROR_NONE;
    end
  end

  cnn_tiled_layer_runtime #(
    .PC(PC),
    .PK(PK),
    .MAX_CIN(MAX_CIN),
    .MAX_COUT(MAX_COUT),
    .MAX_TILE_WIDTH(MAX_TILE_WIDTH),
    .MAX_TILE_HEIGHT(MAX_TILE_HEIGHT),
    .DATA_W(DATA_W),
    .ACC_W(ACC_W),
    .COUNT_W(COUNT_W)
  ) u_tiled_layer_runtime (
    .clk(clk),
    .rst_n(rst_n),
    .clear(clear),
    .start(runtime_start),
    .job_id(job_id),
    .layer_id({13'd0, layer_index}),
    .input_tensor_id(active_input_tensor_id),
    .output_tensor_id(active_output_tensor_id),
    .input_width(active_input_width),
    .input_height(active_input_height),
    .output_width(active_output_width),
    .output_height(active_output_height),
    .kernel_size(active_kernel_size),
    .stride(active_stride),
    .padding_left(active_padding_left),
    .padding_right(active_padding_right),
    .padding_top(active_padding_top),
    .padding_bottom(active_padding_bottom),
    .cin(active_input_channels),
    .cout(active_output_channels),
    .bias_enable(active_bias_enable),
    .relu_enable(active_relu_enable),
    .tile_width_hint(active_tile_width_hint),
    .tile_height_hint(active_tile_height_hint),
    .per_channel_quant_enable(1'b1),
    .quant_multiplier(active_quant_multiplier),
    .quant_shift(active_quant_shift),
    .output_zero_point(captured_output_zero_point),
    .residual_tensor_id(active_residual_tensor_id),
    .residual_mode(captured_residual_mode),
    .parameter_request(parameter_request),
    .parameter_layer_id(parameter_layer_id),
    .parameter_ready(parameter_ready),
    .parameter_release(parameter_release),
    .parameter_quant_enable(parameter_quant_enable),
    .parameter_quant_shift(parameter_quant_shift),
    .parameter_bias(parameter_bias),
    .parameter_weight_read_k_base(parameter_weight_read_k_base),
    .parameter_weight_read_c_base(parameter_weight_read_c_base),
    .parameter_weight_read_kernel_idx(parameter_weight_read_kernel_idx),
    .parameter_weight_out_lane_mask(parameter_weight_out_lane_mask),
    .parameter_weight_in_lane_mask(parameter_weight_in_lane_mask),
    .parameter_weight_mat_data(parameter_weight_mat_data),
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
    .activation_data(activation_data),
    .activation_keep(activation_keep),
    .activation_last(activation_last),
    .m_axis_tdata(m_axis_tdata),
    .m_axis_tkeep(m_axis_tkeep),
    .m_axis_tvalid(m_axis_tvalid),
    .m_axis_tready(m_axis_tready),
    .m_axis_tlast(m_axis_tlast),
    .current_tile_x(current_tile_x),
    .current_tile_y(current_tile_y),
    .completed_tile_count(completed_tile_count),
    .saturation_event_count(runtime_saturation_event_count),
    .busy(),
    .done(runtime_done),
    .error(runtime_error),
    .error_code(runtime_error_code)
  );

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      descriptor_snapshot <= '0;
    end else begin
      descriptor_snapshot.valid <= descriptor_valid;
      descriptor_snapshot.layer_id <= descriptor_layer_id;
      descriptor_snapshot.opcode <= descriptor_opcode;
      descriptor_snapshot.last_layer <= descriptor_last_layer;
      descriptor_snapshot.input_channels <= descriptor_input_channels;
      descriptor_snapshot.output_channels <= descriptor_output_channels;
      descriptor_snapshot.kernel_height <= descriptor_kernel_height;
      descriptor_snapshot.kernel_width <= descriptor_kernel_width;
      descriptor_snapshot.stride_y <= descriptor_stride_y;
      descriptor_snapshot.stride_x <= descriptor_stride_x;
      descriptor_snapshot.padding_top <= descriptor_padding_top;
      descriptor_snapshot.padding_bottom <= descriptor_padding_bottom;
      descriptor_snapshot.padding_left <= descriptor_padding_left;
      descriptor_snapshot.padding_right <= descriptor_padding_right;
      descriptor_snapshot.dilation_y <= descriptor_dilation_y;
      descriptor_snapshot.dilation_x <= descriptor_dilation_x;
      descriptor_snapshot.activation <= descriptor_activation;
      descriptor_snapshot.residual_mode <= descriptor_residual_mode;
      descriptor_snapshot.bias_enable <= descriptor_bias_enable;
      descriptor_snapshot.input_tensor_id <= descriptor_input_tensor_id;
      descriptor_snapshot.output_tensor_id <= descriptor_output_tensor_id;
      descriptor_snapshot.residual_tensor_id <= descriptor_residual_tensor_id;
      descriptor_snapshot.quantization_id <= descriptor_quantization_id;
      descriptor_snapshot.input_ddr_offset <= descriptor_input_ddr_offset;
      descriptor_snapshot.input_allocation_size <=
        descriptor_input_allocation_size;
      descriptor_snapshot.input_row_stride <= descriptor_input_row_stride;
      descriptor_snapshot.input_pixel_stride <= descriptor_input_pixel_stride;
      descriptor_snapshot.input_channel_stride <=
        descriptor_input_channel_stride;
      descriptor_snapshot.output_ddr_offset <= descriptor_output_ddr_offset;
      descriptor_snapshot.output_allocation_size <=
        descriptor_output_allocation_size;
      descriptor_snapshot.output_row_stride <= descriptor_output_row_stride;
      descriptor_snapshot.output_pixel_stride <=
        descriptor_output_pixel_stride;
      descriptor_snapshot.output_channel_stride <=
        descriptor_output_channel_stride;
      descriptor_snapshot.quantization_valid <= descriptor_quantization_valid;
      descriptor_snapshot.quantization_channel_count <=
        descriptor_quantization_channel_count;
      descriptor_snapshot.rounding_mode <= descriptor_rounding_mode;
      descriptor_snapshot.output_zero_point <= descriptor_output_zero_point;
      descriptor_snapshot.output_tensor_quantization_id <=
        descriptor_output_tensor_quantization_id;
      descriptor_snapshot.residual_tensor_valid <=
        descriptor_residual_tensor_valid;
      descriptor_snapshot.residual_width <= descriptor_residual_width;
      descriptor_snapshot.residual_height <= descriptor_residual_height;
      descriptor_snapshot.residual_channels <= descriptor_residual_channels;
      descriptor_snapshot.residual_quantization_id <=
        descriptor_residual_quantization_id;
      descriptor_snapshot.residual_ddr_offset <= descriptor_residual_ddr_offset;
      descriptor_snapshot.input_width <= descriptor_input_width;
      descriptor_snapshot.input_height <= descriptor_input_height;
      descriptor_snapshot.output_width <= descriptor_output_width;
      descriptor_snapshot.output_height <= descriptor_output_height;
      descriptor_snapshot.tile_width_hint <= descriptor_tile_width_hint;
      descriptor_snapshot.tile_height_hint <= descriptor_tile_height_hint;
    end
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      captured_descriptor_valid <= 1'b0;
      captured_layer_id <= '0;
      captured_opcode <= '0;
      captured_last_layer <= 1'b0;
      captured_input_channels <= '0;
      captured_output_channels <= '0;
      captured_kernel_height <= '0;
      captured_kernel_width <= '0;
      captured_stride_y <= '0;
      captured_stride_x <= '0;
      captured_padding_top <= '0;
      captured_padding_bottom <= '0;
      captured_padding_left <= '0;
      captured_padding_right <= '0;
      captured_dilation_y <= '0;
      captured_dilation_x <= '0;
      captured_activation <= '0;
      captured_residual_mode <= '0;
      captured_quantization_valid <= 1'b0;
      captured_quantization_channel_count <= '0;
      captured_rounding_mode <= '0;
      captured_output_zero_point <= '0;
      active_input_tensor_id <= '0;
      active_output_tensor_id <= '0;
      active_residual_tensor_id <= NO_TENSOR_ID;
      active_quantization_id <= '0;
      active_output_tensor_quantization_id <= '0;
      active_residual_tensor_valid <= 1'b0;
      active_residual_width <= '0;
      active_residual_height <= '0;
      active_residual_channels <= '0;
      active_residual_quantization_id <= '0;
      active_residual_ddr_offset <= '0;
      active_input_ddr_offset <= '0;
      active_input_allocation_size <= '0;
      active_input_row_stride <= '0;
      active_input_pixel_stride <= '0;
      active_input_channel_stride <= '0;
      active_output_ddr_offset <= '0;
      active_output_allocation_size <= '0;
      active_output_row_stride <= '0;
      active_output_pixel_stride <= '0;
      active_output_channel_stride <= '0;
      active_input_width <= '0;
      active_input_height <= '0;
      active_output_width <= '0;
      active_output_height <= '0;
      active_input_channels <= '0;
      active_output_channels <= '0;
      active_kernel_size <= '0;
      active_stride <= '0;
      active_padding_left <= 1'b0;
      active_padding_right <= 1'b0;
      active_padding_top <= 1'b0;
      active_padding_bottom <= 1'b0;
      active_bias_enable <= 1'b0;
      active_relu_enable <= 1'b0;
      active_tile_width_hint <= '0;
      active_tile_height_hint <= '0;
      for (int channel = 0; channel < MAX_COUT; channel++) begin
        active_quant_multiplier[channel] <= '0;
        active_quant_shift[channel] <= '0;
      end
    end else if (capture_active_q) begin
      captured_descriptor_valid <= descriptor_snapshot.valid;
      captured_layer_id <= descriptor_snapshot.layer_id;
      captured_opcode <= descriptor_snapshot.opcode;
      captured_last_layer <= descriptor_snapshot.last_layer;
      captured_input_channels <= descriptor_snapshot.input_channels;
      captured_output_channels <= descriptor_snapshot.output_channels;
      captured_kernel_height <= descriptor_snapshot.kernel_height;
      captured_kernel_width <= descriptor_snapshot.kernel_width;
      captured_stride_y <= descriptor_snapshot.stride_y;
      captured_stride_x <= descriptor_snapshot.stride_x;
      captured_padding_top <= descriptor_snapshot.padding_top;
      captured_padding_bottom <= descriptor_snapshot.padding_bottom;
      captured_padding_left <= descriptor_snapshot.padding_left;
      captured_padding_right <= descriptor_snapshot.padding_right;
      captured_dilation_y <= descriptor_snapshot.dilation_y;
      captured_dilation_x <= descriptor_snapshot.dilation_x;
      captured_activation <= descriptor_snapshot.activation;
      captured_residual_mode <= descriptor_snapshot.residual_mode;
      captured_quantization_valid <= descriptor_snapshot.quantization_valid;
      captured_quantization_channel_count <=
        descriptor_snapshot.quantization_channel_count;
      captured_rounding_mode <= descriptor_snapshot.rounding_mode;
      captured_output_zero_point <= descriptor_snapshot.output_zero_point;
      active_input_tensor_id <= descriptor_snapshot.input_tensor_id;
      active_output_tensor_id <= descriptor_snapshot.output_tensor_id;
      active_residual_tensor_id <= descriptor_snapshot.residual_tensor_id;
      active_quantization_id <= descriptor_snapshot.quantization_id;
      active_output_tensor_quantization_id <=
        descriptor_snapshot.output_tensor_quantization_id;
      active_residual_tensor_valid <= descriptor_snapshot.residual_tensor_valid;
      active_residual_width <= descriptor_snapshot.residual_width;
      active_residual_height <= descriptor_snapshot.residual_height;
      active_residual_channels <= descriptor_snapshot.residual_channels;
      active_residual_quantization_id <=
        descriptor_snapshot.residual_quantization_id;
      active_residual_ddr_offset <= descriptor_snapshot.residual_ddr_offset;
      active_input_ddr_offset <= descriptor_snapshot.input_ddr_offset;
      active_input_allocation_size <=
        descriptor_snapshot.input_allocation_size;
      active_input_row_stride <= descriptor_snapshot.input_row_stride;
      active_input_pixel_stride <= descriptor_snapshot.input_pixel_stride;
      active_input_channel_stride <= descriptor_snapshot.input_channel_stride;
      active_output_ddr_offset <= descriptor_snapshot.output_ddr_offset;
      active_output_allocation_size <=
        descriptor_snapshot.output_allocation_size;
      active_output_row_stride <= descriptor_snapshot.output_row_stride;
      active_output_pixel_stride <= descriptor_snapshot.output_pixel_stride;
      active_output_channel_stride <=
        descriptor_snapshot.output_channel_stride;
      active_input_width <= descriptor_snapshot.input_width;
      active_input_height <= descriptor_snapshot.input_height;
      active_output_width <= descriptor_snapshot.output_width;
      active_output_height <= descriptor_snapshot.output_height;
      active_input_channels <= 8'(descriptor_snapshot.input_channels);
      active_output_channels <= 8'(descriptor_snapshot.output_channels);
      active_kernel_size <= 2'(descriptor_snapshot.kernel_width);
      active_stride <= 2'(descriptor_snapshot.stride_x);
      active_padding_left <= descriptor_snapshot.padding_left[0];
      active_padding_right <= descriptor_snapshot.padding_right[0];
      active_padding_top <= descriptor_snapshot.padding_top[0];
      active_padding_bottom <= descriptor_snapshot.padding_bottom[0];
      active_bias_enable <= descriptor_snapshot.bias_enable;
      active_relu_enable <= descriptor_snapshot.activation == ACTIVATION_RELU;
      active_tile_width_hint <= descriptor_snapshot.tile_width_hint;
      active_tile_height_hint <= descriptor_snapshot.tile_height_hint;
      for (int channel = 0; channel < MAX_COUT; channel++) begin
        active_quant_multiplier[channel] <= descriptor_quant_multiplier[channel];
        active_quant_shift[channel] <= descriptor_quant_shift[channel];
      end
    end
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state <= S_IDLE;
      capture_active_q <= 1'b0;
      layer_index <= '0;
      layer_count_q <= '0;
      previous_output_tensor_id <= '0;
      previous_output_width <= '0;
      previous_output_height <= '0;
      previous_output_channels <= '0;
      previous_output_ddr_offset <= '0;
      expected_output_width_q <= '0;
      expected_output_height_q <= '0;
      output_width_numerator_q <= '0;
      output_height_numerator_q <= '0;
      output_width_geometry_valid_q <= 1'b0;
      output_height_geometry_valid_q <= 1'b0;
      minimum_input_allocation_q <= '0;
      minimum_output_allocation_q <= '0;
      minimum_input_row_stride_q <= '0;
      minimum_output_row_stride_q <= '0;
      input_row_span_q <= '0;
      input_pixel_span_q <= '0;
      input_channel_span_q <= '0;
      output_row_span_q <= '0;
      output_pixel_span_q <= '0;
      output_channel_span_q <= '0;
      minimum_input_row_stride_high_q <= '0;
      minimum_output_row_stride_high_q <= '0;
      input_row_span_high_q <= '0;
      input_pixel_span_high_q <= '0;
      input_channel_span_high_q <= '0;
      output_row_span_high_q <= '0;
      output_pixel_span_high_q <= '0;
      output_channel_span_high_q <= '0;
      input_allocation_partial_q <= '0;
      output_allocation_partial_q <= '0;
      input_width_extent_q <= '0;
      input_height_extent_q <= '0;
      input_channel_extent_q <= '0;
      output_width_extent_q <= '0;
      output_height_extent_q <= '0;
      output_channel_extent_q <= '0;
      completed_layer_count <= '0;
      saturation_event_count <= '0;
      layer_done <= 1'b0;
      done <= 1'b0;
      error <= 1'b0;
      error_code <= MULTI_ERROR_NONE;
      error_layer <= '0;
    end else begin
      layer_done <= 1'b0;
      done <= 1'b0;
      capture_active_q <= 1'b0;

      if (clear) begin
        state <= S_IDLE;
        layer_index <= '0;
        completed_layer_count <= '0;
        saturation_event_count <= '0;
        error <= 1'b0;
        error_code <= MULTI_ERROR_NONE;
        error_layer <= '0;
      end else if (start && (state != S_IDLE)) begin
        error <= 1'b1;
        error_code <= MULTI_ERROR_BUSY;
        error_layer <= layer_index;
        state <= S_ERROR;
      end else begin
        unique case (state)
          S_IDLE: begin
            if (start) begin
              layer_index <= '0;
              completed_layer_count <= '0;
              saturation_event_count <= '0;
              error <= 1'b0;
              error_code <= MULTI_ERROR_NONE;
              error_layer <= '0;
              if (!model_active_valid) begin
                error <= 1'b1;
                error_code <= MULTI_ERROR_NO_MODEL;
                state <= S_ERROR;
              end else if ((model_layer_count == 0) ||
                           (model_layer_count > 16'(MAX_LAYERS))) begin
                error <= 1'b1;
                error_code <= MULTI_ERROR_LAYER_COUNT;
                state <= S_ERROR;
              end else begin
                layer_count_q <= 4'(model_layer_count);
                state <= S_FETCH_DESCRIPTOR;
              end
            end
          end

          S_FETCH_DESCRIPTOR: begin
            state <= S_WAIT_DESCRIPTOR;
          end

          S_WAIT_DESCRIPTOR: begin
            if (descriptor_valid) begin
              state <= S_CAPTURE_DESCRIPTOR;
            end
          end

          S_CAPTURE_DESCRIPTOR: begin
            capture_active_q <= 1'b1;
            state <= S_LATCH_DESCRIPTOR;
          end

          S_LATCH_DESCRIPTOR: begin
            state <= S_CALCULATE_DESCRIPTOR;
          end

          S_CALCULATE_DESCRIPTOR: begin
            input_width_extent_q <= active_input_width - 16'd1;
            input_height_extent_q <= active_input_height - 16'd1;
            input_channel_extent_q <= captured_input_channels - 16'd1;
            output_width_extent_q <= active_output_width - 16'd1;
            output_height_extent_q <= active_output_height - 16'd1;
            output_channel_extent_q <= captured_output_channels - 16'd1;
            output_width_geometry_valid_q <=
              (captured_stride_x != 0) &&
                ((32'(active_input_width) +
                  32'(captured_padding_left) +
                  32'(captured_padding_right)) >=
                 32'(captured_kernel_width));
            output_height_geometry_valid_q <=
              (captured_stride_y != 0) &&
                ((32'(active_input_height) +
                  32'(captured_padding_top) +
                  32'(captured_padding_bottom)) >=
                 32'(captured_kernel_height));
            output_width_numerator_q <=
              32'(active_input_width) + 32'(captured_padding_left) +
              32'(captured_padding_right) - 32'(captured_kernel_width);
            output_height_numerator_q <=
              32'(active_input_height) + 32'(captured_padding_top) +
              32'(captured_padding_bottom) - 32'(captured_kernel_height);

            state <= S_MULTIPLY_DESCRIPTOR_SPANS;
          end

          S_MULTIPLY_DESCRIPTOR_SPANS: begin
            expected_output_width_q <= 32'd0;
            expected_output_height_q <= 32'd0;
            if (output_width_geometry_valid_q) begin
              expected_output_width_q <=
                (captured_stride_x == 2) ?
                  (output_width_numerator_q >> 1) + 32'd1 :
                  output_width_numerator_q + 32'd1;
            end
            if (output_height_geometry_valid_q) begin
              expected_output_height_q <=
                (captured_stride_y == 2) ?
                  (output_height_numerator_q >> 1) + 32'd1 :
                  output_height_numerator_q + 32'd1;
            end
            minimum_input_row_stride_q <=
              64'(multiply_16x16(
                active_input_width,
                active_input_pixel_stride[15:0]));
            minimum_input_row_stride_high_q <=
              multiply_16x16(
                active_input_width,
                active_input_pixel_stride[31:16]);
            minimum_output_row_stride_q <=
              64'(multiply_16x16(
                active_output_width,
                active_output_pixel_stride[15:0]));
            minimum_output_row_stride_high_q <=
              multiply_16x16(
                active_output_width,
                active_output_pixel_stride[31:16]);
            input_row_span_q <=
              64'(multiply_16x16(
                input_height_extent_q,
                active_input_row_stride[15:0]));
            input_row_span_high_q <=
              multiply_16x16(
                input_height_extent_q,
                active_input_row_stride[31:16]);
            input_pixel_span_q <=
              64'(multiply_16x16(
                input_width_extent_q,
                active_input_pixel_stride[15:0]));
            input_pixel_span_high_q <=
              multiply_16x16(
                input_width_extent_q,
                active_input_pixel_stride[31:16]);
            input_channel_span_q <=
              64'(multiply_16x16(
                input_channel_extent_q,
                active_input_channel_stride[15:0]));
            input_channel_span_high_q <=
              multiply_16x16(
                input_channel_extent_q,
                active_input_channel_stride[31:16]);
            output_row_span_q <=
              64'(multiply_16x16(
                output_height_extent_q,
                active_output_row_stride[15:0]));
            output_row_span_high_q <=
              multiply_16x16(
                output_height_extent_q,
                active_output_row_stride[31:16]);
            output_pixel_span_q <=
              64'(multiply_16x16(
                output_width_extent_q,
                active_output_pixel_stride[15:0]));
            output_pixel_span_high_q <=
              multiply_16x16(
                output_width_extent_q,
                active_output_pixel_stride[31:16]);
            output_channel_span_q <= 64'(output_channel_extent_q);
            output_channel_span_high_q <= '0;
            state <= S_COMBINE_DESCRIPTOR_SPANS;
          end

          S_COMBINE_DESCRIPTOR_SPANS: begin
            minimum_input_row_stride_q <= combine_stride_product(
              minimum_input_row_stride_q[31:0],
              minimum_input_row_stride_high_q);
            minimum_output_row_stride_q <= combine_stride_product(
              minimum_output_row_stride_q[31:0],
              minimum_output_row_stride_high_q);
            input_row_span_q <= combine_stride_product(
              input_row_span_q[31:0],
              input_row_span_high_q);
            input_pixel_span_q <= combine_stride_product(
              input_pixel_span_q[31:0],
              input_pixel_span_high_q);
            input_channel_span_q <= combine_stride_product(
              input_channel_span_q[31:0],
              input_channel_span_high_q);
            output_row_span_q <= combine_stride_product(
              output_row_span_q[31:0],
              output_row_span_high_q);
            output_pixel_span_q <= combine_stride_product(
              output_pixel_span_q[31:0],
              output_pixel_span_high_q);
            output_channel_span_q <= combine_stride_product(
              output_channel_span_q[31:0],
              output_channel_span_high_q);
            state <= S_SUM_ALLOCATION;
          end

          S_SUM_ALLOCATION: begin
            input_allocation_partial_q <=
              input_row_span_q + input_pixel_span_q;
            output_allocation_partial_q <=
              output_row_span_q + output_pixel_span_q;
            state <= S_FINALIZE_ALLOCATION;
          end

          S_FINALIZE_ALLOCATION: begin
            minimum_input_allocation_q <=
              input_allocation_partial_q + input_channel_span_q + 64'd1;
            minimum_output_allocation_q <=
              output_allocation_partial_q + output_channel_span_q + 64'd1;
            state <= S_CHECK_DESCRIPTOR;
          end

          S_CHECK_DESCRIPTOR: begin
            if (!descriptor_semantic_valid) begin
              error <= 1'b1;
              error_code <= descriptor_error_code;
              error_layer <= layer_index;
              state <= S_ERROR;
            end else begin
              state <= S_START_LAYER;
            end
          end

          S_START_LAYER: begin
            state <= S_WAIT_LAYER;
          end

          S_WAIT_LAYER: begin
            if (runtime_done) begin
              if (runtime_error) begin
                error <= 1'b1;
                error_code <= MULTI_ERROR_RUNTIME;
                error_layer <= layer_index;
                state <= S_ERROR;
              end else begin
                previous_output_tensor_id <= active_output_tensor_id;
                previous_output_width <= active_output_width;
                previous_output_height <= active_output_height;
                previous_output_channels <= 16'(active_output_channels);
                previous_output_ddr_offset <= active_output_ddr_offset;
                completed_layer_count <= completed_layer_count + 32'd1;
                saturation_event_count <= saturation_event_count +
                  runtime_saturation_event_count;
                layer_done <= 1'b1;
                state <= descriptor_is_final ?
                  S_DONE : S_ADVANCE_LAYER;
              end
            end
          end

          S_ADVANCE_LAYER: begin
            layer_index <= layer_index + 3'd1;
            state <= S_FETCH_DESCRIPTOR;
          end

          S_DONE: begin
            done <= 1'b1;
            state <= S_IDLE;
          end

          S_ERROR: begin
            done <= 1'b1;
            state <= S_IDLE;
          end

          default: state <= S_IDLE;
        endcase
      end
    end
  end

endmodule
