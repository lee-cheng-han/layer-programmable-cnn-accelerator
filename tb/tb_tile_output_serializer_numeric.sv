`timescale 1ns/1ps

module tb_tile_output_serializer_numeric;
  localparam int MAX_COUT = 2;

  logic clk = 1'b0;
  logic rst_n = 1'b0;
  logic clear = 1'b0;
  logic pixel_valid = 1'b0;
  logic pixel_ready;
  logic [7:0] pixel_channels = 8'd2;
  logic signed [7:0] pixel_data [MAX_COUT];
  logic pixel_last = 1'b1;
  logic [31:0] pixel_index = '0;
  logic residual_enable = 1'b1;
  logic subtract_residual = 1'b0;
  logic [31:0] residual_read_pixel;
  logic [7:0] residual_read_channel;
  logic signed [7:0] residual_read_data;
  logic byte_valid;
  logic byte_ready = 1'b1;
  logic signed [7:0] byte_data;
  logic byte_last;
  logic busy;
  logic done;
  logic error;
  logic residual_saturation_event;
  logic signed [7:0] residual_memory [4];
  logic signed [7:0] captured [8];
  logic captured_last [8];
  int captured_count = 0;
  int saturation_count = 0;

  always #5 clk = ~clk;

  tile_output_serializer #(
    .MAX_COUT(MAX_COUT),
    .COUNT_W(8),
    .DATA_W(8)
  ) dut (.*);

  always_ff @(posedge clk) begin
    residual_read_data <= residual_memory[
      (residual_read_pixel * MAX_COUT) + 32'(residual_read_channel)];
    if (byte_valid && byte_ready) begin
      captured[captured_count] <= byte_data;
      captured_last[captured_count] <= byte_last;
      captured_count <= captured_count + 1;
    end
    if (residual_saturation_event) begin
      saturation_count <= saturation_count + 1;
    end
  end

  task automatic send_pixel(
    input logic subtract,
    input int pixel,
    input logic signed [7:0] network0,
    input logic signed [7:0] network1,
    input logic signed [7:0] residual0,
    input logic signed [7:0] residual1
  );
    begin
      residual_memory[(pixel * MAX_COUT)] = 8'(residual0);
      residual_memory[(pixel * MAX_COUT) + 1] = 8'(residual1);
      @(negedge clk);
      subtract_residual = subtract;
      pixel_index = 32'(pixel);
      pixel_data[0] = 8'(network0);
      pixel_data[1] = 8'(network1);
      pixel_valid = 1'b1;
      do @(posedge clk); while (!pixel_ready);
      @(negedge clk);
      pixel_valid = 1'b0;
      wait (done);
      @(posedge clk);
    end
  endtask

  initial begin
    pixel_data[0] = '0;
    pixel_data[1] = '0;
    for (int index = 0; index < 4; index++) residual_memory[index] = '0;
    repeat (4) @(posedge clk);
    rst_n = 1'b1;

    send_pixel(1'b0, 0, 100, -100, 50, -50);
    send_pixel(1'b1, 1, 100, -100, -100, 100);
    repeat (2) @(posedge clk);

    if (error || busy || (captured_count != 4) || (saturation_count != 4) ||
        (captured[0] != 8'sd127) || (captured[1] != -8'sd128) ||
        (captured[2] != -8'sd128) || (captured[3] != 8'sd127) ||
        captured_last[0] || !captured_last[1] ||
        captured_last[2] || !captured_last[3]) begin
      $fatal(1,
        "numeric serializer mismatch count=%0d saturation=%0d values=%0d,%0d,%0d,%0d",
        captured_count, saturation_count, captured[0], captured[1],
        captured[2], captured[3]);
    end

    $display("[PASS] tile output residual add/subtract saturation");
    $finish;
  end
endmodule
