`timescale 1ns/1ps

module tb_packed_dma_packet_parser;
  import cnn_dma_packet_pkg::*;

  logic clk;
  logic rst_n;
  logic clear;
  logic [31:0] s_axis_tdata;
  logic [3:0] s_axis_tkeep;
  logic s_axis_tvalid;
  logic s_axis_tready;
  logic s_axis_tlast;
  logic packet_start;
  logic packet_done;
  logic [7:0] packet_type;
  logic [31:0] job_id;
  logic [15:0] tensor_id;
  logic [15:0] layer_id;
  logic [15:0] tile_x;
  logic [15:0] tile_y;
  logic [15:0] tile_width;
  logic [15:0] tile_height;
  logic [15:0] channel_offset;
  logic [15:0] channel_count;
  logic [31:0] payload_length;
  logic payload_valid;
  logic payload_ready;
  logic [31:0] payload_data;
  logic [3:0] payload_keep;
  logic payload_last;
  logic packet_busy;
  logic recovering;
  logic error_valid;
  logic [7:0] error_code;
  logic [31:0] error_count;

  logic [7:0] captured_bytes [0:63];
  int captured_count;
  int completed_packets;
  int checks;
  int errors;

  packed_dma_packet_parser #(
    .MAX_PAYLOAD_BYTES(1024)
  ) dut (
    .clk(clk),
    .rst_n(rst_n),
    .clear(clear),
    .s_axis_tdata(s_axis_tdata),
    .s_axis_tkeep(s_axis_tkeep),
    .s_axis_tvalid(s_axis_tvalid),
    .s_axis_tready(s_axis_tready),
    .s_axis_tlast(s_axis_tlast),
    .packet_start(packet_start),
    .packet_ready(1'b1),
    .packet_done(packet_done),
    .packet_type(packet_type),
    .job_id(job_id),
    .tensor_id(tensor_id),
    .layer_id(layer_id),
    .tile_x(tile_x),
    .tile_y(tile_y),
    .tile_width(tile_width),
    .tile_height(tile_height),
    .channel_offset(channel_offset),
    .channel_count(channel_count),
    .payload_length(payload_length),
    .payload_valid(payload_valid),
    .payload_ready(payload_ready),
    .payload_data(payload_data),
    .payload_keep(payload_keep),
    .payload_last(payload_last),
    .packet_busy(packet_busy),
    .recovering(recovering),
    .error_valid(error_valid),
    .error_code(error_code),
    .error_count(error_count)
  );

  initial begin
    clk = 1'b0;
    forever #5 clk = ~clk;
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      captured_count <= 0;
      completed_packets <= 0;
    end else begin
      if (payload_valid && payload_ready) begin
        for (int lane = 0; lane < 4; lane++) begin
          if (payload_keep[lane]) begin
            captured_bytes[captured_count + lane] <=
              payload_data[(lane * 8) +: 8];
          end
        end
        captured_count <= captured_count + int'(bytes_for_keep(payload_keep));
      end
      if (payload_valid && payload_ready && payload_last) begin
        completed_packets <= completed_packets + 1;
      end
    end
  end

  task automatic check_value(input string name, input int got, input int expected);
    begin
      checks++;
      if (got != expected) begin
        errors++;
        $error("%s got=%0d expected=%0d", name, got, expected);
      end
    end
  endtask

  task automatic send_beat(
    input logic [31:0] data,
    input logic [3:0] keep,
    input logic last
  );
    begin
      @(negedge clk);
      s_axis_tdata = data;
      s_axis_tkeep = keep;
      s_axis_tlast = last;
      s_axis_tvalid = 1'b1;
      do begin
        @(posedge clk);
      end while (!s_axis_tready);
      @(negedge clk);
      s_axis_tvalid = 1'b0;
      s_axis_tlast = 1'b0;
      s_axis_tkeep = '0;
      s_axis_tdata = '0;
    end
  endtask

  task automatic send_header(
    input logic [7:0] type_id,
    input int payload_bytes,
    input int selected_job_id
  );
    begin
      send_beat(DMA_PACKET_MAGIC, 4'hF, 1'b0);
      send_beat({8'd0, 8'(type_id), DMA_PACKET_HEADER_WORDS,
                 DMA_PACKET_VERSION}, 4'hF, 1'b0);
      send_beat(32'(selected_job_id), 4'hF, 1'b0);
      send_beat({16'd3, 16'd9}, 4'hF, 1'b0);
      send_beat({16'd6, 16'd5}, 4'hF, 1'b0);
      send_beat({16'd8, 16'd7}, 4'hF, 1'b0);
      send_beat({16'd10, 16'd2}, 4'hF, 1'b0);
      send_beat(32'(payload_bytes), 4'hF, 1'b0);
    end
  endtask

  task automatic expect_error(
    input string name,
    input logic [7:0] expected_code
  );
    int timeout;
    begin
      timeout = 0;
      while (!error_valid && timeout < 20) begin
        @(negedge clk);
        timeout++;
      end
      check_value(name, int'(error_code), int'(expected_code));
    end
  endtask

  task automatic send_one_byte_packet(input logic [7:0] value);
    begin
      send_header(DMA_PACKET_INPUT_TILE, 1, 77);
      send_beat(32'(value), 4'b0001, 1'b1);
    end
  endtask

  initial begin
    checks = 0;
    errors = 0;
    rst_n = 1'b0;
    clear = 1'b0;
    s_axis_tdata = '0;
    s_axis_tkeep = '0;
    s_axis_tvalid = 1'b0;
    s_axis_tlast = 1'b0;
    payload_ready = 1'b1;

    repeat (4) @(posedge clk);
    rst_n = 1'b1;
    repeat (2) @(posedge clk);

    send_header(DMA_PACKET_INPUT_TILE, 6, 42);
    check_value("packet start", int'(packet_start), 1);
    check_value("packet type", int'(packet_type), int'(DMA_PACKET_INPUT_TILE));
    check_value("job id", int'(job_id), 42);
    check_value("tensor id", int'(tensor_id), 9);
    check_value("layer id", int'(layer_id), 3);
    check_value("tile x", int'(tile_x), 5);
    check_value("tile y", int'(tile_y), 6);
    check_value("tile width", int'(tile_width), 7);
    check_value("tile height", int'(tile_height), 8);
    check_value("channel offset", int'(channel_offset), 2);
    check_value("channel count", int'(channel_count), 10);
    check_value("payload length", int'(payload_length), 6);

    payload_ready = 1'b0;
    fork
      begin
        send_beat(32'h0403_0201, 4'b1111, 1'b0);
      end
      begin
        repeat (3) @(negedge clk);
        check_value("payload backpressure", int'(s_axis_tready), 0);
        payload_ready = 1'b1;
      end
    join
    send_beat(32'h0000_0605, 4'b0011, 1'b1);
    repeat (2) @(posedge clk);
    check_value("first packet complete", completed_packets, 1);
    check_value("packed byte count", captured_count, 6);
    for (int index = 0; index < 6; index++) begin
      check_value("packed byte order", int'(captured_bytes[index]), index + 1);
    end

    send_header(DMA_PACKET_LAYER_WEIGHTS, 4, 43);
    send_beat(32'h4433_2211, 4'b0101, 1'b1);
    expect_error("non-contiguous keep", DMA_PACKET_ERROR_PAYLOAD_KEEP);
    send_one_byte_packet(8'h55);
    repeat (2) @(posedge clk);
    check_value("recovered after bad keep", completed_packets, 2);

    send_header(DMA_PACKET_LAYER_WEIGHTS, 4, 44);
    send_beat(32'h8877_6655, 4'b1111, 1'b0);
    expect_error("missing final TLAST", DMA_PACKET_ERROR_PAYLOAD_LAST);
    check_value("discard state entered", int'(recovering), 1);
    send_beat(32'hDEAD_BEEF, 4'b1111, 1'b1);
    check_value("discard state exited", int'(recovering), 0);
    send_one_byte_packet(8'h66);
    repeat (2) @(posedge clk);
    check_value("recovered after missing TLAST", completed_packets, 3);

    send_header(DMA_PACKET_LAYER_WEIGHTS, 5, 45);
    send_beat(32'h0403_0201, 4'b1111, 1'b1);
    expect_error("early payload TLAST", DMA_PACKET_ERROR_PAYLOAD_LAST);
    send_one_byte_packet(8'h77);
    repeat (2) @(posedge clk);
    check_value("recovered after early TLAST", completed_packets, 4);

    send_beat(DMA_PACKET_MAGIC, 4'hF, 1'b0);
    send_beat({8'd0, DMA_PACKET_INPUT_TILE, DMA_PACKET_HEADER_WORDS, 8'd2},
              4'hF, 1'b0);
    expect_error("bad packet version", DMA_PACKET_ERROR_VERSION);
    send_beat(32'h0, 4'hF, 1'b1);
    send_one_byte_packet(8'h7F);
    repeat (2) @(posedge clk);
    check_value("recovered after bad header", completed_packets, 5);

    send_beat(DMA_PACKET_MAGIC, 4'hF, 1'b1);
    expect_error("TLAST on header", DMA_PACKET_ERROR_HEADER_LAST);
    send_one_byte_packet(8'h80);
    repeat (2) @(posedge clk);
    check_value("recovered after header TLAST", completed_packets, 6);
    check_value("error count", int'(error_count), 5);
    check_value("parser idle", int'(packet_busy), 0);

    if (errors == 0) begin
      $display("[PASS] tb_packed_dma_packet_parser tests=%0d", checks);
    end else begin
      $display("[FAIL] tb_packed_dma_packet_parser errors=%0d tests=%0d",
               errors, checks);
      $fatal(1);
    end
    $finish;
  end
endmodule
