`timescale 1ns/1ps

module single_layer_scheduler #(
  parameter int PC         = 4,
  parameter int PK         = 8,
  parameter int MAX_CIN    = 64,
  parameter int MAX_COUT   = 64,
  parameter int MAX_PIXELS = 4096,
  parameter int DATA_W     = 8,
  parameter int PROD_W     = 16,
  parameter int ACC_W      = 32,
  parameter int BIAS_W     = 32,
  parameter int OUT_W      = 8,
  parameter int COUNT_W    = 8,
  parameter int DIM_W      = 16,
  parameter int ADDR_W     = 32,
  parameter bit MIRROR_OUTPUT_TENSOR = 1'b1
)(
  input  logic clk,
  input  logic rst_n,

  input  logic start,
  input  logic [DIM_W-1:0] input_width,
  input  logic [DIM_W-1:0] input_height,
  input  logic [DIM_W-1:0] output_width,
  input  logic [DIM_W-1:0] output_height,
  input  logic [1:0] kernel_size,
  input  logic [1:0] stride,
  input  logic [1:0] padding,
  input  logic [COUNT_W-1:0] cin,
  input  logic [COUNT_W-1:0] cout,

  input  logic bias_enable,
  input  logic relu_enable,
  input  logic quant_enable,
  input  logic [4:0] quant_shift,
  input  logic per_channel_quant_enable,
  input  logic signed [31:0] quant_multiplier [MAX_COUT],
  input  logic [5:0] per_channel_quant_shift [MAX_COUT],
  input  logic signed [7:0] output_zero_point,

  input  logic signed [DATA_W-1:0] activation [MAX_PIXELS*MAX_CIN],
  input  logic signed [DATA_W-1:0] weights_1x1 [MAX_COUT][MAX_CIN],
  input  logic signed [DATA_W-1:0] weights_3x3 [MAX_COUT][MAX_CIN][9],
  input  logic signed [BIAS_W-1:0] bias [MAX_COUT],

  input  logic use_scratchpad_operands,
  input  logic use_scratchpad_weights,
  output logic [ADDR_W-1:0] scratch_activation_read_pixel,
  output logic [COUNT_W-1:0] scratch_activation_read_c_base,
  output logic [PC-1:0] scratch_activation_lane_mask,
  input  logic signed [DATA_W-1:0] scratch_activation_lane_data [PC],
  output logic [COUNT_W-1:0] scratch_weight_read_k_base,
  output logic [COUNT_W-1:0] scratch_weight_read_c_base,
  output logic [3:0] scratch_weight_read_kernel_idx,
  output logic [PK-1:0] scratch_weight_out_lane_mask,
  output logic [PC-1:0] scratch_weight_in_lane_mask,
  input  logic signed [DATA_W-1:0] scratch_weight_mat_data [PK][PC],

  output logic signed [OUT_W-1:0] output_tensor [MAX_PIXELS*MAX_COUT],
  output logic output_pixel_valid,
  input  logic output_pixel_ready,
  output logic [ADDR_W-1:0] output_pixel_index,
  output logic [COUNT_W-1:0] output_pixel_channels,
  output logic signed [OUT_W-1:0] output_pixel_data [MAX_COUT],
  output logic output_pixel_last,
  output logic [31:0] output_pixel_saturation_count,
  output logic mac_issue_valid,
  output logic [15:0] mac_issue_count,
  output logic [DIM_W-1:0] current_x,
  output logic [DIM_W-1:0] current_y,
  output logic busy,
  output logic done
);

  typedef enum logic [2:0] {
    S_IDLE,
    S_START_PIXEL,
    S_WAIT_PIXEL,
    S_WRITE_PIXEL,
    S_NEXT_PIXEL,
    S_DONE
  } state_t;

  state_t state;

  logic [DIM_W-1:0] out_x;
  logic [DIM_W-1:0] out_y;
  logic [31:0] input_pixel_index_1x1_q;
  logic [31:0] input_row_base_1x1_q;
  logic [31:0] input_row_step_1x1;
  logic [31:0] output_pixel_index_calc;

  logic start_1x1;
  logic start_3x3;
  logic done_1x1;
  logic done_3x3;
  logic busy_1x1;
  logic busy_3x3;
  logic [31:0] saturation_count_1x1;
  logic [31:0] saturation_count_3x3;
  logic mac_issue_valid_1x1;
  logic mac_issue_valid_3x3;
  logic [15:0] mac_issue_count_1x1;
  logic [15:0] mac_issue_count_3x3;

  logic signed [DATA_W-1:0] activation_1x1 [MAX_CIN];
  logic signed [OUT_W-1:0] output_1x1 [MAX_COUT];
  logic signed [OUT_W-1:0] output_3x3 [MAX_COUT];
  logic [ADDR_W-1:0] scratch_activation_read_pixel_1x1;
  logic [ADDR_W-1:0] scratch_activation_read_pixel_3x3;
  logic [COUNT_W-1:0] scratch_activation_read_c_base_1x1;
  logic [COUNT_W-1:0] scratch_activation_read_c_base_3x3;
  logic [PC-1:0] scratch_activation_lane_mask_1x1;
  logic [PC-1:0] scratch_activation_lane_mask_3x3;
  logic [COUNT_W-1:0] scratch_weight_read_k_base_1x1;
  logic [COUNT_W-1:0] scratch_weight_read_k_base_3x3;
  logic [COUNT_W-1:0] scratch_weight_read_c_base_1x1;
  logic [COUNT_W-1:0] scratch_weight_read_c_base_3x3;
  logic [3:0] scratch_weight_read_kernel_idx_1x1;
  logic [3:0] scratch_weight_read_kernel_idx_3x3;
  logic [PK-1:0] scratch_weight_out_lane_mask_1x1;
  logic [PK-1:0] scratch_weight_out_lane_mask_3x3;
  logic [PC-1:0] scratch_weight_in_lane_mask_1x1;
  logic [PC-1:0] scratch_weight_in_lane_mask_3x3;

  assign current_x = out_x;
  assign current_y = out_y;
  assign busy = (state != S_IDLE) && (state != S_DONE);
  assign start_1x1 = (state == S_START_PIXEL) && (kernel_size == 2'd1);
  assign start_3x3 = (state == S_START_PIXEL) && (kernel_size == 2'd3);
  assign mac_issue_valid = (kernel_size == 2'd1) ? mac_issue_valid_1x1 :
                           (kernel_size == 2'd3) ? mac_issue_valid_3x3 : 1'b0;
  assign mac_issue_count = (kernel_size == 2'd1) ? mac_issue_count_1x1 :
                           (kernel_size == 2'd3) ? mac_issue_count_3x3 : 16'd0;
  assign output_pixel_index_calc =
    (ADDR_W'(out_y) * ADDR_W'(output_width)) + ADDR_W'(out_x);
  assign scratch_activation_read_pixel =
    (kernel_size == 2'd1) ? scratch_activation_read_pixel_1x1 :
    scratch_activation_read_pixel_3x3;
  assign scratch_activation_read_c_base =
    (kernel_size == 2'd1) ? scratch_activation_read_c_base_1x1 :
    scratch_activation_read_c_base_3x3;
  assign scratch_activation_lane_mask =
    (kernel_size == 2'd1) ? scratch_activation_lane_mask_1x1 :
    scratch_activation_lane_mask_3x3;
  assign scratch_weight_read_k_base =
    (kernel_size == 2'd1) ? scratch_weight_read_k_base_1x1 :
    scratch_weight_read_k_base_3x3;
  assign scratch_weight_read_c_base =
    (kernel_size == 2'd1) ? scratch_weight_read_c_base_1x1 :
    scratch_weight_read_c_base_3x3;
  assign scratch_weight_read_kernel_idx =
    (kernel_size == 2'd1) ? scratch_weight_read_kernel_idx_1x1 :
    scratch_weight_read_kernel_idx_3x3;
  assign scratch_weight_out_lane_mask =
    (kernel_size == 2'd1) ? scratch_weight_out_lane_mask_1x1 :
    scratch_weight_out_lane_mask_3x3;
  assign scratch_weight_in_lane_mask =
    (kernel_size == 2'd1) ? scratch_weight_in_lane_mask_1x1 :
    scratch_weight_in_lane_mask_3x3;
  assign output_pixel_valid = (state == S_WRITE_PIXEL);
  assign output_pixel_index = ADDR_W'(output_pixel_index_calc);
  assign output_pixel_channels = cout;
  assign output_pixel_last =
    (state == S_WRITE_PIXEL) &&
    ((out_x + DIM_W'(1)) >= output_width) &&
    ((out_y + DIM_W'(1)) >= output_height);
  assign output_pixel_saturation_count =
    (kernel_size == 2'd1) ? saturation_count_1x1 : saturation_count_3x3;

  always_comb begin
    case (stride)
      2'd1: input_row_step_1x1 = 32'(input_width);
      2'd2: input_row_step_1x1 = 32'(input_width) << 1;
      default: input_row_step_1x1 = '0;
    endcase
  end

  always_comb begin
    for (int co = 0; co < MAX_COUT; co++) begin
      output_pixel_data[co] = (kernel_size == 2'd1) ? output_1x1[co] : output_3x3[co];
    end
  end

  always_comb begin
    for (int ci = 0; ci < MAX_CIN; ci++) begin
      if ((ci < cin) && (input_pixel_index_1x1_q < 32'(MAX_PIXELS))) begin
        activation_1x1[ci] =
          activation[(input_pixel_index_1x1_q * 32'(MAX_CIN)) + 32'(ci)];
      end else begin
        activation_1x1[ci] = '0;
      end
    end
  end

  tiled_conv1x1_engine #(
    .PC(PC),
    .PK(PK),
    .MAX_CIN(MAX_CIN),
    .MAX_COUT(MAX_COUT),
    .DATA_W(DATA_W),
    .PROD_W(PROD_W),
    .ACC_W(ACC_W),
    .BIAS_W(BIAS_W),
    .OUT_W(OUT_W),
    .COUNT_W(COUNT_W),
    .ADDR_W(ADDR_W)
  ) u_tiled_conv1x1_engine (
    .clk(clk),
    .rst_n(rst_n),
    .start(start_1x1),
    .cin(cin),
    .cout(cout),
    .bias_enable(bias_enable),
    .relu_enable(relu_enable),
    .quant_enable(quant_enable),
    .quant_shift(quant_shift),
    .per_channel_quant_enable(per_channel_quant_enable),
    .quant_multiplier(quant_multiplier),
    .per_channel_quant_shift(per_channel_quant_shift),
    .output_zero_point(output_zero_point),
    .activation(activation_1x1),
    .weights(weights_1x1),
    .bias(bias),
    .use_scratchpad_operands(use_scratchpad_operands),
    .use_scratchpad_weights(use_scratchpad_weights),
    .scratch_activation_pixel(input_pixel_index_1x1_q),
    .scratch_activation_read_pixel(scratch_activation_read_pixel_1x1),
    .scratch_activation_read_c_base(scratch_activation_read_c_base_1x1),
    .scratch_activation_lane_mask(scratch_activation_lane_mask_1x1),
    .scratch_activation_lane_data(scratch_activation_lane_data),
    .scratch_weight_read_k_base(scratch_weight_read_k_base_1x1),
    .scratch_weight_read_c_base(scratch_weight_read_c_base_1x1),
    .scratch_weight_read_kernel_idx(scratch_weight_read_kernel_idx_1x1),
    .scratch_weight_out_lane_mask(scratch_weight_out_lane_mask_1x1),
    .scratch_weight_in_lane_mask(scratch_weight_in_lane_mask_1x1),
    .scratch_weight_mat_data(scratch_weight_mat_data),
    .output_data(output_1x1),
    .saturation_event_count(saturation_count_1x1),
    .mac_issue_valid(mac_issue_valid_1x1),
    .mac_issue_count(mac_issue_count_1x1),
    .busy(busy_1x1),
    .done(done_1x1)
  );

  tiled_conv3x3_engine #(
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
    .ADDR_W(ADDR_W)
  ) u_tiled_conv3x3_engine (
    .clk(clk),
    .rst_n(rst_n),
    .start(start_3x3),
    .input_width(input_width),
    .input_height(input_height),
    .out_x(out_x),
    .out_y(out_y),
    .stride(stride),
    .padding(padding),
    .cin(cin),
    .cout(cout),
    .bias_enable(bias_enable),
    .relu_enable(relu_enable),
    .quant_enable(quant_enable),
    .quant_shift(quant_shift),
    .per_channel_quant_enable(per_channel_quant_enable),
    .quant_multiplier(quant_multiplier),
    .per_channel_quant_shift(per_channel_quant_shift),
    .output_zero_point(output_zero_point),
    .activation(activation),
    .weights(weights_3x3),
    .bias(bias),
    .use_scratchpad_operands(use_scratchpad_operands),
    .use_scratchpad_weights(use_scratchpad_weights),
    .scratch_activation_read_pixel(scratch_activation_read_pixel_3x3),
    .scratch_activation_read_c_base(scratch_activation_read_c_base_3x3),
    .scratch_activation_lane_mask(scratch_activation_lane_mask_3x3),
    .scratch_activation_lane_data(scratch_activation_lane_data),
    .scratch_weight_read_k_base(scratch_weight_read_k_base_3x3),
    .scratch_weight_read_c_base(scratch_weight_read_c_base_3x3),
    .scratch_weight_read_kernel_idx(scratch_weight_read_kernel_idx_3x3),
    .scratch_weight_out_lane_mask(scratch_weight_out_lane_mask_3x3),
    .scratch_weight_in_lane_mask(scratch_weight_in_lane_mask_3x3),
    .scratch_weight_mat_data(scratch_weight_mat_data),
    .output_data(output_3x3),
    .saturation_event_count(saturation_count_3x3),
    .mac_issue_valid(mac_issue_valid_3x3),
    .mac_issue_count(mac_issue_count_3x3),
    .busy(busy_3x3),
    .done(done_3x3)
  );

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state <= S_IDLE;
      out_x <= '0;
      out_y <= '0;
      input_pixel_index_1x1_q <= '0;
      input_row_base_1x1_q <= '0;
      done  <= 1'b0;

      if (MIRROR_OUTPUT_TENSOR) begin
        for (int i = 0; i < MAX_PIXELS*MAX_COUT; i++) begin
          output_tensor[i] <= '0;
        end
      end
    end else begin
      done <= 1'b0;

      case (state)
        S_IDLE: begin
          if (start) begin
            out_x <= '0;
            out_y <= '0;
            input_pixel_index_1x1_q <= '0;
            input_row_base_1x1_q <= '0;
            state <= ((output_width == '0) || (output_height == '0) || (cout == '0)) ?
                     S_DONE : S_START_PIXEL;
          end
        end

        S_START_PIXEL: begin
          state <= S_WAIT_PIXEL;
        end

        S_WAIT_PIXEL: begin
          if (((kernel_size == 2'd1) && done_1x1) ||
              ((kernel_size == 2'd3) && done_3x3) ||
              ((kernel_size != 2'd1) && (kernel_size != 2'd3))) begin
            state <= S_WRITE_PIXEL;
          end
        end

        S_WRITE_PIXEL: begin
          if (output_pixel_ready) begin
            if (MIRROR_OUTPUT_TENSOR) begin
              for (int co = 0; co < MAX_COUT; co++) begin
                if ((co < cout) &&
                    (output_pixel_index_calc < 32'(MAX_PIXELS)) &&
                    (((output_pixel_index_calc * 32'(MAX_COUT)) + 32'(co)) <
                     32'(MAX_PIXELS*MAX_COUT))) begin
                  output_tensor[(output_pixel_index_calc * 32'(MAX_COUT)) + 32'(co)] <=
                    (kernel_size == 2'd1) ? output_1x1[co] : output_3x3[co];
                end
              end
            end
            state <= S_NEXT_PIXEL;
          end
        end

        S_NEXT_PIXEL: begin
          if ((out_x + DIM_W'(1)) < output_width) begin
            out_x <= out_x + DIM_W'(1);
            input_pixel_index_1x1_q <= input_pixel_index_1x1_q + 32'(stride);
            state <= S_START_PIXEL;
          end else if ((out_y + DIM_W'(1)) < output_height) begin
            out_x <= '0;
            out_y <= out_y + DIM_W'(1);
            input_row_base_1x1_q <= input_row_base_1x1_q + input_row_step_1x1;
            input_pixel_index_1x1_q <= input_row_base_1x1_q + input_row_step_1x1;
            state <= S_START_PIXEL;
          end else begin
            state <= S_DONE;
          end
        end

        S_DONE: begin
          done  <= 1'b1;
          state <= S_IDLE;
        end

        default: begin
          state <= S_IDLE;
        end
      endcase
    end
  end

endmodule
