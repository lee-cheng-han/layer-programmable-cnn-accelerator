`timescale 1ns/1ps

module cnn_runtime_parameter_banks #(
  parameter int PC       = 2,
  parameter int PK       = 4,
  parameter int MAX_CIN  = 16,
  parameter int MAX_COUT = 16,
  parameter int DATA_W   = 8,
  parameter int BIAS_W   = 32,
  parameter int COUNT_W  = 8,
  parameter int WEIGHT_BANK_CAPACITY_BYTES = 4096,
  parameter int POSTPROCESS_BANK_CAPACITY_BYTES = 256
)(
  input  logic clk,
  input  logic rst_n,
  input  logic clear_error,

  input  logic load_start,
  output logic load_ready,
  input  logic [2:0] load_layer_id,
  input  logic [1:0] load_kernel_size,
  input  logic [COUNT_W-1:0] load_cin,
  input  logic [COUNT_W-1:0] load_cout,
  input  logic load_bias_enable,
  input  logic load_quant_enable,
  input  logic [4:0] load_quant_shift,
  input  logic [15:0] load_weight_bytes,
  input  logic [15:0] load_bias_bytes,
  input  logic [31:0] load_expected_crc32,

  input  logic weight_valid,
  output logic weight_ready,
  input  logic signed [DATA_W-1:0] weight_data,
  input  logic bias_valid,
  output logic bias_ready,
  input  logic signed [BIAS_W-1:0] bias_data,

  output logic load_busy,
  output logic load_done,
  output logic error,
  output logic [7:0] error_code,

  input  logic parameter_request,
  input  logic [2:0] parameter_layer_id,
  output logic parameter_ready,
  input  logic parameter_release,
  output logic parameter_use_scratchpad_weights,
  output logic parameter_quant_enable,
  output logic [4:0] parameter_quant_shift,
  output logic signed [BIAS_W-1:0] parameter_bias [MAX_COUT],

  input  logic [COUNT_W-1:0] weight_read_k_base,
  input  logic [COUNT_W-1:0] weight_read_c_base,
  input  logic [3:0] weight_read_kernel_idx,
  input  logic [PK-1:0] weight_out_lane_mask,
  input  logic [PC-1:0] weight_in_lane_mask,
  output logic signed [DATA_W-1:0] weight_mat_data [PK][PC],

  output logic [1:0] bank_valid,
  output logic [2:0] bank0_layer_id,
  output logic [2:0] bank1_layer_id,
  output logic load_bank,
  output logic compute_bank,
  output logic compute_active,
  output logic overlap_active
);
  localparam logic [7:0] PARAMETER_OK = 8'd0;
  localparam logic [7:0] PARAMETER_BAD_CONFIG = 8'd1;
  localparam logic [7:0] PARAMETER_BAD_LENGTH = 8'd2;
  localparam logic [7:0] PARAMETER_BAD_CRC = 8'd3;
  localparam logic [7:0] PARAMETER_NO_FREE_BANK = 8'd4;
  localparam logic [7:0] PARAMETER_BAD_OWNERSHIP = 8'd5;

  typedef enum logic [2:0] {
    S_IDLE,
    S_LOAD_WEIGHTS,
    S_LOAD_BIASES,
    S_VERIFY
  } load_state_t;

  load_state_t load_state;
  logic selected_free_bank;
  logic bank0_free;
  logic bank1_free;
  logic matching_bank_valid;
  logic matching_bank;
  logic layer_already_buffered;
  logic load_config_valid;
  logic [31:0] calculated_weight_bytes;
  logic [31:0] calculated_bias_bytes;
  logic [3:0] kernel_taps;

  logic [2:0] bank_layer_id [0:1];
  logic bank_quant_enable [0:1];
  logic [4:0] bank_quant_shift [0:1];
  logic signed [BIAS_W-1:0] bias_bank [0:1][0:MAX_COUT-1];

  logic [2:0] load_layer_id_q;
  logic [1:0] load_kernel_size_q;
  logic [COUNT_W-1:0] load_cin_q;
  logic [COUNT_W-1:0] load_cout_q;
  logic load_bias_enable_q;
  logic [15:0] expected_weight_bytes_q;
  logic [15:0] expected_bias_bytes_q;
  logic [31:0] expected_crc32_q;
  logic [15:0] weight_count;
  logic [15:0] bias_count;
  logic [COUNT_W-1:0] write_out_channel;
  logic [COUNT_W-1:0] write_in_channel;
  logic [3:0] write_kernel_idx;
  logic [COUNT_W-1:0] write_bias_channel;
  logic [31:0] crc_q;
  logic weight_transfer;
  logic bias_transfer;
  logic last_weight;
  logic last_bias;

  logic scratch_write_enable;
  logic signed [DATA_W-1:0] scratch_debug_data;

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

  function automatic logic [31:0] crc32_word_le(
    input logic [31:0] crc_in,
    input logic [31:0] data
  );
    logic [31:0] value;
    begin
      value = crc32_byte(crc_in, data[7:0]);
      value = crc32_byte(value, data[15:8]);
      value = crc32_byte(value, data[23:16]);
      value = crc32_byte(value, data[31:24]);
      return value;
    end
  endfunction

  assign kernel_taps = (load_kernel_size == 2'd1) ? 4'd1 : 4'd9;
  assign calculated_weight_bytes =
    32'(load_cin) * 32'(load_cout) * 32'(kernel_taps);
  assign calculated_bias_bytes = load_bias_enable ? (32'(load_cout) * 32'd4) : 32'd0;
  assign load_config_valid =
    ((load_kernel_size == 2'd1) || (load_kernel_size == 2'd3)) &&
    (load_cin != 0) && (load_cin <= COUNT_W'(MAX_CIN)) &&
    (load_cout != 0) && (load_cout <= COUNT_W'(MAX_COUT)) &&
    (32'(load_weight_bytes) == calculated_weight_bytes) &&
    (32'(load_bias_bytes) == calculated_bias_bytes) &&
    (32'(load_weight_bytes) <= 32'(WEIGHT_BANK_CAPACITY_BYTES)) &&
    (32'(load_bias_bytes) <= 32'(POSTPROCESS_BANK_CAPACITY_BYTES));

  assign bank0_free = !bank_valid[0] && !(compute_active && !compute_bank);
  assign bank1_free = !bank_valid[1] && !(compute_active && compute_bank);
  assign selected_free_bank = bank0_free ? 1'b0 : 1'b1;
  assign load_ready = (load_state == S_IDLE) && (bank0_free || bank1_free);
  assign layer_already_buffered =
    (bank_valid[0] && (bank_layer_id[0] == load_layer_id)) ||
    (bank_valid[1] && (bank_layer_id[1] == load_layer_id));
  assign load_busy = load_state != S_IDLE;
  assign weight_ready = load_state == S_LOAD_WEIGHTS;
  assign bias_ready = load_state == S_LOAD_BIASES;
  assign weight_transfer = weight_valid && weight_ready;
  assign bias_transfer = bias_valid && bias_ready;
  assign last_weight = weight_count + 16'd1 >= expected_weight_bytes_q;
  assign last_bias = bias_count + 16'd4 >= expected_bias_bytes_q;
  assign scratch_write_enable = weight_transfer;

  always_comb begin
    matching_bank_valid = 1'b0;
    matching_bank = 1'b0;
    if (bank_valid[0] && (bank_layer_id[0] == parameter_layer_id)) begin
      matching_bank_valid = 1'b1;
      matching_bank = 1'b0;
    end else if (bank_valid[1] && (bank_layer_id[1] == parameter_layer_id)) begin
      matching_bank_valid = 1'b1;
      matching_bank = 1'b1;
    end
  end

  assign parameter_ready = parameter_request && !compute_active && matching_bank_valid;
  assign parameter_use_scratchpad_weights = compute_active || parameter_ready;
  assign overlap_active = load_busy && compute_active;
  assign bank0_layer_id = bank_layer_id[0];
  assign bank1_layer_id = bank_layer_id[1];

  always_comb begin
    logic selected_parameter_bank;
    selected_parameter_bank = compute_active ? compute_bank : matching_bank;
    parameter_quant_enable = bank_quant_enable[selected_parameter_bank];
    parameter_quant_shift = bank_quant_shift[selected_parameter_bank];
    for (int channel = 0; channel < MAX_COUT; channel++) begin
      parameter_bias[channel] = bias_bank[selected_parameter_bank][channel];
    end
  end

  ping_pong_weight_scratchpad #(
    .PC(PC),
    .PK(PK),
    .MAX_CIN(MAX_CIN),
    .MAX_COUT(MAX_COUT),
    .DATA_W(DATA_W),
    .COUNT_W(COUNT_W)
  ) u_ping_pong_weight_scratchpad (
    .clk(clk),
    .write_bank(load_bank),
    .write_enable(scratch_write_enable),
    .write_out_channel(write_out_channel),
    .write_in_channel(write_in_channel),
    .write_kernel_idx(write_kernel_idx),
    .write_data(weight_data),
    .read_bank(compute_active ? compute_bank : matching_bank),
    .read_k_base(weight_read_k_base),
    .read_c_base(weight_read_c_base),
    .read_kernel_idx(weight_read_kernel_idx),
    .out_lane_mask(weight_out_lane_mask),
    .in_lane_mask(weight_in_lane_mask),
    .weight_mat(weight_mat_data),
    .debug_bank(1'b0),
    .debug_out_channel('0),
    .debug_in_channel('0),
    .debug_kernel_idx('0),
    .debug_read_data(scratch_debug_data)
  );

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      load_state <= S_IDLE;
      bank_valid <= 2'b00;
      bank_layer_id[0] <= '0;
      bank_layer_id[1] <= '0;
      bank_quant_enable[0] <= 1'b0;
      bank_quant_enable[1] <= 1'b0;
      bank_quant_shift[0] <= '0;
      bank_quant_shift[1] <= '0;
      load_bank <= 1'b0;
      compute_bank <= 1'b0;
      compute_active <= 1'b0;
      load_layer_id_q <= '0;
      load_kernel_size_q <= '0;
      load_cin_q <= '0;
      load_cout_q <= '0;
      load_bias_enable_q <= 1'b0;
      expected_weight_bytes_q <= '0;
      expected_bias_bytes_q <= '0;
      expected_crc32_q <= '0;
      weight_count <= '0;
      bias_count <= '0;
      write_out_channel <= '0;
      write_in_channel <= '0;
      write_kernel_idx <= '0;
      write_bias_channel <= '0;
      crc_q <= 32'hFFFF_FFFF;
      load_done <= 1'b0;
      error <= 1'b0;
      error_code <= PARAMETER_OK;
      for (int bank = 0; bank < 2; bank++) begin
        for (int channel = 0; channel < MAX_COUT; channel++) begin
          bias_bank[bank][channel] <= '0;
        end
      end
    end else begin
      load_done <= 1'b0;
      if (clear_error) begin
        error <= 1'b0;
        error_code <= PARAMETER_OK;
      end

      if (parameter_ready) begin
        compute_bank <= matching_bank;
        compute_active <= 1'b1;
      end

      if (parameter_release) begin
        if (compute_active) begin
          bank_valid[compute_bank] <= 1'b0;
          compute_active <= 1'b0;
        end else begin
          error <= 1'b1;
          error_code <= PARAMETER_BAD_OWNERSHIP;
        end
      end

      case (load_state)
        S_IDLE: begin
          if (load_start) begin
            if (!load_ready) begin
              error <= 1'b1;
              error_code <= PARAMETER_NO_FREE_BANK;
              load_done <= 1'b1;
            end else if (!load_config_valid || layer_already_buffered) begin
              error <= 1'b1;
              error_code <= ((32'(load_weight_bytes) != calculated_weight_bytes) ||
                             (32'(load_bias_bytes) != calculated_bias_bytes)) ?
                            PARAMETER_BAD_LENGTH : PARAMETER_BAD_CONFIG;
              load_done <= 1'b1;
            end else begin
              load_bank <= selected_free_bank;
              load_layer_id_q <= load_layer_id;
              load_kernel_size_q <= load_kernel_size;
              load_cin_q <= load_cin;
              load_cout_q <= load_cout;
              load_bias_enable_q <= load_bias_enable;
              expected_weight_bytes_q <= load_weight_bytes;
              expected_bias_bytes_q <= load_bias_bytes;
              expected_crc32_q <= load_expected_crc32;
              weight_count <= '0;
              bias_count <= '0;
              write_out_channel <= '0;
              write_in_channel <= '0;
              write_kernel_idx <= '0;
              write_bias_channel <= '0;
              crc_q <= 32'hFFFF_FFFF;
              bank_valid[selected_free_bank] <= 1'b0;
              bank_quant_enable[selected_free_bank] <= load_quant_enable;
              bank_quant_shift[selected_free_bank] <= load_quant_shift;
              for (int channel = 0; channel < MAX_COUT; channel++) begin
                bias_bank[selected_free_bank][channel] <= '0;
              end
              load_state <= S_LOAD_WEIGHTS;
            end
          end
        end

        S_LOAD_WEIGHTS: begin
          if (weight_transfer) begin
            crc_q <= crc32_byte(crc_q, weight_data);
            weight_count <= weight_count + 16'd1;
            if (last_weight) begin
              load_state <= load_bias_enable_q ? S_LOAD_BIASES : S_VERIFY;
            end else if (write_kernel_idx + 4'd1 >=
                         ((load_kernel_size_q == 2'd1) ? 4'd1 : 4'd9)) begin
              write_kernel_idx <= '0;
              if (write_in_channel + COUNT_W'(1) >= load_cin_q) begin
                write_in_channel <= '0;
                write_out_channel <= write_out_channel + COUNT_W'(1);
              end else begin
                write_in_channel <= write_in_channel + COUNT_W'(1);
              end
            end else begin
              write_kernel_idx <= write_kernel_idx + 4'd1;
            end
          end
        end

        S_LOAD_BIASES: begin
          if (bias_transfer) begin
            bias_bank[load_bank][int'(write_bias_channel)] <= bias_data;
            crc_q <= crc32_word_le(crc_q, bias_data);
            bias_count <= bias_count + 16'd4;
            if (last_bias) begin
              load_state <= S_VERIFY;
            end else begin
              write_bias_channel <= write_bias_channel + COUNT_W'(1);
            end
          end
        end

        S_VERIFY: begin
          load_done <= 1'b1;
          if ((weight_count != expected_weight_bytes_q) ||
              (bias_count != expected_bias_bytes_q)) begin
            error <= 1'b1;
            error_code <= PARAMETER_BAD_LENGTH;
          end else if ((crc_q ^ 32'hFFFF_FFFF) != expected_crc32_q) begin
            error <= 1'b1;
            error_code <= PARAMETER_BAD_CRC;
          end else begin
            bank_layer_id[load_bank] <= load_layer_id_q;
            bank_valid[load_bank] <= 1'b1;
          end
          load_state <= S_IDLE;
        end

        default: begin
          error <= 1'b1;
          error_code <= PARAMETER_BAD_CONFIG;
          load_state <= S_IDLE;
        end
      endcase
    end
  end
endmodule
