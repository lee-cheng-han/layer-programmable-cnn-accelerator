`timescale 1ns/1ps

module tb_spatial_tile_planner;
  localparam int DIM_W = 16;
  localparam int COUNT_W = 8;

  logic clk = 1'b0;
  logic rst_n = 1'b0;
  logic clear = 1'b0;
  logic start = 1'b0;
  logic [DIM_W-1:0] input_width;
  logic [DIM_W-1:0] input_height;
  logic [DIM_W-1:0] output_width;
  logic [DIM_W-1:0] output_height;
  logic [1:0] kernel_width;
  logic [1:0] kernel_height;
  logic [1:0] stride_x;
  logic [1:0] stride_y;
  logic padding_left;
  logic padding_right;
  logic padding_top;
  logic padding_bottom;
  logic [COUNT_W-1:0] input_channels;
  logic [COUNT_W-1:0] output_channels;
  logic [DIM_W-1:0] tile_width_hint;
  logic [DIM_W-1:0] tile_height_hint;
  logic tile_valid;
  logic tile_ready = 1'b0;
  logic first_tile;
  logic last_tile;
  logic [DIM_W-1:0] tile_x;
  logic [DIM_W-1:0] tile_y;
  logic [DIM_W-1:0] tile_width;
  logic [DIM_W-1:0] tile_height;
  logic signed [DIM_W:0] input_origin_x;
  logic signed [DIM_W:0] input_origin_y;
  logic [DIM_W-1:0] local_input_width;
  logic [DIM_W-1:0] local_input_height;
  logic [DIM_W-1:0] source_x;
  logic [DIM_W-1:0] source_y;
  logic [DIM_W-1:0] source_width;
  logic [DIM_W-1:0] source_height;
  logic [DIM_W-1:0] local_x_offset;
  logic [DIM_W-1:0] local_y_offset;
  logic [DIM_W-1:0] padding_right_count;
  logic [DIM_W-1:0] padding_bottom_count;
  logic [31:0] input_payload_bytes;
  logic [31:0] output_payload_bytes;
  logic busy;
  logic done;
  logic error;
  logic [7:0] error_code;
  logic [31:0] random_seed;

  always #5 clk = ~clk;

  spatial_tile_planner dut (.*);

  function automatic int random_range(input int minimum, input int maximum);
    random_seed = (random_seed * 32'd1664525) + 32'd1013904223;
    return minimum + int'(random_seed % (maximum - minimum + 1));
  endfunction

  task automatic pulse_start;
    begin
      @(negedge clk);
      start = 1'b1;
      @(negedge clk);
      start = 1'b0;
    end
  endtask

  task automatic accept_tile(
    input int expected_x,
    input int expected_y,
    input int expected_width,
    input int expected_height
  );
    begin
      wait (tile_valid);
      if ((tile_x != expected_x) || (tile_y != expected_y) ||
          (tile_width != expected_width) ||
          (tile_height != expected_height)) begin
        $fatal(1, "tile mismatch: got (%0d,%0d %0dx%0d)",
               tile_x, tile_y, tile_width, tile_height);
      end
      @(negedge clk);
      tile_ready = 1'b1;
      @(negedge clk);
      tile_ready = 1'b0;
    end
  endtask

  task automatic configure(
    input int in_w,
    input int in_h,
    input int out_w,
    input int out_h,
    input int kernel,
    input int stride,
    input int pad_l,
    input int pad_r,
    input int pad_t,
    input int pad_b,
    input int cin,
    input int cout,
    input int tile_w,
    input int tile_h
  );
    begin
      input_width = in_w;
      input_height = in_h;
      output_width = out_w;
      output_height = out_h;
      kernel_width = kernel;
      kernel_height = kernel;
      stride_x = stride;
      stride_y = stride;
      padding_left = pad_l;
      padding_right = pad_r;
      padding_top = pad_t;
      padding_bottom = pad_b;
      input_channels = cin;
      output_channels = cout;
      tile_width_hint = tile_w;
      tile_height_hint = tile_h;
    end
  endtask

  initial begin
    configure(1, 1, 1, 1, 1, 1, 0, 0, 0, 0, 1, 1, 0, 0);
    repeat (4) @(posedge clk);
    rst_n = 1'b1;

    configure(35, 19, 35, 19, 3, 1, 1, 1, 1, 1, 3, 5, 16, 16);
    pulse_start();
    wait (tile_valid);
    if (!first_tile || (input_origin_x != -1) || (input_origin_y != -1) ||
        (local_input_width != 18) || (local_input_height != 18) ||
        (source_x != 0) || (source_y != 0) ||
        (source_width != 17) || (source_height != 17) ||
        (local_x_offset != 1) || (local_y_offset != 1) ||
        (padding_right_count != 0) || (padding_bottom_count != 0) ||
        (input_payload_bytes != 867) || (output_payload_bytes != 1280)) begin
      $fatal(1, "top-left halo geometry mismatch");
    end
    accept_tile(0, 0, 16, 16);
    wait (tile_valid);
    if ((input_origin_x != 15) || (input_origin_y != -1) ||
        (source_x != 15) || (source_width != 18) ||
        (source_height != 17) || (local_y_offset != 1)) begin
      $fatal(1, "top interior tile geometry mismatch");
    end
    accept_tile(16, 0, 16, 16);
    accept_tile(32, 0, 3, 16);
    accept_tile(0, 16, 16, 3);
    accept_tile(16, 16, 16, 3);
    wait (tile_valid);
    if (!last_tile || (local_input_width != 5) ||
        (local_input_height != 5) || (source_x != 31) ||
        (source_y != 15) || (source_width != 4) ||
        (source_height != 4) || (padding_right_count != 1) ||
        (padding_bottom_count != 1) ||
        (input_payload_bytes != 48) || (output_payload_bytes != 45)) begin
      $fatal(1, "bottom-right partial tile geometry mismatch");
    end
    accept_tile(32, 16, 3, 3);
    wait (done);
    if (busy || error) $fatal(1, "valid tile plan ended incorrectly");

    configure(5, 5, 3, 3, 3, 2, 1, 1, 1, 1, 1, 1, 2, 2);
    pulse_start();
    wait (tile_valid);
    if ((local_input_width != 5) || (local_input_height != 5) ||
        (source_width != 4) || (source_height != 4) ||
        (local_x_offset != 1) || (local_y_offset != 1) ||
        (input_payload_bytes != 16)) begin
      $fatal(1, "stride-two halo geometry mismatch");
    end
    accept_tile(0, 0, 2, 2);
    accept_tile(2, 0, 1, 2);
    accept_tile(0, 2, 2, 1);
    accept_tile(2, 2, 1, 1);
    wait (done);

    configure(17, 2, 17, 2, 1, 1, 0, 0, 0, 0, 4, 2, 16, 16);
    pulse_start();
    accept_tile(0, 0, 16, 2);
    wait (tile_valid);
    if ((local_input_width != 1) || (source_width != 1) ||
        (input_payload_bytes != 8) || (output_payload_bytes != 4)) begin
      $fatal(1, "1x1 partial tile geometry mismatch");
    end
    accept_tile(16, 0, 1, 2);
    wait (done);

    configure(4, 1, 3, 1, 3, 1, 1, 0, 1, 1, 1, 1, 3, 1);
    pulse_start();
    wait (tile_valid);
    if ((input_origin_x != -1) || (local_input_width != 5) ||
        (source_width != 4) || (local_x_offset != 1)) begin
      $fatal(1, "asymmetric padding geometry mismatch");
    end
    accept_tile(0, 0, 3, 1);
    wait (done);

    configure(5, 5, 4, 5, 3, 1, 1, 1, 1, 1, 1, 1, 2, 2);
    pulse_start();
    wait (done);
    if (!error || (error_code != 8'd6) || tile_valid) begin
      $fatal(1, "invalid output shape was not rejected");
    end

    random_seed = 32'h51A7_2026;
    for (int test_index = 0; test_index < 50; test_index++) begin
      int random_input_width;
      int random_input_height;
      int random_output_width;
      int random_output_height;
      int random_kernel;
      int random_stride;
      int random_padding_left;
      int random_padding_right;
      int random_padding_top;
      int random_padding_bottom;
      int random_tile_width;
      int random_tile_height;
      int expected_tile_x;
      int expected_tile_y;
      int expected_tile_count;

      random_input_width = random_range(3, 64);
      random_input_height = random_range(3, 64);
      random_kernel = random_range(0, 1) ? 3 : 1;
      random_stride = random_range(1, 2);
      random_padding_left = random_range(0, 1);
      random_padding_right = random_range(0, 1);
      random_padding_top = random_range(0, 1);
      random_padding_bottom = random_range(0, 1);
      random_output_width =
        ((random_input_width + random_padding_left + random_padding_right -
          random_kernel) / random_stride) + 1;
      random_output_height =
        ((random_input_height + random_padding_top + random_padding_bottom -
          random_kernel) / random_stride) + 1;
      random_tile_width = random_range(1, 16);
      random_tile_height = random_range(1, 16);

      configure(
        random_input_width,
        random_input_height,
        random_output_width,
        random_output_height,
        random_kernel,
        random_stride,
        random_padding_left,
        random_padding_right,
        random_padding_top,
        random_padding_bottom,
        $urandom_range(1, 16),
        $urandom_range(1, 16),
        random_tile_width,
        random_tile_height
      );
      pulse_start();

      expected_tile_x = 0;
      expected_tile_y = 0;
      expected_tile_count = 0;
      while (tile_valid) begin
        int expected_tile_width;
        int expected_tile_height;
        int expected_origin_x;
        int expected_origin_y;
        int expected_local_width;
        int expected_local_height;
        int expected_source_x;
        int expected_source_y;
        int expected_source_x_end;
        int expected_source_y_end;
        int expected_source_width;
        int expected_source_height;

        expected_tile_width =
          ((expected_tile_x + random_tile_width) > random_output_width) ?
            (random_output_width - expected_tile_x) : random_tile_width;
        expected_tile_height =
          ((expected_tile_y + random_tile_height) > random_output_height) ?
            (random_output_height - expected_tile_y) : random_tile_height;
        expected_origin_x =
          (expected_tile_x * random_stride) - random_padding_left;
        expected_origin_y =
          (expected_tile_y * random_stride) - random_padding_top;
        expected_local_width =
          ((expected_tile_width - 1) * random_stride) + random_kernel;
        expected_local_height =
          ((expected_tile_height - 1) * random_stride) + random_kernel;
        expected_source_x = (expected_origin_x < 0) ? 0 : expected_origin_x;
        expected_source_y = (expected_origin_y < 0) ? 0 : expected_origin_y;
        expected_source_x_end =
          ((expected_origin_x + expected_local_width) > random_input_width) ?
            random_input_width : (expected_origin_x + expected_local_width);
        expected_source_y_end =
          ((expected_origin_y + expected_local_height) > random_input_height) ?
            random_input_height : (expected_origin_y + expected_local_height);
        expected_source_width = expected_source_x_end - expected_source_x;
        expected_source_height = expected_source_y_end - expected_source_y;

        if ((tile_x != expected_tile_x) ||
            (tile_y != expected_tile_y) ||
            (tile_width != expected_tile_width) ||
            (tile_height != expected_tile_height) ||
            (input_origin_x != expected_origin_x) ||
            (input_origin_y != expected_origin_y) ||
            (local_input_width != expected_local_width) ||
            (local_input_height != expected_local_height) ||
            (source_x != expected_source_x) ||
            (source_y != expected_source_y) ||
            (source_width != expected_source_width) ||
            (source_height != expected_source_height) ||
            (local_x_offset != (expected_source_x - expected_origin_x)) ||
            (local_y_offset != (expected_source_y - expected_origin_y)) ||
            (input_payload_bytes !=
             (expected_source_width * expected_source_height *
              int'(input_channels))) ||
            (output_payload_bytes !=
             (expected_tile_width * expected_tile_height *
              int'(output_channels)))) begin
          $fatal(1, "random tile geometry mismatch test=%0d tile=%0d",
                 test_index, expected_tile_count);
        end

        expected_tile_count++;
        if ((expected_tile_x + expected_tile_width) < random_output_width) begin
          expected_tile_x = expected_tile_x + random_tile_width;
        end else begin
          expected_tile_x = 0;
          expected_tile_y = expected_tile_y + random_tile_height;
        end

        @(negedge clk);
        tile_ready = 1'b1;
        @(negedge clk);
        tile_ready = 1'b0;
      end
      if (error || (expected_tile_count == 0)) begin
        $fatal(1, "random plan failed test=%0d error=%0d",
               test_index, error_code);
      end
    end

    $display("[PASS] spatial tile planner directed and randomized geometry");
    $finish;
  end
endmodule
