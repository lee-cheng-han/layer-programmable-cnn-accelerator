`timescale 1ns/1ps

module tb_tiled_multi_layer_controller;
  import cnn_accel_abi_pkg::*;
  import cnn_dma_packet_pkg::*;

  localparam int PC = 2;
  localparam int PK = 2;
  localparam int MAX_CIN = 2;
  localparam int MAX_COUT = 2;

  logic clk = 1'b0;
  logic rst_n = 1'b0;
  logic clear = 1'b0;
  logic start = 1'b0;
  logic [31:0] job_id = 32'd200;
  logic model_active_valid = 1'b1;
  logic [15:0] model_layer_count = 16'd2;
  logic [2:0] descriptor_layer_index;
  logic descriptor_valid;
  logic [15:0] descriptor_layer_id;
  logic [15:0] descriptor_opcode;
  logic descriptor_last_layer;
  logic descriptor_bias_enable;
  logic [15:0] descriptor_input_tensor_id;
  logic [15:0] descriptor_output_tensor_id;
  logic [15:0] descriptor_residual_tensor_id;
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
  logic bad_chain;

  logic parameter_request;
  logic [2:0] parameter_layer_id;
  logic parameter_ready;
  logic parameter_release;
  logic parameter_quant_enable = 1'b0;
  logic [4:0] parameter_quant_shift = '0;
  logic signed [31:0] parameter_bias [MAX_COUT];
  logic [7:0] parameter_weight_read_k_base;
  logic [7:0] parameter_weight_read_c_base;
  logic [3:0] parameter_weight_read_kernel_idx;
  logic [PK-1:0] parameter_weight_out_lane_mask;
  logic [PC-1:0] parameter_weight_in_lane_mask;
  logic signed [7:0] parameter_weight_mat_data [PK][PC];

  logic activation_packet_start = 1'b0;
  logic activation_packet_ready;
  logic [31:0] activation_job_id;
  logic [15:0] activation_tensor_id;
  logic [15:0] activation_layer_id;
  logic [15:0] activation_tile_x;
  logic [15:0] activation_tile_y;
  logic [15:0] activation_tile_width;
  logic [15:0] activation_tile_height;
  logic [15:0] activation_channel_offset = 16'd0;
  logic [15:0] activation_channel_count = 16'd1;
  logic [31:0] activation_payload_length;
  logic activation_valid = 1'b0;
  logic activation_ready;
  logic [31:0] activation_data = '0;
  logic [3:0] activation_keep = '0;
  logic activation_last = 1'b0;

  logic [31:0] m_axis_tdata;
  logic [3:0] m_axis_tkeep;
  logic m_axis_tvalid;
  logic m_axis_tready;
  logic m_axis_tlast;
  logic [2:0] active_layer;
  logic [15:0] active_input_tensor_id;
  logic [15:0] active_output_tensor_id;
  logic [63:0] active_input_ddr_offset;
  logic [31:0] active_input_allocation_size;
  logic [31:0] active_input_row_stride;
  logic [31:0] active_input_pixel_stride;
  logic [31:0] active_input_channel_stride;
  logic [63:0] active_output_ddr_offset;
  logic [31:0] active_output_allocation_size;
  logic [31:0] active_output_row_stride;
  logic [31:0] active_output_pixel_stride;
  logic [31:0] active_output_channel_stride;
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

  logic weight_write_enable = 1'b0;
  logic [7:0] weight_write_out_channel = '0;
  logic [7:0] weight_write_in_channel = '0;
  logic [3:0] weight_write_kernel_idx = '0;
  logic signed [7:0] weight_write_data = 8'sd1;
  logic signed [7:0] weight_debug_data;
  logic [31:0] captured_data [0:63];
  logic [3:0] captured_keep [0:63];
  logic captured_last [0:63];
  int captured_count;
  int ready_counter;

  always #5 clk = ~clk;

  assign parameter_ready =
    parameter_request && (parameter_layer_id == active_layer);

  always_comb begin
    descriptor_valid = 1'b1;
    descriptor_layer_id = 16'(descriptor_layer_index);
    descriptor_opcode = OPCODE_CONV2D;
    descriptor_last_layer = descriptor_layer_index == 3'd1;
    descriptor_bias_enable = 1'b0;
    descriptor_input_tensor_id =
      (descriptor_layer_index == 0) ? 16'd0 : 16'd1;
    descriptor_output_tensor_id =
      (descriptor_layer_index == 0) ? 16'd1 : 16'd2;
    descriptor_residual_tensor_id = NO_TENSOR_ID;
    descriptor_input_width = 16'd3;
    descriptor_input_height = 16'd2;
    descriptor_input_channels = 16'd1;
    descriptor_output_width = 16'd3;
    descriptor_output_height = 16'd2;
    descriptor_output_channels = 16'd1;
    descriptor_kernel_height = 8'd1;
    descriptor_kernel_width = 8'd1;
    descriptor_stride_y = 8'd1;
    descriptor_stride_x = 8'd1;
    descriptor_padding_top = 8'd0;
    descriptor_padding_bottom = 8'd0;
    descriptor_padding_left = 8'd0;
    descriptor_padding_right = 8'd0;
    descriptor_dilation_y = 8'd1;
    descriptor_dilation_x = 8'd1;
    descriptor_activation = ACTIVATION_NONE;
    descriptor_residual_mode = RESIDUAL_NONE;
    descriptor_tile_height_hint = 16'd2;
    descriptor_tile_width_hint = 16'd2;
    descriptor_input_ddr_offset =
      (descriptor_layer_index == 0) ? 64'h1000 :
      (bad_chain ? 64'h2800 : 64'h2000);
    descriptor_output_ddr_offset =
      (descriptor_layer_index == 0) ? 64'h2000 : 64'h3000;
    descriptor_input_allocation_size = 32'd6;
    descriptor_input_row_stride = 32'd3;
    descriptor_input_pixel_stride = 32'd1;
    descriptor_input_channel_stride = 32'd1;
    descriptor_output_allocation_size = 32'd6;
    descriptor_output_row_stride = 32'd3;
    descriptor_output_pixel_stride = 32'd1;
    descriptor_output_channel_stride = 32'd1;

    for (int channel = 0; channel < MAX_COUT; channel++) begin
      parameter_bias[channel] = '0;
    end
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      captured_count <= 0;
      ready_counter <= 0;
      m_axis_tready <= 1'b0;
    end else begin
      ready_counter <= ready_counter + 1;
      m_axis_tready <= (ready_counter % 4) != 1;
      if (m_axis_tvalid && m_axis_tready) begin
        captured_data[captured_count] <= m_axis_tdata;
        captured_keep[captured_count] <= m_axis_tkeep;
        captured_last[captured_count] <= m_axis_tlast;
        captured_count <= captured_count + 1;
      end
    end
  end

  banked_weight_scratchpad #(
    .PC(PC),
    .PK(PK),
    .MAX_CIN(MAX_CIN),
    .MAX_COUT(MAX_COUT)
  ) weight_scratchpad (
    .clk(clk),
    .write_enable(weight_write_enable),
    .write_out_channel(weight_write_out_channel),
    .write_in_channel(weight_write_in_channel),
    .write_kernel_idx(weight_write_kernel_idx),
    .write_data(weight_write_data),
    .read_k_base(parameter_weight_read_k_base),
    .read_c_base(parameter_weight_read_c_base),
    .read_kernel_idx(parameter_weight_read_kernel_idx),
    .out_lane_mask(parameter_weight_out_lane_mask),
    .in_lane_mask(parameter_weight_in_lane_mask),
    .weight_mat(parameter_weight_mat_data),
    .debug_out_channel('0),
    .debug_in_channel('0),
    .debug_kernel_idx('0),
    .debug_read_data(weight_debug_data)
  );

  cnn_tiled_multi_layer_controller #(
    .PC(PC),
    .PK(PK),
    .MAX_CIN(MAX_CIN),
    .MAX_COUT(MAX_COUT),
    .MAX_LAYERS(2),
    .MAX_TILE_WIDTH(2),
    .MAX_TILE_HEIGHT(2)
  ) dut (.*);

  task automatic pulse_start;
    begin
      @(negedge clk);
      start = 1'b1;
      @(negedge clk);
      start = 1'b0;
    end
  endtask

  task automatic send_tile(
    input int expected_layer,
    input int expected_tensor,
    input int tile_x_value,
    input int tile_width_value,
    input logic [31:0] data,
    input logic [3:0] keep,
    input int length
  );
    begin
      wait ((active_layer == expected_layer) && activation_packet_ready);
      activation_job_id = job_id;
      activation_tensor_id = 16'(expected_tensor);
      activation_layer_id = 16'(expected_layer);
      activation_tile_x = 16'(tile_x_value);
      activation_tile_y = 16'd0;
      activation_tile_width = 16'(tile_width_value);
      activation_tile_height = 16'd2;
      activation_payload_length = 32'(length);
      @(negedge clk);
      activation_packet_start = 1'b1;
      @(negedge clk);
      activation_packet_start = 1'b0;
      wait (activation_ready);
      @(negedge clk);
      activation_data = data;
      activation_keep = keep;
      activation_last = 1'b1;
      activation_valid = 1'b1;
      @(posedge clk);
      #1;
      activation_valid = 1'b0;
      activation_last = 1'b0;
    end
  endtask

  task automatic run_layer_zero_tiles;
    begin
      send_tile(0, 0, 0, 2, 32'h0504_0201, 4'b1111, 4);
      send_tile(0, 0, 2, 1, 32'h0000_0603, 4'b0011, 2);
    end
  endtask

  initial begin
    bad_chain = 1'b0;
    activation_job_id = '0;
    activation_tensor_id = '0;
    activation_layer_id = '0;
    activation_tile_x = '0;
    activation_tile_y = '0;
    activation_tile_width = '0;
    activation_tile_height = '0;
    activation_payload_length = '0;

    repeat (4) @(posedge clk);
    rst_n = 1'b1;
    @(negedge clk);
    weight_write_enable = 1'b1;
    @(negedge clk);
    weight_write_enable = 1'b0;
    repeat (3) @(posedge clk);

    pulse_start();
    run_layer_zero_tiles();
    send_tile(1, 1, 0, 2, 32'h0504_0201, 4'b1111, 4);
    send_tile(1, 1, 2, 1, 32'h0000_0603, 4'b0011, 2);

    fork
      wait (done);
      begin
        repeat (10000) @(posedge clk);
        $fatal(1, "two-layer tiled job timed out");
      end
    join_any
    disable fork;
    repeat (2) @(posedge clk);

    if (error || (completed_layer_count != 2) || (captured_count != 36)) begin
      $fatal(1, "valid job error=%0d/%0d layers=%0d beats=%0d",
             error, error_code, completed_layer_count, captured_count);
    end
    if ((captured_data[3] != {16'd0, 16'd1}) ||
        (captured_data[8] != 32'h0504_0201) ||
        (captured_data[12] != {16'd0, 16'd1}) ||
        (captured_data[17] != 32'h0000_0603) ||
        (captured_data[21] != {16'd1, 16'd2}) ||
        (captured_data[26] != 32'h0504_0201) ||
        (captured_data[30] != {16'd1, 16'd2}) ||
        (captured_data[35] != 32'h0000_0603) ||
        (captured_keep[35] != 4'b0011) || !captured_last[35]) begin
      $fatal(1, "multi-layer packet content mismatch");
    end

    bad_chain = 1'b1;
    job_id = 32'd201;
    pulse_start();
    run_layer_zero_tiles();
    fork
      wait (done);
      begin
        repeat (6000) @(posedge clk);
        $fatal(1, "bad-chain job timed out");
      end
    join_any
    disable fork;

    if (!error || (error_code != 8'd6) || (error_layer != 1) ||
        (completed_layer_count != 1)) begin
      $fatal(1, "bad chain not rejected error=%0d/%0d layer=%0d complete=%0d",
             error, error_code, error_layer, completed_layer_count);
    end

    $display("[PASS] tiled two-layer DDR handoff and chain rejection");
    $finish;
  end
endmodule
