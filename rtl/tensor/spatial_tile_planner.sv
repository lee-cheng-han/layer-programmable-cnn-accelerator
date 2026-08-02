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
  logic config_pending_q;
  logic config_validation_pending_q;
  logic [7:0] config_error_code_q;
  logic [31:0] expected_output_width_q;
  logic [31:0] expected_output_height_q;
  logic [31:0] max_local_width_q;
  logic [31:0] max_local_height_q;
  logic geometry_partial_q;
  logic geometry_footprint_q;
  logic geometry_bounds_q;
  logic geometry_valid_q;
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
  logic padding_right_q;
  logic padding_top_q;
  logic padding_bottom_q;
  logic [COUNT_W-1:0] input_channels_q;
  logic [COUNT_W-1:0] output_channels_q;
  logic [DIM_W-1:0] selected_tile_width_q;
  logic [DIM_W-1:0] selected_tile_height_q;
  logic [DIM_W-1:0] tile_x_q;
  logic [DIM_W-1:0] tile_y_q;
  logic last_tile_q;
  logic [DIM_W-1:0] tile_width_q;
  logic [DIM_W-1:0] tile_height_q;
  logic signed [DIM_W:0] input_origin_x_q;
  logic signed [DIM_W:0] input_origin_y_q;
  logic [DIM_W-1:0] local_input_width_q;
  logic [DIM_W-1:0] local_input_height_q;
  logic [DIM_W-1:0] source_x_q;
  logic [DIM_W-1:0] source_y_q;
  logic [DIM_W-1:0] source_width_q;
  logic [DIM_W-1:0] source_height_q;
  logic [DIM_W-1:0] local_x_offset_q;
  logic [DIM_W-1:0] local_y_offset_q;
  logic [DIM_W-1:0] padding_right_count_q;
  logic [DIM_W-1:0] padding_bottom_count_q;

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
  logic signed [32:0] source_x0_q;
  logic signed [32:0] source_y0_q;
  logic signed [32:0] source_x1_q;
  logic signed [32:0] source_y1_q;

  assign selected_tile_width =
    (tile_width_hint == '0) ? 32'(MAX_TILE_WIDTH) : 32'(tile_width_hint);
  assign selected_tile_height =
    (tile_height_hint == '0) ? 32'(MAX_TILE_HEIGHT) : 32'(tile_height_hint);
  assign padded_input_width =
    32'(input_width_q) + 32'(padding_left_q) + 32'(padding_right_q);
  assign padded_input_height =
    32'(input_height_q) + 32'(padding_top_q) + 32'(padding_bottom_q);
  assign expected_output_width =
    (padded_input_width >= 32'(kernel_width_q)) ?
      ((stride_x_q == 2'd1) ?
        ((padded_input_width - 32'(kernel_width_q)) + 32'd1) :
        ((stride_x_q == 2'd2) ?
          (((padded_input_width - 32'(kernel_width_q)) >> 1) + 32'd1) :
          32'd0)) :
      32'd0;
  assign expected_output_height =
    (padded_input_height >= 32'(kernel_height_q)) ?
      ((stride_y_q == 2'd1) ?
        ((padded_input_height - 32'(kernel_height_q)) + 32'd1) :
        ((stride_y_q == 2'd2) ?
          (((padded_input_height - 32'(kernel_height_q)) >> 1) + 32'd1) :
          32'd0)) :
      32'd0;
  assign max_local_width =
    (stride_x_q == 2'd2) ?
      ((32'(selected_tile_width_q) - 32'd1) << 1) +
        32'(kernel_width_q) :
      (32'(selected_tile_width_q) - 32'd1) + 32'(kernel_width_q);
  assign max_local_height =
    (stride_y_q == 2'd2) ?
      ((32'(selected_tile_height_q) - 32'd1) << 1) +
        32'(kernel_height_q) :
      (32'(selected_tile_height_q) - 32'd1) + 32'(kernel_height_q);

  always_comb begin
    config_error_code = TILE_ERROR_NONE;

    if ((input_width_q == '0) || (input_height_q == '0) ||
        (output_width_q == '0) || (output_height_q == '0) ||
        (input_width_q > DIM_W'(MAX_TENSOR_DIM)) ||
        (input_height_q > DIM_W'(MAX_TENSOR_DIM)) ||
        (output_width_q > DIM_W'(MAX_TENSOR_DIM)) ||
        (output_height_q > DIM_W'(MAX_TENSOR_DIM))) begin
      config_error_code = TILE_ERROR_DIMENSIONS;
    end else if ((input_channels_q == '0) || (output_channels_q == '0) ||
                 (input_channels_q > COUNT_W'(MAX_CHANNELS)) ||
                 (output_channels_q > COUNT_W'(MAX_CHANNELS))) begin
      config_error_code = TILE_ERROR_CHANNELS;
    end else if (!(((kernel_width_q == 2'd1) &&
                     (kernel_height_q == 2'd1)) ||
                    ((kernel_width_q == 2'd3) &&
                     (kernel_height_q == 2'd3)))) begin
      config_error_code = TILE_ERROR_KERNEL;
    end else if (!(((stride_x_q == 2'd1) || (stride_x_q == 2'd2)) &&
                   ((stride_y_q == 2'd1) || (stride_y_q == 2'd2)))) begin
      config_error_code = TILE_ERROR_STRIDE;
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
      $signed({1'b0, tile_width_q}) * $signed({31'd0, stride_x_q}) -
      $signed({31'd0, stride_x_q}) +
      $signed({31'd0, kernel_width_q});
    local_height_calc =
      $signed({1'b0, tile_height_q}) * $signed({31'd0, stride_y_q}) -
      $signed({31'd0, stride_y_q}) +
      $signed({31'd0, kernel_height_q});

    source_x0_calc =
      (input_origin_x_q < 0) ? 33'sd0 :
      33'($signed(input_origin_x_q));
    source_y0_calc =
      (input_origin_y_q < 0) ? 33'sd0 :
      33'($signed(input_origin_y_q));
    source_x1_calc =
      ((33'($signed(input_origin_x_q)) +
        $signed({1'b0, local_input_width_q})) >
       $signed({17'd0, input_width_q})) ?
        $signed({17'd0, input_width_q}) :
        (33'($signed(input_origin_x_q)) +
         $signed({1'b0, local_input_width_q}));
    source_y1_calc =
      ((33'($signed(input_origin_y_q)) +
        $signed({1'b0, local_input_height_q})) >
       $signed({17'd0, input_height_q})) ?
        $signed({17'd0, input_height_q}) :
        (33'($signed(input_origin_y_q)) +
         $signed({1'b0, local_input_height_q}));
    source_height_calc =
      (source_y1_q > source_y0_q) ?
        (source_y1_q - source_y0_q) : 33'sd0;
    source_width_calc =
      (source_x1_q > source_x0_q) ?
        (source_x1_q - source_x0_q) : 33'sd0;
    local_x_offset_calc =
      source_x0_q - 33'($signed(input_origin_x_q));
    local_y_offset_calc =
      source_y0_q - 33'($signed(input_origin_y_q));
  end

  assign tile_valid = active && geometry_valid_q;
  assign busy = active || config_pending_q || config_validation_pending_q;
  assign first_tile = tile_valid && first_tile_q;
  assign tile_x = tile_x_q;
  assign tile_y = tile_y_q;
  assign tile_width = tile_width_q;
  assign tile_height = tile_height_q;
  assign input_origin_x = input_origin_x_q;
  assign input_origin_y = input_origin_y_q;
  assign local_input_width = local_input_width_q;
  assign local_input_height = local_input_height_q;
  assign source_x = source_x_q;
  assign source_y = source_y_q;
  assign source_width = source_width_q;
  assign source_height = source_height_q;
  assign local_x_offset = local_x_offset_q;
  assign local_y_offset = local_y_offset_q;
  assign padding_right_count = padding_right_count_q;
  assign padding_bottom_count = padding_bottom_count_q;
  assign input_payload_bytes =
    32'(source_width_calc) * 32'(source_height_calc) *
    32'(input_channels_q);
  assign output_payload_bytes =
    tile_width_calc * tile_height_calc * 32'(output_channels_q);
  assign last_tile = tile_valid && last_tile_q;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      active <= 1'b0;
      config_pending_q <= 1'b0;
      config_validation_pending_q <= 1'b0;
      config_error_code_q <= TILE_ERROR_NONE;
      expected_output_width_q <= '0;
      expected_output_height_q <= '0;
      max_local_width_q <= '0;
      max_local_height_q <= '0;
      geometry_partial_q <= 1'b0;
      geometry_footprint_q <= 1'b0;
      geometry_bounds_q <= 1'b0;
      geometry_valid_q <= 1'b0;
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
      padding_right_q <= 1'b0;
      padding_top_q <= 1'b0;
      padding_bottom_q <= 1'b0;
      input_channels_q <= '0;
      output_channels_q <= '0;
      selected_tile_width_q <= '0;
      selected_tile_height_q <= '0;
      tile_x_q <= '0;
      tile_y_q <= '0;
      last_tile_q <= 1'b0;
      tile_width_q <= '0;
      tile_height_q <= '0;
      input_origin_x_q <= '0;
      input_origin_y_q <= '0;
      local_input_width_q <= '0;
      local_input_height_q <= '0;
      source_x_q <= '0;
      source_y_q <= '0;
      source_width_q <= '0;
      source_height_q <= '0;
      source_x0_q <= '0;
      source_y0_q <= '0;
      source_x1_q <= '0;
      source_y1_q <= '0;
      local_x_offset_q <= '0;
      local_y_offset_q <= '0;
      padding_right_count_q <= '0;
      padding_bottom_count_q <= '0;
      done <= 1'b0;
      error <= 1'b0;
      error_code <= TILE_ERROR_NONE;
    end else begin
      done <= 1'b0;

      if (clear) begin
        active <= 1'b0;
        config_pending_q <= 1'b0;
        config_validation_pending_q <= 1'b0;
        config_error_code_q <= TILE_ERROR_NONE;
        geometry_partial_q <= 1'b0;
        geometry_footprint_q <= 1'b0;
        geometry_bounds_q <= 1'b0;
        geometry_valid_q <= 1'b0;
        first_tile_q <= 1'b0;
        error <= 1'b0;
        error_code <= TILE_ERROR_NONE;
      end else begin
        if (start) begin
          if (active || config_pending_q || config_validation_pending_q) begin
            error <= 1'b1;
            error_code <= TILE_ERROR_BUSY;
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
            padding_right_q <= padding_right;
            padding_top_q <= padding_top;
            padding_bottom_q <= padding_bottom;
            input_channels_q <= input_channels;
            output_channels_q <= output_channels;
            selected_tile_width_q <= DIM_W'(selected_tile_width);
            selected_tile_height_q <= DIM_W'(selected_tile_height);
            config_pending_q <= 1'b1;
            error <= 1'b0;
            error_code <= TILE_ERROR_NONE;
          end
        end

        if (config_pending_q) begin
          config_pending_q <= 1'b0;
          config_error_code_q <= config_error_code;
          expected_output_width_q <= expected_output_width;
          expected_output_height_q <= expected_output_height;
          max_local_width_q <= max_local_width;
          max_local_height_q <= max_local_height;
          config_validation_pending_q <= 1'b1;
        end

        if (config_validation_pending_q) begin
          config_validation_pending_q <= 1'b0;
          if (config_error_code_q != TILE_ERROR_NONE) begin
            error <= 1'b1;
            error_code <= config_error_code_q;
            done <= 1'b1;
          end else if ((expected_output_width_q != 32'(output_width_q)) ||
                       (expected_output_height_q !=
                        32'(output_height_q))) begin
            error <= 1'b1;
            error_code <= TILE_ERROR_OUTPUT_SHAPE;
            done <= 1'b1;
          end else if ((selected_tile_width_q == '0) ||
                       (selected_tile_height_q == '0) ||
                       (selected_tile_width_q >
                        DIM_W'(MAX_TILE_WIDTH)) ||
                       (selected_tile_height_q >
                        DIM_W'(MAX_TILE_HEIGHT))) begin
            error <= 1'b1;
            error_code <= TILE_ERROR_TILE_HINT;
            done <= 1'b1;
          end else if ((max_local_width_q > 32'(MAX_LOCAL_WIDTH)) ||
                       (max_local_height_q > 32'(MAX_LOCAL_HEIGHT))) begin
            error <= 1'b1;
            error_code <= TILE_ERROR_LOCAL_FOOTPRINT;
            done <= 1'b1;
          end else begin
            tile_x_q <= '0;
            tile_y_q <= '0;
            first_tile_q <= 1'b1;
            active <= 1'b1;
            geometry_partial_q <= 1'b0;
            geometry_footprint_q <= 1'b0;
            geometry_bounds_q <= 1'b0;
            geometry_valid_q <= 1'b0;
          end
        end

        if (active && !geometry_valid_q) begin
          if (!geometry_partial_q) begin
            tile_width_q <= DIM_W'(tile_width_calc);
            tile_height_q <= DIM_W'(tile_height_calc);
            input_origin_x_q <= (DIM_W+1)'(origin_x_calc);
            input_origin_y_q <= (DIM_W+1)'(origin_y_calc);
            geometry_partial_q <= 1'b1;
          end else if (!geometry_footprint_q) begin
            local_input_width_q <= DIM_W'(local_width_calc);
            local_input_height_q <= DIM_W'(local_height_calc);
            geometry_footprint_q <= 1'b1;
          end else if (!geometry_bounds_q) begin
            source_x0_q <= source_x0_calc;
            source_y0_q <= source_y0_calc;
            source_x1_q <= source_x1_calc;
            source_y1_q <= source_y1_calc;
            geometry_bounds_q <= 1'b1;
          end else begin
            source_x_q <= DIM_W'(source_x0_q);
            source_y_q <= DIM_W'(source_y0_q);
            source_width_q <= DIM_W'(source_width_calc);
            source_height_q <= DIM_W'(source_height_calc);
            local_x_offset_q <= DIM_W'(local_x_offset_calc);
            local_y_offset_q <= DIM_W'(local_y_offset_calc);
            padding_right_count_q <= DIM_W'(
              33'($signed({1'b0, local_input_width_q})) -
              local_x_offset_calc - source_width_calc
            );
            padding_bottom_count_q <= DIM_W'(
              33'($signed({1'b0, local_input_height_q})) -
              local_y_offset_calc - source_height_calc
            );
            last_tile_q <=
              ((32'(tile_x_q) + 32'(tile_width_q)) >=
               32'(output_width_q)) &&
              ((32'(tile_y_q) + 32'(tile_height_q)) >=
               32'(output_height_q));
            geometry_partial_q <= 1'b0;
            geometry_footprint_q <= 1'b0;
            geometry_bounds_q <= 1'b0;
            geometry_valid_q <= 1'b1;
          end
        end

        if (tile_valid && tile_ready) begin
          geometry_partial_q <= 1'b0;
          geometry_footprint_q <= 1'b0;
          geometry_bounds_q <= 1'b0;
          geometry_valid_q <= 1'b0;
          first_tile_q <= 1'b0;
          if (last_tile) begin
            active <= 1'b0;
            done <= 1'b1;
          end else if ((32'(tile_x_q) + 32'(tile_width_q)) <
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
