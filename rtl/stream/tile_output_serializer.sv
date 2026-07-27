`timescale 1ns/1ps

module tile_output_serializer #(
  parameter int MAX_COUT = 16,
  parameter int COUNT_W = 8,
  parameter int DATA_W = 8
)(
  input  logic clk,
  input  logic rst_n,
  input  logic clear,

  input  logic pixel_valid,
  output logic pixel_ready,
  input  logic [COUNT_W-1:0] pixel_channels,
  input  logic signed [DATA_W-1:0] pixel_data [MAX_COUT],
  input  logic pixel_last,

  output logic byte_valid,
  input  logic byte_ready,
  output logic signed [DATA_W-1:0] byte_data,
  output logic byte_last,
  output logic busy,
  output logic done,
  output logic error
);

  localparam int CHANNEL_INDEX_W =
    (MAX_COUT <= 1) ? 1 : $clog2(MAX_COUT);

  logic buffer_valid;
  logic [COUNT_W-1:0] channels_q;
  logic [COUNT_W-1:0] channel_index;
  logic signed [DATA_W-1:0] data_q [MAX_COUT];
  logic pixel_last_q;
  logic byte_transfer;

  assign pixel_ready = !buffer_valid;
  assign byte_valid = buffer_valid;
  assign byte_data = data_q[channel_index[CHANNEL_INDEX_W-1:0]];
  assign byte_last =
    buffer_valid && pixel_last_q &&
    ((channel_index + COUNT_W'(1)) >= channels_q);
  assign busy = buffer_valid;
  assign byte_transfer = byte_valid && byte_ready;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      buffer_valid <= 1'b0;
      channels_q <= '0;
      channel_index <= '0;
      pixel_last_q <= 1'b0;
      done <= 1'b0;
      error <= 1'b0;
      for (int channel = 0; channel < MAX_COUT; channel++) begin
        data_q[channel] <= '0;
      end
    end else begin
      done <= 1'b0;

      if (clear) begin
        buffer_valid <= 1'b0;
        channels_q <= '0;
        channel_index <= '0;
        pixel_last_q <= 1'b0;
        error <= 1'b0;
      end else begin
        if (pixel_valid && pixel_ready) begin
          if ((pixel_channels == '0) ||
              (pixel_channels > COUNT_W'(MAX_COUT))) begin
            error <= 1'b1;
          end else begin
            buffer_valid <= 1'b1;
            channels_q <= pixel_channels;
            channel_index <= '0;
            pixel_last_q <= pixel_last;
            for (int channel = 0; channel < MAX_COUT; channel++) begin
              data_q[channel] <= pixel_data[channel];
            end
          end
        end

        if (byte_transfer) begin
          if ((channel_index + COUNT_W'(1)) >= channels_q) begin
            buffer_valid <= 1'b0;
            channel_index <= '0;
            if (pixel_last_q) begin
              done <= 1'b1;
            end
          end else begin
            channel_index <= channel_index + COUNT_W'(1);
          end
        end
      end
    end
  end

endmodule
