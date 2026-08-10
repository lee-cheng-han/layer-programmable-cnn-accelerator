`timescale 1ns/1ps

module tb_programmable_system_top;
  import cnn_dma_packet_pkg::*;

  localparam logic [11:0] ADDR_CONTROL = 12'h000;
  localparam logic [11:0] ADDR_STATUS = 12'h004;
  localparam logic [11:0] ADDR_JOB_ID = 12'h010;
  localparam logic [11:0] ADDR_PARAMETER_LAYER = 12'h014;
  localparam logic [11:0] ADDR_MODEL_COMMAND = 12'h018;
  localparam logic [11:0] ADDR_MODEL_STATUS = 12'h01C;
  localparam logic [11:0] ADDR_ACTIVE_MODEL_ID = 12'h020;
  localparam logic [11:0] ADDR_ACTIVE_GENERATION = 12'h024;
  localparam logic [11:0] ADDR_METADATA_ADDRESS = 12'h02C;
  localparam logic [11:0] ADDR_METADATA_DATA = 12'h030;
  localparam logic [11:0] ADDR_METADATA_COMMIT = 12'h034;
  localparam logic [11:0] ADDR_ACTIVE_TENSORS = 12'h040;
  localparam logic [11:0] ADDR_CURRENT_TILE = 12'h044;
  localparam logic [11:0] ADDR_COMPLETED_LAYERS = 12'h048;
  localparam logic [11:0] ADDR_PACKET_ERRORS = 12'h050;
  localparam logic [11:0] ADDR_PARAMETER_BANKS = 12'h054;
  localparam logic [11:0] ADDR_INPUT_DDR_LO = 12'h058;
  localparam logic [11:0] ADDR_OUTPUT_DDR_LO = 12'h060;
  localparam logic [11:0] ADDR_SATURATION_EVENTS = 12'h068;
  localparam logic [11:0] ADDR_VERSION = 12'h0FC;

  logic aclk = 1'b0;
  logic aresetn = 1'b0;
  logic [11:0] s_axi_awaddr = '0;
  logic s_axi_awvalid = 1'b0;
  logic s_axi_awready;
  logic [31:0] s_axi_wdata = '0;
  logic [3:0] s_axi_wstrb = '0;
  logic s_axi_wvalid = 1'b0;
  logic s_axi_wready;
  logic [1:0] s_axi_bresp;
  logic s_axi_bvalid;
  logic s_axi_bready = 1'b0;
  logic [11:0] s_axi_araddr = '0;
  logic s_axi_arvalid = 1'b0;
  logic s_axi_arready;
  logic [31:0] s_axi_rdata;
  logic [1:0] s_axi_rresp;
  logic s_axi_rvalid;
  logic s_axi_rready = 1'b0;
  logic [31:0] s_axis_tdata = '0;
  logic [3:0] s_axis_tkeep = '0;
  logic s_axis_tvalid = 1'b0;
  logic s_axis_tready;
  logic s_axis_tlast = 1'b0;
  logic [31:0] m_axis_tdata;
  logic [3:0] m_axis_tkeep;
  logic m_axis_tvalid;
  logic m_axis_tready = 1'b0;
  logic m_axis_tlast;
  logic irq;
  logic busy;
  logic done;
  logic error;
  logic [31:0] captured_data [0:31];
  logic [3:0] captured_keep [0:31];
  logic captured_last [0:31];
  int captured_count = 0;
  logic [15:0] ready_lfsr = 16'hACE1;

  always #5 aclk = ~aclk;

  cnn_programmable_system_top #(
    .PC(2), .PK(2), .MAX_CIN(2), .MAX_COUT(2),
    .MAX_LAYERS(2), .MAX_TENSORS(4), .MAX_QUANTIZATIONS(2),
    .MAX_TILE_WIDTH(2), .MAX_TILE_HEIGHT(2)
  ) dut (.*);

  always_ff @(posedge aclk) begin
    if (!aresetn) begin
      ready_lfsr <= 16'hACE1;
      m_axis_tready <= 1'b0;
    end else begin
      ready_lfsr <= {ready_lfsr[14:0],
                     ready_lfsr[15] ^ ready_lfsr[13] ^
                     ready_lfsr[12] ^ ready_lfsr[10]};
      m_axis_tready <= ready_lfsr[0] | ready_lfsr[2];
    end
    if (m_axis_tvalid && m_axis_tready) begin
      captured_data[captured_count] <= m_axis_tdata;
      captured_keep[captured_count] <= m_axis_tkeep;
      captured_last[captured_count] <= m_axis_tlast;
      captured_count <= captured_count + 1;
    end
  end

  function automatic logic [31:0] crc32_byte(
    input logic [31:0] crc_in,
    input logic [7:0] data
  );
    logic [31:0] value;
    begin
      value = crc_in ^ {24'd0, data};
      for (int bit_index = 0; bit_index < 8; bit_index++) begin
        value = value[0] ? ((value >> 1) ^ 32'hEDB8_8320) : (value >> 1);
      end
      return value;
    end
  endfunction

  function automatic logic [31:0] metadata_address(
    input logic [1:0] kind,
    input int record_index,
    input int word_index
  );
    return {18'd0, 6'(word_index), 6'(record_index), kind};
  endfunction

  task automatic axi_write(
    input logic [11:0] address,
    input logic [31:0] data
  );
    begin
      @(negedge aclk);
      s_axi_awaddr = address;
      s_axi_awvalid = 1'b1;
      s_axi_wdata = data;
      s_axi_wstrb = 4'hF;
      s_axi_wvalid = 1'b1;
      s_axi_bready = 1'b1;
      fork
        wait (s_axi_awready);
        wait (s_axi_wready);
      join
      @(negedge aclk);
      s_axi_awvalid = 1'b0;
      s_axi_wvalid = 1'b0;
      wait (s_axi_bvalid);
      if (s_axi_bresp != 0) $fatal(1, "AXI write failed at %h", address);
      @(negedge aclk);
      s_axi_bready = 1'b0;
    end
  endtask

  task automatic axi_read(
    input logic [11:0] address,
    output logic [31:0] data
  );
    begin
      @(negedge aclk);
      s_axi_araddr = address;
      s_axi_arvalid = 1'b1;
      s_axi_rready = 1'b1;
      wait (s_axi_arready);
      @(negedge aclk);
      s_axi_arvalid = 1'b0;
      wait (s_axi_rvalid);
      data = s_axi_rdata;
      if (s_axi_rresp != 0) $fatal(1, "AXI read failed at %h", address);
      @(negedge aclk);
      s_axi_rready = 1'b0;
    end
  endtask

  task automatic write_metadata(
    input logic [1:0] kind,
    input int record_index,
    input int word_index,
    input logic [31:0] data
  );
    begin
      axi_write(ADDR_METADATA_ADDRESS,
                metadata_address(kind, record_index, word_index));
      axi_write(ADDR_METADATA_DATA, data);
    end
  endtask

  task automatic commit_metadata(input logic [1:0] kind, input int index);
    begin
      axi_write(ADDR_METADATA_ADDRESS, metadata_address(kind, index, 0));
      axi_write(ADDR_METADATA_COMMIT, 32'd1);
    end
  endtask

  task automatic load_model;
    logic [31:0] parameter_crc;
    begin
      parameter_crc = crc32_byte(32'hFFFF_FFFF, 8'd1) ^ 32'hFFFF_FFFF;
      write_metadata(0, 0, 0, 32'h314E_4E43);
      write_metadata(0, 0, 1, 32'h0080_0001);
      write_metadata(0, 0, 4, 32'd501);
      write_metadata(0, 0, 5, 32'd12);
      write_metadata(0, 0, 6, 32'h0002_0001);
      write_metadata(0, 0, 7, 32'h0000_0001);
      commit_metadata(0, 0);
      write_metadata(1, 0, 0, 32'h0080_0001);
      write_metadata(1, 0, 1, 32'h0001_0000);
      write_metadata(1, 0, 2, 32'h0000_0002);
      write_metadata(1, 0, 3, 32'h0001_0000);
      write_metadata(1, 0, 4, 32'h0000_FFFF);
      write_metadata(1, 0, 6, 32'd1);
      write_metadata(1, 0, 8, 32'd0);
      write_metadata(1, 0, 9, parameter_crc);
      write_metadata(1, 0, 10, 32'h0101_0101);
      write_metadata(1, 0, 11, 32'd0);
      write_metadata(1, 0, 12, 32'h0000_0101);
      write_metadata(1, 0, 13, 32'h0002_0002);
      commit_metadata(1, 0);
      for (int tensor = 0; tensor < 2; tensor++) begin
        write_metadata(2, tensor, 0, 32'h0040_0001);
        write_metadata(2, tensor, 1, {16'd1, 16'(tensor)});
        write_metadata(2, tensor, 2,
                       tensor == 0 ? 32'h1000 : 32'h2000);
        write_metadata(2, tensor, 3, 32'd0);
        write_metadata(2, tensor, 4, 32'd6);
        write_metadata(2, tensor, 5, 32'h0002_0003);
        write_metadata(2, tensor, 6, 32'h0101_0001);
        write_metadata(2, tensor, 7, 32'd0);
        write_metadata(2, tensor, 9, 32'd3);
        write_metadata(2, tensor, 10, 32'd1);
        write_metadata(2, tensor, 11, 32'd1);
        commit_metadata(2, tensor);
      end
      write_metadata(3, 0, 0, 32'h00C0_0001);
      write_metadata(3, 0, 1, 32'd0);
      write_metadata(3, 0, 2, 32'h0001_0001);
      write_metadata(3, 0, 16, 32'd1);
      write_metadata(3, 0, 17, 32'd0);
      commit_metadata(3, 0);
    end
  endtask

  task automatic send_beat(
    input logic [31:0] data,
    input logic [3:0] keep,
    input logic last
  );
    begin
      @(negedge aclk);
      s_axis_tdata = data;
      s_axis_tkeep = keep;
      s_axis_tlast = last;
      s_axis_tvalid = 1'b1;
      do @(posedge aclk); while (!s_axis_tready);
      @(negedge aclk);
      s_axis_tvalid = 1'b0;
      s_axis_tlast = 1'b0;
      s_axis_tkeep = '0;
    end
  endtask

  task automatic send_packet(
    input logic [7:0] type_id,
    input int tensor_id,
    input int layer_id,
    input int tile_x,
    input int tile_width,
    input logic [31:0] payload,
    input logic [3:0] keep,
    input int payload_bytes
  );
    begin
      send_beat(DMA_PACKET_MAGIC, 4'hF, 1'b0);
      send_beat({8'd0, type_id, DMA_PACKET_HEADER_WORDS,
                 DMA_PACKET_VERSION}, 4'hF, 1'b0);
      send_beat(32'd99, 4'hF, 1'b0);
      send_beat({16'(layer_id), 16'(tensor_id)}, 4'hF, 1'b0);
      send_beat({16'd0, 16'(tile_x)}, 4'hF, 1'b0);
      send_beat({16'd2, 16'(tile_width)}, 4'hF, 1'b0);
      send_beat({16'd1, 16'd0}, 4'hF, 1'b0);
      send_beat(32'(payload_bytes), 4'hF, 1'b0);
      send_beat(payload, keep, 1'b1);
    end
  endtask

  initial begin
    logic [31:0] value;
    repeat (4) @(posedge aclk);
    aresetn = 1'b1;
    repeat (2) @(posedge aclk);

    axi_read(ADDR_VERSION, value);
    if (value != 32'h0005_0001) $fatal(1, "bad register version");
    axi_write(ADDR_JOB_ID, 32'd99);
    axi_write(ADDR_PARAMETER_LAYER, 32'd0);
    axi_write(ADDR_MODEL_COMMAND, 32'h1);
    load_model();
    axi_write(ADDR_MODEL_COMMAND, 32'h2);
    axi_write(ADDR_MODEL_COMMAND, 32'h4);
    axi_write(ADDR_MODEL_COMMAND, 32'h8);
    axi_read(ADDR_MODEL_STATUS, value);
    if (!value[3] || (value[11:4] != 0)) $fatal(1, "model not active");
    axi_read(ADDR_ACTIVE_MODEL_ID, value);
    if (value != 501) $fatal(1, "active model ID mismatch");
    axi_read(ADDR_ACTIVE_GENERATION, value);
    if (value != 12) $fatal(1, "active generation mismatch");

    send_packet(DMA_PACKET_LAYER_WEIGHTS, 0, 0, 0, 0,
                32'h0000_0101, 4'b0011, 1);
    repeat (4) @(posedge aclk);
    axi_read(ADDR_STATUS, value);
    if (!value[2]) $fatal(1, "malformed parameter packet was not rejected");
    axi_read(ADDR_PACKET_ERRORS, value);
    if (value != 1) $fatal(1, "malformed packet count mismatch");
    axi_read(ADDR_ACTIVE_MODEL_ID, value);
    if (value != 501) $fatal(1, "malformed packet corrupted active model");
    axi_write(ADDR_CONTROL, 32'd2);
    repeat (3) @(posedge aclk);
    axi_read(ADDR_STATUS, value);
    if (value[2] || !value[4])
      $fatal(1, "runtime did not recover with active model preserved");
    axi_read(ADDR_PACKET_ERRORS, value);
    if (value != 0) $fatal(1, "packet error count did not clear");

    send_packet(DMA_PACKET_LAYER_WEIGHTS, 0, 0, 0, 0,
                32'd1, 4'b0001, 1);
    do axi_read(ADDR_PARAMETER_BANKS, value); while (value[1:0] == 0);
    axi_write(ADDR_CONTROL, 32'd1);
    wait (busy && dut.current_tile_x == 0);
    repeat (2) @(posedge aclk);
    if (!dut.u_runtime.parameter_config_valid_q)
      $fatal(1, "parameter refill configuration unavailable while busy");
    send_packet(DMA_PACKET_INPUT_TILE, 0, 0, 0, 2,
                32'h0504_0201, 4'hF, 4);
    wait (busy && dut.current_tile_x == 2);
    send_packet(DMA_PACKET_INPUT_TILE, 0, 0, 2, 1,
                32'h0000_0603, 4'h3, 2);
    fork
      wait (done);
      begin
        repeat (10000) @(posedge aclk);
        $fatal(1, "programmable AXI-Lite system timed out");
      end
    join_any
    disable fork;
    repeat (2) @(posedge aclk);

    axi_read(ADDR_STATUS, value);
    if (error || value[2] || (captured_count != 18))
      $fatal(1, "bad final status %h beats=%0d", value, captured_count);
    axi_read(ADDR_COMPLETED_LAYERS, value);
    if (value != 1) $fatal(1, "completed layer count mismatch");
    axi_read(ADDR_PACKET_ERRORS, value);
    if (value != 0) $fatal(1, "packet errors observed");
    axi_read(ADDR_SATURATION_EVENTS, value);
    if (value != 0) $fatal(1, "unexpected saturation events");
    axi_read(ADDR_ACTIVE_TENSORS, value);
    if (value != 32'h0001_0000) $fatal(1, "active tensor context mismatch");
    axi_read(ADDR_INPUT_DDR_LO, value);
    if (value != 32'h1000) $fatal(1, "input DDR offset mismatch");
    axi_read(ADDR_OUTPUT_DDR_LO, value);
    if (value != 32'h2000) $fatal(1, "output DDR offset mismatch");
    axi_read(ADDR_CURRENT_TILE, value);
    if (value != 32'h0000_0002) $fatal(1, "tile progress mismatch");
    if ((captured_data[8] != 32'h0504_0201) ||
        (captured_data[17] != 32'h0000_0603) ||
        (captured_keep[17] != 4'h3) || !captured_last[17])
      $fatal(1, "packed output mismatch");

    $display("[PASS] AXI-Lite model lifecycle to packed tiled output");
    $finish;
  end
endmodule
