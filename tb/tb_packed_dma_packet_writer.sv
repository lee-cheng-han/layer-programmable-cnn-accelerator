`timescale 1ns/1ps

module tb_packed_dma_packet_writer;
  import cnn_dma_packet_pkg::*;

  logic clk;
  logic rst_n;
  logic clear;
  logic packet_start;
  logic packet_ready;
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
  logic payload_byte_valid;
  logic payload_byte_ready;
  logic signed [7:0] payload_byte_data;
  logic [31:0] m_axis_tdata;
  logic [3:0] m_axis_tkeep;
  logic m_axis_tvalid;
  logic m_axis_tready;
  logic m_axis_tlast;
  logic busy;
  logic packet_done;
  logic error;
  logic [7:0] error_code;

  logic [31:0] captured_data [0:15];
  logic [3:0] captured_keep [0:15];
  logic captured_last [0:15];
  int captured_count;
  int checks;
  int errors;

  packed_dma_packet_writer #(
    .MAX_PAYLOAD_BYTES(1024)
  ) dut (
    .clk(clk),
    .rst_n(rst_n),
    .clear(clear),
    .packet_start(packet_start),
    .packet_ready(packet_ready),
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
    .payload_byte_valid(payload_byte_valid),
    .payload_byte_ready(payload_byte_ready),
    .payload_byte_data(payload_byte_data),
    .m_axis_tdata(m_axis_tdata),
    .m_axis_tkeep(m_axis_tkeep),
    .m_axis_tvalid(m_axis_tvalid),
    .m_axis_tready(m_axis_tready),
    .m_axis_tlast(m_axis_tlast),
    .busy(busy),
    .packet_done(packet_done),
    .error(error),
    .error_code(error_code)
  );

  initial begin
    clk = 1'b0;
    forever #5 clk = ~clk;
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      captured_count <= 0;
    end else if (m_axis_tvalid && m_axis_tready) begin
      captured_data[captured_count] <= m_axis_tdata;
      captured_keep[captured_count] <= m_axis_tkeep;
      captured_last[captured_count] <= m_axis_tlast;
      captured_count <= captured_count + 1;
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

  task automatic send_byte(input int value);
    begin
      @(negedge clk);
      while (!payload_byte_ready) @(negedge clk);
      payload_byte_data = 8'(value);
      payload_byte_valid = 1'b1;
      @(negedge clk);
      payload_byte_valid = 1'b0;
    end
  endtask

  initial begin
    checks = 0;
    errors = 0;
    rst_n = 1'b0;
    clear = 1'b0;
    packet_start = 1'b0;
    job_id = 32'd42;
    tensor_id = 16'd9;
    layer_id = 16'd3;
    tile_x = 16'd5;
    tile_y = 16'd6;
    tile_width = 16'd7;
    tile_height = 16'd8;
    channel_offset = 16'd2;
    channel_count = 16'd10;
    payload_length = 32'd6;
    payload_byte_valid = 1'b0;
    payload_byte_data = '0;
    m_axis_tready = 1'b1;

    repeat (4) @(posedge clk);
    rst_n = 1'b1;
    repeat (2) @(posedge clk);

    @(negedge clk);
    packet_start = 1'b1;
    @(negedge clk);
    packet_start = 1'b0;

    wait (captured_count == 2);
    @(negedge clk);
    m_axis_tready = 1'b0;
    repeat (3) @(negedge clk);
    check_value("header backpressure valid", int'(m_axis_tvalid), 1);
    check_value("header backpressure stable",
                int'(m_axis_tdata), int'(32'd42));
    m_axis_tready = 1'b1;

    for (int value = 1; value <= 6; value++) begin
      send_byte(value);
    end
    wait (packet_done);
    @(negedge clk);

    check_value("packet beat count", captured_count, 10);
    check_value("magic", int'(captured_data[0]), int'(DMA_PACKET_MAGIC));
    check_value("type/version",
                int'(captured_data[1]),
                int'({8'd0, DMA_PACKET_OUTPUT_TILE,
                      DMA_PACKET_HEADER_WORDS, DMA_PACKET_VERSION}));
    check_value("job", int'(captured_data[2]), 42);
    check_value("ids", int'(captured_data[3]), int'({16'd3, 16'd9}));
    check_value("coordinates",
                int'(captured_data[4]), int'({16'd6, 16'd5}));
    check_value("shape", int'(captured_data[5]), int'({16'd8, 16'd7}));
    check_value("channels",
                int'(captured_data[6]), int'({16'd10, 16'd2}));
    check_value("length", int'(captured_data[7]), 6);
    check_value("first payload data",
                int'(captured_data[8]), int'(32'h0403_0201));
    check_value("first payload keep", int'(captured_keep[8]), 15);
    check_value("first payload last", int'(captured_last[8]), 0);
    check_value("final payload data",
                int'(captured_data[9]), int'(32'h0000_0605));
    check_value("final payload keep", int'(captured_keep[9]), 3);
    check_value("final payload last", int'(captured_last[9]), 1);
    check_value("writer idle", int'(busy), 0);
    check_value("writer error clear", int'(error), 0);

    payload_length = 0;
    @(negedge clk);
    packet_start = 1'b1;
    @(negedge clk);
    packet_start = 1'b0;
    check_value("zero length rejected", int'(error), 1);
    check_value("length error code", int'(error_code), 1);
    check_value("invalid packet not emitted", captured_count, 10);

    if (errors == 0) begin
      $display("[PASS] tb_packed_dma_packet_writer tests=%0d", checks);
    end else begin
      $display("[FAIL] tb_packed_dma_packet_writer errors=%0d tests=%0d",
               errors, checks);
      $fatal(1);
    end
    $finish;
  end
endmodule
