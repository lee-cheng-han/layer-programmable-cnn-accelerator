`timescale 1ns/1ps

module cnn_tiled_layer_runtime #(
  parameter int PC = 2,
  parameter int PK = 4,
  parameter int MAX_CIN = 16,
  parameter int MAX_COUT = 16,
  parameter int MAX_TILE_WIDTH = 16,
  parameter int MAX_TILE_HEIGHT = 16,
  parameter int MAX_LOCAL_WIDTH = 33,
  parameter int MAX_LOCAL_HEIGHT = 33,
  parameter int DATA_W = 8,
  parameter int ACC_W = 32,
  parameter int COUNT_W = 8,
  parameter int DIM_W = 16,
  parameter int ADDR_W = 32
)(
  input  logic clk,
  input  logic rst_n,
  input  logic clear,

  input  logic start,
  input  logic [31:0] job_id,
  input  logic [15:0] layer_id,
  input  logic [15:0] input_tensor_id,
  input  logic [15:0] output_tensor_id,
  input  logic [DIM_W-1:0] input_width,
  input  logic [DIM_W-1:0] input_height,
  input  logic [DIM_W-1:0] output_width,
  input  logic [DIM_W-1:0] output_height,
  input  logic [1:0] kernel_size,
  input  logic [1:0] stride,
  input  logic padding_left,
  input  logic padding_right,
  input  logic padding_top,
  input  logic padding_bottom,
  input  logic [COUNT_W-1:0] cin,
  input  logic [COUNT_W-1:0] cout,
  input  logic bias_enable,
  input  logic relu_enable,
  input  logic [DIM_W-1:0] tile_width_hint,
  input  logic [DIM_W-1:0] tile_height_hint,

  output logic parameter_request,
  output logic [2:0] parameter_layer_id,
  input  logic parameter_ready,
  output logic parameter_release,
  input  logic parameter_quant_enable,
  input  logic [4:0] parameter_quant_shift,
  input  logic signed [ACC_W-1:0] parameter_bias [MAX_COUT],
  output logic [COUNT_W-1:0] parameter_weight_read_k_base,
  output logic [COUNT_W-1:0] parameter_weight_read_c_base,
  output logic [3:0] parameter_weight_read_kernel_idx,
  output logic [PK-1:0] parameter_weight_out_lane_mask,
  output logic [PC-1:0] parameter_weight_in_lane_mask,
  input  logic signed [DATA_W-1:0] parameter_weight_mat_data [PK][PC],

  input  logic activation_packet_start,
  output logic activation_packet_ready,
  input  logic [31:0] activation_job_id,
  input  logic [15:0] activation_tensor_id,
  input  logic [15:0] activation_layer_id,
  input  logic [15:0] activation_tile_x,
  input  logic [15:0] activation_tile_y,
  input  logic [15:0] activation_tile_width,
  input  logic [15:0] activation_tile_height,
  input  logic [15:0] activation_channel_offset,
  input  logic [15:0] activation_channel_count,
  input  logic [31:0] activation_payload_length,
  input  logic activation_valid,
  output logic activation_ready,
  input  logic [31:0] activation_data,
  input  logic [3:0] activation_keep,
  input  logic activation_last,

  output logic [31:0] m_axis_tdata,
  output logic [3:0] m_axis_tkeep,
  output logic m_axis_tvalid,
  input  logic m_axis_tready,
  output logic m_axis_tlast,

  output logic [15:0] current_tile_x,
  output logic [15:0] current_tile_y,
  output logic [31:0] completed_tile_count,
  output logic busy,
  output logic done,
  output logic error,
  output logic [7:0] error_code
);

  localparam int MAX_LOCAL_PIXELS = MAX_LOCAL_WIDTH * MAX_LOCAL_HEIGHT;
  localparam logic [7:0] RUNTIME_ERROR_NONE = 8'd0;
  localparam logic [7:0] RUNTIME_ERROR_BUSY = 8'd1;
  localparam logic [7:0] RUNTIME_ERROR_LAYER_ID = 8'd2;
  localparam logic [7:0] RUNTIME_ERROR_PLANNER = 8'd3;
  localparam logic [7:0] RUNTIME_ERROR_TILE_LOAD = 8'd4;
  localparam logic [7:0] RUNTIME_ERROR_OUTPUT = 8'd5;

  typedef enum logic [3:0] {
    S_IDLE,
    S_WAIT_PARAMETER,
    S_WAIT_TILE,
    S_WAIT_INPUT,
    S_START_TILE,
    S_RUN_TILE,
    S_RELEASE_PARAMETER,
    S_DONE,
    S_ERROR
  } state_t;

  state_t state;
  logic planner_start;
  logic planner_tile_valid;
  logic planner_tile_ready;
  logic planner_first_tile;
  logic planner_last_tile;
  logic [DIM_W-1:0] planner_tile_x;
  logic [DIM_W-1:0] planner_tile_y;
  logic [DIM_W-1:0] planner_tile_width;
  logic [DIM_W-1:0] planner_tile_height;
  logic signed [DIM_W:0] planner_input_origin_x;
  logic signed [DIM_W:0] planner_input_origin_y;
  logic [DIM_W-1:0] planner_local_input_width;
  logic [DIM_W-1:0] planner_local_input_height;
  logic [DIM_W-1:0] planner_source_x;
  logic [DIM_W-1:0] planner_source_y;
  logic [DIM_W-1:0] planner_source_width;
  logic [DIM_W-1:0] planner_source_height;
  logic [DIM_W-1:0] planner_local_x_offset;
  logic [DIM_W-1:0] planner_local_y_offset;
  logic [DIM_W-1:0] planner_padding_right_count;
  logic [DIM_W-1:0] planner_padding_bottom_count;
  logic [31:0] planner_input_payload_bytes;
  logic [31:0] planner_output_payload_bytes;
  logic planner_done;
  logic planner_error;
  logic [7:0] planner_error_code;

  logic tile_last_q;
  logic [15:0] tile_x_q;
  logic [15:0] tile_y_q;
  logic [15:0] tile_width_q;
  logic [15:0] tile_height_q;
  logic [DIM_W-1:0] local_input_width_q;
  logic [DIM_W-1:0] local_input_height_q;
  logic [DIM_W-1:0] source_width_q;
  logic [DIM_W-1:0] source_height_q;
  logic [DIM_W-1:0] local_x_offset_q;
  logic [DIM_W-1:0] local_y_offset_q;
  logic [31:0] input_payload_bytes_q;
  logic [31:0] output_payload_bytes_q;

  logic loader_write_enable;
  logic loader_packet_ready;
  logic [ADDR_W-1:0] loader_write_pixel;
  logic [COUNT_W-1:0] loader_write_channel;
  logic signed [DATA_W-1:0] loader_write_data;
  logic loader_done;
  logic loader_error;
  logic [7:0] loader_error_code;

  logic [ADDR_W-1:0] scratch_activation_read_pixel;
  logic [COUNT_W-1:0] scratch_activation_read_c_base;
  logic [PC-1:0] scratch_activation_lane_mask;
  logic signed [DATA_W-1:0] scratch_activation_lane_data [PC];

  logic scheduler_start;
  logic scheduler_output_valid;
  logic scheduler_output_ready;
  logic [ADDR_W-1:0] scheduler_output_index;
  logic [COUNT_W-1:0] scheduler_output_channels;
  logic signed [DATA_W-1:0] scheduler_output_data [MAX_COUT];
  logic scheduler_output_last;
  logic scheduler_done;
  logic signed [DATA_W-1:0] dummy_activation [MAX_LOCAL_PIXELS*MAX_CIN];
  logic signed [DATA_W-1:0] dummy_weights_1x1 [MAX_COUT][MAX_CIN];
  logic signed [DATA_W-1:0] dummy_weights_3x3 [MAX_COUT][MAX_CIN][9];
  logic signed [DATA_W-1:0] unused_output_tensor [MAX_LOCAL_PIXELS*MAX_COUT];

  logic serializer_clear;
  logic serializer_byte_valid;
  logic serializer_byte_ready;
  logic signed [DATA_W-1:0] serializer_byte_data;
  logic serializer_done;
  logic serializer_error;

  logic writer_start;
  logic writer_ready;
  logic writer_done;
  logic writer_error;
  logic [7:0] writer_error_code;
  logic compute_done_q;
  logic output_done_q;
  logic parameter_acquired_q;
  logic input_packet_accepted_q;

  assign busy = (state != S_IDLE) && (state != S_DONE);
  assign current_tile_x = tile_x_q;
  assign current_tile_y = tile_y_q;
  assign parameter_layer_id = layer_id[2:0];
  assign parameter_request = state == S_WAIT_PARAMETER;
  assign planner_start = (state == S_IDLE) && start &&
                         (layer_id[15:3] == 0);
  assign planner_tile_ready = state == S_WAIT_TILE;
  assign scheduler_start = (state == S_START_TILE) && writer_ready;
  assign writer_start = scheduler_start;
  assign serializer_clear = clear || (state == S_WAIT_TILE);
  assign activation_packet_ready =
    (state == S_WAIT_INPUT) && !input_packet_accepted_q &&
    loader_packet_ready;

  spatial_tile_planner #(
    .MAX_CHANNELS((MAX_CIN > MAX_COUT) ? MAX_CIN : MAX_COUT),
    .MAX_TILE_WIDTH(MAX_TILE_WIDTH),
    .MAX_TILE_HEIGHT(MAX_TILE_HEIGHT),
    .MAX_LOCAL_WIDTH(MAX_LOCAL_WIDTH),
    .MAX_LOCAL_HEIGHT(MAX_LOCAL_HEIGHT),
    .DIM_W(DIM_W),
    .COUNT_W(COUNT_W)
  ) u_tile_planner (
    .clk(clk),
    .rst_n(rst_n),
    .clear(clear),
    .start(planner_start),
    .input_width(input_width),
    .input_height(input_height),
    .output_width(output_width),
    .output_height(output_height),
    .kernel_width(kernel_size),
    .kernel_height(kernel_size),
    .stride_x(stride),
    .stride_y(stride),
    .padding_left(padding_left),
    .padding_right(padding_right),
    .padding_top(padding_top),
    .padding_bottom(padding_bottom),
    .input_channels(cin),
    .output_channels(cout),
    .tile_width_hint(tile_width_hint),
    .tile_height_hint(tile_height_hint),
    .tile_valid(planner_tile_valid),
    .tile_ready(planner_tile_ready),
    .first_tile(planner_first_tile),
    .last_tile(planner_last_tile),
    .tile_x(planner_tile_x),
    .tile_y(planner_tile_y),
    .tile_width(planner_tile_width),
    .tile_height(planner_tile_height),
    .input_origin_x(planner_input_origin_x),
    .input_origin_y(planner_input_origin_y),
    .local_input_width(planner_local_input_width),
    .local_input_height(planner_local_input_height),
    .source_x(planner_source_x),
    .source_y(planner_source_y),
    .source_width(planner_source_width),
    .source_height(planner_source_height),
    .local_x_offset(planner_local_x_offset),
    .local_y_offset(planner_local_y_offset),
    .padding_right_count(planner_padding_right_count),
    .padding_bottom_count(planner_padding_bottom_count),
    .input_payload_bytes(planner_input_payload_bytes),
    .output_payload_bytes(planner_output_payload_bytes),
    .busy(),
    .done(planner_done),
    .error(planner_error),
    .error_code(planner_error_code)
  );

  halo_tile_load_controller #(
    .MAX_LOCAL_PIXELS(MAX_LOCAL_PIXELS),
    .MAX_CHANNELS(MAX_CIN),
    .DIM_W(DIM_W),
    .COUNT_W(COUNT_W),
    .ADDR_W(ADDR_W)
  ) u_tile_loader (
    .clk(clk),
    .rst_n(rst_n),
    .clear(clear),
    .expected_valid(state == S_WAIT_INPUT),
    .expected_job_id(job_id),
    .expected_tensor_id(input_tensor_id),
    .expected_layer_id(layer_id),
    .expected_tile_x(tile_x_q),
    .expected_tile_y(tile_y_q),
    .expected_tile_width(tile_width_q),
    .expected_tile_height(tile_height_q),
    .local_input_width(local_input_width_q),
    .local_input_height(local_input_height_q),
    .source_width(source_width_q),
    .source_height(source_height_q),
    .local_x_offset(local_x_offset_q),
    .local_y_offset(local_y_offset_q),
    .input_channels(cin),
    .expected_payload_bytes(input_payload_bytes_q),
    .packet_start(activation_packet_start),
    .packet_ready(loader_packet_ready),
    .packet_job_id(activation_job_id),
    .packet_tensor_id(activation_tensor_id),
    .packet_layer_id(activation_layer_id),
    .packet_tile_x(activation_tile_x),
    .packet_tile_y(activation_tile_y),
    .packet_tile_width(activation_tile_width),
    .packet_tile_height(activation_tile_height),
    .packet_channel_offset(activation_channel_offset),
    .packet_channel_count(activation_channel_count),
    .packet_payload_length(activation_payload_length),
    .payload_valid(activation_valid),
    .payload_ready(activation_ready),
    .payload_data(activation_data),
    .payload_keep(activation_keep),
    .payload_last(activation_last),
    .scratch_write_enable(loader_write_enable),
    .scratch_write_pixel(loader_write_pixel),
    .scratch_write_channel(loader_write_channel),
    .scratch_write_data(loader_write_data),
    .busy(),
    .done(loader_done),
    .error(loader_error),
    .error_code(loader_error_code)
  );

  banked_activation_scratchpad #(
    .PC(PC),
    .MAX_PIXELS(MAX_LOCAL_PIXELS),
    .MAX_C(MAX_CIN),
    .DATA_W(DATA_W),
    .DIM_W(DIM_W),
    .COUNT_W(COUNT_W),
    .ADDR_W(ADDR_W)
  ) u_tile_activation_scratchpad (
    .clk(clk),
    .write_enable(loader_write_enable),
    .write_pixel(loader_write_pixel),
    .write_channel(loader_write_channel),
    .write_data(loader_write_data),
    .read_pixel(scratch_activation_read_pixel),
    .read_c_base(scratch_activation_read_c_base),
    .lane_mask(scratch_activation_lane_mask),
    .lane_data(scratch_activation_lane_data),
    .debug_read_pixel('0),
    .debug_read_channel('0),
    .debug_read_data()
  );

  single_layer_scheduler #(
    .PC(PC),
    .PK(PK),
    .MAX_CIN(MAX_CIN),
    .MAX_COUT(MAX_COUT),
    .MAX_PIXELS(MAX_LOCAL_PIXELS),
    .DATA_W(DATA_W),
    .ACC_W(ACC_W),
    .BIAS_W(ACC_W),
    .OUT_W(DATA_W),
    .COUNT_W(COUNT_W),
    .DIM_W(DIM_W),
    .ADDR_W(ADDR_W),
    .MIRROR_OUTPUT_TENSOR(1'b0)
  ) u_scheduler (
    .clk(clk),
    .rst_n(rst_n),
    .start(scheduler_start),
    .input_width(local_input_width_q),
    .input_height(local_input_height_q),
    .output_width(tile_width_q),
    .output_height(tile_height_q),
    .kernel_size(kernel_size),
    .stride(stride),
    .padding(2'd0),
    .cin(cin),
    .cout(cout),
    .bias_enable(bias_enable),
    .relu_enable(relu_enable),
    .quant_enable(parameter_quant_enable),
    .quant_shift(parameter_quant_shift),
    .activation(dummy_activation),
    .weights_1x1(dummy_weights_1x1),
    .weights_3x3(dummy_weights_3x3),
    .bias(parameter_bias),
    .use_scratchpad_operands(1'b1),
    .use_scratchpad_weights(1'b1),
    .scratch_activation_read_pixel(scratch_activation_read_pixel),
    .scratch_activation_read_c_base(scratch_activation_read_c_base),
    .scratch_activation_lane_mask(scratch_activation_lane_mask),
    .scratch_activation_lane_data(scratch_activation_lane_data),
    .scratch_weight_read_k_base(parameter_weight_read_k_base),
    .scratch_weight_read_c_base(parameter_weight_read_c_base),
    .scratch_weight_read_kernel_idx(parameter_weight_read_kernel_idx),
    .scratch_weight_out_lane_mask(parameter_weight_out_lane_mask),
    .scratch_weight_in_lane_mask(parameter_weight_in_lane_mask),
    .scratch_weight_mat_data(parameter_weight_mat_data),
    .output_tensor(unused_output_tensor),
    .output_pixel_valid(scheduler_output_valid),
    .output_pixel_ready(scheduler_output_ready),
    .output_pixel_index(scheduler_output_index),
    .output_pixel_channels(scheduler_output_channels),
    .output_pixel_data(scheduler_output_data),
    .output_pixel_last(scheduler_output_last),
    .current_x(),
    .current_y(),
    .busy(),
    .done(scheduler_done)
  );

  tile_output_serializer #(
    .MAX_COUT(MAX_COUT),
    .COUNT_W(COUNT_W),
    .DATA_W(DATA_W)
  ) u_output_serializer (
    .clk(clk),
    .rst_n(rst_n),
    .clear(serializer_clear),
    .pixel_valid(scheduler_output_valid),
    .pixel_ready(scheduler_output_ready),
    .pixel_channels(scheduler_output_channels),
    .pixel_data(scheduler_output_data),
    .pixel_last(scheduler_output_last),
    .byte_valid(serializer_byte_valid),
    .byte_ready(serializer_byte_ready),
    .byte_data(serializer_byte_data),
    .byte_last(),
    .busy(),
    .done(serializer_done),
    .error(serializer_error)
  );

  packed_dma_packet_writer #(
    .MAX_PAYLOAD_BYTES(
      MAX_TILE_WIDTH * MAX_TILE_HEIGHT * MAX_COUT
    )
  ) u_output_writer (
    .clk(clk),
    .rst_n(rst_n),
    .clear(clear),
    .packet_start(writer_start),
    .packet_ready(writer_ready),
    .job_id(job_id),
    .tensor_id(output_tensor_id),
    .layer_id(layer_id),
    .tile_x(tile_x_q),
    .tile_y(tile_y_q),
    .tile_width(tile_width_q),
    .tile_height(tile_height_q),
    .channel_offset(16'd0),
    .channel_count(16'(cout)),
    .payload_length(output_payload_bytes_q),
    .payload_byte_valid(serializer_byte_valid),
    .payload_byte_ready(serializer_byte_ready),
    .payload_byte_data(serializer_byte_data),
    .m_axis_tdata(m_axis_tdata),
    .m_axis_tkeep(m_axis_tkeep),
    .m_axis_tvalid(m_axis_tvalid),
    .m_axis_tready(m_axis_tready),
    .m_axis_tlast(m_axis_tlast),
    .busy(),
    .packet_done(writer_done),
    .error(writer_error),
    .error_code(writer_error_code)
  );

  always_comb begin
    for (int pixel = 0; pixel < MAX_LOCAL_PIXELS; pixel++) begin
      for (int channel = 0; channel < MAX_CIN; channel++) begin
        dummy_activation[(pixel * MAX_CIN) + channel] = '0;
      end
    end
    for (int out_channel = 0; out_channel < MAX_COUT; out_channel++) begin
      for (int in_channel = 0; in_channel < MAX_CIN; in_channel++) begin
        dummy_weights_1x1[out_channel][in_channel] = '0;
        for (int tap = 0; tap < 9; tap++) begin
          dummy_weights_3x3[out_channel][in_channel][tap] = '0;
        end
      end
    end
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state <= S_IDLE;
      tile_last_q <= 1'b0;
      tile_x_q <= '0;
      tile_y_q <= '0;
      tile_width_q <= '0;
      tile_height_q <= '0;
      local_input_width_q <= '0;
      local_input_height_q <= '0;
      source_width_q <= '0;
      source_height_q <= '0;
      local_x_offset_q <= '0;
      local_y_offset_q <= '0;
      input_payload_bytes_q <= '0;
      output_payload_bytes_q <= '0;
      compute_done_q <= 1'b0;
      output_done_q <= 1'b0;
      parameter_acquired_q <= 1'b0;
      input_packet_accepted_q <= 1'b0;
      completed_tile_count <= '0;
      parameter_release <= 1'b0;
      done <= 1'b0;
      error <= 1'b0;
      error_code <= RUNTIME_ERROR_NONE;
    end else begin
      parameter_release <= 1'b0;
      done <= 1'b0;

      if (clear) begin
        state <= S_IDLE;
        completed_tile_count <= '0;
        compute_done_q <= 1'b0;
        output_done_q <= 1'b0;
        parameter_acquired_q <= 1'b0;
        input_packet_accepted_q <= 1'b0;
        error <= 1'b0;
        error_code <= RUNTIME_ERROR_NONE;
      end else begin
        if (activation_packet_start && activation_packet_ready) begin
          input_packet_accepted_q <= 1'b1;
        end

        if (start && (state != S_IDLE)) begin
          error <= 1'b1;
          error_code <= RUNTIME_ERROR_BUSY;
          state <= S_ERROR;
        end else if (planner_error && (state != S_IDLE) &&
            (state != S_DONE) && (state != S_ERROR)) begin
          error <= 1'b1;
          error_code <= RUNTIME_ERROR_PLANNER;
          state <= S_ERROR;
        end else begin
          unique case (state)
            S_IDLE: begin
              if (start) begin
                completed_tile_count <= '0;
                error <= 1'b0;
                error_code <= RUNTIME_ERROR_NONE;
                if (layer_id[15:3] != 0) begin
                  error <= 1'b1;
                  error_code <= RUNTIME_ERROR_LAYER_ID;
                  state <= S_ERROR;
                end else begin
                  state <= S_WAIT_PARAMETER;
                end
              end
            end

            S_WAIT_PARAMETER: begin
              if (parameter_ready) begin
                parameter_acquired_q <= 1'b1;
                state <= S_WAIT_TILE;
              end
            end

            S_WAIT_TILE: begin
              if (planner_tile_valid) begin
                tile_last_q <= planner_last_tile;
                tile_x_q <= planner_tile_x;
                tile_y_q <= planner_tile_y;
                tile_width_q <= planner_tile_width;
                tile_height_q <= planner_tile_height;
                local_input_width_q <= planner_local_input_width;
                local_input_height_q <= planner_local_input_height;
                source_width_q <= planner_source_width;
                source_height_q <= planner_source_height;
                local_x_offset_q <= planner_local_x_offset;
                local_y_offset_q <= planner_local_y_offset;
                input_payload_bytes_q <= planner_input_payload_bytes;
                output_payload_bytes_q <= planner_output_payload_bytes;
                input_packet_accepted_q <= 1'b0;
                state <= S_WAIT_INPUT;
              end
            end

            S_WAIT_INPUT: begin
              if (loader_done) begin
                if (loader_error) begin
                  error <= 1'b1;
                  error_code <= RUNTIME_ERROR_TILE_LOAD;
                  state <= S_ERROR;
                end else begin
                  state <= S_START_TILE;
                end
              end
            end

            S_START_TILE: begin
              if (writer_ready) begin
                compute_done_q <= 1'b0;
                output_done_q <= 1'b0;
                state <= S_RUN_TILE;
              end
            end

            S_RUN_TILE: begin
              if (scheduler_done) compute_done_q <= 1'b1;
              if (writer_done) output_done_q <= 1'b1;

              if (serializer_error || writer_error) begin
                error <= 1'b1;
                error_code <= RUNTIME_ERROR_OUTPUT;
                state <= S_ERROR;
              end else if ((compute_done_q || scheduler_done) &&
                           (output_done_q || writer_done)) begin
                completed_tile_count <= completed_tile_count + 32'd1;
                state <= tile_last_q ?
                  S_RELEASE_PARAMETER : S_WAIT_TILE;
              end
            end

            S_RELEASE_PARAMETER: begin
              parameter_release <= 1'b1;
              parameter_acquired_q <= 1'b0;
              state <= S_DONE;
            end

            S_DONE: begin
              done <= 1'b1;
              state <= S_IDLE;
            end

            S_ERROR: begin
              parameter_release <= parameter_acquired_q;
              parameter_acquired_q <= 1'b0;
              done <= 1'b1;
              state <= S_IDLE;
            end

            default: state <= S_IDLE;
          endcase
        end
      end
    end
  end

endmodule
