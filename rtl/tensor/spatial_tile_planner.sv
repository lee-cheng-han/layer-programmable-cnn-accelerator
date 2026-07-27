`timescale 1ns/1ps

module spatial_tile_planner #(
  parameter int MAX_TENSOR_DIM = 1024,
  parameter int MAX_CHANNELS   = 16,
  parameter int MAX_TILE_WIDTH = 16,
  parameter int MAX_TILE_HEIGHT = 16,
  parameter int MAX_LOCAL_WIDTH = 33,
  parameter int MAX_LOCAL_HEIGHT = 33,
  parameter int DIM_W = 16,
  parameter int COUNT_W = 8
)(
  input  logic clk,
  input  logic rst_n,
  input  logic clear,

  input  logic start,
  input  logic [DIM_W-1:0] input_width,
  input  logic [DIM_W-1:0] input_height,
  input  logic [DIM_W-1:0] output_width,
  input  logic [DIM_W-1:0] output_height,
  input  logic [1:0] kernel_width,
  input  logic [1:0] kernel_height,
  input  logic [1:0] stride_x,
  input  logic [1:0] stride_y,
  input  logic padding_left,
  input  logic padding_right,
  input  logic padding_top,
  input  logic padding_bottom,
  input  logic [COUNT_W-1:0] input_channels,
  input  logic [COUNT_W-1:0] output_channels,
  input  logic [DIM_W-1:0] tile_width_hint,
  input  logic [DIM_W-1:0] tile_height_hint,

  output logic tile_valid,
  input  logic tile_ready,
  output logic first_tile,
  output logic last_tile,
  output logic [DIM_W-1:0] tile_x,
  output logic [DIM_W-1:0] tile_y,
  output logic [DIM_W-1:0] tile_width,
  output logic [DIM_W-1:0] tile_height,

  output logic signed [DIM_W:0] input_origin_x,
  output logic signed [DIM_W:0] input_origin_y,
  output logic [DIM_W-1:0] local_input_width,
  output logic [DIM_W-1:0] local_input_height,
  output logic [DIM_W-1:0] source_x,
  output logic [DIM_W-1:0] source_y,
  output logic [DIM_W-1:0] source_width,
  output logic [DIM_W-1:0] source_height,
  output logic [DIM_W-1:0] local_x_offset,
  output logic [DIM_W-1:0] local_y_offset,
  output logic [DIM_W-1:0] padding_right_count,
  output logic [DIM_W-1:0] padding_bottom_count,
  output logic [31:0] input_payload_bytes,
  output logic [31:0] output_payload_bytes,

  output logic busy,
  output logic done,
  output logic error,
  output logic [7:0] error_code
);

  localparam logic [7:0] TILE_ERROR_NONE = 8'd0;
  localparam logic [7:0] TILE_ERROR_BUSY = 8'd1;
  localparam logic [7:0] TILE_ERROR_DIMENSIONS = 8'd2;
  localparam logic [7:0] TILE_ERROR_CHANNELS = 8'd3;
  localparam logic [7:0] TILE_ERROR_KERNEL = 8'd4;
  localparam logic [7:0] TILE_ERROR_STRIDE = 8'd5;
  localparam logic [7:0] TILE_ERROR_OUTPUT_SHAPE = 8'd6;
  localparam logic [7:0] TILE_ERROR_TILE_HINT = 8'd7;
  localparam logic [7:0] TILE_ERROR_LOCAL_FOOTPRINT = 8'd8;

  logic active;
  logic first_tile_q;
  logic [DIM_W-1:0] input_width_q;
  logic [DIM_W-1:0] input_height_q;
  logic [DIM_W-1:0] output_width_q;
  logic [DIM_W-1:0] output_height_q;
  logic [1:0] kernel_width_q;
  logic [1:0] kernel_height_q;
  logic [1:0] stride_x_q;
  logic [1:0] stride_y_q;
  logic padding_left_q;
  logic padding_top_q;
  logic [COUNT_W-1:0] input_channels_q;
  logic [COUNT_W-1:0] output_channels_q;
  logic [DIM_W-1:0] selected_tile_width_q;
  logic [DIM_W-1:0] selected_tile_height_q;
  logic [DIM_W-1:0] tile_x_q;
  logic [DIM_W-1:0] tile_y_q;

  logic config_valid;
  logic [7:0] config_error_code;
  logic [31:0] expected_output_width;
  logic [31:0] expected_output_height;
  logic [31:0] padded_input_width;
  logic [31:0] padded_input_height;
  logic [31:0] selected_tile_width;
  logic [31:0] selected_tile_height;
  logic [31:0] max_local_width;
  logic [31:0] max_local_height;

  logic [31:0] tile_width_calc;
  logic [31:0] tile_height_calc;
  logic signed [32:0] origin_x_calc;
  logic signed [32:0] origin_y_calc;
  logic signed [32:0] local_width_calc;
  logic signed [32:0] local_height_calc;
  logic signed [32:0] source_x0_calc;
  logic signed [32:0] source_y0_calc;
  logic signed [32:0] source_x1_calc;
  logic signed [32:0] source_y1_calc;
  logic signed [32:0] source_width_calc;
  logic signed [32:0] source_height_calc;
  logic signed [32:0] local_x_offset_calc;
  logic signed [32:0] local_y_offset_calc;

  assign selected_tile_width =
    (tile_width_hint == '0) ? 32'(MAX_TILE_WIDTH) : 32'(tile_width_hint);
  assign selected_tile_height =
    (tile_height_hint == '0) ? 32'(MAX_TILE_HEIGHT) : 32'(tile_height_hint);
  assign padded_input_width =
    32'(input_width) + 32'(padding_left) + 32'(padding_right);
  assign padded_input_height =
    32'(input_height) + 32'(padding_top) + 32'(padding_bottom);
  assign expected_output_width =
    ((stride_x != 0) && (padded_input_width >= 32'(kernel_width))) ?
      (((padded_input_width - 32'(kernel_width)) / 32'(stride_x)) + 32'd1) :
      32'd0;
  assign expected_output_height =
    ((stride_y != 0) && (padded_input_height >= 32'(kernel_height))) ?
      (((padded_input_height - 32'(kernel_height)) / 32'(stride_y)) + 32'd1) :
      32'd0;
  assign max_local_width =
    ((selected_tile_width - 32'd1) * 32'(stride_x)) + 32'(kernel_width);
  assign max_local_height =
    ((selected_tile_height - 32'd1) * 32'(stride_y)) + 32'(kernel_height);

  always_comb begin
    config_valid = 1'b0;
    config_error_code = TILE_ERROR_NONE;

    if ((input_width == '0) || (input_height == '0) ||
        (output_width == '0) || (output_height == '0) ||
        (input_width > DIM_W'(MAX_TENSOR_DIM)) ||
        (input_height > DIM_W'(MAX_TENSOR_DIM)) ||
        (output_width > DIM_W'(MAX_TENSOR_DIM)) ||
        (output_height > DIM_W'(MAX_TENSOR_DIM))) begin
      config_error_code = TILE_ERROR_DIMENSIONS;
    end else if ((input_channels == '0) || (output_channels == '0) ||
                 (input_channels > COUNT_W'(MAX_CHANNELS)) ||
                 (output_channels > COUNT_W'(MAX_CHANNELS))) begin
      config_error_code = TILE_ERROR_CHANNELS;
    end else if (!(((kernel_width == 2'd1) && (kernel_height == 2'd1)) ||
                   ((kernel_width == 2'd3) && (kernel_height == 2'd3)))) begin
      config_error_code = TILE_ERROR_KERNEL;
    end else if (!(((stride_x == 2'd1) || (stride_x == 2'd2)) &&
                   ((stride_y == 2'd1) || (stride_y == 2'd2)))) begin
      config_error_code = TILE_ERROR_STRIDE;
    end else if ((expected_output_width != 32'(output_width)) ||
                 (expected_output_height != 32'(output_height))) begin
      config_error_code = TILE_ERROR_OUTPUT_SHAPE;
    end else if ((selected_tile_width == 0) ||
                 (selected_tile_height == 0) ||
                 (selected_tile_width > MAX_TILE_WIDTH) ||
                 (selected_tile_height > MAX_TILE_HEIGHT)) begin
      config_error_code = TILE_ERROR_TILE_HINT;
    end else if ((max_local_width > MAX_LOCAL_WIDTH) ||
                 (max_local_height > MAX_LOCAL_HEIGHT)) begin
      config_error_code = TILE_ERROR_LOCAL_FOOTPRINT;
    end else begin
      config_valid = 1'b1;
    end
  end

  always_comb begin
    tile_width_calc =
      ((32'(tile_x_q) + 32'(selected_tile_width_q)) > 32'(output_width_q)) ?
        (32'(output_width_q) - 32'(tile_x_q)) :
        32'(selected_tile_width_q);
    tile_height_calc =
      ((32'(tile_y_q) + 32'(selected_tile_height_q)) > 32'(output_height_q)) ?
        (32'(output_height_q) - 32'(tile_y_q)) :
        32'(selected_tile_height_q);

    origin_x_calc =
      $signed({1'b0, tile_x_q}) * $signed({31'd0, stride_x_q}) -
      $signed({32'd0, padding_left_q});
    origin_y_calc =
      $signed({1'b0, tile_y_q}) * $signed({31'd0, stride_y_q}) -
      $signed({32'd0, padding_top_q});
    local_width_calc =
      $signed({1'b0, tile_width_calc}) * $signed({31'd0, stride_x_q}) -
      $signed({31'd0, stride_x_q}) +
      $signed({31'd0, kernel_width_q});
    local_height_calc =
      $signed({1'b0, tile_height_calc}) * $signed({31'd0, stride_y_q}) -
      $signed({31'd0, stride_y_q}) +
      $signed({31'd0, kernel_height_q});

    source_x0_calc = (origin_x_calc < 0) ? 33'sd0 : origin_x_calc;
    source_y0_calc = (origin_y_calc < 0) ? 33'sd0 : origin_y_calc;
    source_x1_calc =
      ((origin_x_calc + local_width_calc) >
       $signed({17'd0, input_width_q})) ?
        $signed({17'd0, input_width_q}) :
        (origin_x_calc + local_width_calc);
    source_y1_calc =
      ((origin_y_calc + local_height_calc) >
       $signed({17'd0, input_height_q})) ?
        $signed({17'd0, input_height_q}) :
        (origin_y_calc + local_height_calc);
    source_width_calc =
      (source_x1_calc > source_x0_calc) ?
        (source_x1_calc - source_x0_calc) : 33'sd0;
    source_height_calc =
      (source_y1_calc > source_y0_calc) ?
        (source_y1_calc - source_y0_calc) : 33'sd0;
    local_x_offset_calc = source_x0_calc - origin_x_calc;
    local_y_offset_calc = source_y0_calc - origin_y_calc;
  end

  assign tile_valid = active;
  assign busy = active;
  assign first_tile = active && first_tile_q;
  assign tile_x = tile_x_q;
  assign tile_y = tile_y_q;
  assign tile_width = DIM_W'(tile_width_calc);
  assign tile_height = DIM_W'(tile_height_calc);
  assign input_origin_x = (DIM_W+1)'(origin_x_calc);
  assign input_origin_y = (DIM_W+1)'(origin_y_calc);
  assign local_input_width = DIM_W'(local_width_calc);
  assign local_input_height = DIM_W'(local_height_calc);
  assign source_x = DIM_W'(source_x0_calc);
  assign source_y = DIM_W'(source_y0_calc);
  assign source_width = DIM_W'(source_width_calc);
  assign source_height = DIM_W'(source_height_calc);
  assign local_x_offset = DIM_W'(local_x_offset_calc);
  assign local_y_offset = DIM_W'(local_y_offset_calc);
  assign padding_right_count = DIM_W'(
    local_width_calc - local_x_offset_calc - source_width_calc
  );
  assign padding_bottom_count = DIM_W'(
    local_height_calc - local_y_offset_calc - source_height_calc
  );
  assign input_payload_bytes =
    32'(source_width_calc) * 32'(source_height_calc) *
    32'(input_channels_q);
  assign output_payload_bytes =
    tile_width_calc * tile_height_calc * 32'(output_channels_q);
  assign last_tile =
    active &&
    ((32'(tile_x_q) + tile_width_calc) >= 32'(output_width_q)) &&
    ((32'(tile_y_q) + tile_height_calc) >= 32'(output_height_q));

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      active <= 1'b0;
      first_tile_q <= 1'b0;
      input_width_q <= '0;
      input_height_q <= '0;
      output_width_q <= '0;
      output_height_q <= '0;
      kernel_width_q <= '0;
      kernel_height_q <= '0;
      stride_x_q <= '0;
      stride_y_q <= '0;
      padding_left_q <= 1'b0;
      padding_top_q <= 1'b0;
      input_channels_q <= '0;
      output_channels_q <= '0;
      selected_tile_width_q <= '0;
      selected_tile_height_q <= '0;
      tile_x_q <= '0;
      tile_y_q <= '0;
      done <= 1'b0;
      error <= 1'b0;
      error_code <= TILE_ERROR_NONE;
    end else begin
      done <= 1'b0;

      if (clear) begin
        active <= 1'b0;
        first_tile_q <= 1'b0;
        error <= 1'b0;
        error_code <= TILE_ERROR_NONE;
      end else begin
        if (start) begin
          if (active) begin
            error <= 1'b1;
            error_code <= TILE_ERROR_BUSY;
          end else if (!config_valid) begin
            error <= 1'b1;
            error_code <= config_error_code;
            done <= 1'b1;
          end else begin
            input_width_q <= input_width;
            input_height_q <= input_height;
            output_width_q <= output_width;
            output_height_q <= output_height;
            kernel_width_q <= kernel_width;
            kernel_height_q <= kernel_height;
            stride_x_q <= stride_x;
            stride_y_q <= stride_y;
            padding_left_q <= padding_left;
            padding_top_q <= padding_top;
            input_channels_q <= input_channels;
            output_channels_q <= output_channels;
            selected_tile_width_q <= DIM_W'(selected_tile_width);
            selected_tile_height_q <= DIM_W'(selected_tile_height);
            tile_x_q <= '0;
            tile_y_q <= '0;
            first_tile_q <= 1'b1;
            active <= 1'b1;
            error <= 1'b0;
            error_code <= TILE_ERROR_NONE;
          end
        end

        if (tile_valid && tile_ready) begin
          first_tile_q <= 1'b0;
          if (last_tile) begin
            active <= 1'b0;
            done <= 1'b1;
          end else if ((32'(tile_x_q) + tile_width_calc) <
                       32'(output_width_q)) begin
            tile_x_q <= tile_x_q + selected_tile_width_q;
          end else begin
            tile_x_q <= '0;
            tile_y_q <= tile_y_q + selected_tile_height_q;
          end
        end
      end
    end
  end

endmodule
