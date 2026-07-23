`timescale 1ns/1ps

module descriptor_driven_job_controller #(
  parameter int PC         = 2,
  parameter int PK         = 4,
  parameter int MAX_CIN    = 16,
  parameter int MAX_COUT   = 16,
  parameter int MAX_PIXELS = 64,
  parameter int DATA_W     = 8,
  parameter int PROD_W     = 16,
  parameter int ACC_W      = 32,
  parameter int BIAS_W     = 32,
  parameter int OUT_W      = 8,
  parameter int COUNT_W    = 8,
  parameter int DIM_W      = 16,
  parameter int ADDR_W     = 32
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

  output logic parameter_request,
  output logic parameter_release,
  input  logic parameter_ready,
  input  logic parameter_use_scratchpad_weights,
  input  logic parameter_quant_enable,
  input  logic [4:0] parameter_quant_shift,
  input  logic signed [DATA_W-1:0] parameter_weights_1x1 [MAX_COUT][MAX_CIN],
  input  logic signed [DATA_W-1:0] parameter_weights_3x3 [MAX_COUT][MAX_CIN][9],
  input  logic signed [BIAS_W-1:0] parameter_bias [MAX_COUT],
  output logic [COUNT_W-1:0] parameter_weight_read_k_base,
  output logic [COUNT_W-1:0] parameter_weight_read_c_base,
  output logic [3:0] parameter_weight_read_kernel_idx,
  output logic [PK-1:0] parameter_weight_out_lane_mask,
  output logic [PC-1:0] parameter_weight_in_lane_mask,
  input  logic signed [DATA_W-1:0] parameter_weight_mat_data [PK][PC],

  input  logic signed [DATA_W-1:0] input_tensor [MAX_PIXELS*MAX_CIN],
  output logic signed [OUT_W-1:0] output_tensor [MAX_PIXELS*MAX_COUT],

  output logic [2:0] active_layer,
  output logic busy,
  output logic done,
  output logic error,
  output logic [7:0] error_code,
  output logic [2:0] error_layer
);
  import cnn_accel_abi_pkg::*;

  localparam logic [7:0] EXECUTION_OK = 8'd0;
  localparam logic [7:0] EXECUTION_NO_ACTIVE_MODEL = 8'd1;
  localparam logic [7:0] EXECUTION_BAD_LAYER_COUNT = 8'd2;
  localparam logic [7:0] EXECUTION_BAD_DESCRIPTOR = 8'd3;
  localparam logic [7:0] EXECUTION_BAD_GEOMETRY = 8'd4;
  localparam logic [7:0] EXECUTION_BAD_CHAIN = 8'd5;
  localparam logic [7:0] EXECUTION_UNSUPPORTED = 8'd6;

  typedef enum logic [2:0] {
    S_IDLE,
    S_LATCH_DESCRIPTOR,
    S_WAIT_PARAMETER,
    S_START_LAYER,
    S_WAIT_LAYER,
    S_STORE_LAYER,
    S_DONE
  } state_t;

  state_t state;
  logic [2:0] layer_index;
  logic [3:0] layer_count_q;
  logic scheduler_start;
  logic scheduler_done;

  logic [DIM_W-1:0] active_input_width;
  logic [DIM_W-1:0] active_input_height;
  logic [DIM_W-1:0] active_output_width;
  logic [DIM_W-1:0] active_output_height;
  logic [COUNT_W-1:0] active_input_channels;
  logic [COUNT_W-1:0] active_output_channels;
  logic [1:0] active_kernel_size;
  logic [1:0] active_stride;
  logic [1:0] active_padding;
  logic active_bias_enable;
  logic active_relu_enable;
  logic active_quant_enable;
  logic [4:0] active_quant_shift;
  logic [7:0] active_residual_mode;
  logic [15:0] active_input_tensor_id;
  logic [15:0] active_output_tensor_id;
  logic [15:0] active_residual_tensor_id;

  logic [15:0] model_input_width;
  logic [15:0] model_input_height;
  logic [15:0] model_input_channels;
  logic [15:0] model_input_tensor_id;
  logic [15:0] previous_output_width;
  logic [15:0] previous_output_height;
  logic [15:0] previous_output_channels;
  logic [15:0] previous_output_tensor_id;

  logic descriptor_is_final;
  logic descriptor_semantic_valid;
  logic [7:0] descriptor_error_code;
  logic [31:0] expected_output_width;
  logic [31:0] expected_output_height;
  logic [31:0] descriptor_output_pixels;

  logic signed [DATA_W-1:0] feature_bank0 [MAX_PIXELS*MAX_CIN];
  logic signed [DATA_W-1:0] feature_bank1 [MAX_PIXELS*MAX_CIN];
  logic signed [DATA_W-1:0] scheduler_activation [MAX_PIXELS*MAX_CIN];
  logic signed [OUT_W-1:0] scheduler_output [MAX_PIXELS*MAX_COUT];
  logic signed [DATA_W-1:0] unused_scratch_activation [PC];

  assign descriptor_layer_index = layer_index;
  assign active_layer = layer_index;
  assign busy = (state != S_IDLE) && (state != S_DONE);
  assign parameter_request = state == S_WAIT_PARAMETER;
  assign parameter_release = state == S_STORE_LAYER;
  assign scheduler_start = state == S_START_LAYER;
  assign descriptor_is_final = (4'(layer_index) + 4'd1) == layer_count_q;

  always_comb begin
    expected_output_width = 32'd0;
    expected_output_height = 32'd0;
    descriptor_output_pixels =
      32'(descriptor_output_width) * 32'(descriptor_output_height);

    if ((descriptor_stride_x != 0) &&
        ((32'(descriptor_input_width) + (32'(descriptor_padding_left) * 2)) >=
         32'(descriptor_kernel_width))) begin
      expected_output_width =
        ((32'(descriptor_input_width) + (32'(descriptor_padding_left) * 2) -
          32'(descriptor_kernel_width)) / 32'(descriptor_stride_x)) + 32'd1;
    end

    if ((descriptor_stride_y != 0) &&
        ((32'(descriptor_input_height) + (32'(descriptor_padding_top) * 2)) >=
         32'(descriptor_kernel_height))) begin
      expected_output_height =
        ((32'(descriptor_input_height) + (32'(descriptor_padding_top) * 2) -
          32'(descriptor_kernel_height)) / 32'(descriptor_stride_y)) + 32'd1;
    end
  end

  always_comb begin
    descriptor_semantic_valid = 1'b0;
    descriptor_error_code = EXECUTION_BAD_DESCRIPTOR;

    if (!descriptor_valid ||
        (descriptor_layer_id != 16'(layer_index)) ||
        (descriptor_last_layer != descriptor_is_final)) begin
      descriptor_error_code = EXECUTION_BAD_DESCRIPTOR;
    end else if (descriptor_opcode != OPCODE_CONV2D ||
                 !((descriptor_kernel_width == 1) ||
                   (descriptor_kernel_width == 3)) ||
                 (descriptor_kernel_height != descriptor_kernel_width) ||
                 !((descriptor_stride_x == 1) || (descriptor_stride_x == 2)) ||
                 (descriptor_stride_y != descriptor_stride_x) ||
                 (descriptor_padding_top > 1) ||
                 (descriptor_padding_bottom != descriptor_padding_top) ||
                 (descriptor_padding_left != descriptor_padding_top) ||
                 (descriptor_padding_right != descriptor_padding_top) ||
                 (descriptor_dilation_x != 1) ||
                 (descriptor_dilation_y != 1) ||
                 (descriptor_activation > ACTIVATION_RELU) ||
                 (descriptor_residual_mode > RESIDUAL_POST_QUANT_SUBTRACT)) begin
      descriptor_error_code = EXECUTION_UNSUPPORTED;
    end else if ((descriptor_input_width == 0) ||
                 (descriptor_input_height == 0) ||
                 (descriptor_output_width == 0) ||
                 (descriptor_output_height == 0) ||
                 (descriptor_input_channels == 0) ||
                 (32'(descriptor_input_channels) > 32'(MAX_CIN)) ||
                 (descriptor_output_channels == 0) ||
                 (32'(descriptor_output_channels) > 32'(MAX_COUT)) ||
                 (!descriptor_is_final &&
                  (32'(descriptor_output_channels) > 32'(MAX_CIN))) ||
                 (descriptor_output_pixels > MAX_PIXELS) ||
                 (expected_output_width != 32'(descriptor_output_width)) ||
                 (expected_output_height != 32'(descriptor_output_height))) begin
      descriptor_error_code = EXECUTION_BAD_GEOMETRY;
    end else if ((layer_index != 0) &&
                 ((descriptor_input_tensor_id != previous_output_tensor_id) ||
                  (descriptor_input_width != previous_output_width) ||
                  (descriptor_input_height != previous_output_height) ||
                  (descriptor_input_channels != previous_output_channels))) begin
      descriptor_error_code = EXECUTION_BAD_CHAIN;
    end else if ((descriptor_residual_mode != RESIDUAL_NONE) &&
                 (!descriptor_is_final ||
                  (descriptor_residual_tensor_id !=
                   ((layer_index == 0) ? descriptor_input_tensor_id :
                    model_input_tensor_id)) ||
                  (descriptor_output_width !=
                   ((layer_index == 0) ? descriptor_input_width :
                    model_input_width)) ||
                  (descriptor_output_height !=
                   ((layer_index == 0) ? descriptor_input_height :
                    model_input_height)) ||
                  (descriptor_output_channels !=
                   ((layer_index == 0) ? descriptor_input_channels :
                    model_input_channels)))) begin
      descriptor_error_code = EXECUTION_BAD_CHAIN;
    end else begin
      descriptor_semantic_valid = 1'b1;
      descriptor_error_code = EXECUTION_OK;
    end
  end

  always_comb begin
    for (int i = 0; i < MAX_PIXELS*MAX_CIN; i++) begin
      if (layer_index == 0) begin
        scheduler_activation[i] = input_tensor[i];
      end else if (layer_index[0]) begin
        scheduler_activation[i] = feature_bank0[i];
      end else begin
        scheduler_activation[i] = feature_bank1[i];
      end
    end

    for (int lane = 0; lane < PC; lane++) begin
      unused_scratch_activation[lane] = '0;
    end
  end

  function automatic logic signed [OUT_W-1:0] saturate_int8(
    input logic signed [ACC_W-1:0] value
  );
    begin
      if (value > 32'sd127) begin
        return 8'sd127;
      end
      if (value < -32'sd128) begin
        return -8'sd128;
      end
      return value[OUT_W-1:0];
    end
  endfunction

  single_layer_scheduler #(
    .PC(PC),
    .PK(PK),
    .MAX_CIN(MAX_CIN),
    .MAX_COUT(MAX_COUT),
    .MAX_PIXELS(MAX_PIXELS),
    .DATA_W(DATA_W),
    .PROD_W(PROD_W),
    .ACC_W(ACC_W),
    .BIAS_W(BIAS_W),
    .OUT_W(OUT_W),
    .COUNT_W(COUNT_W),
    .DIM_W(DIM_W),
    .ADDR_W(ADDR_W),
    .MIRROR_OUTPUT_TENSOR(1'b1)
  ) u_single_layer_scheduler (
    .clk(clk),
    .rst_n(rst_n),
    .start(scheduler_start),
    .input_width(active_input_width),
    .input_height(active_input_height),
    .output_width(active_output_width),
    .output_height(active_output_height),
    .kernel_size(active_kernel_size),
    .stride(active_stride),
    .padding(active_padding),
    .cin(active_input_channels),
    .cout(active_output_channels),
    .bias_enable(active_bias_enable),
    .relu_enable(active_relu_enable),
    .quant_enable(active_quant_enable),
    .quant_shift(active_quant_shift),
    .activation(scheduler_activation),
    .weights_1x1(parameter_weights_1x1),
    .weights_3x3(parameter_weights_3x3),
    .bias(parameter_bias),
    .use_scratchpad_operands(1'b0),
    .use_scratchpad_weights(parameter_use_scratchpad_weights),
    .scratch_activation_read_pixel(),
    .scratch_activation_read_c_base(),
    .scratch_activation_lane_mask(),
    .scratch_activation_lane_data(unused_scratch_activation),
    .scratch_weight_read_k_base(parameter_weight_read_k_base),
    .scratch_weight_read_c_base(parameter_weight_read_c_base),
    .scratch_weight_read_kernel_idx(parameter_weight_read_kernel_idx),
    .scratch_weight_out_lane_mask(parameter_weight_out_lane_mask),
    .scratch_weight_in_lane_mask(parameter_weight_in_lane_mask),
    .scratch_weight_mat_data(parameter_weight_mat_data),
    .output_tensor(scheduler_output),
    .output_pixel_valid(),
    .output_pixel_ready(1'b1),
    .output_pixel_index(),
    .output_pixel_channels(),
    .output_pixel_data(),
    .output_pixel_last(),
    .current_x(),
    .current_y(),
    .busy(),
    .done(scheduler_done)
  );

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state <= S_IDLE;
      layer_index <= '0;
      layer_count_q <= '0;
      active_input_width <= '0;
      active_input_height <= '0;
      active_output_width <= '0;
      active_output_height <= '0;
      active_input_channels <= '0;
      active_output_channels <= '0;
      active_kernel_size <= '0;
      active_stride <= '0;
      active_padding <= '0;
      active_bias_enable <= 1'b0;
      active_relu_enable <= 1'b0;
      active_quant_enable <= 1'b0;
      active_quant_shift <= '0;
      active_residual_mode <= RESIDUAL_NONE;
      active_input_tensor_id <= '0;
      active_output_tensor_id <= '0;
      active_residual_tensor_id <= NO_TENSOR_ID;
      model_input_width <= '0;
      model_input_height <= '0;
      model_input_channels <= '0;
      model_input_tensor_id <= '0;
      previous_output_width <= '0;
      previous_output_height <= '0;
      previous_output_channels <= '0;
      previous_output_tensor_id <= '0;
      done <= 1'b0;
      error <= 1'b0;
      error_code <= EXECUTION_OK;
      error_layer <= '0;

      for (int i = 0; i < MAX_PIXELS*MAX_CIN; i++) begin
        feature_bank0[i] <= '0;
        feature_bank1[i] <= '0;
      end
      for (int i = 0; i < MAX_PIXELS*MAX_COUT; i++) begin
        output_tensor[i] <= '0;
      end
    end else begin
      done <= 1'b0;

      case (state)
        S_IDLE: begin
          if (start) begin
            layer_index <= '0;
            error <= 1'b0;
            error_code <= EXECUTION_OK;
            error_layer <= '0;

            if (!model_active_valid) begin
              error <= 1'b1;
              error_code <= EXECUTION_NO_ACTIVE_MODEL;
              state <= S_DONE;
            end else if ((model_layer_count == 0) ||
                         (32'(model_layer_count) > 32'(MAX_LAYERS))) begin
              error <= 1'b1;
              error_code <= EXECUTION_BAD_LAYER_COUNT;
              state <= S_DONE;
            end else begin
              layer_count_q <= model_layer_count[3:0];
              state <= S_LATCH_DESCRIPTOR;
            end
          end
        end

        S_LATCH_DESCRIPTOR: begin
          if (!descriptor_semantic_valid) begin
            error <= 1'b1;
            error_code <= descriptor_error_code;
            error_layer <= layer_index;
            state <= S_DONE;
          end else begin
            active_input_width <= DIM_W'(descriptor_input_width);
            active_input_height <= DIM_W'(descriptor_input_height);
            active_output_width <= DIM_W'(descriptor_output_width);
            active_output_height <= DIM_W'(descriptor_output_height);
            active_input_channels <= COUNT_W'(descriptor_input_channels);
            active_output_channels <= COUNT_W'(descriptor_output_channels);
            active_kernel_size <= 2'(descriptor_kernel_width);
            active_stride <= 2'(descriptor_stride_x);
            active_padding <= 2'(descriptor_padding_left);
            active_bias_enable <= descriptor_bias_enable;
            active_relu_enable <= descriptor_activation == ACTIVATION_RELU;
            active_residual_mode <= descriptor_residual_mode;
            active_input_tensor_id <= descriptor_input_tensor_id;
            active_output_tensor_id <= descriptor_output_tensor_id;
            active_residual_tensor_id <= descriptor_residual_tensor_id;

            if (layer_index == 0) begin
              model_input_width <= descriptor_input_width;
              model_input_height <= descriptor_input_height;
              model_input_channels <= descriptor_input_channels;
              model_input_tensor_id <= descriptor_input_tensor_id;
            end
            state <= S_WAIT_PARAMETER;
          end
        end

        S_WAIT_PARAMETER: begin
          if (parameter_ready) begin
            active_quant_enable <= parameter_quant_enable;
            active_quant_shift <= parameter_quant_shift;
            state <= S_START_LAYER;
          end
        end

        S_START_LAYER: begin
          state <= S_WAIT_LAYER;
        end

        S_WAIT_LAYER: begin
          if (scheduler_done) begin
            state <= S_STORE_LAYER;
          end
        end

        S_STORE_LAYER: begin
          for (int p = 0; p < MAX_PIXELS; p++) begin
            for (int c = 0; c < MAX_COUT; c++) begin
              if (!descriptor_is_final && (c < active_output_channels)) begin
                if (!layer_index[0]) begin
                  feature_bank0[(p * MAX_CIN) + c] <=
                    DATA_W'(scheduler_output[(p * MAX_COUT) + c]);
                end else begin
                  feature_bank1[(p * MAX_CIN) + c] <=
                    DATA_W'(scheduler_output[(p * MAX_COUT) + c]);
                end
              end

              if (descriptor_is_final) begin
                if ((p < (active_output_width * active_output_height)) &&
                    (c < active_output_channels)) begin
                  logic signed [ACC_W-1:0] residual_value;
                  residual_value =
                    {{(ACC_W-OUT_W){scheduler_output[(p * MAX_COUT) + c][OUT_W-1]}},
                     scheduler_output[(p * MAX_COUT) + c]};
                  if (active_residual_mode == RESIDUAL_POST_QUANT_ADD) begin
                    residual_value =
                      {{(ACC_W-DATA_W){input_tensor[(p * MAX_CIN) + c][DATA_W-1]}},
                       input_tensor[(p * MAX_CIN) + c]} + residual_value;
                  end else if (active_residual_mode == RESIDUAL_POST_QUANT_SUBTRACT) begin
                    residual_value =
                      {{(ACC_W-DATA_W){input_tensor[(p * MAX_CIN) + c][DATA_W-1]}},
                       input_tensor[(p * MAX_CIN) + c]} - residual_value;
                  end
                  output_tensor[(p * MAX_COUT) + c] <= saturate_int8(residual_value);
                end else begin
                  output_tensor[(p * MAX_COUT) + c] <= '0;
                end
              end
            end
          end

          previous_output_width <= active_output_width;
          previous_output_height <= active_output_height;
          previous_output_channels <= 16'(active_output_channels);
          previous_output_tensor_id <= active_output_tensor_id;

          if (descriptor_is_final) begin
            state <= S_DONE;
          end else begin
            layer_index <= layer_index + 3'd1;
            state <= S_LATCH_DESCRIPTOR;
          end
        end

        S_DONE: begin
          done <= 1'b1;
          state <= S_IDLE;
        end

        default: begin
          error <= 1'b1;
          error_code <= EXECUTION_BAD_DESCRIPTOR;
          error_layer <= layer_index;
          state <= S_DONE;
        end
      endcase
    end
  end
endmodule
