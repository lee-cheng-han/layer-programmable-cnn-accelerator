`timescale 1ns/1ps

module halo_tile_load_controller #(
  parameter int MAX_LOCAL_PIXELS = 33 * 33,
  parameter int MAX_CHANNELS = 16,
  parameter int DIM_W = 16,
  parameter int COUNT_W = 8,
  parameter int ADDR_W = 32
)(
  input  logic clk,
  input  logic rst_n,
  input  logic clear,

  input  logic expected_valid,
  input  logic [31:0] expected_job_id,
  input  logic [15:0] expected_tensor_id,
  input  logic [15:0] expected_layer_id,
  input  logic [15:0] expected_tile_x,
  input  logic [15:0] expected_tile_y,
  input  logic [15:0] expected_tile_width,
  input  logic [15:0] expected_tile_height,
  input  logic [DIM_W-1:0] local_input_width,
  input  logic [DIM_W-1:0] local_input_height,
  input  logic [DIM_W-1:0] source_width,
  input  logic [DIM_W-1:0] source_height,
  input  logic [DIM_W-1:0] local_x_offset,
  input  logic [DIM_W-1:0] local_y_offset,
  input  logic [COUNT_W-1:0] input_channels,
  input  logic [31:0] expected_payload_bytes,

  input  logic packet_start,
  output logic packet_ready,
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

  input  logic payload_valid,
  output logic payload_ready,
  input  logic [31:0] payload_data,
  input  logic [3:0] payload_keep,
  input  logic payload_last,

  output logic scratch_write_enable,
  output logic [ADDR_W-1:0] scratch_write_pixel,
  output logic [COUNT_W-1:0] scratch_write_channel,
  output logic signed [7:0] scratch_write_data,

  output logic busy,
  output logic done,
  output logic error,
  output logic [7:0] error_code
);
  import cnn_dma_packet_pkg::*;

  localparam logic [7:0] LOAD_ERROR_NONE = 8'd0;
  localparam logic [7:0] LOAD_ERROR_CONTEXT = 8'd1;
  localparam logic [7:0] LOAD_ERROR_PACKET_METADATA = 8'd2;
  localparam logic [7:0] LOAD_ERROR_PAYLOAD_LENGTH = 8'd3;
  localparam logic [7:0] LOAD_ERROR_KEEP = 8'd4;
  localparam logic [7:0] LOAD_ERROR_EARLY_LAST = 8'd5;
  localparam logic [7:0] LOAD_ERROR_MISSING_LAST = 8'd6;

  typedef enum logic [2:0] {
    S_IDLE,
    S_CLEAR,
    S_WAIT_BEAT,
    S_WRITE_BYTES,
    S_FLUSH,
    S_DROP,
    S_DONE
  } state_t;

  state_t state;
  logic [DIM_W-1:0] local_input_width_q;
  logic [DIM_W-1:0] local_input_height_q;
  logic [DIM_W-1:0] source_width_q;
  logic [DIM_W-1:0] local_x_offset_q;
  logic [DIM_W-1:0] local_y_offset_q;
  logic [COUNT_W-1:0] input_channels_q;
  logic [31:0] expected_payload_bytes_q;

  logic [ADDR_W-1:0] clear_pixel;
  logic [COUNT_W-1:0] clear_channel;
  logic [DIM_W-1:0] payload_x;
  logic [DIM_W-1:0] payload_y;
  logic [COUNT_W-1:0] payload_channel;
  logic [31:0] payload_byte_count;
  logic [31:0] beat_data_q;
  logic [3:0] beat_keep_q;
  logic beat_last_q;
  logic [1:0] beat_lane;
  logic [2:0] beat_byte_count;
  logic metadata_valid;
  logic context_valid;
  logic keep_valid;
  logic payload_transfer;

  assign context_valid =
    expected_valid &&
    (local_input_width != '0) &&
    (local_input_height != '0) &&
    (source_width != '0) &&
    (source_height != '0) &&
    (input_channels != '0) &&
    ((32'(local_input_width) * 32'(local_input_height)) <=
     32'(MAX_LOCAL_PIXELS)) &&
    (input_channels <= COUNT_W'(MAX_CHANNELS)) &&
    ((32'(local_x_offset) + 32'(source_width)) <=
     32'(local_input_width)) &&
    ((32'(local_y_offset) + 32'(source_height)) <=
     32'(local_input_height)) &&
    (expected_payload_bytes ==
     (32'(source_width) * 32'(source_height) * 32'(input_channels)));

  assign metadata_valid =
    (packet_job_id == expected_job_id) &&
    (packet_tensor_id == expected_tensor_id) &&
    (packet_layer_id == expected_layer_id) &&
    (packet_tile_x == expected_tile_x) &&
    (packet_tile_y == expected_tile_y) &&
    (packet_tile_width == expected_tile_width) &&
    (packet_tile_height == expected_tile_height) &&
    (packet_channel_offset == 16'd0) &&
    (packet_channel_count == 16'(input_channels)) &&
    (packet_payload_length == expected_payload_bytes);

  assign beat_byte_count = bytes_for_keep(beat_keep_q);
  assign keep_valid =
    (payload_keep == 4'b0001) ||
    (payload_keep == 4'b0011) ||
    (payload_keep == 4'b0111) ||
    (payload_keep == 4'b1111);
  assign packet_ready = state == S_IDLE;
  assign payload_ready = (state == S_WAIT_BEAT) || (state == S_DROP);
  assign payload_transfer = payload_valid && payload_ready;
  assign busy = (state != S_IDLE) && (state != S_DONE);

  always_comb begin
    scratch_write_enable = 1'b0;
    scratch_write_pixel = '0;
    scratch_write_channel = '0;
    scratch_write_data = '0;

    if (state == S_CLEAR) begin
      scratch_write_enable = 1'b1;
      scratch_write_pixel = clear_pixel;
      scratch_write_channel = clear_channel;
    end else if (state == S_WRITE_BYTES) begin
      scratch_write_enable = 1'b1;
      scratch_write_pixel =
        (ADDR_W'(payload_y + local_y_offset_q) *
         ADDR_W'(local_input_width_q)) +
        ADDR_W'(payload_x + local_x_offset_q);
      scratch_write_channel = payload_channel;
      scratch_write_data =
        $signed(beat_data_q[(int'(beat_lane) * 8) +: 8]);
    end
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state <= S_IDLE;
      local_input_width_q <= '0;
      local_input_height_q <= '0;
      source_width_q <= '0;
      local_x_offset_q <= '0;
      local_y_offset_q <= '0;
      input_channels_q <= '0;
      expected_payload_bytes_q <= '0;
      clear_pixel <= '0;
      clear_channel <= '0;
      payload_x <= '0;
      payload_y <= '0;
      payload_channel <= '0;
      payload_byte_count <= '0;
      beat_data_q <= '0;
      beat_keep_q <= '0;
      beat_last_q <= 1'b0;
      beat_lane <= '0;
      done <= 1'b0;
      error <= 1'b0;
      error_code <= LOAD_ERROR_NONE;
    end else begin
      done <= 1'b0;

      if (clear) begin
        state <= S_IDLE;
        error <= 1'b0;
        error_code <= LOAD_ERROR_NONE;
      end else begin
        unique case (state)
          S_IDLE: begin
            if (packet_start) begin
              error <= 1'b0;
              error_code <= LOAD_ERROR_NONE;
              if (!context_valid) begin
                error <= 1'b1;
                error_code <= LOAD_ERROR_CONTEXT;
                state <= S_DROP;
              end else if (!metadata_valid) begin
                error <= 1'b1;
                error_code <=
                  (packet_payload_length != expected_payload_bytes) ?
                    LOAD_ERROR_PAYLOAD_LENGTH :
                    LOAD_ERROR_PACKET_METADATA;
                state <= S_DROP;
              end else begin
                local_input_width_q <= local_input_width;
                local_input_height_q <= local_input_height;
                source_width_q <= source_width;
                local_x_offset_q <= local_x_offset;
                local_y_offset_q <= local_y_offset;
                input_channels_q <= input_channels;
                expected_payload_bytes_q <= expected_payload_bytes;
                clear_pixel <= '0;
                clear_channel <= '0;
                payload_x <= '0;
                payload_y <= '0;
                payload_channel <= '0;
                payload_byte_count <= '0;
                state <= S_CLEAR;
              end
            end
          end

          S_CLEAR: begin
            if ((clear_channel + COUNT_W'(1)) < input_channels_q) begin
              clear_channel <= clear_channel + COUNT_W'(1);
            end else begin
              clear_channel <= '0;
              if ((clear_pixel + ADDR_W'(1)) <
                  (ADDR_W'(local_input_width_q) *
                   ADDR_W'(local_input_height_q))) begin
                clear_pixel <= clear_pixel + ADDR_W'(1);
              end else begin
                state <= S_WAIT_BEAT;
              end
            end
          end

          S_WAIT_BEAT: begin
            if (payload_transfer) begin
              if (!keep_valid) begin
                error <= 1'b1;
                error_code <= LOAD_ERROR_KEEP;
                state <= payload_last ? S_DONE : S_DROP;
              end else begin
                beat_data_q <= payload_data;
                beat_keep_q <= payload_keep;
                beat_last_q <= payload_last;
                beat_lane <= '0;
                state <= S_WRITE_BYTES;
              end
            end
          end

          S_WRITE_BYTES: begin
            payload_byte_count <= payload_byte_count + 32'd1;

            if ((payload_channel + COUNT_W'(1)) < input_channels_q) begin
              payload_channel <= payload_channel + COUNT_W'(1);
            end else begin
              payload_channel <= '0;
              if ((payload_x + DIM_W'(1)) < source_width_q) begin
                payload_x <= payload_x + DIM_W'(1);
              end else begin
                payload_x <= '0;
                payload_y <= payload_y + DIM_W'(1);
              end
            end

            if ((3'(beat_lane) + 3'd1) < beat_byte_count) begin
              beat_lane <= beat_lane + 2'd1;
            end else if (beat_last_q) begin
              if ((payload_byte_count + 32'd1) ==
                  expected_payload_bytes_q) begin
                state <= S_FLUSH;
              end else begin
                error <= 1'b1;
                error_code <= LOAD_ERROR_EARLY_LAST;
                state <= S_DONE;
              end
            end else if ((payload_byte_count + 32'd1) >=
                         expected_payload_bytes_q) begin
              error <= 1'b1;
              error_code <= LOAD_ERROR_MISSING_LAST;
              state <= S_DROP;
            end else begin
              state <= S_WAIT_BEAT;
            end
          end

          S_FLUSH: begin
            state <= S_DONE;
          end

          S_DROP: begin
            if (payload_transfer && payload_last) begin
              state <= S_DONE;
            end
          end

          S_DONE: begin
            done <= 1'b1;
            state <= S_IDLE;
          end

          default: state <= S_IDLE;
        endcase
      end
    end
  end

endmodule
