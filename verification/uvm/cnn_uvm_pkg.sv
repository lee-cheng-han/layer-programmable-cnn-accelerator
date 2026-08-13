package cnn_uvm_pkg;
  import uvm_pkg::*;
  `include "uvm_macros.svh"

  localparam logic [31:0] DMA_MAGIC = 32'h3150_4E43;
  localparam int DMA_HEADER_WORDS = 8;

  typedef enum bit {AXI_READ, AXI_WRITE} cnn_axi_kind_e;

  class cnn_axi_lite_item extends uvm_sequence_item;
    rand cnn_axi_kind_e kind;
    rand bit [11:0] address;
    rand bit [31:0] data;
    rand bit [3:0] strobe;
    rand int unsigned address_delay;
    rand int unsigned data_delay;
    rand int unsigned response_ready_delay;
    bit [1:0] response;

    constraint bounded_delays_c {
      address_delay inside {[0:15]};
      data_delay inside {[0:15]};
      response_ready_delay inside {[0:15]};
    }

    `uvm_object_utils_begin(cnn_axi_lite_item)
      `uvm_field_enum(cnn_axi_kind_e, kind, UVM_DEFAULT)
      `uvm_field_int(address, UVM_HEX)
      `uvm_field_int(data, UVM_HEX)
      `uvm_field_int(strobe, UVM_HEX)
      `uvm_field_int(address_delay, UVM_DEC)
      `uvm_field_int(data_delay, UVM_DEC)
      `uvm_field_int(response_ready_delay, UVM_DEC)
      `uvm_field_int(response, UVM_HEX)
    `uvm_object_utils_end

    function new(string name = "cnn_axi_lite_item");
      super.new(name);
      strobe = 4'hF;
      address_delay = 0;
      data_delay = 0;
      response_ready_delay = 0;
    endfunction
  endclass

  class cnn_axis_packet extends uvm_sequence_item;
    rand bit [7:0] packet_type;
    rand bit [31:0] job_id;
    rand bit [15:0] tensor_id;
    rand bit [15:0] layer_id;
    rand bit [15:0] tile_x;
    rand bit [15:0] tile_y;
    rand bit [15:0] tile_width;
    rand bit [15:0] tile_height;
    rand bit [15:0] channel_offset;
    rand bit [15:0] channel_count;
    rand byte unsigned payload[];
    bit [31:0] protocol_magic = DMA_MAGIC;
    bit [7:0] protocol_version = 1;
    bit [7:0] protocol_header_words = DMA_HEADER_WORDS;
    bit [7:0] protocol_flags = 0;
    int declared_payload_length = -1;

    constraint payload_size_c { payload.size() inside {[1:4096]}; }

    `uvm_object_utils_begin(cnn_axis_packet)
      `uvm_field_int(packet_type, UVM_DEC)
      `uvm_field_int(job_id, UVM_HEX)
      `uvm_field_int(tensor_id, UVM_DEC)
      `uvm_field_int(layer_id, UVM_DEC)
      `uvm_field_int(tile_x, UVM_DEC)
      `uvm_field_int(tile_y, UVM_DEC)
      `uvm_field_int(tile_width, UVM_DEC)
      `uvm_field_int(tile_height, UVM_DEC)
      `uvm_field_int(channel_offset, UVM_DEC)
      `uvm_field_int(channel_count, UVM_DEC)
      `uvm_field_int(protocol_magic, UVM_HEX)
      `uvm_field_int(protocol_version, UVM_DEC)
      `uvm_field_int(protocol_header_words, UVM_DEC)
      `uvm_field_int(protocol_flags, UVM_HEX)
      `uvm_field_array_int(payload, UVM_HEX)
      `uvm_field_int(declared_payload_length, UVM_DEC)
    `uvm_object_utils_end

    function new(string name = "cnn_axis_packet");
      super.new(name);
    endfunction

    function bit compare_packet(cnn_axis_packet rhs, output string reason);
      if (packet_type != rhs.packet_type || job_id != rhs.job_id ||
          tensor_id != rhs.tensor_id || layer_id != rhs.layer_id ||
          tile_x != rhs.tile_x || tile_y != rhs.tile_y ||
          tile_width != rhs.tile_width || tile_height != rhs.tile_height ||
          channel_offset != rhs.channel_offset ||
          channel_count != rhs.channel_count) begin
        reason = "header mismatch";
        return 0;
      end
      if (payload.size() != rhs.payload.size()) begin
        reason = $sformatf("payload length mismatch got=%0d expected=%0d",
                           payload.size(), rhs.payload.size());
        return 0;
      end
      foreach (payload[index]) begin
        if (payload[index] != rhs.payload[index]) begin
          reason = $sformatf("payload[%0d] got=%02x expected=%02x",
                             index, payload[index], rhs.payload[index]);
          return 0;
        end
      end
      reason = "";
      return 1;
    endfunction
  endclass

  class cnn_axi_lite_sequencer extends uvm_sequencer #(cnn_axi_lite_item);
    `uvm_component_utils(cnn_axi_lite_sequencer)
    function new(string name, uvm_component parent);
      super.new(name, parent);
    endfunction
  endclass

  class cnn_axi_lite_driver extends uvm_driver #(cnn_axi_lite_item);
    `uvm_component_utils(cnn_axi_lite_driver)
    virtual cnn_axi_lite_if vif;

    function new(string name, uvm_component parent);
      super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      if (!uvm_config_db#(virtual cnn_axi_lite_if)::get(this, "", "vif", vif))
        `uvm_fatal("NOVIF", "AXI-Lite driver has no virtual interface")
    endfunction

    task run_phase(uvm_phase phase);
      cnn_axi_lite_item request;
      cnn_axi_lite_item response;
      vif.reset_master();
      wait (vif.aresetn);
      forever begin
        seq_item_port.get_next_item(request);
        response = cnn_axi_lite_item::type_id::create("response");
        response.set_id_info(request);
        response.kind = request.kind;
        response.address = request.address;
        if (request.kind == AXI_WRITE) drive_write(request, response);
        else drive_read(request, response);
        seq_item_port.item_done(response);
      end
    endtask

    task drive_write(cnn_axi_lite_item request, cnn_axi_lite_item response);
      vif.bready <= 1'b0;
      fork
        begin
          repeat (request.address_delay) @(posedge vif.aclk);
          @(negedge vif.aclk);
          vif.awaddr <= request.address;
          vif.awvalid <= 1'b1;
          do @(posedge vif.aclk); while (!vif.awready);
          @(negedge vif.aclk);
          vif.awvalid <= 1'b0;
        end
        begin
          repeat (request.data_delay) @(posedge vif.aclk);
          @(negedge vif.aclk);
          vif.wdata <= request.data;
          vif.wstrb <= request.strobe;
          vif.wvalid <= 1'b1;
          do @(posedge vif.aclk); while (!vif.wready);
          @(negedge vif.aclk);
          vif.wvalid <= 1'b0;
        end
      join
      repeat (request.response_ready_delay) @(posedge vif.aclk);
      @(negedge vif.aclk);
      vif.bready <= 1'b1;
      do @(posedge vif.aclk); while (!vif.bvalid);
      response.data = request.data;
      response.strobe = request.strobe;
      response.response = vif.bresp;
      @(negedge vif.aclk);
      vif.bready <= 1'b0;
    endtask

    task drive_read(cnn_axi_lite_item request, cnn_axi_lite_item response);
      repeat (request.address_delay) @(posedge vif.aclk);
      @(negedge vif.aclk);
      vif.araddr <= request.address;
      vif.arvalid <= 1'b1;
      vif.rready <= 1'b0;
      do @(posedge vif.aclk); while (!vif.arready);
      @(negedge vif.aclk);
      vif.arvalid <= 1'b0;
      repeat (request.response_ready_delay) @(posedge vif.aclk);
      @(negedge vif.aclk);
      vif.rready <= 1'b1;
      do @(posedge vif.aclk); while (!vif.rvalid);
      response.data = vif.rdata;
      response.response = vif.rresp;
      @(negedge vif.aclk);
      vif.rready <= 1'b0;
    endtask
  endclass

  class cnn_axi_lite_monitor extends uvm_monitor;
    `uvm_component_utils(cnn_axi_lite_monitor)
    virtual cnn_axi_lite_if vif;
    uvm_analysis_port #(cnn_axi_lite_item) analysis_port;
    bit [11:0] write_address;
    bit [31:0] write_data;
    bit [3:0] write_strobe;
    bit [11:0] read_address;
    bit have_address;
    bit have_data;
    bit have_read_address;
    longint unsigned cycle_count;
    longint unsigned address_cycle;
    longint unsigned data_cycle;
    longint unsigned read_address_cycle;

    function new(string name, uvm_component parent);
      super.new(name, parent);
      analysis_port = new("analysis_port", this);
    endfunction

    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      if (!uvm_config_db#(virtual cnn_axi_lite_if)::get(this, "", "vif", vif))
        `uvm_fatal("NOVIF", "AXI-Lite monitor has no virtual interface")
    endfunction

    task run_phase(uvm_phase phase);
      cnn_axi_lite_item item;
      forever begin
        @(posedge vif.aclk);
        cycle_count++;
        if (!vif.aresetn) begin
          have_address = 0;
          have_data = 0;
          have_read_address = 0;
        end else begin
          if (vif.awvalid && vif.awready) begin
            write_address = vif.awaddr;
            address_cycle = cycle_count;
            have_address = 1;
          end
          if (vif.wvalid && vif.wready) begin
            write_data = vif.wdata;
            write_strobe = vif.wstrb;
            data_cycle = cycle_count;
            have_data = 1;
          end
          if (vif.arvalid && vif.arready) begin
            read_address = vif.araddr;
            read_address_cycle = cycle_count;
            have_read_address = 1;
          end
          if (vif.bvalid && vif.bready && have_address && have_data) begin
            item = cnn_axi_lite_item::type_id::create("observed_write");
            item.kind = AXI_WRITE;
            item.address = write_address;
            item.data = write_data;
            item.strobe = write_strobe;
            if (address_cycle <= data_cycle) begin
              item.address_delay = 0;
              item.data_delay = data_cycle - address_cycle;
            end else begin
              item.address_delay = address_cycle - data_cycle;
              item.data_delay = 0;
            end
            item.response_ready_delay = cycle_count -
                                        ((address_cycle > data_cycle) ?
                                         address_cycle : data_cycle);
            item.response = vif.bresp;
            analysis_port.write(item);
            have_address = 0;
            have_data = 0;
          end
          if (vif.rvalid && vif.rready && have_read_address) begin
            item = cnn_axi_lite_item::type_id::create("observed_read");
            item.kind = AXI_READ;
            item.address = read_address;
            item.data = vif.rdata;
            item.response_ready_delay = cycle_count - read_address_cycle;
            item.response = vif.rresp;
            analysis_port.write(item);
            have_read_address = 0;
          end
        end
      end
    endtask
  endclass

  class cnn_axi_lite_agent extends uvm_agent;
    `uvm_component_utils(cnn_axi_lite_agent)
    cnn_axi_lite_sequencer sequencer;
    cnn_axi_lite_driver driver;
    cnn_axi_lite_monitor monitor;

    function new(string name, uvm_component parent);
      super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      monitor = cnn_axi_lite_monitor::type_id::create("monitor", this);
      if (get_is_active() == UVM_ACTIVE) begin
        sequencer = cnn_axi_lite_sequencer::type_id::create("sequencer", this);
        driver = cnn_axi_lite_driver::type_id::create("driver", this);
      end
    endfunction

    function void connect_phase(uvm_phase phase);
      if (get_is_active() == UVM_ACTIVE)
        driver.seq_item_port.connect(sequencer.seq_item_export);
    endfunction
  endclass

  class cnn_axis_sequencer extends uvm_sequencer #(cnn_axis_packet);
    `uvm_component_utils(cnn_axis_sequencer)
    function new(string name, uvm_component parent);
      super.new(name, parent);
    endfunction
  endclass

  class cnn_axis_source_driver extends uvm_driver #(cnn_axis_packet);
    `uvm_component_utils(cnn_axis_source_driver)
    virtual cnn_axis_if vif;

    function new(string name, uvm_component parent);
      super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      if (!uvm_config_db#(virtual cnn_axis_if)::get(this, "", "vif", vif))
        `uvm_fatal("NOVIF", "AXIS source driver has no virtual interface")
    endfunction

    task send_beat(bit [31:0] data, bit [3:0] keep, bit last);
      @(negedge vif.aclk);
      vif.tdata <= data;
      vif.tkeep <= keep;
      vif.tlast <= last;
      vif.tvalid <= 1'b1;
      do @(posedge vif.aclk); while (!vif.tready);
      @(negedge vif.aclk);
      vif.tvalid <= 1'b0;
      vif.tkeep <= '0;
      vif.tlast <= 1'b0;
    endtask

    task drive_packet(cnn_axis_packet packet);
      bit [31:0] headers[8];
      bit [31:0] data;
      int remaining;
      headers[0] = packet.protocol_magic;
      headers[1] = {packet.protocol_flags, packet.packet_type,
                    packet.protocol_header_words, packet.protocol_version};
      headers[2] = packet.job_id;
      headers[3] = {packet.layer_id, packet.tensor_id};
      headers[4] = {packet.tile_y, packet.tile_x};
      headers[5] = {packet.tile_height, packet.tile_width};
      headers[6] = {packet.channel_count, packet.channel_offset};
      headers[7] = packet.declared_payload_length < 0 ?
                   packet.payload.size() : packet.declared_payload_length;
      foreach (headers[index]) send_beat(headers[index], 4'hF, 1'b0);
      for (int offset = 0; offset < packet.payload.size(); offset += 4) begin
        data = '0;
        remaining = packet.payload.size() - offset;
        for (int lane = 0; lane < 4 && lane < remaining; lane++)
          data[lane*8 +: 8] = packet.payload[offset + lane];
        send_beat(data, (remaining >= 4) ? 4'hF : ((1 << remaining) - 1),
                  remaining <= 4);
      end
    endtask

    task run_phase(uvm_phase phase);
      cnn_axis_packet request;
      vif.reset_source();
      wait (vif.aresetn);
      forever begin
        seq_item_port.get_next_item(request);
        drive_packet(request);
        seq_item_port.item_done();
      end
    endtask
  endclass

  class cnn_axis_monitor extends uvm_monitor;
    `uvm_component_utils(cnn_axis_monitor)
    virtual cnn_axis_if vif;
    uvm_analysis_port #(cnn_axis_packet) analysis_port;
    bit [31:0] words[$];
    bit [3:0] keeps[$];
    int unsigned expected_protocol_errors;
    int unsigned observed_protocol_errors;

    function new(string name, uvm_component parent);
      super.new(name, parent);
      analysis_port = new("analysis_port", this);
      expected_protocol_errors = 0;
      observed_protocol_errors = 0;
    endfunction

    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      if (!uvm_config_db#(virtual cnn_axis_if)::get(this, "", "vif", vif))
        `uvm_fatal("NOVIF", "AXIS monitor has no virtual interface")
    endfunction

    function bit validate_packet(output string reason);
      int payload_bytes;
      int payload_beats;
      bit [3:0] expected_keep;
      if (words.size() < DMA_HEADER_WORDS) begin
        reason = "TLAST arrived before the complete header";
        return 0;
      end
      for (int index = 0; index < DMA_HEADER_WORDS; index++) begin
        if (keeps[index] != 4'hF) begin
          reason = $sformatf("header beat %0d has TKEEP=%x", index,
                             keeps[index]);
          return 0;
        end
      end
      if (words[0] != DMA_MAGIC) begin
        reason = $sformatf("bad magic %08x", words[0]);
        return 0;
      end
      if (words[1][7:0] != 1) begin
        reason = $sformatf("unsupported version %0d", words[1][7:0]);
        return 0;
      end
      if (words[1][15:8] != DMA_HEADER_WORDS) begin
        reason = $sformatf("header words %0d expected %0d",
                           words[1][15:8], DMA_HEADER_WORDS);
        return 0;
      end
      if (!(words[1][23:16] inside {[1:4]})) begin
        reason = $sformatf("invalid packet type %0d", words[1][23:16]);
        return 0;
      end
      if (words[1][31:24] != 0) begin
        reason = $sformatf("unsupported flags %02x", words[1][31:24]);
        return 0;
      end
      payload_bytes = words[7];
      payload_beats = (payload_bytes + 3) / 4;
      if (words.size() != DMA_HEADER_WORDS + payload_beats) begin
        reason = $sformatf("captured %0d beats for %0d-byte payload",
                           words.size(), payload_bytes);
        return 0;
      end
      for (int index = 0; index < payload_beats; index++) begin
        expected_keep = ((index == payload_beats - 1) &&
                         ((payload_bytes % 4) != 0)) ?
                        ((4'b0001 << (payload_bytes % 4)) - 1'b1) : 4'hF;
        if (keeps[DMA_HEADER_WORDS + index] != expected_keep) begin
          reason = $sformatf("payload beat %0d has TKEEP=%x expected=%x",
                             index, keeps[DMA_HEADER_WORDS + index],
                             expected_keep);
          return 0;
        end
      end
      reason = "";
      return 1;
    endfunction

    function void report_protocol_error(string reason);
      observed_protocol_errors++;
      if (observed_protocol_errors <= expected_protocol_errors)
        `uvm_info("AXIS_PROTOCOL_EXPECTED", reason, UVM_LOW)
      else
        `uvm_error("AXIS_PROTOCOL", reason)
    endfunction

    function void publish_packet();
      cnn_axis_packet item;
      int payload_bytes;
      string reason;
      if (!validate_packet(reason)) begin
        report_protocol_error(reason);
        return;
      end
      item = cnn_axis_packet::type_id::create("observed_packet");
      item.protocol_magic = words[0];
      item.protocol_version = words[1][7:0];
      item.protocol_header_words = words[1][15:8];
      item.packet_type = words[1][23:16];
      item.protocol_flags = words[1][31:24];
      item.job_id = words[2];
      item.tensor_id = words[3][15:0];
      item.layer_id = words[3][31:16];
      item.tile_x = words[4][15:0];
      item.tile_y = words[4][31:16];
      item.tile_width = words[5][15:0];
      item.tile_height = words[5][31:16];
      item.channel_offset = words[6][15:0];
      item.channel_count = words[6][31:16];
      payload_bytes = words[7];
      item.payload = new[payload_bytes];
      for (int index = 0; index < payload_bytes; index++)
        item.payload[index] = words[DMA_HEADER_WORDS + index/4][(index%4)*8 +: 8];
      analysis_port.write(item);
    endfunction

    function void check_phase(uvm_phase phase);
      super.check_phase(phase);
      if (observed_protocol_errors != expected_protocol_errors)
        `uvm_error("AXIS_PROTOCOL_COUNT", $sformatf(
          "observed %0d protocol errors expected %0d",
          observed_protocol_errors, expected_protocol_errors))
      if (words.size() != 0)
        `uvm_error("AXIS_PROTOCOL", "simulation ended with an incomplete packet")
    endfunction

    task run_phase(uvm_phase phase);
      forever begin
        @(posedge vif.aclk);
        if (!vif.aresetn) begin
          words.delete();
          keeps.delete();
        end else if (vif.tvalid && vif.tready) begin
          words.push_back(vif.tdata);
          keeps.push_back(vif.tkeep);
          if (vif.tlast) begin
            publish_packet();
            words.delete();
            keeps.delete();
          end
        end
      end
    endtask
  endclass

  class cnn_axis_source_agent extends uvm_agent;
    `uvm_component_utils(cnn_axis_source_agent)
    cnn_axis_sequencer sequencer;
    cnn_axis_source_driver driver;
    cnn_axis_monitor monitor;
    function new(string name, uvm_component parent); super.new(name, parent); endfunction
    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      sequencer = cnn_axis_sequencer::type_id::create("sequencer", this);
      driver = cnn_axis_source_driver::type_id::create("driver", this);
      monitor = cnn_axis_monitor::type_id::create("monitor", this);
    endfunction
    function void connect_phase(uvm_phase phase);
      driver.seq_item_port.connect(sequencer.seq_item_export);
    endfunction
  endclass

  class cnn_axis_sink_agent extends uvm_agent;
    `uvm_component_utils(cnn_axis_sink_agent)
    virtual cnn_axis_if vif;
    cnn_axis_monitor monitor;
    bit [15:0] lfsr;
    function new(string name, uvm_component parent); super.new(name, parent); endfunction
    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      monitor = cnn_axis_monitor::type_id::create("monitor", this);
      if (!uvm_config_db#(virtual cnn_axis_if)::get(this, "", "vif", vif))
        `uvm_fatal("NOVIF", "AXIS sink agent has no virtual interface")
    endfunction
    task run_phase(uvm_phase phase);
      lfsr = 16'hACE1;
      vif.tready <= 1'b0;
      wait (vif.aresetn);
      forever begin
        @(negedge vif.aclk);
        lfsr = {lfsr[14:0], lfsr[15] ^ lfsr[13] ^ lfsr[12] ^ lfsr[10]};
        vif.tready <= lfsr[0] | lfsr[2];
      end
    endtask
  endclass

  class cnn_packet_scoreboard extends uvm_scoreboard;
    `uvm_component_utils(cnn_packet_scoreboard)
    uvm_analysis_imp #(cnn_axis_packet, cnn_packet_scoreboard) actual_export;
    cnn_axis_packet expected[$];
    int matched;
    event matched_event;

    function new(string name, uvm_component parent);
      super.new(name, parent);
      actual_export = new("actual_export", this);
    endfunction

    function void enqueue_expected(cnn_axis_packet item);
      cnn_axis_packet copy;
      $cast(copy, item.clone());
      expected.push_back(copy);
    endfunction

    function void write(cnn_axis_packet actual);
      cnn_axis_packet wanted;
      string reason;
      if (expected.size() == 0) begin
        `uvm_error("SCOREBOARD", "unexpected output packet")
        return;
      end
      wanted = expected.pop_front();
      if (!actual.compare_packet(wanted, reason))
        `uvm_error("SCOREBOARD", {"output packet mismatch: ", reason})
      else begin
        matched++;
        ->matched_event;
      end
    endfunction

    task wait_for_matches(int count, time timeout);
      fork
        begin while (matched < count) @matched_event; end
        begin #(timeout); `uvm_fatal("TIMEOUT", "scoreboard match timeout") end
      join_any
      disable fork;
    endtask

    function void check_phase(uvm_phase phase);
      if (expected.size() != 0)
        `uvm_error("SCOREBOARD", $sformatf("%0d expected packets missing", expected.size()))
    endfunction
  endclass

  class cnn_tensor_layout extends uvm_object;
    `uvm_object_utils(cnn_tensor_layout)
    longint unsigned base_address;
    int unsigned width;
    int unsigned height;
    int unsigned channels;
    int unsigned row_stride;
    int unsigned pixel_stride;
    int unsigned channel_stride;

    function new(string name = "cnn_tensor_layout");
      super.new(name);
    endfunction
  endclass

  class cnn_ddr_tensor_model extends uvm_component;
    `uvm_component_utils(cnn_ddr_tensor_model)
    uvm_analysis_imp #(cnn_axis_packet, cnn_ddr_tensor_model) output_export;
    cnn_tensor_layout layouts[int unsigned];
    byte unsigned memory[longint unsigned];
    int unsigned output_packet_count[int unsigned];
    event output_event;

    function new(string name, uvm_component parent);
      super.new(name, parent);
      output_export = new("output_export", this);
    endfunction

    function void configure_tensor(
      int unsigned tensor_id,
      longint unsigned base_address,
      int unsigned width,
      int unsigned height,
      int unsigned channels,
      int unsigned row_stride,
      int unsigned pixel_stride,
      int unsigned channel_stride = 1
    );
      cnn_tensor_layout layout = cnn_tensor_layout::type_id::create(
        $sformatf("tensor_%0d_layout", tensor_id));
      layout.base_address = base_address;
      layout.width = width;
      layout.height = height;
      layout.channels = channels;
      layout.row_stride = row_stride;
      layout.pixel_stride = pixel_stride;
      layout.channel_stride = channel_stride;
      layouts[tensor_id] = layout;
    endfunction

    function longint unsigned element_address(
      cnn_tensor_layout layout,
      int unsigned y,
      int unsigned x,
      int unsigned channel
    );
      return layout.base_address + y * layout.row_stride +
             x * layout.pixel_stride + channel * layout.channel_stride;
    endfunction

    function void write(cnn_axis_packet packet);
      cnn_tensor_layout layout;
      int unsigned expected_bytes;
      int unsigned payload_index;
      longint unsigned address;
      if ((packet.packet_type != 4) || !layouts.exists(packet.tensor_id)) return;
      layout = layouts[packet.tensor_id];
      if ((packet.tile_x + packet.tile_width > layout.width) ||
          (packet.tile_y + packet.tile_height > layout.height) ||
          (packet.channel_offset + packet.channel_count > layout.channels)) begin
        `uvm_error("DDR_MODEL", "output tile exceeds configured tensor bounds")
        return;
      end
      expected_bytes = packet.tile_width * packet.tile_height *
                       packet.channel_count;
      if (packet.payload.size() != expected_bytes) begin
        `uvm_error("DDR_MODEL", $sformatf(
          "tensor %0d payload length got=%0d expected=%0d",
          packet.tensor_id, packet.payload.size(), expected_bytes))
        return;
      end
      payload_index = 0;
      for (int y = 0; y < packet.tile_height; y++) begin
        for (int x = 0; x < packet.tile_width; x++) begin
          for (int channel = 0; channel < packet.channel_count; channel++) begin
            address = element_address(layout, packet.tile_y + y,
                                      packet.tile_x + x,
                                      packet.channel_offset + channel);
            memory[address] = packet.payload[payload_index++];
          end
        end
      end
      output_packet_count[packet.tensor_id]++;
      ->output_event;
    endfunction

    task wait_for_tensor_packets(int unsigned tensor_id, int unsigned count,
                                 time timeout);
      fork
        begin
          while (!output_packet_count.exists(tensor_id) ||
                 (output_packet_count[tensor_id] < count)) @output_event;
        end
        begin
          #(timeout);
          `uvm_fatal("DDR_TIMEOUT", $sformatf(
            "timed out waiting for tensor %0d packet %0d", tensor_id, count))
        end
      join_any
      disable fork;
    endtask

    function cnn_axis_packet gather_activation(
      int unsigned tensor_id,
      bit [31:0] job_id,
      int unsigned layer_id,
      int unsigned tile_x,
      int unsigned tile_y,
      int unsigned tile_width,
      int unsigned tile_height,
      int unsigned channel_offset,
      int unsigned channel_count
    );
      cnn_axis_packet packet;
      cnn_tensor_layout layout;
      int unsigned payload_index;
      longint unsigned address;
      packet = cnn_axis_packet::type_id::create("ddr_gathered_activation");
      if (!layouts.exists(tensor_id)) begin
        `uvm_fatal("DDR_MODEL", $sformatf("tensor %0d is not configured", tensor_id))
        return packet;
      end
      layout = layouts[tensor_id];
      if ((tile_x + tile_width > layout.width) ||
          (tile_y + tile_height > layout.height) ||
          (channel_offset + channel_count > layout.channels)) begin
        `uvm_fatal("DDR_MODEL", "activation gather exceeds configured tensor bounds")
        return packet;
      end
      packet.packet_type = 1;
      packet.job_id = job_id;
      packet.tensor_id = tensor_id;
      packet.layer_id = layer_id;
      packet.tile_x = tile_x;
      packet.tile_y = tile_y;
      packet.tile_width = tile_width;
      packet.tile_height = tile_height;
      packet.channel_offset = channel_offset;
      packet.channel_count = channel_count;
      packet.payload = new[tile_width * tile_height * channel_count];
      payload_index = 0;
      for (int y = 0; y < tile_height; y++) begin
        for (int x = 0; x < tile_width; x++) begin
          for (int channel = 0; channel < channel_count; channel++) begin
            address = element_address(layout, tile_y + y, tile_x + x,
                                      channel_offset + channel);
            if (!memory.exists(address)) begin
              `uvm_fatal("DDR_MODEL", $sformatf(
                "read before write tensor=%0d y=%0d x=%0d channel=%0d",
                tensor_id, tile_y + y, tile_x + x,
                channel_offset + channel))
              return packet;
            end
            packet.payload[payload_index++] = memory[address];
          end
        end
      end
      return packet;
    endfunction

    function bit compare_tensor(int unsigned tensor_id,
                                byte unsigned expected[],
                                output string reason);
      cnn_tensor_layout layout;
      int unsigned expected_elements;
      int unsigned index;
      longint unsigned address;
      if (!layouts.exists(tensor_id)) begin
        reason = $sformatf("tensor %0d is not configured", tensor_id);
        return 0;
      end
      layout = layouts[tensor_id];
      expected_elements = layout.width * layout.height * layout.channels;
      if (expected.size() != expected_elements) begin
        reason = $sformatf("expected tensor size got=%0d required=%0d",
                           expected.size(), expected_elements);
        return 0;
      end
      index = 0;
      for (int y = 0; y < layout.height; y++) begin
        for (int x = 0; x < layout.width; x++) begin
          for (int channel = 0; channel < layout.channels; channel++) begin
            address = element_address(layout, y, x, channel);
            if (!memory.exists(address)) begin
              reason = $sformatf("tensor byte missing at y=%0d x=%0d channel=%0d",
                                 y, x, channel);
              return 0;
            end
            if (memory[address] != expected[index]) begin
              reason = $sformatf(
                "tensor mismatch y=%0d x=%0d channel=%0d got=%02x expected=%02x",
                y, x, channel, memory[address], expected[index]);
              return 0;
            end
            index++;
          end
        end
      end
      reason = "";
      return 1;
    endfunction
  endclass

  class cnn_packet_coverage extends uvm_subscriber #(cnn_axis_packet);
    `uvm_component_utils(cnn_packet_coverage)
    cnn_axis_packet sampled;
    covergroup packet_cg;
      option.per_instance = 1;
      type_cp: coverpoint sampled.packet_type { bins legal[] = {[1:4]}; }
      layer_cp: coverpoint sampled.layer_id { bins layers[] = {[0:7]}; }
      channels_cp: coverpoint sampled.channel_count {
        bins tail = {[1:3]}; bins vector = {4, 8, 16};
      }
      payload_cp: coverpoint sampled.payload.size() {
        bins partial = {1, 2, 3}; bins full_beats = {[4:4096]};
      }
      type_x_channels: cross type_cp, channels_cp;
    endgroup
    function new(string name, uvm_component parent);
      super.new(name, parent);
      packet_cg = new;
    endfunction
    function void write(cnn_axis_packet t);
      sampled = t;
      packet_cg.sample();
    endfunction
  endclass

  class cnn_axi_coverage extends uvm_subscriber #(cnn_axi_lite_item);
    `uvm_component_utils(cnn_axi_coverage)
    cnn_axi_lite_item sampled;
    covergroup axi_cg;
      option.per_instance = 1;
      kind_cp: coverpoint sampled.kind;
      address_cp: coverpoint sampled.address {
        bins control = {[12'h000:12'h03c]};
        bins progress = {[12'h040:12'h068]};
        bins version = {12'h0fc};
      }
      response_cp: coverpoint sampled.response { bins okay = {0}; bins error = {2}; }
      strobe_cp: coverpoint sampled.strobe iff (sampled.kind == AXI_WRITE) {
        bins none = {0}; bins single_lane[] = {1, 2, 4, 8};
        bins partial = {3, 5, 6, 7, 9, 10, 11, 12, 13, 14};
        bins full = {15};
      }
      write_order_cp: coverpoint {sampled.address_delay != 0,
                                  sampled.data_delay != 0}
                      iff (sampled.kind == AXI_WRITE) {
        bins together = {2'b00};
        bins data_first = {2'b10};
        bins address_first = {2'b01};
      }
      response_latency_cp: coverpoint sampled.response_ready_delay {
        bins immediate = {[0:1]}; bins stalled = {[2:31]};
        bins long_stall = {[32:$]};
      }
      kind_x_address: cross kind_cp, address_cp;
    endgroup
    function new(string name, uvm_component parent);
      super.new(name, parent);
      axi_cg = new;
    endfunction
    function void write(cnn_axi_lite_item t);
      sampled = t;
      axi_cg.sample();
    endfunction
  endclass

  class cnn_reg32 extends uvm_reg;
    `uvm_object_utils(cnn_reg32)
    uvm_reg_field byte_fields[4];
    string access_mode;
    uvm_reg_data_t reset_value;
    bit is_volatile;
    function new(string name = "cnn_reg32", string access = "RW",
                 uvm_reg_data_t reset = 0, bit volatile_field = 0);
      super.new(name, 32, UVM_NO_COVERAGE);
      access_mode = access;
      reset_value = reset;
      is_volatile = volatile_field;
    endfunction
    virtual function void build();
      for (int lane = 0; lane < 4; lane++) begin
        byte_fields[lane] = uvm_reg_field::type_id::create(
          $sformatf("byte_%0d", lane));
        byte_fields[lane].configure(
          this, 8, lane * 8, access_mode, is_volatile,
          (reset_value >> (lane * 8)) & 8'hFF, 1, 0, 0);
      end
    endfunction
  endclass

  class cnn_reg_block extends uvm_reg_block;
    `uvm_object_utils(cnn_reg_block)
    cnn_reg32 control, status, irq_status, irq_enable, job_id;
    cnn_reg32 parameter_layer, model_command, model_status;
    cnn_reg32 active_model_id, active_generation, active_layer_count;
    cnn_reg32 metadata_address, metadata_data, metadata_commit;
    cnn_reg32 model_error, runtime_error, active_tensors, current_tile;
    cnn_reg32 completed_layers, completed_tiles, packet_errors;
    cnn_reg32 parameter_banks, input_ddr_lo, input_ddr_hi;
    cnn_reg32 output_ddr_lo, output_ddr_hi, saturation_events, version_reg;
    function new(string name = "cnn_reg_block");
      super.new(name, UVM_NO_COVERAGE);
    endfunction
    virtual function void build();
      default_map = create_map("default_map", 0, 4, UVM_LITTLE_ENDIAN);
      control = make_reg("control", "WO", 'h000);
      status = make_reg("status", "RO", 'h004, 0, 1);
      irq_status = make_reg("irq_status", "W1C", 'h008, 0, 1);
      irq_enable = make_reg("irq_enable", "RW", 'h00c);
      job_id = make_reg("job_id", "RW", 'h010);
      parameter_layer = make_reg("parameter_layer", "RW", 'h014);
      model_command = make_reg("model_command", "WO", 'h018);
      model_status = make_reg("model_status", "RO", 'h01c, 0, 1);
      active_model_id = make_reg("active_model_id", "RO", 'h020, 0, 1);
      active_generation = make_reg("active_generation", "RO", 'h024, 0, 1);
      active_layer_count = make_reg("active_layer_count", "RO", 'h028, 0, 1);
      metadata_address = make_reg("metadata_address", "RW", 'h02c);
      metadata_data = make_reg("metadata_data", "RW", 'h030, 0, 1);
      metadata_commit = make_reg("metadata_commit", "WO", 'h034);
      model_error = make_reg("model_error", "W1C", 'h038, 0, 1);
      runtime_error = make_reg("runtime_error", "RO", 'h03c, 0, 1);
      active_tensors = make_reg("active_tensors", "RO", 'h040, 0, 1);
      current_tile = make_reg("current_tile", "RO", 'h044, 0, 1);
      completed_layers = make_reg("completed_layers", "RO", 'h048, 0, 1);
      completed_tiles = make_reg("completed_tiles", "RO", 'h04c, 0, 1);
      packet_errors = make_reg("packet_errors", "RO", 'h050, 0, 1);
      parameter_banks = make_reg("parameter_banks", "RO", 'h054, 0, 1);
      input_ddr_lo = make_reg("input_ddr_lo", "RO", 'h058, 0, 1);
      input_ddr_hi = make_reg("input_ddr_hi", "RO", 'h05c, 0, 1);
      output_ddr_lo = make_reg("output_ddr_lo", "RO", 'h060, 0, 1);
      output_ddr_hi = make_reg("output_ddr_hi", "RO", 'h064, 0, 1);
      saturation_events = make_reg("saturation_events", "RO", 'h068, 0, 1);
      version_reg = make_reg("version", "RO", 'h0fc, 32'h0005_0001);
      lock_model();
      reset();
    endfunction
    function cnn_reg32 make_reg(string name, string access,
                                uvm_reg_addr_t offset,
                                uvm_reg_data_t reset = 0,
                                bit volatile_field = 0);
      cnn_reg32 reg_instance;
      reg_instance = new(name, access, reset, volatile_field);
      reg_instance.configure(this, null, "");
      reg_instance.build();
      if (access == "RO")
        default_map.add_reg(reg_instance, offset, "RO");
      else if (access == "WO")
        default_map.add_reg(reg_instance, offset, "WO");
      else
        default_map.add_reg(reg_instance, offset, "RW");
      return reg_instance;
    endfunction
  endclass

  class cnn_reg_adapter extends uvm_reg_adapter;
    `uvm_object_utils(cnn_reg_adapter)
    function new(string name = "cnn_reg_adapter");
      super.new(name);
      supports_byte_enable = 1;
      provides_responses = 1;
    endfunction
    virtual function uvm_sequence_item reg2bus(const ref uvm_reg_bus_op rw);
      cnn_axi_lite_item item = cnn_axi_lite_item::type_id::create("reg_item");
      item.kind = rw.kind == UVM_READ ? AXI_READ : AXI_WRITE;
      item.address = rw.addr[11:0];
      item.data = rw.data;
      item.strobe = rw.byte_en[3:0];
      return item;
    endfunction
    virtual function void bus2reg(uvm_sequence_item bus_item, ref uvm_reg_bus_op rw);
      cnn_axi_lite_item item;
      if (!$cast(item, bus_item)) begin
        rw.status = UVM_NOT_OK;
        return;
      end
      rw.kind = item.kind == AXI_READ ? UVM_READ : UVM_WRITE;
      rw.addr = item.address;
      rw.data = item.data;
      rw.byte_en = item.strobe;
      rw.status = item.response == 0 ? UVM_IS_OK : UVM_NOT_OK;
    endfunction
  endclass

  class cnn_virtual_sequencer extends uvm_sequencer;
    `uvm_component_utils(cnn_virtual_sequencer)
    cnn_axi_lite_sequencer axi_sequencer;
    cnn_axis_sequencer axis_sequencer;
    function new(string name, uvm_component parent); super.new(name, parent); endfunction
  endclass

  class cnn_uvm_env extends uvm_env;
    `uvm_component_utils(cnn_uvm_env)
    cnn_axi_lite_agent axi_agent;
    cnn_axis_source_agent input_agent;
    cnn_axis_sink_agent output_agent;
    cnn_packet_scoreboard scoreboard;
    cnn_ddr_tensor_model ddr_model;
    cnn_packet_coverage input_coverage;
    cnn_packet_coverage output_coverage;
    cnn_axi_coverage axi_coverage;
    cnn_virtual_sequencer virtual_sequencer;
    cnn_reg_block registers;
    cnn_reg_adapter reg_adapter;
    uvm_reg_predictor #(cnn_axi_lite_item) reg_predictor;

    function new(string name, uvm_component parent); super.new(name, parent); endfunction
    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      axi_agent = cnn_axi_lite_agent::type_id::create("axi_agent", this);
      input_agent = cnn_axis_source_agent::type_id::create("input_agent", this);
      output_agent = cnn_axis_sink_agent::type_id::create("output_agent", this);
      scoreboard = cnn_packet_scoreboard::type_id::create("scoreboard", this);
      ddr_model = cnn_ddr_tensor_model::type_id::create("ddr_model", this);
      input_coverage = cnn_packet_coverage::type_id::create("input_coverage", this);
      output_coverage = cnn_packet_coverage::type_id::create("output_coverage", this);
      axi_coverage = cnn_axi_coverage::type_id::create("axi_coverage", this);
      virtual_sequencer = cnn_virtual_sequencer::type_id::create("virtual_sequencer", this);
      registers = cnn_reg_block::type_id::create("registers");
      registers.build();
      reg_adapter = cnn_reg_adapter::type_id::create("reg_adapter");
      reg_predictor = new("reg_predictor", this);
    endfunction
    function void connect_phase(uvm_phase phase);
      virtual_sequencer.axi_sequencer = axi_agent.sequencer;
      virtual_sequencer.axis_sequencer = input_agent.sequencer;
      registers.default_map.set_sequencer(axi_agent.sequencer, reg_adapter);
      registers.default_map.set_auto_predict(0);
      reg_predictor.map = registers.default_map;
      reg_predictor.adapter = reg_adapter;
      axi_agent.monitor.analysis_port.connect(reg_predictor.bus_in);
      axi_agent.monitor.analysis_port.connect(axi_coverage.analysis_export);
      input_agent.monitor.analysis_port.connect(input_coverage.analysis_export);
      output_agent.monitor.analysis_port.connect(output_coverage.analysis_export);
      output_agent.monitor.analysis_port.connect(scoreboard.actual_export);
      output_agent.monitor.analysis_port.connect(ddr_model.output_export);
    endfunction
  endclass

endpackage
