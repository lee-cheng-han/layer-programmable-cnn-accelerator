`timescale 1ns/1ps

module packed_dma_runtime_router (
  input  logic clk,
  input  logic rst_n,
  input  logic clear,

  input  logic packet_start,
  output logic packet_ready,
  input  logic [7:0] packet_type,
  input  logic [31:0] packet_job_id,
  input  logic [15:0] packet_tensor_id,
  input  logic [15:0] packet_layer_id,
  input  logic [15:0] packet_tile_x,
  input  logic [15:0] packet_tile_y,
  input  logic [15:0] packet_tile_width,
  input  logic [15:0] packet_tile_height,
  input  logic [15:0] packet_channel_offset,
  input  logic [15:0] packet_channel_count,
  input  logic [31:0] packet_payload_length,
  input  logic packet_error_valid,

  input  logic payload_valid,
  output logic payload_ready,
  input  logic [31:0] payload_data,
  input  logic [3:0] payload_keep,
  input  logic payload_last,

  input  logic parameter_config_valid,
  input  logic [2:0] parameter_config_layer_id,
  input  logic [1:0] parameter_config_kernel_size,
  input  logic [7:0] parameter_config_cin,
  input  logic [7:0] parameter_config_cout,
  input  logic parameter_config_bias_enable,
  input  logic parameter_config_quant_enable,
  input  logic [4:0] parameter_config_quant_shift,
  input  logic [15:0] parameter_config_weight_bytes,
  input  logic [15:0] parameter_config_bias_bytes,
  input  logic [31:0] parameter_config_crc32,

  output logic parameter_load_start,
  output logic parameter_load_abort,
  input  logic parameter_load_ready,
  output logic [2:0] parameter_load_layer_id,
  output logic [1:0] parameter_load_kernel_size,
  output logic [7:0] parameter_load_cin,
  output logic [7:0] parameter_load_cout,
  output logic parameter_load_bias_enable,
  output logic parameter_load_quant_enable,
  output logic [4:0] parameter_load_quant_shift,
  output logic [15:0] parameter_load_weight_bytes,
  output logic [15:0] parameter_load_bias_bytes,
  output logic [31:0] parameter_load_expected_crc32,
  output logic parameter_weight_valid,
  input  logic parameter_weight_ready,
  output logic signed [7:0] parameter_weight_data,
  output logic parameter_bias_valid,
  input  logic parameter_bias_ready,
  output logic signed [31:0] parameter_bias_data,

  output logic activation_packet_start,
  input  logic activation_packet_ready,
  output logic [31:0] activation_job_id,
  output logic [15:0] activation_tensor_id,
  output logic [15:0] activation_layer_id,
  output logic [15:0] activation_tile_x,
  output logic [15:0] activation_tile_y,
  output logic [15:0] activation_tile_width,
  output logic [15:0] activation_tile_height,
  output logic [15:0] activation_channel_offset,
  output logic [15:0] activation_channel_count,
  output logic [31:0] activation_payload_length,
  output logic activation_valid,
  input  logic activation_ready,
  output logic [31:0] activation_data,
  output logic [3:0] activation_keep,
  output logic activation_last,

  output logic error,
  output logic [7:0] error_code
);
  import cnn_dma_packet_pkg::*;

  localparam logic [7:0] ROUTER_ERROR_NONE = 8'd0;
  localparam logic [7:0] ROUTER_ERROR_PACKET_ORDER = 8'd1;
  localparam logic [7:0] ROUTER_ERROR_LAYER_ID = 8'd2;
  localparam logic [7:0] ROUTER_ERROR_PAYLOAD_LENGTH = 8'd3;
  localparam logic [7:0] ROUTER_ERROR_PARAMETER_CONFIG = 8'd4;

  typedef enum logic [2:0] {
    S_IDLE,
    S_WEIGHTS,
    S_WAIT_BIAS,
    S_BIASES,
    S_ACTIVATION,
    S_DROP
  } state_t;

  state_t state;
  logic weight_buffer_valid;
  logic [31:0] weight_buffer_data;
  logic [3:0] weight_buffer_keep;
  logic weight_buffer_last;
  logic [1:0] weight_lane;
  logic [2:0] weight_buffer_bytes;
  logic weight_byte_transfer;
  logic weight_buffer_complete;
  logic bias_buffer_valid;
  logic signed [31:0] bias_buffer_data;
  logic bias_buffer_last;
  logic bias_buffer_transfer;
  logic activation_buffer_valid;
  logic [31:0] activation_buffer_data;
  logic [3:0] activation_buffer_keep;
  logic activation_buffer_last;
  logic activation_buffer_transfer;
  logic payload_transfer;
  logic semantic_error;
  logic [7:0] semantic_error_code;
  logic parameter_config_valid_q;
  logic [2:0] parameter_layer_id_q;
  logic [1:0] parameter_kernel_size_q;
  logic [7:0] parameter_cin_q;
  logic [7:0] parameter_cout_q;
  logic parameter_bias_enable_q;
  logic parameter_quant_enable_q;
  logic [4:0] parameter_quant_shift_q;
  logic [15:0] parameter_weight_bytes_q;
  logic [15:0] parameter_bias_bytes_q;
  logic [31:0] parameter_crc32_q;

  assign parameter_load_layer_id = parameter_layer_id_q;
  assign parameter_load_kernel_size = parameter_kernel_size_q;
  assign parameter_load_cin = parameter_cin_q;
  assign parameter_load_cout = parameter_cout_q;
  assign parameter_load_bias_enable = parameter_bias_enable_q;
  assign parameter_load_quant_enable = parameter_quant_enable_q;
  assign parameter_load_quant_shift = parameter_quant_shift_q;
  assign parameter_load_weight_bytes = parameter_weight_bytes_q;
  assign parameter_load_bias_bytes = parameter_bias_bytes_q;
  assign parameter_load_expected_crc32 = parameter_crc32_q;

  assign activation_data = activation_buffer_data;
  assign activation_keep = activation_buffer_keep;
  assign activation_last = activation_buffer_last;
  assign activation_valid = activation_buffer_valid;
  assign activation_buffer_transfer =
    activation_valid && activation_ready;

  assign weight_buffer_bytes = bytes_for_keep(weight_buffer_keep);
  assign parameter_weight_valid = (state == S_WEIGHTS) && weight_buffer_valid;
  assign parameter_weight_data =
    weight_buffer_data[(int'(weight_lane) * 8) +: 8];
  assign weight_byte_transfer = parameter_weight_valid && parameter_weight_ready;
  assign weight_buffer_complete =
    weight_lane + 2'd1 >= weight_buffer_bytes;

  assign parameter_bias_valid = bias_buffer_valid;
  assign parameter_bias_data = bias_buffer_data;
  assign bias_buffer_transfer =
    parameter_bias_valid && parameter_bias_ready;

  always_comb begin
    unique case (state)
      S_WEIGHTS: payload_ready = !weight_buffer_valid;
      S_BIASES: payload_ready = !bias_buffer_valid || parameter_bias_ready;
      S_ACTIVATION: payload_ready = !activation_buffer_valid || activation_ready;
      S_DROP: payload_ready = 1'b1;
      default: payload_ready = 1'b0;
    endcase
  end
  assign payload_transfer = payload_valid && payload_ready;

  always_comb begin
    unique case (state)
      S_IDLE: begin
        if (packet_type == DMA_PACKET_INPUT_TILE) begin
          packet_ready = activation_packet_ready;
        end else if (packet_type == DMA_PACKET_LAYER_WEIGHTS) begin
          packet_ready = parameter_config_valid_q && parameter_load_ready;
        end else begin
          packet_ready = 1'b1;
        end
      end
      S_WAIT_BIAS: packet_ready = 1'b1;
      default: packet_ready = 1'b0;
    endcase
  end

  always_comb begin
    semantic_error = 1'b0;
    semantic_error_code = ROUTER_ERROR_NONE;
    if (state == S_IDLE) begin
      if (packet_type == DMA_PACKET_LAYER_WEIGHTS) begin
        if (!parameter_config_valid_q) begin
          semantic_error = 1'b1;
          semantic_error_code = ROUTER_ERROR_PARAMETER_CONFIG;
        end else if (packet_layer_id[15:3] != 0 ||
                     packet_layer_id[2:0] != parameter_layer_id_q) begin
          semantic_error = 1'b1;
          semantic_error_code = ROUTER_ERROR_LAYER_ID;
        end else if (packet_payload_length !=
                     32'(parameter_weight_bytes_q)) begin
          semantic_error = 1'b1;
          semantic_error_code = ROUTER_ERROR_PAYLOAD_LENGTH;
        end
      end else if (packet_type != DMA_PACKET_INPUT_TILE) begin
        semantic_error = 1'b1;
        semantic_error_code = ROUTER_ERROR_PACKET_ORDER;
      end
      end else if (state == S_WAIT_BIAS) begin
        if (packet_type != DMA_PACKET_LAYER_BIASES) begin
          semantic_error = 1'b1;
          semantic_error_code = ROUTER_ERROR_PACKET_ORDER;
        end else if (packet_layer_id[15:3] != 0 ||
                     packet_layer_id[2:0] != parameter_layer_id_q) begin
          semantic_error = 1'b1;
          semantic_error_code = ROUTER_ERROR_LAYER_ID;
        end else if (packet_payload_length !=
                     32'(parameter_bias_bytes_q)) begin
          semantic_error = 1'b1;
          semantic_error_code = ROUTER_ERROR_PAYLOAD_LENGTH;
      end
    end
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state <= S_IDLE;
      weight_buffer_valid <= 1'b0;
      weight_buffer_data <= '0;
      weight_buffer_keep <= '0;
      weight_buffer_last <= 1'b0;
      weight_lane <= '0;
      bias_buffer_valid <= 1'b0;
      bias_buffer_data <= '0;
      bias_buffer_last <= 1'b0;
      activation_buffer_valid <= 1'b0;
      activation_buffer_data <= '0;
      activation_buffer_keep <= '0;
      activation_buffer_last <= 1'b0;
      parameter_load_start <= 1'b0;
      parameter_load_abort <= 1'b0;
      parameter_config_valid_q <= 1'b0;
      parameter_layer_id_q <= '0;
      parameter_kernel_size_q <= '0;
      parameter_cin_q <= '0;
      parameter_cout_q <= '0;
      parameter_bias_enable_q <= 1'b0;
      parameter_quant_enable_q <= 1'b0;
      parameter_quant_shift_q <= '0;
      parameter_weight_bytes_q <= '0;
      parameter_bias_bytes_q <= '0;
      parameter_crc32_q <= '0;
      activation_packet_start <= 1'b0;
      activation_job_id <= '0;
      activation_tensor_id <= '0;
      activation_layer_id <= '0;
      activation_tile_x <= '0;
      activation_tile_y <= '0;
      activation_tile_width <= '0;
      activation_tile_height <= '0;
      activation_channel_offset <= '0;
      activation_channel_count <= '0;
      activation_payload_length <= '0;
      error <= 1'b0;
      error_code <= ROUTER_ERROR_NONE;
    end else begin
      parameter_load_start <= 1'b0;
      parameter_load_abort <= 1'b0;
      activation_packet_start <= 1'b0;

      if (clear) begin
        state <= S_IDLE;
        parameter_config_valid_q <= 1'b0;
        weight_buffer_valid <= 1'b0;
        weight_lane <= '0;
        bias_buffer_valid <= 1'b0;
        activation_buffer_valid <= 1'b0;
        error <= 1'b0;
        error_code <= ROUTER_ERROR_NONE;
      end else if (packet_error_valid) begin
        if ((state == S_WEIGHTS) || (state == S_WAIT_BIAS) ||
            (state == S_BIASES)) begin
          parameter_load_abort <= 1'b1;
        end
        state <= S_IDLE;
        weight_buffer_valid <= 1'b0;
        weight_lane <= '0;
        bias_buffer_valid <= 1'b0;
        activation_buffer_valid <= 1'b0;
      end else begin
        if ((state == S_IDLE) && !packet_start) begin
          parameter_config_valid_q <= parameter_config_valid;
          parameter_layer_id_q <= parameter_config_layer_id;
          parameter_kernel_size_q <= parameter_config_kernel_size;
          parameter_cin_q <= parameter_config_cin;
          parameter_cout_q <= parameter_config_cout;
          parameter_bias_enable_q <= parameter_config_bias_enable;
          parameter_quant_enable_q <= parameter_config_quant_enable;
          parameter_quant_shift_q <= parameter_config_quant_shift;
          parameter_weight_bytes_q <= parameter_config_weight_bytes;
          parameter_bias_bytes_q <= parameter_config_bias_bytes;
          parameter_crc32_q <= parameter_config_crc32;
        end

        if (packet_start) begin
          if (semantic_error) begin
            error <= 1'b1;
            error_code <= semantic_error_code;
            if (state == S_WAIT_BIAS) begin
              parameter_load_abort <= 1'b1;
            end
            state <= S_DROP;
          end else if (state == S_IDLE &&
                       packet_type == DMA_PACKET_INPUT_TILE) begin
            activation_job_id <= packet_job_id;
            activation_tensor_id <= packet_tensor_id;
            activation_layer_id <= packet_layer_id;
            activation_tile_x <= packet_tile_x;
            activation_tile_y <= packet_tile_y;
            activation_tile_width <= packet_tile_width;
            activation_tile_height <= packet_tile_height;
            activation_channel_offset <= packet_channel_offset;
            activation_channel_count <= packet_channel_count;
            activation_payload_length <= packet_payload_length;
            activation_packet_start <= 1'b1;
            state <= S_ACTIVATION;
          end else if (state == S_IDLE) begin
            parameter_load_start <= 1'b1;
            state <= S_WEIGHTS;
          end else begin
            state <= S_BIASES;
          end
        end

        if ((state == S_WEIGHTS) && payload_transfer) begin
          weight_buffer_valid <= 1'b1;
          weight_buffer_data <= payload_data;
          weight_buffer_keep <= payload_keep;
          weight_buffer_last <= payload_last;
          weight_lane <= '0;
        end

        if (weight_byte_transfer) begin
          if (weight_buffer_complete) begin
            weight_buffer_valid <= 1'b0;
            weight_lane <= '0;
            if (weight_buffer_last) begin
              state <= parameter_bias_enable_q ? S_WAIT_BIAS : S_IDLE;
            end
          end else begin
            weight_lane <= weight_lane + 2'd1;
          end
        end

        if (bias_buffer_transfer) begin
          bias_buffer_valid <= 1'b0;
          if (bias_buffer_last) begin
            state <= S_IDLE;
          end
        end

        if ((state == S_BIASES) && payload_transfer) begin
          bias_buffer_valid <= 1'b1;
          bias_buffer_data <= payload_data;
          bias_buffer_last <= payload_last;
        end

        if (activation_buffer_transfer) begin
          activation_buffer_valid <= 1'b0;
          if (activation_buffer_last) begin
            state <= S_IDLE;
          end
        end

        if ((state == S_ACTIVATION) && payload_transfer) begin
          activation_buffer_valid <= 1'b1;
          activation_buffer_data <= payload_data;
          activation_buffer_keep <= payload_keep;
          activation_buffer_last <= payload_last;
        end

        if ((state == S_DROP) && payload_transfer && payload_last) begin
          state <= S_IDLE;
        end
      end
    end
  end
endmodule
