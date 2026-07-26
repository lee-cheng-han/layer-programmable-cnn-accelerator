`timescale 1ns/1ps

module packed_dma_packet_parser #(
  parameter int MAX_PAYLOAD_BYTES = 4 * 1024 * 1024
)(
  input  logic clk,
  input  logic rst_n,
  input  logic clear,

  input  logic [31:0] s_axis_tdata,
  input  logic [3:0] s_axis_tkeep,
  input  logic s_axis_tvalid,
  output logic s_axis_tready,
  input  logic s_axis_tlast,

  output logic packet_start,
  input  logic packet_ready,
  output logic packet_done,
  output logic [7:0] packet_type,
  output logic [31:0] job_id,
  output logic [15:0] tensor_id,
  output logic [15:0] layer_id,
  output logic [15:0] tile_x,
  output logic [15:0] tile_y,
  output logic [15:0] tile_width,
  output logic [15:0] tile_height,
  output logic [15:0] channel_offset,
  output logic [15:0] channel_count,
  output logic [31:0] payload_length,

  output logic payload_valid,
  input  logic payload_ready,
  output logic [31:0] payload_data,
  output logic [3:0] payload_keep,
  output logic payload_last,

  output logic packet_busy,
  output logic recovering,
  output logic error_valid,
  output logic [7:0] error_code,
  output logic [31:0] error_count
);
  import cnn_dma_packet_pkg::*;

  typedef enum logic [1:0] {
    S_HEADER,
    S_PAYLOAD,
    S_DISCARD
  } state_t;

  state_t state;
  logic [2:0] header_word_index;
  logic [31:0] payload_bytes_received;
  logic [31:0] payload_bytes_remaining;
  logic [2:0] expected_beat_bytes;
  logic [3:0] expected_keep;
  logic expected_last;
  logic payload_beat_valid;
  logic input_transfer;
  logic header_error;
  logic [7:0] header_error_code;
  logic payload_error;
  logic [7:0] payload_error_code;

  assign payload_bytes_remaining = payload_length - payload_bytes_received;
  assign expected_beat_bytes =
    (payload_bytes_remaining >= 32'd4) ? 3'd4 : 3'(payload_bytes_remaining);
  assign expected_keep = keep_for_byte_count(expected_beat_bytes);
  assign expected_last = payload_bytes_remaining <= 32'd4;
  assign payload_beat_valid =
    (s_axis_tkeep == expected_keep) && (s_axis_tlast == expected_last);

  always_comb begin
    header_error = 1'b0;
    header_error_code = DMA_PACKET_ERROR_NONE;
    if (s_axis_tkeep != 4'b1111) begin
      header_error = 1'b1;
      header_error_code = DMA_PACKET_ERROR_HEADER_KEEP;
    end else if (s_axis_tlast) begin
      header_error = 1'b1;
      header_error_code = DMA_PACKET_ERROR_HEADER_LAST;
    end else begin
      unique case (header_word_index)
        3'd0: begin
          if (s_axis_tdata != DMA_PACKET_MAGIC) begin
            header_error = 1'b1;
            header_error_code = DMA_PACKET_ERROR_MAGIC;
          end
        end
        3'd1: begin
          if (s_axis_tdata[7:0] != DMA_PACKET_VERSION) begin
            header_error = 1'b1;
            header_error_code = DMA_PACKET_ERROR_VERSION;
          end else if (s_axis_tdata[15:8] != DMA_PACKET_HEADER_WORDS) begin
            header_error = 1'b1;
            header_error_code = DMA_PACKET_ERROR_HEADER_SIZE;
          end else if (!packet_type_supported(s_axis_tdata[23:16])) begin
            header_error = 1'b1;
            header_error_code = DMA_PACKET_ERROR_TYPE;
          end else if (s_axis_tdata[31:24] != 8'd0) begin
            header_error = 1'b1;
            header_error_code = DMA_PACKET_ERROR_FLAGS;
          end
        end
        3'd7: begin
          if ((s_axis_tdata == 0) ||
              (s_axis_tdata > 32'(MAX_PAYLOAD_BYTES))) begin
            header_error = 1'b1;
            header_error_code = DMA_PACKET_ERROR_PAYLOAD_LENGTH;
          end
        end
        default: begin
        end
      endcase
    end
  end

  always_comb begin
    payload_error = 1'b0;
    payload_error_code = DMA_PACKET_ERROR_NONE;
    if (s_axis_tkeep != expected_keep) begin
      payload_error = 1'b1;
      payload_error_code = DMA_PACKET_ERROR_PAYLOAD_KEEP;
    end else if (s_axis_tlast != expected_last) begin
      payload_error = 1'b1;
      payload_error_code = DMA_PACKET_ERROR_PAYLOAD_LAST;
    end
  end

  always_comb begin
    unique case (state)
      S_HEADER: begin
        s_axis_tready = (header_word_index == 3'd7) ? packet_ready : 1'b1;
      end
      S_PAYLOAD: begin
        s_axis_tready = (s_axis_tvalid && payload_error) ? 1'b1 : payload_ready;
      end
      S_DISCARD: s_axis_tready = 1'b1;
      default: s_axis_tready = 1'b0;
    endcase
  end

  assign input_transfer = s_axis_tvalid && s_axis_tready;
  assign payload_valid =
    (state == S_PAYLOAD) && s_axis_tvalid && !payload_error;
  assign payload_data = s_axis_tdata;
  assign payload_keep = s_axis_tkeep;
  assign payload_last = s_axis_tlast;
  assign packet_busy = state != S_HEADER || header_word_index != 0;
  assign recovering = state == S_DISCARD;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state <= S_HEADER;
      header_word_index <= '0;
      payload_bytes_received <= '0;
      packet_type <= '0;
      job_id <= '0;
      tensor_id <= '0;
      layer_id <= '0;
      tile_x <= '0;
      tile_y <= '0;
      tile_width <= '0;
      tile_height <= '0;
      channel_offset <= '0;
      channel_count <= '0;
      payload_length <= '0;
      packet_start <= 1'b0;
      packet_done <= 1'b0;
      error_valid <= 1'b0;
      error_code <= DMA_PACKET_ERROR_NONE;
      error_count <= '0;
    end else begin
      packet_start <= 1'b0;
      packet_done <= 1'b0;
      error_valid <= 1'b0;

      if (clear) begin
        state <= S_HEADER;
        header_word_index <= '0;
        payload_bytes_received <= '0;
        error_code <= DMA_PACKET_ERROR_NONE;
        error_count <= '0;
      end else begin
        unique case (state)
          S_HEADER: begin
            if (input_transfer) begin
              if (header_error) begin
                error_valid <= 1'b1;
                error_code <= header_error_code;
                error_count <= error_count + 32'd1;
                header_word_index <= '0;
                state <= s_axis_tlast ? S_HEADER : S_DISCARD;
              end else begin
                unique case (header_word_index)
                  3'd1: packet_type <= s_axis_tdata[23:16];
                  3'd2: job_id <= s_axis_tdata;
                  3'd3: begin
                    tensor_id <= s_axis_tdata[15:0];
                    layer_id <= s_axis_tdata[31:16];
                  end
                  3'd4: begin
                    tile_x <= s_axis_tdata[15:0];
                    tile_y <= s_axis_tdata[31:16];
                  end
                  3'd5: begin
                    tile_width <= s_axis_tdata[15:0];
                    tile_height <= s_axis_tdata[31:16];
                  end
                  3'd6: begin
                    channel_offset <= s_axis_tdata[15:0];
                    channel_count <= s_axis_tdata[31:16];
                  end
                  3'd7: begin
                    payload_length <= s_axis_tdata;
                    payload_bytes_received <= '0;
                    packet_start <= 1'b1;
                    header_word_index <= '0;
                    state <= S_PAYLOAD;
                  end
                  default: begin
                  end
                endcase
                if (header_word_index != 3'd7) begin
                  header_word_index <= header_word_index + 3'd1;
                end
              end
            end
          end

          S_PAYLOAD: begin
            if (input_transfer) begin
              if (payload_error) begin
                error_valid <= 1'b1;
                error_code <= payload_error_code;
                error_count <= error_count + 32'd1;
                payload_bytes_received <= '0;
                state <= s_axis_tlast ? S_HEADER : S_DISCARD;
              end else if (expected_last) begin
                payload_bytes_received <= '0;
                packet_done <= 1'b1;
                state <= S_HEADER;
              end else begin
                payload_bytes_received <=
                  payload_bytes_received + 32'(bytes_for_keep(s_axis_tkeep));
              end
            end
          end

          S_DISCARD: begin
            if (input_transfer && s_axis_tlast) begin
              state <= S_HEADER;
              header_word_index <= '0;
              payload_bytes_received <= '0;
            end
          end

          default: begin
            state <= S_HEADER;
            header_word_index <= '0;
            payload_bytes_received <= '0;
          end
        endcase
      end
    end
  end
endmodule
