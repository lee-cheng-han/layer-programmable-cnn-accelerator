`timescale 1ns/1ps

module tb_tiled_layer_runtime_3x3_stride2;
  import cnn_dma_packet_pkg::*;

  localparam int PC = 2;
  localparam int PK = 2;
  localparam int MAX_CIN = 2;
  localparam int MAX_COUT = 2;
  localparam int INPUT_WIDTH = 5;
  localparam int OUTPUT_WIDTH = 3;
  localparam int OUTPUT_HEIGHT = 3;

  logic clk = 1'b0;
  logic rst_n = 1'b0;
  logic clear = 1'b0;
  logic start = 1'b0;
  logic [31:0] job_id = 32'd100;
  logic [15:0] layer_id = 16'd2;
  logic [15:0] input_tensor_id = 16'd8;
  logic [15:0] output_tensor_id = 16'd9;
  logic [15:0] input_width = 16'd5;
  logic [15:0] input_height = 16'd5;
  logic [15:0] output_width = 16'd3;
  logic [15:0] output_height = 16'd3;
  logic [1:0] kernel_size = 2'd3;
  logic [1:0] stride = 2'd2;
  logic padding_left = 1'b1;
  logic padding_right = 1'b1;
  logic padding_top = 1'b1;
  logic padding_bottom = 1'b1;
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
  logic [31:0] activation_job_id = 32'd100;
  logic [15:0] activation_tensor_id = 16'd8;
  logic [15:0] activation_layer_id = 16'd2;
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
  logic [3:0] weight_write_kernel_idx = 4'd4;
  logic signed [7:0] weight_write_data = 8'sd1;
  logic signed [7:0] weight_debug_data;

  logic output_packet_start;
  logic [7:0] output_packet_type;
  logic [31:0] output_job_id;
  logic [15:0] output_tensor_id_seen;
  logic [15:0] output_layer_id;
  logic [15:0] output_tile_x;
  logic [15:0] output_tile_y;
  logic [15:0] output_tile_width;
  logic [15:0] output_tile_height;
  logic [15:0] output_channel_offset;
  logic [15:0] output_channel_count;
  logic [31:0] output_payload_length;
  logic output_payload_valid;
  logic output_payload_ready;
  logic [31:0] output_payload_data;
  logic [3:0] output_payload_keep;
  logic output_payload_last;
  logic output_parser_error;
  logic [7:0] output_parser_error_code;
  logic [31:0] output_parser_error_count;

  logic [15:0] packet_tile_x_q;
  logic [15:0] packet_tile_y_q;
  logic [15:0] packet_tile_width_q;
  int output_byte_index;
  int output_packet_count;
  int output_ready_counter;
  logic signed [7:0] reconstructed_output [0:OUTPUT_WIDTH*OUTPUT_HEIGHT-1];

  always #5 clk = ~clk;

  assign parameter_ready =
    parameter_request && (parameter_layer_id == layer_id[2:0]);

  always_comb begin
    for (int channel = 0; channel < MAX_COUT; channel++) begin
      parameter_bias[channel] = '0;
      quant_multiplier[channel] = 32'sd1;
      quant_shift[channel] = '0;
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

  packed_dma_packet_parser #(
    .MAX_PAYLOAD_BYTES(64)
  ) output_parser (
    .clk(clk),
    .rst_n(rst_n),
    .clear(clear),
    .s_axis_tdata(m_axis_tdata),
    .s_axis_tkeep(m_axis_tkeep),
    .s_axis_tvalid(m_axis_tvalid),
    .s_axis_tready(m_axis_tready),
    .s_axis_tlast(m_axis_tlast),
    .packet_start(output_packet_start),
    .packet_ready(1'b1),
    .packet_done(),
    .packet_type(output_packet_type),
    .job_id(output_job_id),
    .tensor_id(output_tensor_id_seen),
    .layer_id(output_layer_id),
    .tile_x(output_tile_x),
    .tile_y(output_tile_y),
    .tile_width(output_tile_width),
    .tile_height(output_tile_height),
    .channel_offset(output_channel_offset),
    .channel_count(output_channel_count),
    .payload_length(output_payload_length),
    .payload_valid(output_payload_valid),
    .payload_ready(output_payload_ready),
    .payload_data(output_payload_data),
    .payload_keep(output_payload_keep),
    .payload_last(output_payload_last),
    .packet_busy(),
    .recovering(),
    .error_valid(output_parser_error),
    .error_code(output_parser_error_code),
    .error_count(output_parser_error_count)
  );

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      output_ready_counter <= 0;
      output_payload_ready <= 1'b0;
      packet_tile_x_q <= '0;
      packet_tile_y_q <= '0;
      packet_tile_width_q <= '0;
      output_byte_index <= 0;
      output_packet_count <= 0;
      for (int pixel = 0; pixel < OUTPUT_WIDTH*OUTPUT_HEIGHT; pixel++) begin
        reconstructed_output[pixel] <= '0;
      end
    end else begin
      output_ready_counter <= output_ready_counter + 1;
      output_payload_ready <= (output_ready_counter % 5) != 2;

      if (output_packet_start) begin
        if ((output_packet_type != DMA_PACKET_OUTPUT_TILE) ||
            (output_job_id != job_id) ||
            (output_tensor_id_seen != output_tensor_id) ||
            (output_layer_id != layer_id) ||
            (output_channel_offset != 0) ||
            (output_channel_count != 1) ||
            (output_payload_length !=
             (32'(output_tile_width) * 32'(output_tile_height)))) begin
          $fatal(1, "invalid output packet metadata");
        end
        packet_tile_x_q <= output_tile_x;
        packet_tile_y_q <= output_tile_y;
        packet_tile_width_q <= output_tile_width;
        output_byte_index <= 0;
        output_packet_count <= output_packet_count + 1;
      end

      if (output_payload_valid && output_payload_ready) begin
        for (int lane = 0; lane < 4; lane++) begin
          if (output_payload_keep[lane]) begin
            int local_x;
            int local_y;
            int global_pixel;
            local_x = (output_byte_index + lane) % int'(packet_tile_width_q);
            local_y = (output_byte_index + lane) / int'(packet_tile_width_q);
            global_pixel =
              ((int'(packet_tile_y_q) + local_y) * OUTPUT_WIDTH) +
              int'(packet_tile_x_q) + local_x;
            reconstructed_output[global_pixel] <=
              $signed(output_payload_data[(lane * 8) +: 8]);
          end
        end
        output_byte_index <= output_byte_index +
          int'(output_payload_keep[0]) + int'(output_payload_keep[1]) +
          int'(output_payload_keep[2]) + int'(output_payload_keep[3]);
      end
    end
  end

  task automatic pulse_start;
    begin
      @(negedge clk);
      start = 1'b1;
      @(negedge clk);
      start = 1'b0;
    end
  endtask

  task automatic send_activation_beat(
    input logic [31:0] data,
    input logic [3:0] keep,
    input logic last
  );
    begin
      wait (activation_ready);
      @(negedge clk);
      activation_data = data;
      activation_keep = keep;
      activation_last = last;
      activation_valid = 1'b1;
      @(posedge clk);
      #1;
      activation_valid = 1'b0;
      activation_last = 1'b0;
    end
  endtask

  task automatic send_input_tile(
    input int tile_x_value,
    input int tile_y_value,
    input int tile_width_value,
    input int tile_height_value,
    input int source_x_value,
    input int source_y_value,
    input int source_width_value,
    input int source_height_value
  );
    logic [31:0] beat_data;
    logic [3:0] beat_keep;
    int payload_bytes;
    int byte_index;
    begin
      payload_bytes = source_width_value * source_height_value;
      activation_tile_x = 16'(tile_x_value);
      activation_tile_y = 16'(tile_y_value);
      activation_tile_width = 16'(tile_width_value);
      activation_tile_height = 16'(tile_height_value);
      activation_payload_length = 32'(payload_bytes);

      wait (activation_packet_ready);
      @(negedge clk);
      activation_packet_start = 1'b1;
      @(negedge clk);
      activation_packet_start = 1'b0;

      byte_index = 0;
      while (byte_index < payload_bytes) begin
        beat_data = '0;
        beat_keep = '0;
        for (int lane = 0; lane < 4; lane++) begin
          if ((byte_index + lane) < payload_bytes) begin
            int source_local_x;
            int source_local_y;
            int value;
            source_local_x = (byte_index + lane) % source_width_value;
            source_local_y = (byte_index + lane) / source_width_value;
            value =
              ((source_y_value + source_local_y) * INPUT_WIDTH) +
              source_x_value + source_local_x + 1;
            beat_data[(lane * 8) +: 8] = 8'(value);
            beat_keep[lane] = 1'b1;
          end
        end
        send_activation_beat(
          beat_data,
          beat_keep,
          (byte_index + 4) >= payload_bytes
        );
        byte_index = byte_index + 4;
      end
    end
  endtask

  initial begin
    repeat (4) @(posedge clk);
    rst_n = 1'b1;

    @(negedge clk);
    weight_write_enable = 1'b1;
    @(negedge clk);
    weight_write_enable = 1'b0;
    repeat (3) @(posedge clk);

    pulse_start();
    send_input_tile(0, 0, 2, 2, 0, 0, 4, 4);
    send_input_tile(2, 0, 1, 2, 3, 0, 2, 4);
    send_input_tile(0, 2, 2, 1, 0, 3, 4, 2);
    send_input_tile(2, 2, 1, 1, 3, 3, 2, 2);

    fork
      begin
        wait (done);
      end
      begin
        repeat (12000) @(posedge clk);
        $fatal(1,
          "3x3 stride-2 timeout tile=(%0d,%0d) completed=%0d packets=%0d busy=%0d error=%0d/%0d loader=%0d",
          current_tile_x, current_tile_y, completed_tile_count,
          output_packet_count, busy, error, error_code, dut.loader_error_code
        );
      end
    join_any
    disable fork;
    repeat (3) @(posedge clk);

    if (error) $fatal(1, "runtime error=%0d", error_code);
    if (output_parser_error || (output_parser_error_count != 0)) begin
      $fatal(1, "output parser error=%0d", output_parser_error_code);
    end
    if ((completed_tile_count != 4) || (output_packet_count != 4)) begin
      $fatal(1, "tile counts runtime=%0d output=%0d",
             completed_tile_count, output_packet_count);
    end

    for (int output_y = 0; output_y < OUTPUT_HEIGHT; output_y++) begin
      for (int output_x = 0; output_x < OUTPUT_WIDTH; output_x++) begin
        int expected;
        int output_pixel;
        expected = ((output_y * 2) * INPUT_WIDTH) + (output_x * 2) + 1;
        output_pixel = (output_y * OUTPUT_WIDTH) + output_x;
        if (reconstructed_output[output_pixel] !== $signed(8'(expected))) begin
          $fatal(1, "output[%0d,%0d]=%0d expected=%0d",
                 output_y, output_x,
                 reconstructed_output[output_pixel], expected);
        end
      end
    end

    $display("[PASS] tiled 3x3 stride-2 halo golden output");
    $finish;
  end
endmodule
