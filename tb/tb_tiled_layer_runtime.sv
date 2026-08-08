`timescale 1ns/1ps

module tb_tiled_layer_runtime;
  import cnn_dma_packet_pkg::*;

  localparam int PC = 2;
  localparam int PK = 2;
  localparam int MAX_CIN = 2;
  localparam int MAX_COUT = 2;

  logic clk = 1'b0;
  logic rst_n = 1'b0;
  logic clear = 1'b0;
  logic start = 1'b0;
  logic [31:0] job_id = 32'd99;
  logic [15:0] layer_id = 16'd1;
  logic [15:0] input_tensor_id = 16'd4;
  logic [15:0] output_tensor_id = 16'd5;
  logic [15:0] input_width = 16'd3;
  logic [15:0] input_height = 16'd2;
  logic [15:0] output_width = 16'd3;
  logic [15:0] output_height = 16'd2;
  logic [1:0] kernel_size = 2'd1;
  logic [1:0] stride = 2'd1;
  logic padding_left = 1'b0;
  logic padding_right = 1'b0;
  logic padding_top = 1'b0;
  logic padding_bottom = 1'b0;
  logic [7:0] cin = 8'd1;
  logic [7:0] cout = 8'd1;
  logic bias_enable = 1'b0;
  logic relu_enable = 1'b0;
  logic [15:0] tile_width_hint = 16'd2;
  logic [15:0] tile_height_hint = 16'd2;
  logic per_channel_quant_enable = 1'b0;
  logic signed [31:0] quant_multiplier [MAX_COUT];
  logic [5:0] quant_shift [MAX_COUT];
  logic signed [7:0] output_zero_point = '0;
  logic [15:0] residual_tensor_id = 16'hFFFF;
  logic [7:0] residual_mode = 8'd0;

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
  logic [31:0] activation_job_id = 32'd99;
  logic [15:0] activation_tensor_id = 16'd4;
  logic [15:0] activation_layer_id = 16'd1;
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
  logic [15:0] current_tile_x;
  logic [15:0] current_tile_y;
  logic [31:0] completed_tile_count;
  logic [31:0] saturation_event_count;
  logic busy;
  logic done;
  logic error;
  logic [7:0] error_code;

  logic weight_write_enable = 1'b0;
  logic [7:0] weight_write_out_channel = '0;
  logic [7:0] weight_write_in_channel = '0;
  logic [3:0] weight_write_kernel_idx = '0;
  logic signed [7:0] weight_write_data = '0;
  logic signed [7:0] weight_debug_data;
  logic [31:0] captured_data [0:31];
  logic [3:0] captured_keep [0:31];
  logic captured_last [0:31];
  int captured_count = 0;
  int ready_counter = 0;

  always #5 clk = ~clk;

  assign parameter_ready = parameter_request &&
                           (parameter_layer_id == layer_id[2:0]);

  always_comb begin
    for (int channel = 0; channel < MAX_COUT; channel++) begin
      parameter_bias[channel] = '0;
      quant_multiplier[channel] = 32'sd1;
      quant_shift[channel] = '0;
    end
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      ready_counter <= 0;
      m_axis_tready <= 1'b0;
      captured_count <= 0;
    end else begin
      ready_counter <= ready_counter + 1;
      m_axis_tready <= (ready_counter % 4) != 2;
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

  cnn_tiled_layer_runtime #(
    .PC(PC),
    .PK(PK),
    .MAX_CIN(MAX_CIN),
    .MAX_COUT(MAX_COUT),
    .MAX_TILE_WIDTH(2),
    .MAX_TILE_HEIGHT(2),
    .MAX_LOCAL_WIDTH(5),
    .MAX_LOCAL_HEIGHT(5)
  ) dut (.*);

  task automatic load_identity_weight;
    begin
      @(negedge clk);
      weight_write_enable = 1'b1;
      weight_write_data = 8'sd1;
      @(negedge clk);
      weight_write_enable = 1'b0;
      repeat (3) @(posedge clk);
    end
  endtask

  task automatic pulse_start;
    begin
      @(negedge clk);
      start = 1'b1;
      @(negedge clk);
      start = 1'b0;
    end
  endtask

  task automatic send_tile(
    input int tile_x_value,
    input int tile_width_value,
    input logic [31:0] data,
    input logic [3:0] keep,
    input int length
  );
    begin
      activation_tile_x = tile_x_value;
      activation_tile_y = 0;
      activation_tile_width = tile_width_value;
      activation_tile_height = 2;
      activation_payload_length = length;
      wait (activation_packet_ready);
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

  task automatic check_word(
    input int index,
    input logic [31:0] expected_data,
    input logic [3:0] expected_keep,
    input logic expected_last
  );
    begin
      if ((captured_data[index] !== expected_data) ||
          (captured_keep[index] !== expected_keep) ||
          (captured_last[index] !== expected_last)) begin
        $fatal(1,
          "beat %0d got data=%08x keep=%x last=%0d expected=%08x/%x/%0d",
          index, captured_data[index], captured_keep[index],
          captured_last[index], expected_data, expected_keep, expected_last
        );
      end
    end
  endtask

  initial begin
    repeat (4) @(posedge clk);
    rst_n = 1'b1;
    load_identity_weight();
    pulse_start();

    send_tile(0, 2, 32'h0504_0201, 4'b1111, 4);
    wait ((current_tile_x == 2) && activation_packet_ready);
    send_tile(2, 1, 32'h0000_0603, 4'b0011, 2);

    fork
      begin
        wait (done);
      end
      begin
        repeat (5000) @(posedge clk);
        $fatal(1, "tiled layer runtime timed out");
      end
    join_any
    disable fork;

    if (error) $fatal(1, "tiled layer runtime error=%0d", error_code);
    if (completed_tile_count != 2) begin
      $fatal(1, "completed tile count=%0d expected 2", completed_tile_count);
    end
    if (captured_count != 18) begin
      $fatal(1, "captured beat count=%0d expected 18", captured_count);
    end

    check_word(0, DMA_PACKET_MAGIC, 4'b1111, 1'b0);
    check_word(2, 32'd99, 4'b1111, 1'b0);
    check_word(3, {16'd1, 16'd5}, 4'b1111, 1'b0);
    check_word(4, {16'd0, 16'd0}, 4'b1111, 1'b0);
    check_word(5, {16'd2, 16'd2}, 4'b1111, 1'b0);
    check_word(7, 32'd4, 4'b1111, 1'b0);
    check_word(8, 32'h0504_0201, 4'b1111, 1'b1);
    check_word(9, DMA_PACKET_MAGIC, 4'b1111, 1'b0);
    check_word(13, {16'd0, 16'd2}, 4'b1111, 1'b0);
    check_word(14, {16'd2, 16'd1}, 4'b1111, 1'b0);
    check_word(16, 32'd2, 4'b1111, 1'b0);
    check_word(17, 32'h0000_0603, 4'b0011, 1'b1);

    $display("[PASS] tiled layer runtime golden output with backpressure");
    $finish;
  end
endmodule
