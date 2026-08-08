`timescale 1ns/1ps

module multi_layer_job_controller #(
  parameter int PC          = 4,
  parameter int PK          = 8,
  parameter int MAX_CIN     = 16,
  parameter int MAX_COUT    = 16,
  parameter int MAX_PIXELS  = 64,
  parameter int INPUT_C     = 3,
  parameter int HIDDEN_C    = 16,
  parameter int OUTPUT_C    = 3,
  parameter int DATA_W      = 8,
  parameter int PROD_W      = 16,
  parameter int ACC_W       = 32,
  parameter int BIAS_W      = 32,
  parameter int OUT_W       = 8,
  parameter int COUNT_W     = 8,
  parameter int DIM_W       = 16,
  parameter int ADDR_W      = 32,
  parameter bit DIRECT_ARRAY_OPERANDS = 1'b1,
  parameter bit MIRROR_SCHEDULER_OUTPUT = 1'b1,
  parameter bit STREAM_INTERMEDIATE_OUTPUTS = 1'b0,
  parameter bit STREAM_FINAL_OUTPUTS = 1'b0
)(
  input  logic clk,
  input  logic rst_n,

  input  logic start,
  input  logic final_residual_enable,
  input  logic [DIM_W-1:0] image_width,
  input  logic [DIM_W-1:0] image_height,
  input  logic [2:0] layer_ready,

  input  logic signed [DATA_W-1:0] input_tensor [MAX_PIXELS*MAX_CIN],
  input  logic signed [DATA_W-1:0] weights_l0 [HIDDEN_C][INPUT_C][9],
  input  logic signed [DATA_W-1:0] weights_l1 [HIDDEN_C][HIDDEN_C][9],
  input  logic signed [DATA_W-1:0] weights_l2 [OUTPUT_C][HIDDEN_C][9],
  input  logic signed [BIAS_W-1:0] bias_l0 [HIDDEN_C],
  input  logic signed [BIAS_W-1:0] bias_l1 [HIDDEN_C],
  input  logic signed [BIAS_W-1:0] bias_l2 [OUTPUT_C],

  input  logic use_scratchpad_operands,
  input  logic scratch_input_write_enable,
  input  logic [ADDR_W-1:0] scratch_input_write_pixel,
  input  logic [COUNT_W-1:0] scratch_input_write_channel,
  input  logic signed [DATA_W-1:0] scratch_input_write_data,
  input  logic scratch_weight_write_enable,
  input  logic [1:0] scratch_weight_write_layer,
  input  logic [COUNT_W-1:0] scratch_weight_write_out_channel,
  input  logic [COUNT_W-1:0] scratch_weight_write_in_channel,
  input  logic [3:0] scratch_weight_write_kernel_idx,
  input  logic signed [DATA_W-1:0] scratch_weight_write_data,

  output logic signed [OUT_W-1:0] output_tensor [MAX_PIXELS*MAX_COUT],
  output logic output_pixel_valid,
  input  logic output_pixel_ready,
  output logic [ADDR_W-1:0] output_pixel_index,
  output logic [COUNT_W-1:0] output_pixel_channels,
  output logic signed [OUT_W-1:0] output_pixel_data [MAX_COUT],
  output logic output_pixel_last,
  output logic [1:0] active_layer,
  output logic activation_read_bank,
  output logic activation_write_bank,
  output logic waiting_for_layer,
  output logic busy,
  output logic done
);

  typedef enum logic [3:0] {
    S_IDLE,
    S_LATCH_LAYER,
    S_START_LAYER,
    S_WAIT_LAYER,
    S_STORE_LAYER,
    S_WRITE_SCRATCH,
    S_NEXT_LAYER,
    S_DONE
  } state_t;

  state_t state;

  logic [1:0] layer_index;
  logic scheduler_start;
  logic scheduler_done;
  logic current_layer_ready;
  logic descriptor_valid;
  logic [DIM_W-1:0] desc_input_width;
  logic [DIM_W-1:0] desc_input_height;
  logic [COUNT_W-1:0] desc_input_channels;
  logic [COUNT_W-1:0] desc_output_channels;
  logic [1:0] desc_kernel_size;
  logic [1:0] desc_stride;
  logic [1:0] desc_padding;
  logic desc_bias_enable;
  logic desc_relu_enable;
  logic desc_quant_enable;
  logic [4:0] desc_quant_shift;
  logic desc_residual_enable;
  logic active_descriptor_valid;
  logic [DIM_W-1:0] active_input_width;
  logic [DIM_W-1:0] active_input_height;
  logic [COUNT_W-1:0] active_input_channels;
  logic [COUNT_W-1:0] active_output_channels;
  logic [1:0] active_kernel_size;
  logic [1:0] active_stride;
  logic [1:0] active_padding;
  logic active_bias_enable;
  logic active_relu_enable;
  logic active_quant_enable;
  logic [4:0] active_quant_shift;
  logic active_residual_enable;

  logic signed [DATA_W-1:0] feature_bank0 [MAX_PIXELS*MAX_CIN];
  logic signed [DATA_W-1:0] feature_bank1 [MAX_PIXELS*MAX_CIN];
  logic signed [DATA_W-1:0] scheduler_activation [MAX_PIXELS*MAX_CIN];
  logic signed [DATA_W-1:0] scheduler_weights_1x1 [MAX_COUT][MAX_CIN];
  logic signed [DATA_W-1:0] scheduler_weights_3x3 [MAX_COUT][MAX_CIN][9];
  logic signed [BIAS_W-1:0] scheduler_bias [MAX_COUT];
  logic signed [31:0] legacy_quant_multiplier [MAX_COUT];
  logic [5:0] legacy_quant_shift [MAX_COUT];
  logic signed [OUT_W-1:0] scheduler_output [MAX_PIXELS*MAX_COUT];
  logic [ADDR_W-1:0] scratch_activation_read_pixel;
  logic [COUNT_W-1:0] scratch_activation_read_c_base;
  logic [PC-1:0] scratch_activation_lane_mask;
  logic signed [DATA_W-1:0] scratch_activation_input_lane_data [PC];
  logic signed [DATA_W-1:0] scratch_activation_feature0_lane_data [PC];
  logic signed [DATA_W-1:0] scratch_activation_feature1_lane_data [PC];
  logic signed [DATA_W-1:0] scheduler_scratch_activation_lane_data [PC];
  logic [COUNT_W-1:0] scratch_weight_read_k_base;
  logic [COUNT_W-1:0] scratch_weight_read_c_base;
  logic [3:0] scratch_weight_read_kernel_idx;
  logic [PK-1:0] scratch_weight_out_lane_mask;
  logic [PC-1:0] scratch_weight_in_lane_mask;
  logic signed [DATA_W-1:0] scratch_weight_l0_mat_data [PK][PC];
  logic signed [DATA_W-1:0] scratch_weight_l1_mat_data [PK][PC];
  logic signed [DATA_W-1:0] scratch_weight_l2_mat_data [PK][PC];
  logic signed [DATA_W-1:0] scheduler_scratch_weight_mat_data [PK][PC];
  logic [ADDR_W-1:0] scratch_store_pixel;
  logic [COUNT_W-1:0] scratch_store_channel;
  logic [ADDR_W-1:0] scratch_store_pixel_count;
  logic scratch_store_valid;
  logic scratch_store_last;
  logic scratch_feature0_write_enable;
  logic scratch_feature1_write_enable;
  logic signed [DATA_W-1:0] scratch_feature_write_data;
  logic scheduler_output_pixel_valid;
  logic scheduler_output_pixel_ready;
  logic [ADDR_W-1:0] scheduler_output_pixel_index;
  logic [COUNT_W-1:0] scheduler_output_pixel_channels;
  logic signed [OUT_W-1:0] scheduler_output_pixel_data [MAX_COUT];
  logic scheduler_output_pixel_last;
  logic stream_store_pending;
  logic [ADDR_W-1:0] stream_store_pixel;
  logic [COUNT_W-1:0] stream_store_channel;
  logic [COUNT_W-1:0] stream_store_channels;
  logic signed [OUT_W-1:0] stream_store_data [MAX_COUT];
  logic stream_store_valid;
  logic stream_store_last_channel;
  logic stream_intermediate_mode;
  logic stream_final_mode;
  logic scheduler_done_seen;
  logic final_output_stage0_valid;
  logic [ADDR_W-1:0] final_output_stage0_index;
  logic final_output_stage0_last;
  logic signed [OUT_W-1:0] final_output_stage0_data [MAX_COUT];
  logic final_output_stage1_valid;
  logic [ADDR_W-1:0] final_output_stage1_index;
  logic final_output_stage1_last;
  logic signed [OUT_W-1:0] final_output_stage1_data [MAX_COUT];
  logic signed [OUT_W-1:0] final_output_stage1_residual [MAX_COUT];
  logic final_output_stage2_valid;
  logic [ADDR_W-1:0] final_output_stage2_index;
  logic final_output_stage2_last;
  logic signed [OUT_W-1:0] final_output_stage2_data [MAX_COUT];
  logic final_output_drained;

  assign active_layer = layer_index;
  assign activation_read_bank = (layer_index == 2'd2);
  assign activation_write_bank = (layer_index == 2'd1);
  assign waiting_for_layer =
    (state == S_START_LAYER) && active_descriptor_valid && !current_layer_ready;
  assign busy = (state != S_IDLE) && (state != S_DONE);
  assign scheduler_start =
    (state == S_START_LAYER) && active_descriptor_valid && current_layer_ready;
  assign stream_intermediate_mode =
    (STREAM_INTERMEDIATE_OUTPUTS != 0) && use_scratchpad_operands;
  assign stream_final_mode =
    (STREAM_FINAL_OUTPUTS != 0) && use_scratchpad_operands;
  assign scratch_store_pixel_count =
    ADDR_W'(image_width) * ADDR_W'(image_height);
  assign scratch_store_valid =
    use_scratchpad_operands &&
    (layer_index != 2'd2) &&
    (scratch_store_pixel < scratch_store_pixel_count) &&
    (scratch_store_channel < active_output_channels) &&
    (!stream_intermediate_mode) &&
    (state == S_WRITE_SCRATCH);
  assign stream_store_valid =
    stream_intermediate_mode &&
    stream_store_pending &&
    (layer_index != 2'd2) &&
    (stream_store_channel < stream_store_channels);
  assign scratch_store_last =
    scratch_store_valid &&
    (scratch_store_pixel == (scratch_store_pixel_count - ADDR_W'(1))) &&
    (scratch_store_channel == (active_output_channels - COUNT_W'(1)));
  assign stream_store_last_channel =
    stream_store_valid &&
    (stream_store_channel == (stream_store_channels - COUNT_W'(1)));
  assign final_output_drained =
    !final_output_stage0_valid && !final_output_stage1_valid &&
    !final_output_stage2_valid;
  assign scratch_feature0_write_enable =
    (scratch_store_valid || stream_store_valid) && (layer_index == 2'd0);
  assign scratch_feature1_write_enable =
    (scratch_store_valid || stream_store_valid) && (layer_index == 2'd1);
  assign scratch_feature_write_data =
    stream_store_valid ? DATA_W'(stream_store_data[int'(stream_store_channel)]) :
    scratch_store_valid ?
      DATA_W'(scheduler_output[(scratch_store_pixel * ADDR_W'(MAX_COUT)) +
                               ADDR_W'(scratch_store_channel)]) :
    '0;
  assign output_pixel_valid =
    stream_final_mode &&
    (layer_index == 2'd2) &&
    final_output_stage2_valid;
  assign output_pixel_index = final_output_stage2_index;
  assign output_pixel_channels = COUNT_W'(OUTPUT_C);
  assign output_pixel_last = final_output_stage2_last;
  assign scheduler_output_pixel_ready =
    (stream_intermediate_mode && (layer_index != 2'd2)) ?
      ((state == S_WAIT_LAYER) && !stream_store_pending) :
    (stream_final_mode && (layer_index == 2'd2)) ?
      ((state == S_WAIT_LAYER) && !final_output_stage0_valid) :
      1'b1;

  always_comb begin
    for (int co = 0; co < MAX_COUT; co++) begin
      output_pixel_data[co] = final_output_stage2_data[co];
    end
  end

  always_comb begin
    unique case (layer_index)
      2'd0: current_layer_ready = layer_ready[0];
      2'd1: current_layer_ready = layer_ready[1];
      2'd2: current_layer_ready = layer_ready[2];
      default: current_layer_ready = 1'b0;
    endcase
  end

  function automatic logic signed [OUT_W-1:0] sat8(input logic signed [ACC_W-1:0] value);
    begin
      if (value > 32'sd127) begin
        return 8'sd127;
      end else if (value < -32'sd128) begin
        return -8'sd128;
      end else begin
        return value[OUT_W-1:0];
      end
    end
  endfunction

  function automatic logic signed [OUT_W-1:0] residual_sub(
    input logic signed [DATA_W-1:0] base,
    input logic signed [OUT_W-1:0] predicted
  );
    logic signed [ACC_W-1:0] value;
    begin
      value = {{(ACC_W-DATA_W){base[DATA_W-1]}}, base} -
              {{(ACC_W-OUT_W){predicted[OUT_W-1]}}, predicted};
      return sat8(value);
    end
  endfunction

  denoise_layer_descriptor_rom #(
    .DIM_W(DIM_W),
    .CH_W(COUNT_W),
    .FINAL_RESIDUAL_ENABLE(1'b1)
  ) u_denoise_layer_descriptor_rom (
    .layer_index(layer_index),
    .image_width(image_width),
    .image_height(image_height),
    .valid(descriptor_valid),
    .input_base(),
    .output_base(),
    .weight_base(),
    .bias_base(),
    .input_width(desc_input_width),
    .input_height(desc_input_height),
    .input_channels(desc_input_channels),
    .output_channels(desc_output_channels),
    .kernel_size(desc_kernel_size),
    .stride(desc_stride),
    .padding(desc_padding),
    .bias_enable(desc_bias_enable),
    .relu_enable(desc_relu_enable),
    .quant_enable(desc_quant_enable),
    .quant_shift(desc_quant_shift),
    .residual_enable(desc_residual_enable),
    .residual_input_base()
  );

  always_comb begin
    for (int i = 0; i < MAX_PIXELS*MAX_CIN; i++) begin
      scheduler_activation[i] = '0;
      if (DIRECT_ARRAY_OPERANDS) begin
        unique case (layer_index)
          2'd0: scheduler_activation[i] = input_tensor[i];
          2'd1: scheduler_activation[i] = feature_bank0[i];
          2'd2: scheduler_activation[i] = feature_bank1[i];
          default: scheduler_activation[i] = '0;
        endcase
      end
    end

    for (int co = 0; co < MAX_COUT; co++) begin
      legacy_quant_multiplier[co] = 32'sd1;
      legacy_quant_shift[co] = '0;
      unique case (layer_index)
        2'd0: scheduler_bias[co] = (co < HIDDEN_C) ? bias_l0[co] : '0;
        2'd1: scheduler_bias[co] = (co < HIDDEN_C) ? bias_l1[co] : '0;
        2'd2: scheduler_bias[co] = (co < OUTPUT_C) ? bias_l2[co] : '0;
        default: scheduler_bias[co] = '0;
      endcase

      for (int ci = 0; ci < MAX_CIN; ci++) begin
        scheduler_weights_1x1[co][ci] = '0;

        for (int k = 0; k < 9; k++) begin
          scheduler_weights_3x3[co][ci][k] = '0;
          if (DIRECT_ARRAY_OPERANDS) begin
            unique case (layer_index)
              2'd0: begin
                if ((co < HIDDEN_C) && (ci < INPUT_C)) begin
                  scheduler_weights_3x3[co][ci][k] = weights_l0[co][ci][k];
                end else begin
                  scheduler_weights_3x3[co][ci][k] = '0;
                end
              end

              2'd1: begin
                if ((co < HIDDEN_C) && (ci < HIDDEN_C)) begin
                  scheduler_weights_3x3[co][ci][k] = weights_l1[co][ci][k];
                end else begin
                  scheduler_weights_3x3[co][ci][k] = '0;
                end
              end

              2'd2: begin
                if ((co < OUTPUT_C) && (ci < HIDDEN_C)) begin
                  scheduler_weights_3x3[co][ci][k] = weights_l2[co][ci][k];
                end else begin
                  scheduler_weights_3x3[co][ci][k] = '0;
                end
              end

              default: begin
                scheduler_weights_3x3[co][ci][k] = '0;
              end
            endcase
          end
        end
      end
    end

    for (int pc = 0; pc < PC; pc++) begin
      unique case (layer_index)
        2'd0: scheduler_scratch_activation_lane_data[pc] =
          scratch_activation_input_lane_data[pc];
        2'd1: scheduler_scratch_activation_lane_data[pc] =
          scratch_activation_feature0_lane_data[pc];
        2'd2: scheduler_scratch_activation_lane_data[pc] =
          scratch_activation_feature1_lane_data[pc];
        default: scheduler_scratch_activation_lane_data[pc] = '0;
      endcase
    end

    for (int pk = 0; pk < PK; pk++) begin
      for (int pc = 0; pc < PC; pc++) begin
        unique case (layer_index)
          2'd0: scheduler_scratch_weight_mat_data[pk][pc] =
            scratch_weight_l0_mat_data[pk][pc];
          2'd1: scheduler_scratch_weight_mat_data[pk][pc] =
            scratch_weight_l1_mat_data[pk][pc];
          2'd2: scheduler_scratch_weight_mat_data[pk][pc] =
            scratch_weight_l2_mat_data[pk][pc];
          default: scheduler_scratch_weight_mat_data[pk][pc] = '0;
        endcase
      end
    end
  end

  banked_activation_scratchpad #(
    .PC(PC),
    .MAX_PIXELS(MAX_PIXELS),
    .MAX_C(MAX_CIN),
    .DATA_W(DATA_W),
    .DIM_W(DIM_W),
    .COUNT_W(COUNT_W),
    .ADDR_W(ADDR_W)
  ) u_input_activation_scratchpad (
    .clk(clk),
    .write_enable(scratch_input_write_enable),
    .write_pixel(scratch_input_write_pixel),
    .write_channel(scratch_input_write_channel),
    .write_data(scratch_input_write_data),
    .read_pixel(scratch_activation_read_pixel),
    .read_c_base(scratch_activation_read_c_base),
    .lane_mask(scratch_activation_lane_mask),
    .lane_data(scratch_activation_input_lane_data),
    .debug_read_pixel('0),
    .debug_read_channel('0),
    .debug_read_data()
  );

  banked_activation_scratchpad #(
    .PC(PC),
    .MAX_PIXELS(MAX_PIXELS),
    .MAX_C(MAX_CIN),
    .DATA_W(DATA_W),
    .DIM_W(DIM_W),
    .COUNT_W(COUNT_W),
    .ADDR_W(ADDR_W)
  ) u_feature0_activation_scratchpad (
    .clk(clk),
    .write_enable(scratch_feature0_write_enable),
    .write_pixel(stream_store_valid ? stream_store_pixel : scratch_store_pixel),
    .write_channel(stream_store_valid ? stream_store_channel : scratch_store_channel),
    .write_data(scratch_feature_write_data),
    .read_pixel(scratch_activation_read_pixel),
    .read_c_base(scratch_activation_read_c_base),
    .lane_mask(scratch_activation_lane_mask),
    .lane_data(scratch_activation_feature0_lane_data),
    .debug_read_pixel('0),
    .debug_read_channel('0),
    .debug_read_data()
  );

  banked_activation_scratchpad #(
    .PC(PC),
    .MAX_PIXELS(MAX_PIXELS),
    .MAX_C(MAX_CIN),
    .DATA_W(DATA_W),
    .DIM_W(DIM_W),
    .COUNT_W(COUNT_W),
    .ADDR_W(ADDR_W)
  ) u_feature1_activation_scratchpad (
    .clk(clk),
    .write_enable(scratch_feature1_write_enable),
    .write_pixel(stream_store_valid ? stream_store_pixel : scratch_store_pixel),
    .write_channel(stream_store_valid ? stream_store_channel : scratch_store_channel),
    .write_data(scratch_feature_write_data),
    .read_pixel(scratch_activation_read_pixel),
    .read_c_base(scratch_activation_read_c_base),
    .lane_mask(scratch_activation_lane_mask),
    .lane_data(scratch_activation_feature1_lane_data),
    .debug_read_pixel('0),
    .debug_read_channel('0),
    .debug_read_data()
  );

  banked_weight_scratchpad #(
    .PC(PC),
    .PK(PK),
    .MAX_CIN(MAX_CIN),
    .MAX_COUT(MAX_COUT),
    .DATA_W(DATA_W),
    .COUNT_W(COUNT_W),
    .ADDR_W(ADDR_W)
  ) u_weight_l0_scratchpad (
    .clk(clk),
    .write_enable(scratch_weight_write_enable && (scratch_weight_write_layer == 2'd0)),
    .write_out_channel(scratch_weight_write_out_channel),
    .write_in_channel(scratch_weight_write_in_channel),
    .write_kernel_idx(scratch_weight_write_kernel_idx),
    .write_data(scratch_weight_write_data),
    .read_k_base(scratch_weight_read_k_base),
    .read_c_base(scratch_weight_read_c_base),
    .read_kernel_idx(scratch_weight_read_kernel_idx),
    .out_lane_mask(scratch_weight_out_lane_mask),
    .in_lane_mask(scratch_weight_in_lane_mask),
    .weight_mat(scratch_weight_l0_mat_data),
    .debug_out_channel('0),
    .debug_in_channel('0),
    .debug_kernel_idx('0),
    .debug_read_data()
  );

  banked_weight_scratchpad #(
    .PC(PC),
    .PK(PK),
    .MAX_CIN(MAX_CIN),
    .MAX_COUT(MAX_COUT),
    .DATA_W(DATA_W),
    .COUNT_W(COUNT_W),
    .ADDR_W(ADDR_W)
  ) u_weight_l1_scratchpad (
    .clk(clk),
    .write_enable(scratch_weight_write_enable && (scratch_weight_write_layer == 2'd1)),
    .write_out_channel(scratch_weight_write_out_channel),
    .write_in_channel(scratch_weight_write_in_channel),
    .write_kernel_idx(scratch_weight_write_kernel_idx),
    .write_data(scratch_weight_write_data),
    .read_k_base(scratch_weight_read_k_base),
    .read_c_base(scratch_weight_read_c_base),
    .read_kernel_idx(scratch_weight_read_kernel_idx),
    .out_lane_mask(scratch_weight_out_lane_mask),
    .in_lane_mask(scratch_weight_in_lane_mask),
    .weight_mat(scratch_weight_l1_mat_data),
    .debug_out_channel('0),
    .debug_in_channel('0),
    .debug_kernel_idx('0),
    .debug_read_data()
  );

  banked_weight_scratchpad #(
    .PC(PC),
    .PK(PK),
    .MAX_CIN(MAX_CIN),
    .MAX_COUT(MAX_COUT),
    .DATA_W(DATA_W),
    .COUNT_W(COUNT_W),
    .ADDR_W(ADDR_W)
  ) u_weight_l2_scratchpad (
    .clk(clk),
    .write_enable(scratch_weight_write_enable && (scratch_weight_write_layer == 2'd2)),
    .write_out_channel(scratch_weight_write_out_channel),
    .write_in_channel(scratch_weight_write_in_channel),
    .write_kernel_idx(scratch_weight_write_kernel_idx),
    .write_data(scratch_weight_write_data),
    .read_k_base(scratch_weight_read_k_base),
    .read_c_base(scratch_weight_read_c_base),
    .read_kernel_idx(scratch_weight_read_kernel_idx),
    .out_lane_mask(scratch_weight_out_lane_mask),
    .in_lane_mask(scratch_weight_in_lane_mask),
    .weight_mat(scratch_weight_l2_mat_data),
    .debug_out_channel('0),
    .debug_in_channel('0),
    .debug_kernel_idx('0),
    .debug_read_data()
  );

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
    .MIRROR_OUTPUT_TENSOR(MIRROR_SCHEDULER_OUTPUT)
  ) u_single_layer_scheduler (
    .clk(clk),
    .rst_n(rst_n),
    .start(scheduler_start),
    .input_width(active_input_width),
    .input_height(active_input_height),
    .output_width(image_width),
    .output_height(image_height),
    .kernel_size(active_kernel_size),
    .stride(active_stride),
    .padding(active_padding),
    .cin(active_input_channels),
    .cout(active_output_channels),
    .bias_enable(active_bias_enable),
    .relu_enable(active_relu_enable),
    .quant_enable(active_quant_enable),
    .quant_shift(active_quant_shift),
    .per_channel_quant_enable(1'b0),
    .quant_multiplier(legacy_quant_multiplier),
    .per_channel_quant_shift(legacy_quant_shift),
    .output_zero_point(8'sd0),
    .activation(scheduler_activation),
    .weights_1x1(scheduler_weights_1x1),
    .weights_3x3(scheduler_weights_3x3),
    .bias(scheduler_bias),
 .use_scratchpad_operands(use_scratchpad_operands),
 .use_scratchpad_weights(use_scratchpad_operands),
    .scratch_activation_read_pixel(scratch_activation_read_pixel),
    .scratch_activation_read_c_base(scratch_activation_read_c_base),
    .scratch_activation_lane_mask(scratch_activation_lane_mask),
    .scratch_activation_lane_data(scheduler_scratch_activation_lane_data),
    .scratch_weight_read_k_base(scratch_weight_read_k_base),
    .scratch_weight_read_c_base(scratch_weight_read_c_base),
    .scratch_weight_read_kernel_idx(scratch_weight_read_kernel_idx),
    .scratch_weight_out_lane_mask(scratch_weight_out_lane_mask),
    .scratch_weight_in_lane_mask(scratch_weight_in_lane_mask),
    .scratch_weight_mat_data(scheduler_scratch_weight_mat_data),
    .output_tensor(scheduler_output),
    .output_pixel_valid(scheduler_output_pixel_valid),
    .output_pixel_ready(scheduler_output_pixel_ready),
    .output_pixel_index(scheduler_output_pixel_index),
    .output_pixel_channels(scheduler_output_pixel_channels),
    .output_pixel_data(scheduler_output_pixel_data),
    .output_pixel_last(scheduler_output_pixel_last),
    .output_pixel_saturation_count(),
    .current_x(),
    .current_y(),
    .busy(),
    .done(scheduler_done)
  );

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state <= S_IDLE;
      layer_index <= '0;
      scratch_store_pixel <= '0;
      scratch_store_channel <= '0;
      stream_store_pending <= 1'b0;
      stream_store_pixel <= '0;
      stream_store_channel <= '0;
      stream_store_channels <= '0;
      scheduler_done_seen <= 1'b0;
      final_output_stage0_valid <= 1'b0;
      final_output_stage0_index <= '0;
      final_output_stage0_last <= 1'b0;
      final_output_stage1_valid <= 1'b0;
      final_output_stage1_index <= '0;
      final_output_stage1_last <= 1'b0;
      final_output_stage2_valid <= 1'b0;
      final_output_stage2_index <= '0;
      final_output_stage2_last <= 1'b0;
      active_descriptor_valid <= 1'b0;
      active_input_width <= '0;
      active_input_height <= '0;
      active_input_channels <= '0;
      active_output_channels <= '0;
      active_kernel_size <= '0;
      active_stride <= '0;
      active_padding <= '0;
      active_bias_enable <= 1'b0;
      active_relu_enable <= 1'b0;
      active_quant_enable <= 1'b0;
      active_quant_shift <= '0;
      active_residual_enable <= 1'b0;
      done <= 1'b0;

      if (DIRECT_ARRAY_OPERANDS) begin
        for (int i = 0; i < MAX_PIXELS*MAX_CIN; i++) begin
          feature_bank0[i] <= '0;
          feature_bank1[i] <= '0;
        end
      end

      for (int c = 0; c < MAX_COUT; c++) begin
        stream_store_data[c] <= '0;
        final_output_stage0_data[c] <= '0;
        final_output_stage1_data[c] <= '0;
        final_output_stage1_residual[c] <= '0;
        final_output_stage2_data[c] <= '0;
      end

      if (!stream_final_mode) begin
        for (int i = 0; i < MAX_PIXELS*MAX_COUT; i++) begin
          output_tensor[i] <= '0;
        end
      end
    end else begin
      done <= 1'b0;

      if (stream_store_valid) begin
        if (stream_store_last_channel) begin
          stream_store_pending <= 1'b0;
          stream_store_channel <= '0;
        end else begin
          stream_store_channel <= stream_store_channel + COUNT_W'(1);
        end
      end

      if (stream_intermediate_mode &&
          (state == S_WAIT_LAYER) &&
          (layer_index != 2'd2) &&
          scheduler_output_pixel_valid &&
          scheduler_output_pixel_ready) begin
        stream_store_pending <= 1'b1;
        stream_store_pixel <= scheduler_output_pixel_index;
        stream_store_channel <= '0;
        stream_store_channels <= scheduler_output_pixel_channels;

        for (int c = 0; c < MAX_COUT; c++) begin
          stream_store_data[c] <= scheduler_output_pixel_data[c];
        end
      end

      if (stream_final_mode && (layer_index == 2'd2)) begin
        if (final_output_stage2_valid && output_pixel_ready) begin
          final_output_stage2_valid <= 1'b0;
        end

        if (final_output_stage1_valid && !final_output_stage2_valid) begin
          final_output_stage2_valid <= 1'b1;
          final_output_stage2_index <= final_output_stage1_index;
          final_output_stage2_last <= final_output_stage1_last;
          final_output_stage1_valid <= 1'b0;

          for (int c = 0; c < MAX_COUT; c++) begin
            if ((c < OUTPUT_C) &&
                active_residual_enable &&
                final_residual_enable) begin
              final_output_stage2_data[c] <=
                residual_sub(final_output_stage1_residual[c],
                             final_output_stage1_data[c]);
            end else begin
              final_output_stage2_data[c] <= final_output_stage1_data[c];
            end
          end
        end

        if (final_output_stage0_valid && !final_output_stage1_valid) begin
          final_output_stage1_valid <= 1'b1;
          final_output_stage1_index <= final_output_stage0_index;
          final_output_stage1_last <= final_output_stage0_last;
          final_output_stage0_valid <= 1'b0;

          for (int c = 0; c < MAX_COUT; c++) begin
            final_output_stage1_data[c] <= final_output_stage0_data[c];
            final_output_stage1_residual[c] <=
              input_tensor[(final_output_stage0_index * ADDR_W'(MAX_CIN)) +
                           ADDR_W'(c)];
          end
        end

        if (!final_output_stage0_valid &&
            scheduler_output_pixel_valid &&
            scheduler_output_pixel_ready) begin
          final_output_stage0_valid <= 1'b1;
          final_output_stage0_index <= scheduler_output_pixel_index;
          final_output_stage0_last <= scheduler_output_pixel_last;

          for (int c = 0; c < MAX_COUT; c++) begin
            final_output_stage0_data[c] <= scheduler_output_pixel_data[c];
          end
        end
      end else begin
        final_output_stage0_valid <= 1'b0;
        final_output_stage1_valid <= 1'b0;
        final_output_stage2_valid <= 1'b0;
      end

      if (scheduler_done) begin
        scheduler_done_seen <= 1'b1;
      end

      case (state)
        S_IDLE: begin
          if (start) begin
            layer_index <= 2'd0;
            stream_store_pending <= 1'b0;
            stream_store_pixel <= '0;
            stream_store_channel <= '0;
            stream_store_channels <= '0;
            scheduler_done_seen <= 1'b0;
            final_output_stage0_valid <= 1'b0;
            final_output_stage1_valid <= 1'b0;
            final_output_stage2_valid <= 1'b0;
            active_descriptor_valid <= 1'b0;
            state <= ((image_width == '0) || (image_height == '0)) ? S_DONE : S_LATCH_LAYER;
          end
        end

        S_LATCH_LAYER: begin
          scheduler_done_seen <= 1'b0;
          if (!descriptor_valid) begin
            active_descriptor_valid <= 1'b0;
            state <= S_DONE;
          end else begin
            active_descriptor_valid <= 1'b1;
            active_input_width <= desc_input_width;
            active_input_height <= desc_input_height;
            active_input_channels <= desc_input_channels;
            active_output_channels <= desc_output_channels;
            active_kernel_size <= desc_kernel_size;
            active_stride <= desc_stride;
            active_padding <= desc_padding;
            active_bias_enable <= desc_bias_enable;
            active_relu_enable <= desc_relu_enable;
            active_quant_enable <= desc_quant_enable;
            active_quant_shift <= desc_quant_shift;
            active_residual_enable <= desc_residual_enable;
            state <= S_START_LAYER;
          end
        end

        S_START_LAYER: begin
          scheduler_done_seen <= 1'b0;
          if (!active_descriptor_valid) begin
            state <= S_DONE;
          end else if (current_layer_ready) begin
            state <= S_WAIT_LAYER;
          end
        end

        S_WAIT_LAYER: begin
          if ((scheduler_done || scheduler_done_seen) &&
              !stream_store_pending &&
              (!(stream_final_mode && (layer_index == 2'd2)) ||
               final_output_drained)) begin
            scheduler_done_seen <= 1'b0;
            state <= S_STORE_LAYER;
          end
        end

        S_STORE_LAYER: begin
          if (DIRECT_ARRAY_OPERANDS || ((layer_index == 2'd2) && !stream_final_mode)) begin
            for (int p = 0; p < MAX_PIXELS; p++) begin
              if (DIRECT_ARRAY_OPERANDS) begin
                for (int c = 0; c < MAX_CIN; c++) begin
                  if (layer_index == 2'd0) begin
                    feature_bank0[(p * MAX_CIN) + c] <=
                      (c < HIDDEN_C) ? scheduler_output[(p * MAX_COUT) + c] : '0;
                  end else if (layer_index == 2'd1) begin
                    feature_bank1[(p * MAX_CIN) + c] <=
                      (c < HIDDEN_C) ? scheduler_output[(p * MAX_COUT) + c] : '0;
                  end
                end
              end

              for (int c = 0; c < MAX_COUT; c++) begin
                if (layer_index == 2'd2) begin
                  if (c < OUTPUT_C) begin
                    if (active_residual_enable && final_residual_enable) begin
                      output_tensor[(p * MAX_COUT) + c] <=
                        residual_sub(input_tensor[(p * MAX_CIN) + c],
                                     scheduler_output[(p * MAX_COUT) + c]);
                    end else begin
                      output_tensor[(p * MAX_COUT) + c] <= scheduler_output[(p * MAX_COUT) + c];
                    end
                  end else begin
                    output_tensor[(p * MAX_COUT) + c] <= '0;
                  end
                end
              end
            end
          end

          scratch_store_pixel <= '0;
          scratch_store_channel <= '0;
          if (use_scratchpad_operands &&
              !stream_intermediate_mode &&
              (layer_index != 2'd2) &&
              (scratch_store_pixel_count != '0) &&
              (active_output_channels != '0)) begin
            state <= S_WRITE_SCRATCH;
          end else begin
            state <= S_NEXT_LAYER;
          end
        end

        S_WRITE_SCRATCH: begin
          if (scratch_store_last) begin
            scratch_store_pixel <= '0;
            scratch_store_channel <= '0;
            state <= S_NEXT_LAYER;
          end else if (scratch_store_valid) begin
            if (scratch_store_channel == (active_output_channels - COUNT_W'(1))) begin
              scratch_store_channel <= '0;
              scratch_store_pixel <= scratch_store_pixel + ADDR_W'(1);
            end else begin
              scratch_store_channel <= scratch_store_channel + COUNT_W'(1);
            end
          end else begin
            state <= S_NEXT_LAYER;
          end
        end

        S_NEXT_LAYER: begin
          if (layer_index < 2'd2) begin
            layer_index <= layer_index + 2'd1;
            active_descriptor_valid <= 1'b0;
            state <= S_LATCH_LAYER;
          end else begin
            state <= S_DONE;
          end
        end

        S_DONE: begin
          done <= 1'b1;
          state <= S_IDLE;
        end

        default: begin
          state <= S_IDLE;
        end
      endcase
    end
  end

endmodule
