`timescale 1ns/1ps

module tb_halo_tile_load_controller;
  localparam int PC = 2;
  localparam int MAX_LOCAL_PIXELS = 25;
  localparam int MAX_CHANNELS = 2;
  localparam int DIM_W = 16;
  localparam int COUNT_W = 8;
  localparam int ADDR_W = 32;

  logic clk = 1'b0;
  logic rst_n = 1'b0;
  logic clear = 1'b0;
  logic expected_valid = 1'b1;
  logic [31:0] expected_job_id = 32'h1234;
  logic [15:0] expected_tensor_id = 16'd7;
  logic [15:0] expected_layer_id = 16'd2;
  logic [15:0] expected_tile_x = 16'd0;
  logic [15:0] expected_tile_y = 16'd0;
  logic [15:0] expected_tile_width = 16'd2;
  logic [15:0] expected_tile_height = 16'd2;
  logic [DIM_W-1:0] local_input_width = 16'd5;
  logic [DIM_W-1:0] local_input_height = 16'd5;
  logic [DIM_W-1:0] source_width = 16'd4;
  logic [DIM_W-1:0] source_height = 16'd4;
  logic [DIM_W-1:0] local_x_offset = 16'd1;
  logic [DIM_W-1:0] local_y_offset = 16'd1;
  logic [COUNT_W-1:0] input_channels = 8'd2;
  logic [31:0] expected_payload_bytes = 32'd32;
  logic packet_start = 1'b0;
  logic packet_ready;
  logic [31:0] packet_job_id = 32'h1234;
  logic [15:0] packet_tensor_id = 16'd7;
  logic [15:0] packet_layer_id = 16'd2;
  logic [15:0] packet_tile_x = 16'd0;
  logic [15:0] packet_tile_y = 16'd0;
  logic [15:0] packet_tile_width = 16'd2;
  logic [15:0] packet_tile_height = 16'd2;
  logic [15:0] packet_channel_offset = 16'd0;
  logic [15:0] packet_channel_count = 16'd2;
  logic [31:0] packet_payload_length = 32'd32;
  logic payload_valid = 1'b0;
  logic payload_ready;
  logic [31:0] payload_data = '0;
  logic [3:0] payload_keep = '0;
  logic payload_last = 1'b0;
  logic scratch_write_enable;
  logic [ADDR_W-1:0] scratch_write_pixel;
  logic [COUNT_W-1:0] scratch_write_channel;
  logic signed [7:0] scratch_write_data;
  logic busy;
  logic done;
  logic error;
  logic [7:0] error_code;

  logic [ADDR_W-1:0] scratch_read_pixel = '0;
  logic [COUNT_W-1:0] scratch_read_c_base = '0;
  logic [PC-1:0] scratch_lane_mask = '0;
  logic signed [7:0] scratch_lane_data [PC];
  logic [ADDR_W-1:0] debug_read_pixel = '0;
  logic [COUNT_W-1:0] debug_read_channel = '0;
  logic signed [7:0] debug_read_data;

  always #5 clk = ~clk;

  halo_tile_load_controller #(
    .MAX_LOCAL_PIXELS(MAX_LOCAL_PIXELS),
    .MAX_CHANNELS(MAX_CHANNELS)
  ) dut (
    .*,
    .scratch_write_enable(scratch_write_enable),
    .scratch_write_pixel(scratch_write_pixel),
    .scratch_write_channel(scratch_write_channel),
    .scratch_write_data(scratch_write_data)
  );

  banked_activation_scratchpad #(
    .PC(PC),
    .MAX_PIXELS(MAX_LOCAL_PIXELS),
    .MAX_C(MAX_CHANNELS)
  ) scratchpad (
    .clk(clk),
    .write_enable(scratch_write_enable),
    .write_pixel(scratch_write_pixel),
    .write_channel(scratch_write_channel),
    .write_data(scratch_write_data),
    .read_pixel(scratch_read_pixel),
    .read_c_base(scratch_read_c_base),
    .lane_mask(scratch_lane_mask),
    .lane_data(scratch_lane_data),
    .debug_read_pixel(debug_read_pixel),
    .debug_read_channel(debug_read_channel),
    .debug_read_data(debug_read_data)
  );

  task automatic send_header;
    begin
      wait (packet_ready);
      @(negedge clk);
      packet_start = 1'b1;
      @(negedge clk);
      packet_start = 1'b0;
    end
  endtask

  task automatic send_beat(
    input logic [31:0] data,
    input logic [3:0] keep,
    input logic last
  );
    begin
      wait (payload_ready);
      @(negedge clk);
      payload_data = data;
      payload_keep = keep;
      payload_last = last;
      payload_valid = 1'b1;
      @(posedge clk);
      #1;
      payload_valid = 1'b0;
      payload_last = 1'b0;
    end
  endtask

  task automatic check_cell(
    input int pixel,
    input int channel,
    input int expected
  );
    begin
      @(negedge clk);
      debug_read_pixel = pixel;
      debug_read_channel = channel;
      @(posedge clk);
      #1;
      if (debug_read_data !== $signed(8'(expected))) begin
        $fatal(1, "scratch[%0d][%0d]=%0d expected %0d",
               pixel, channel, debug_read_data, expected);
      end
    end
  endtask

  initial begin
    repeat (4) @(posedge clk);
    rst_n = 1'b1;

    send_header();
    if (payload_ready) begin
      $fatal(1, "payload admitted before local halo clear completed");
    end
    for (int beat = 0; beat < 8; beat++) begin
      send_beat({
        8'((beat * 4) + 4),
        8'((beat * 4) + 3),
        8'((beat * 4) + 2),
        8'((beat * 4) + 1)
      }, 4'b1111, beat == 7);
    end
    wait (done);
    if (error) $fatal(1, "valid halo tile load failed: %0d", error_code);

    for (int y = 0; y < 5; y++) begin
      for (int x = 0; x < 5; x++) begin
        for (int c = 0; c < 2; c++) begin
          if ((x == 0) || (y == 0)) begin
            check_cell((y * 5) + x, c, 0);
          end else begin
            check_cell(
              (y * 5) + x,
              c,
              ((((y - 1) * 4) + (x - 1)) * 2) + c + 1
            );
          end
        end
      end
    end

    packet_payload_length = 32'd4;
    send_header();
    send_beat(32'h0403_0201, 4'b1111, 1'b1);
    wait (done);
    if (!error || (error_code != 8'd3)) begin
      $fatal(1, "bad payload length was not rejected");
    end

    $display("[PASS] halo tile load, zero fill, packing, and validation");
    $finish;
  end
endmodule
