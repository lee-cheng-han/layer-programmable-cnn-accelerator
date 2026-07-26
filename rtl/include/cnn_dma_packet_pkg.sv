`default_nettype none
`timescale 1ns/1ps

package cnn_dma_packet_pkg;
  localparam logic [31:0] DMA_PACKET_MAGIC = 32'h3150_4E43;
  localparam logic [7:0] DMA_PACKET_VERSION = 8'd1;
  localparam logic [7:0] DMA_PACKET_HEADER_WORDS = 8'd8;
  localparam int unsigned DMA_PACKET_HEADER_BYTES = 32;

  typedef enum logic [7:0] {
    DMA_PACKET_INPUT_TILE = 8'd1,
    DMA_PACKET_LAYER_WEIGHTS = 8'd2,
    DMA_PACKET_LAYER_BIASES = 8'd3,
    DMA_PACKET_OUTPUT_TILE = 8'd4
  } dma_packet_type_e;

  typedef enum logic [7:0] {
    DMA_PACKET_ERROR_NONE = 8'd0,
    DMA_PACKET_ERROR_HEADER_KEEP = 8'd1,
    DMA_PACKET_ERROR_HEADER_LAST = 8'd2,
    DMA_PACKET_ERROR_MAGIC = 8'd3,
    DMA_PACKET_ERROR_VERSION = 8'd4,
    DMA_PACKET_ERROR_HEADER_SIZE = 8'd5,
    DMA_PACKET_ERROR_TYPE = 8'd6,
    DMA_PACKET_ERROR_FLAGS = 8'd7,
    DMA_PACKET_ERROR_PAYLOAD_LENGTH = 8'd8,
    DMA_PACKET_ERROR_PAYLOAD_KEEP = 8'd9,
    DMA_PACKET_ERROR_PAYLOAD_LAST = 8'd10
  } dma_packet_error_e;

  function automatic logic packet_type_supported(input logic [7:0] packet_type);
    return (packet_type >= DMA_PACKET_INPUT_TILE) &&
           (packet_type <= DMA_PACKET_OUTPUT_TILE);
  endfunction

  function automatic logic [3:0] keep_for_byte_count(input logic [2:0] byte_count);
    unique case (byte_count)
      3'd1: return 4'b0001;
      3'd2: return 4'b0011;
      3'd3: return 4'b0111;
      default: return 4'b1111;
    endcase
  endfunction

  function automatic logic [2:0] bytes_for_keep(input logic [3:0] keep);
    unique case (keep)
      4'b0001: return 3'd1;
      4'b0011: return 3'd2;
      4'b0111: return 3'd3;
      4'b1111: return 3'd4;
      default: return 3'd0;
    endcase
  endfunction
endpackage

`default_nettype wire
