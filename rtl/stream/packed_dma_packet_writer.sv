`timescale 1ns/1ps

module packed_dma_packet_writer #(
  parameter int MAX_PAYLOAD_BYTES = 4 * 1024 * 1024
)(
  input  logic clk,
  input  logic rst_n,
  input  logic clear,

  input  logic packet_start,
  output logic packet_ready,
  input  logic [31:0] job_id,
  input  logic [15:0] tensor_id,
  input  logic [15:0] layer_id,
  input  logic [15:0] tile_x,
  input  logic [15:0] tile_y,
  input  logic [15:0] tile_width,
  input  logic [15:0] tile_height,
  input  logic [15:0] channel_offset,
  input  logic [15:0] channel_count,
  input  logic [31:0] payload_length,

  input  logic payload_byte_valid,
  output logic payload_byte_ready,
  input  logic signed [7:0] payload_byte_data,

  output logic [31:0] m_axis_tdata,
  output logic [3:0] m_axis_tkeep,
  output logic m_axis_tvalid,
  input  logic m_axis_tready,
  output logic m_axis_tlast,

  output logic busy,
  output logic packet_done,
  output logic error,
  output logic [7:0] error_code
);
  import cnn_dma_packet_pkg::*;

  localparam logic [7:0] WRITER_ERROR_NONE = 8'd0;
  localparam logic [7:0] WRITER_ERROR_PAYLOAD_LENGTH = 8'd1;
  localparam logic [7:0] WRITER_ERROR_EARLY_START = 8'd2;

  typedef enum logic [1:0] {
    S_IDLE,
    S_HEADER,
    S_FILL,
    S_SEND
  } state_t;

  state_t state;
  logic [2:0] header_word_index;
  logic [31:0] job_id_q;
  logic [15:0] tensor_id_q;
  logic [15:0] layer_id_q;
  logic [15:0] tile_x_q;
  logic [15:0] tile_y_q;
  logic [15:0] tile_width_q;
  logic [15:0] tile_height_q;
  logic [15:0] channel_offset_q;
  logic [15:0] channel_count_q;
  logic [31:0] payload_length_q;
  logic [31:0] payload_bytes_accepted;
  logic [31:0] payload_buffer;
  logic [2:0] payload_buffer_bytes;
  logic payload_buffer_last;
  logic output_transfer;
  logic payload_byte_transfer;

  always_comb begin
    unique case (header_word_index)
      3'd0: m_axis_tdata = DMA_PACKET_MAGIC;
      3'd1: m_axis_tdata = {
        8'd0, DMA_PACKET_OUTPUT_TILE, DMA_PACKET_HEADER_WORDS,
        DMA_PACKET_VERSION
      };
      3'd2: m_axis_tdata = job_id_q;
      3'd3: m_axis_tdata = {layer_id_q, tensor_id_q};
      3'd4: m_axis_tdata = {tile_y_q, tile_x_q};
      3'd5: m_axis_tdata = {tile_height_q, tile_width_q};
      3'd6: m_axis_tdata = {channel_count_q, channel_offset_q};
      default: m_axis_tdata = payload_length_q;
    endcase

    m_axis_tkeep = 4'b1111;
    m_axis_tvalid = state == S_HEADER;
    m_axis_tlast = 1'b0;
    if (state == S_SEND) begin
      m_axis_tdata = payload_buffer;
      m_axis_tkeep = keep_for_byte_count(payload_buffer_bytes);
      m_axis_tvalid = 1'b1;
      m_axis_tlast = payload_buffer_last;
    end
  end

  assign packet_ready = state == S_IDLE;
  assign payload_byte_ready = state == S_FILL;
  assign busy = state != S_IDLE;
  assign output_transfer = m_axis_tvalid && m_axis_tready;
  assign payload_byte_transfer = payload_byte_valid && payload_byte_ready;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state <= S_IDLE;
      header_word_index <= '0;
      job_id_q <= '0;
      tensor_id_q <= '0;
      layer_id_q <= '0;
      tile_x_q <= '0;
      tile_y_q <= '0;
      tile_width_q <= '0;
      tile_height_q <= '0;
      channel_offset_q <= '0;
      channel_count_q <= '0;
      payload_length_q <= '0;
      payload_bytes_accepted <= '0;
      payload_buffer <= '0;
      payload_buffer_bytes <= '0;
      payload_buffer_last <= 1'b0;
      packet_done <= 1'b0;
      error <= 1'b0;
      error_code <= WRITER_ERROR_NONE;
    end else begin
      packet_done <= 1'b0;

      if (clear) begin
        state <= S_IDLE;
        header_word_index <= '0;
        payload_bytes_accepted <= '0;
        payload_buffer_bytes <= '0;
        error <= 1'b0;
        error_code <= WRITER_ERROR_NONE;
      end else begin
        if (packet_start && !packet_ready) begin
          error <= 1'b1;
          error_code <= WRITER_ERROR_EARLY_START;
        end

        unique case (state)
          S_IDLE: begin
            if (packet_start) begin
              if ((payload_length == 0) ||
                  (payload_length > 32'(MAX_PAYLOAD_BYTES))) begin
                error <= 1'b1;
                error_code <= WRITER_ERROR_PAYLOAD_LENGTH;
              end else begin
                job_id_q <= job_id;
                tensor_id_q <= tensor_id;
                layer_id_q <= layer_id;
                tile_x_q <= tile_x;
                tile_y_q <= tile_y;
                tile_width_q <= tile_width;
                tile_height_q <= tile_height;
                channel_offset_q <= channel_offset;
                channel_count_q <= channel_count;
                payload_length_q <= payload_length;
                payload_bytes_accepted <= '0;
                payload_buffer <= '0;
                payload_buffer_bytes <= '0;
                payload_buffer_last <= 1'b0;
                header_word_index <= '0;
                state <= S_HEADER;
              end
            end
          end

          S_HEADER: begin
            if (output_transfer) begin
              if (header_word_index == 3'd7) begin
                header_word_index <= '0;
                state <= S_FILL;
              end else begin
                header_word_index <= header_word_index + 3'd1;
              end
            end
          end

          S_FILL: begin
            if (payload_byte_transfer) begin
              payload_buffer[
                (int'(payload_buffer_bytes) * 8) +: 8
              ] <= payload_byte_data;
              payload_buffer_bytes <= payload_buffer_bytes + 3'd1;
              payload_bytes_accepted <= payload_bytes_accepted + 32'd1;
              if (payload_bytes_accepted + 32'd1 >= payload_length_q) begin
                payload_buffer_last <= 1'b1;
                state <= S_SEND;
              end else if (payload_buffer_bytes == 3'd3) begin
                payload_buffer_last <= 1'b0;
                state <= S_SEND;
              end
            end
          end

          S_SEND: begin
            if (output_transfer) begin
              payload_buffer <= '0;
              payload_buffer_bytes <= '0;
              if (payload_buffer_last) begin
                packet_done <= 1'b1;
                state <= S_IDLE;
              end else begin
                state <= S_FILL;
              end
            end
          end

          default: state <= S_IDLE;
        endcase
      end
    end
  end
endmodule
