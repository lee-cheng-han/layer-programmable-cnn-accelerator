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
  input  logic [31:0] pixel_index,
  input  logic residual_enable,
  input  logic subtract_residual,

  output logic [31:0] residual_read_pixel,
  output logic [COUNT_W-1:0] residual_read_channel,
  input  logic signed [DATA_W-1:0] residual_read_data,

  output logic byte_valid,
  input  logic byte_ready,
  output logic signed [DATA_W-1:0] byte_data,
  output logic byte_last,
  output logic busy,
  output logic done,
  output logic error,
  output logic residual_saturation_event
);

  localparam int CHANNEL_INDEX_W =
    (MAX_COUT <= 1) ? 1 : $clog2(MAX_COUT);

  typedef enum logic [1:0] {
    S_IDLE,
    S_WAIT_RESIDUAL,
    S_EMIT
  } state_t;

  state_t state;
  logic [COUNT_W-1:0] channels_q;
  logic [COUNT_W-1:0] channel_index;
  logic signed [DATA_W-1:0] data_q [MAX_COUT];
  logic pixel_last_q;
  logic [31:0] pixel_index_q;
  logic residual_enable_q;
  logic subtract_residual_q;
  logic byte_transfer;
  logic signed [DATA_W:0] residual_combined;
  logic signed [DATA_W-1:0] selected_data;
  localparam logic signed [DATA_W:0] SAT_MAX =
    (DATA_W+1)'((1 << (DATA_W - 1)) - 1);
  localparam logic signed [DATA_W:0] SAT_MIN =
    -(DATA_W+1)'(1 << (DATA_W - 1));

  assign pixel_ready = state == S_IDLE;
  assign byte_valid = state == S_EMIT;
  assign byte_data = selected_data;
  assign byte_last =
    (state == S_EMIT) && pixel_last_q &&
    ((channel_index + COUNT_W'(1)) >= channels_q);
  assign busy = state != S_IDLE;
  assign byte_transfer = byte_valid && byte_ready;
  assign residual_read_pixel = pixel_index_q;
  assign residual_read_channel = channel_index;

  always_comb begin
    residual_combined = {
      data_q[channel_index[CHANNEL_INDEX_W-1:0]][DATA_W-1],
      data_q[channel_index[CHANNEL_INDEX_W-1:0]]
    };
    if (residual_enable_q) begin
      if (subtract_residual_q) begin
        residual_combined =
          {residual_read_data[DATA_W-1], residual_read_data} -
          {data_q[channel_index[CHANNEL_INDEX_W-1:0]][DATA_W-1],
           data_q[channel_index[CHANNEL_INDEX_W-1:0]]};
      end else begin
        residual_combined =
          {residual_read_data[DATA_W-1], residual_read_data} +
          {data_q[channel_index[CHANNEL_INDEX_W-1:0]][DATA_W-1],
           data_q[channel_index[CHANNEL_INDEX_W-1:0]]};
      end
    end

    if (residual_combined > SAT_MAX) begin
      selected_data = {1'b0, {(DATA_W-1){1'b1}}};
    end else if (residual_combined < SAT_MIN) begin
      selected_data = {1'b1, {(DATA_W-1){1'b0}}};
    end else begin
      selected_data = residual_combined[DATA_W-1:0];
    end
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state <= S_IDLE;
      channels_q <= '0;
      channel_index <= '0;
      pixel_last_q <= 1'b0;
      pixel_index_q <= '0;
      residual_enable_q <= 1'b0;
      subtract_residual_q <= 1'b0;
      done <= 1'b0;
      error <= 1'b0;
      residual_saturation_event <= 1'b0;
      for (int channel = 0; channel < MAX_COUT; channel++) begin
        data_q[channel] <= '0;
      end
    end else begin
      done <= 1'b0;
      residual_saturation_event <= 1'b0;

      if (clear) begin
        state <= S_IDLE;
        channels_q <= '0;
        channel_index <= '0;
        pixel_last_q <= 1'b0;
        pixel_index_q <= '0;
        residual_enable_q <= 1'b0;
        subtract_residual_q <= 1'b0;
        error <= 1'b0;
      end else begin
        if (pixel_valid && pixel_ready) begin
          if ((pixel_channels == '0) ||
              (pixel_channels > COUNT_W'(MAX_COUT))) begin
            error <= 1'b1;
          end else begin
            channels_q <= pixel_channels;
            channel_index <= '0;
            pixel_last_q <= pixel_last;
            pixel_index_q <= pixel_index;
            residual_enable_q <= residual_enable;
            subtract_residual_q <= subtract_residual;
            state <= residual_enable ? S_WAIT_RESIDUAL : S_EMIT;
            for (int channel = 0; channel < MAX_COUT; channel++) begin
              data_q[channel] <= pixel_data[channel];
            end
          end
        end

        if (byte_transfer) begin
          residual_saturation_event <= residual_enable_q &&
            ((residual_combined > SAT_MAX) || (residual_combined < SAT_MIN));
          if ((channel_index + COUNT_W'(1)) >= channels_q) begin
            state <= S_IDLE;
            channel_index <= '0;
            if (pixel_last_q) begin
              done <= 1'b1;
            end
          end else begin
            channel_index <= channel_index + COUNT_W'(1);
            state <= residual_enable_q ? S_WAIT_RESIDUAL : S_EMIT;
          end
        end

        if (state == S_WAIT_RESIDUAL) begin
          state <= S_EMIT;
        end
      end
    end
  end

endmodule
