`timescale 1ns/1ps

module cnn_programmable_job_engine #(
  parameter int PC         = 2,
  parameter int PK         = 4,
  parameter int MAX_CIN    = 16,
  parameter int MAX_COUT   = 16,
  parameter int MAX_PIXELS = 64,
  parameter int DATA_W     = 8,
  parameter int BIAS_W     = 32,
  parameter int OUT_W      = 8,
  parameter int COUNT_W    = 8
)(
  input  logic clk,
  input  logic rst_n,

  input  logic start,
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

  input  logic parameter_load_start,
  output logic parameter_load_ready,
  input  logic [2:0] parameter_load_layer_id,
  input  logic [1:0] parameter_load_kernel_size,
  input  logic [COUNT_W-1:0] parameter_load_cin,
  input  logic [COUNT_W-1:0] parameter_load_cout,
  input  logic parameter_load_bias_enable,
  input  logic parameter_load_quant_enable,
  input  logic [4:0] parameter_load_quant_shift,
  input  logic [15:0] parameter_load_weight_bytes,
  input  logic [15:0] parameter_load_bias_bytes,
  input  logic [31:0] parameter_load_expected_crc32,
  input  logic parameter_weight_valid,
  output logic parameter_weight_ready,
  input  logic signed [DATA_W-1:0] parameter_weight_data,
  input  logic parameter_bias_valid,
  output logic parameter_bias_ready,
  input  logic signed [BIAS_W-1:0] parameter_bias_data,
  input  logic parameter_clear_error,
  output logic parameter_load_busy,
  output logic parameter_load_done,
  output logic parameter_error,
  output logic [7:0] parameter_error_code,
  output logic [1:0] parameter_bank_valid,
  output logic parameter_overlap_active,

  input  logic signed [DATA_W-1:0] input_tensor [MAX_PIXELS*MAX_CIN],
  output logic signed [OUT_W-1:0] output_tensor [MAX_PIXELS*MAX_COUT],
  output logic [2:0] active_layer,
  output logic busy,
  output logic done,
  output logic error,
  output logic [7:0] error_code,
  output logic [2:0] error_layer
);
  logic parameter_request;
  logic parameter_release;
  logic parameter_ready;
  logic parameter_use_scratchpad_weights;
  logic parameter_quant_enable;
  logic [4:0] parameter_quant_shift;
  logic signed [BIAS_W-1:0] selected_bias [MAX_COUT];
  logic [COUNT_W-1:0] weight_read_k_base;
  logic [COUNT_W-1:0] weight_read_c_base;
  logic [3:0] weight_read_kernel_idx;
  logic [PK-1:0] weight_out_lane_mask;
  logic [PC-1:0] weight_in_lane_mask;
  logic signed [DATA_W-1:0] weight_mat_data [PK][PC];
  logic signed [DATA_W-1:0] unused_weights_1x1 [MAX_COUT][MAX_CIN];
  logic signed [DATA_W-1:0] unused_weights_3x3 [MAX_COUT][MAX_CIN][9];

  always_comb begin
    for (int co = 0; co < MAX_COUT; co++) begin
      for (int ci = 0; ci < MAX_CIN; ci++) begin
        unused_weights_1x1[co][ci] = '0;
        for (int tap = 0; tap < 9; tap++) begin
          unused_weights_3x3[co][ci][tap] = '0;
        end
      end
    end
  end

  cnn_runtime_parameter_banks #(
    .PC(PC),
    .PK(PK),
    .MAX_CIN(MAX_CIN),
    .MAX_COUT(MAX_COUT),
    .DATA_W(DATA_W),
    .BIAS_W(BIAS_W),
    .COUNT_W(COUNT_W)
  ) u_runtime_parameter_banks (
    .clk(clk),
    .rst_n(rst_n),
    .clear_error(parameter_clear_error),
    .load_start(parameter_load_start),
    .load_abort(1'b0),
    .load_ready(parameter_load_ready),
    .load_layer_id(parameter_load_layer_id),
    .load_kernel_size(parameter_load_kernel_size),
    .load_cin(parameter_load_cin),
    .load_cout(parameter_load_cout),
    .load_bias_enable(parameter_load_bias_enable),
    .load_quant_enable(parameter_load_quant_enable),
    .load_quant_shift(parameter_load_quant_shift),
    .load_weight_bytes(parameter_load_weight_bytes),
    .load_bias_bytes(parameter_load_bias_bytes),
    .load_expected_crc32(parameter_load_expected_crc32),
    .weight_valid(parameter_weight_valid),
    .weight_ready(parameter_weight_ready),
    .weight_data(parameter_weight_data),
    .bias_valid(parameter_bias_valid),
    .bias_ready(parameter_bias_ready),
    .bias_data(parameter_bias_data),
    .load_busy(parameter_load_busy),
    .load_done(parameter_load_done),
    .error(parameter_error),
    .error_code(parameter_error_code),
    .parameter_request(parameter_request),
    .parameter_layer_id(active_layer),
    .parameter_ready(parameter_ready),
    .parameter_release(parameter_release),
    .parameter_use_scratchpad_weights(parameter_use_scratchpad_weights),
    .parameter_quant_enable(parameter_quant_enable),
    .parameter_quant_shift(parameter_quant_shift),
    .parameter_bias(selected_bias),
    .weight_read_k_base(weight_read_k_base),
    .weight_read_c_base(weight_read_c_base),
    .weight_read_kernel_idx(weight_read_kernel_idx),
    .weight_out_lane_mask(weight_out_lane_mask),
    .weight_in_lane_mask(weight_in_lane_mask),
    .weight_mat_data(weight_mat_data),
    .bank_valid(parameter_bank_valid),
    .bank0_layer_id(),
    .bank1_layer_id(),
    .load_bank(),
    .compute_bank(),
    .compute_active(),
    .overlap_active(parameter_overlap_active)
  );

  descriptor_driven_job_controller #(
    .PC(PC),
    .PK(PK),
    .MAX_CIN(MAX_CIN),
    .MAX_COUT(MAX_COUT),
    .MAX_PIXELS(MAX_PIXELS),
    .DATA_W(DATA_W),
    .BIAS_W(BIAS_W),
    .OUT_W(OUT_W),
    .COUNT_W(COUNT_W)
  ) u_descriptor_driven_job_controller (
    .clk(clk),
    .rst_n(rst_n),
    .start(start),
    .model_active_valid(model_active_valid),
    .model_layer_count(model_layer_count),
    .descriptor_layer_index(descriptor_layer_index),
    .descriptor_valid(descriptor_valid),
    .descriptor_layer_id(descriptor_layer_id),
    .descriptor_opcode(descriptor_opcode),
    .descriptor_last_layer(descriptor_last_layer),
    .descriptor_bias_enable(descriptor_bias_enable),
    .descriptor_input_tensor_id(descriptor_input_tensor_id),
    .descriptor_output_tensor_id(descriptor_output_tensor_id),
    .descriptor_residual_tensor_id(descriptor_residual_tensor_id),
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
    .parameter_request(parameter_request),
    .parameter_release(parameter_release),
    .parameter_ready(parameter_ready),
    .parameter_use_scratchpad_weights(parameter_use_scratchpad_weights),
    .parameter_quant_enable(parameter_quant_enable),
    .parameter_quant_shift(parameter_quant_shift),
    .parameter_weights_1x1(unused_weights_1x1),
    .parameter_weights_3x3(unused_weights_3x3),
    .parameter_bias(selected_bias),
    .parameter_weight_read_k_base(weight_read_k_base),
    .parameter_weight_read_c_base(weight_read_c_base),
    .parameter_weight_read_kernel_idx(weight_read_kernel_idx),
    .parameter_weight_out_lane_mask(weight_out_lane_mask),
    .parameter_weight_in_lane_mask(weight_in_lane_mask),
    .parameter_weight_mat_data(weight_mat_data),
    .input_tensor(input_tensor),
    .output_tensor(output_tensor),
    .active_layer(active_layer),
    .busy(busy),
    .done(done),
    .error(error),
    .error_code(error_code),
    .error_layer(error_layer)
  );
endmodule
