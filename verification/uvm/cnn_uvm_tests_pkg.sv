package cnn_uvm_tests_pkg;
  import uvm_pkg::*;
  import cnn_uvm_pkg::*;
  `include "uvm_macros.svh"

  class cnn_axi_single_sequence extends uvm_sequence #(cnn_axi_lite_item);
    `uvm_object_utils(cnn_axi_single_sequence)
    cnn_axi_kind_e kind;
    bit [11:0] address;
    bit [31:0] data;
    bit [3:0] strobe = 4'hF;
    cnn_axi_lite_item response;
    function new(string name = "cnn_axi_single_sequence"); super.new(name); endfunction
    task body();
      cnn_axi_lite_item request = cnn_axi_lite_item::type_id::create("request");
      start_item(request);
      request.kind = kind;
      request.address = address;
      request.data = data;
      request.strobe = strobe;
      finish_item(request);
      get_response(response);
    endtask
  endclass

  class cnn_axis_single_sequence extends uvm_sequence #(cnn_axis_packet);
    `uvm_object_utils(cnn_axis_single_sequence)
    cnn_axis_packet packet;
    function new(string name = "cnn_axis_single_sequence"); super.new(name); endfunction
    task body();
      start_item(packet);
      finish_item(packet);
    endtask
  endclass

  class cnn_uvm_base_test extends uvm_test;
    `uvm_component_utils(cnn_uvm_base_test)
    cnn_uvm_env env;

    localparam bit [11:0] ADDR_CONTROL = 12'h000;
    localparam bit [11:0] ADDR_STATUS = 12'h004;
    localparam bit [11:0] ADDR_JOB_ID = 12'h010;
    localparam bit [11:0] ADDR_PARAMETER_LAYER = 12'h014;
    localparam bit [11:0] ADDR_MODEL_COMMAND = 12'h018;
    localparam bit [11:0] ADDR_MODEL_STATUS = 12'h01C;
    localparam bit [11:0] ADDR_ACTIVE_MODEL_ID = 12'h020;
    localparam bit [11:0] ADDR_ACTIVE_GENERATION = 12'h024;
    localparam bit [11:0] ADDR_METADATA_ADDRESS = 12'h02C;
    localparam bit [11:0] ADDR_METADATA_DATA = 12'h030;
    localparam bit [11:0] ADDR_METADATA_COMMIT = 12'h034;
    localparam bit [11:0] ADDR_COMPLETED_LAYERS = 12'h048;
    localparam bit [11:0] ADDR_PACKET_ERRORS = 12'h050;
    localparam bit [11:0] ADDR_PARAMETER_BANKS = 12'h054;
    localparam bit [11:0] ADDR_VERSION = 12'h0FC;

    function new(string name, uvm_component parent); super.new(name, parent); endfunction
    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      env = cnn_uvm_env::type_id::create("env", this);
    endfunction

    task axi_write(bit [11:0] address, bit [31:0] data,
                   bit [3:0] strobe = 4'hF);
      cnn_axi_single_sequence seq =
        cnn_axi_single_sequence::type_id::create("axi_write_sequence");
      seq.kind = AXI_WRITE;
      seq.address = address;
      seq.data = data;
      seq.strobe = strobe;
      seq.start(env.axi_agent.sequencer);
      if (seq.response.response != 0)
        `uvm_fatal("AXI_WRITE", $sformatf("write %03x response %0d",
                                          address, seq.response.response))
    endtask

    task axi_read(bit [11:0] address, output bit [31:0] data,
                  output bit [1:0] response);
      cnn_axi_single_sequence seq =
        cnn_axi_single_sequence::type_id::create("axi_read_sequence");
      seq.kind = AXI_READ;
      seq.address = address;
      seq.start(env.axi_agent.sequencer);
      data = seq.response.data;
      response = seq.response.response;
    endtask

    task checked_read(bit [11:0] address, output bit [31:0] data);
      bit [1:0] response;
      axi_read(address, data, response);
      if (response != 0)
        `uvm_fatal("AXI_READ", $sformatf("read %03x response %0d", address, response))
    endtask

    function automatic bit [31:0] crc32_byte(bit [31:0] crc_in,
                                              bit [7:0] data);
      bit [31:0] value = crc_in ^ data;
      for (int bit_index = 0; bit_index < 8; bit_index++)
        value = value[0] ? ((value >> 1) ^ 32'hEDB8_8320) : (value >> 1);
      return value;
    endfunction

    function automatic bit [31:0] metadata_address(bit [1:0] kind,
                                                    int record_index,
                                                    int word_index);
      return {18'd0, 6'(word_index), 6'(record_index), kind};
    endfunction

    task write_metadata(bit [1:0] kind, int record_index, int word_index,
                        bit [31:0] data);
      axi_write(ADDR_METADATA_ADDRESS,
                metadata_address(kind, record_index, word_index));
      axi_write(ADDR_METADATA_DATA, data);
    endtask

    task commit_metadata(bit [1:0] kind, int record_index);
      axi_write(ADDR_METADATA_ADDRESS, metadata_address(kind, record_index, 0));
      axi_write(ADDR_METADATA_COMMIT, 1);
    endtask

    task load_smoke_model();
      bit [31:0] parameter_crc =
        crc32_byte(32'hFFFF_FFFF, 8'd1) ^ 32'hFFFF_FFFF;
      axi_write(ADDR_JOB_ID, 99);
      axi_write(ADDR_PARAMETER_LAYER, 0);
      axi_write(ADDR_MODEL_COMMAND, 1);
      write_metadata(0, 0, 0, 32'h314E_4E43);
      write_metadata(0, 0, 1, 32'h0080_0001);
      write_metadata(0, 0, 4, 501);
      write_metadata(0, 0, 5, 12);
      write_metadata(0, 0, 6, 32'h0002_0001);
      write_metadata(0, 0, 7, 32'h0000_0001);
      commit_metadata(0, 0);
      write_metadata(1, 0, 0, 32'h0080_0001);
      write_metadata(1, 0, 1, 32'h0001_0000);
      write_metadata(1, 0, 2, 32'h0000_0002);
      write_metadata(1, 0, 3, 32'h0001_0000);
      write_metadata(1, 0, 4, 32'h0000_FFFF);
      write_metadata(1, 0, 6, 1);
      write_metadata(1, 0, 8, 0);
      write_metadata(1, 0, 9, parameter_crc);
      write_metadata(1, 0, 10, 32'h0101_0101);
      write_metadata(1, 0, 11, 0);
      write_metadata(1, 0, 12, 32'h0000_0101);
      write_metadata(1, 0, 13, 32'h0002_0002);
      commit_metadata(1, 0);
      for (int tensor = 0; tensor < 2; tensor++) begin
        write_metadata(2, tensor, 0, 32'h0040_0001);
        write_metadata(2, tensor, 1, {16'd1, 16'(tensor)});
        write_metadata(2, tensor, 2, tensor == 0 ? 32'h1000 : 32'h2000);
        write_metadata(2, tensor, 3, 0);
        write_metadata(2, tensor, 4, 6);
        write_metadata(2, tensor, 5, 32'h0002_0003);
        write_metadata(2, tensor, 6, 32'h0101_0001);
        write_metadata(2, tensor, 7, 0);
        write_metadata(2, tensor, 9, 3);
        write_metadata(2, tensor, 10, 1);
        write_metadata(2, tensor, 11, 1);
        commit_metadata(2, tensor);
      end
      write_metadata(3, 0, 0, 32'h00C0_0001);
      write_metadata(3, 0, 1, 0);
      write_metadata(3, 0, 2, 32'h0001_0001);
      write_metadata(3, 0, 16, 1);
      write_metadata(3, 0, 17, 0);
      commit_metadata(3, 0);
      axi_write(ADDR_MODEL_COMMAND, 2);
      axi_write(ADDR_MODEL_COMMAND, 4);
      axi_write(ADDR_MODEL_COMMAND, 8);
    endtask

    task load_two_layer_identity_model();
      bit [31:0] parameter_crc =
        crc32_byte(32'hFFFF_FFFF, 8'd1) ^ 32'hFFFF_FFFF;
      axi_write(ADDR_JOB_ID, 99);
      axi_write(ADDR_PARAMETER_LAYER, 0);
      axi_write(ADDR_MODEL_COMMAND, 1);
      write_metadata(0, 0, 0, 32'h314E_4E43);
      write_metadata(0, 0, 1, 32'h0080_0001);
      write_metadata(0, 0, 4, 502);
      write_metadata(0, 0, 5, 12);
      write_metadata(0, 0, 6, 32'h0003_0002);
      write_metadata(0, 0, 7, 32'h0000_0001);
      commit_metadata(0, 0);
      for (int layer = 0; layer < 2; layer++) begin
        write_metadata(1, layer, 0, 32'h0080_0001);
        write_metadata(1, layer, 1, {16'd1, 16'(layer)});
        write_metadata(1, layer, 2, layer == 1 ? 32'h0000_0002 : 0);
        write_metadata(1, layer, 3,
                       {16'(layer + 1), 16'(layer)});
        write_metadata(1, layer, 4, 32'h0000_FFFF);
        write_metadata(1, layer, 6, 1);
        write_metadata(1, layer, 8, 0);
        write_metadata(1, layer, 9, parameter_crc);
        write_metadata(1, layer, 10, 32'h0101_0101);
        write_metadata(1, layer, 11, 0);
        write_metadata(1, layer, 12, 32'h0000_0101);
        write_metadata(1, layer, 13, 32'h0002_0002);
        commit_metadata(1, layer);
      end
      for (int tensor = 0; tensor < 3; tensor++) begin
        bit [15:0] flags = tensor == 0 ? 16'd1 :
                           tensor == 2 ? 16'd2 : 16'd0;
        write_metadata(2, tensor, 0, 32'h0040_0001);
        write_metadata(2, tensor, 1, {flags, 16'(tensor)});
        write_metadata(2, tensor, 2, 32'h1000 * (tensor + 1));
        write_metadata(2, tensor, 3, 0);
        write_metadata(2, tensor, 4, 6);
        write_metadata(2, tensor, 5, 32'h0002_0003);
        write_metadata(2, tensor, 6, 32'h0101_0001);
        write_metadata(2, tensor, 7, 0);
        write_metadata(2, tensor, 9, 3);
        write_metadata(2, tensor, 10, 1);
        write_metadata(2, tensor, 11, 1);
        commit_metadata(2, tensor);
      end
      write_metadata(3, 0, 0, 32'h00C0_0001);
      write_metadata(3, 0, 1, 0);
      write_metadata(3, 0, 2, 32'h0001_0001);
      write_metadata(3, 0, 16, 1);
      write_metadata(3, 0, 17, 0);
      commit_metadata(3, 0);
      axi_write(ADDR_MODEL_COMMAND, 2);
      axi_write(ADDR_MODEL_COMMAND, 4);
      axi_write(ADDR_MODEL_COMMAND, 8);
    endtask

    function cnn_axis_packet make_packet(byte packet_type, int tensor_id,
                                         int layer_id, int tile_x,
                                         int tile_width,
                                         byte unsigned payload[]);
      cnn_axis_packet packet = cnn_axis_packet::type_id::create("packet");
      packet.packet_type = packet_type;
      packet.job_id = 99;
      packet.tensor_id = tensor_id;
      packet.layer_id = layer_id;
      packet.tile_x = tile_x;
      packet.tile_y = 0;
      packet.tile_width = tile_width;
      packet.tile_height = 2;
      packet.channel_offset = 0;
      packet.channel_count = packet_type inside {1, 4} ? 1 : 0;
      packet.payload = new[payload.size()](payload);
      return packet;
    endfunction

    task send_packet(cnn_axis_packet packet);
      cnn_axis_single_sequence seq =
        cnn_axis_single_sequence::type_id::create("axis_sequence");
      seq.packet = packet;
      seq.start(env.input_agent.sequencer);
    endtask

    task preload_parameters();
      byte unsigned weight[] = new[1];
      bit [31:0] value;
      weight[0] = 1;
      send_packet(make_packet(2, 0, 0, 0, 0, weight));
      for (int poll = 0; poll < 100; poll++) begin
        checked_read(ADDR_PARAMETER_BANKS, value);
        if (value[1:0] != 0) return;
      end
      `uvm_fatal("PARAMETER", "parameter bank did not become valid")
    endtask

    task preload_parameter_layer(int layer);
      byte unsigned weight[] = new[1];
      bit [31:0] value;
      weight[0] = 1;
      axi_write(ADDR_PARAMETER_LAYER, layer);
      send_packet(make_packet(2, 0, layer, 0, 0, weight));
      for (int poll = 0; poll < 100; poll++) begin
        checked_read(ADDR_PARAMETER_BANKS, value);
        if ((layer == 0 && value[1:0] != 0) ||
            (layer != 0 && value[1:0] == 2'b11)) return;
      end
      `uvm_fatal("PARAMETER", $sformatf(
        "parameter layer %0d did not become valid", layer))
    endtask

    task run_valid_job();
      byte unsigned input0[] = '{1, 2, 4, 5};
      byte unsigned input1[] = '{3, 6};
      cnn_axis_packet expected0 = make_packet(4, 1, 0, 0, 2, input0);
      cnn_axis_packet expected1 = make_packet(4, 1, 0, 2, 1, input1);
      env.scoreboard.enqueue_expected(expected0);
      env.scoreboard.enqueue_expected(expected1);
      axi_write(ADDR_CONTROL, 1);
      send_packet(make_packet(1, 0, 0, 0, 2, input0));
      send_packet(make_packet(1, 0, 0, 2, 1, input1));
      env.scoreboard.wait_for_matches(2, 200us);
    endtask
  endclass

  class cnn_uvm_smoke_test extends cnn_uvm_base_test;
    `uvm_component_utils(cnn_uvm_smoke_test)
    function new(string name, uvm_component parent); super.new(name, parent); endfunction
    task run_phase(uvm_phase phase);
      bit [31:0] value;
      phase.raise_objection(this);
      checked_read(ADDR_VERSION, value);
      if (value != 32'h0005_0001) `uvm_fatal("VERSION", "register version mismatch")
      load_smoke_model();
      checked_read(ADDR_MODEL_STATUS, value);
      if (!value[3] || value[11:4] != 0) `uvm_fatal("MODEL", "model activation failed")
      checked_read(ADDR_ACTIVE_MODEL_ID, value);
      if (value != 501) `uvm_fatal("MODEL", "active model ID mismatch")
      preload_parameters();
      run_valid_job();
      checked_read(ADDR_STATUS, value);
      if (value[2]) `uvm_fatal("RUNTIME", "runtime reported error")
      checked_read(ADDR_COMPLETED_LAYERS, value);
      if (value != 1) `uvm_fatal("RUNTIME", "completed layer count mismatch")
      phase.drop_objection(this);
    endtask
  endclass

  class cnn_uvm_protocol_recovery_test extends cnn_uvm_base_test;
    `uvm_component_utils(cnn_uvm_protocol_recovery_test)
    function new(string name, uvm_component parent); super.new(name, parent); endfunction
    task run_phase(uvm_phase phase);
      byte unsigned malformed[] = '{1, 1};
      cnn_axis_packet packet;
      bit [31:0] value;
      phase.raise_objection(this);
      load_smoke_model();
      packet = make_packet(2, 0, 0, 0, 0, malformed);
      packet.declared_payload_length = 1;
      send_packet(packet);
      repeat (8) #10ns;
      checked_read(ADDR_STATUS, value);
      if (!value[2]) `uvm_fatal("RECOVERY", "malformed packet was not rejected")
      checked_read(ADDR_PACKET_ERRORS, value);
      if (value == 0) `uvm_fatal("RECOVERY", "packet error counter did not increment")
      checked_read(ADDR_ACTIVE_MODEL_ID, value);
      if (value != 501) `uvm_fatal("RECOVERY", "active model was corrupted")
      axi_write(ADDR_CONTROL, 2);
      preload_parameters();
      run_valid_job();
      phase.drop_objection(this);
    endtask
  endclass

  class cnn_uvm_closed_loop_ddr_test extends cnn_uvm_base_test;
    `uvm_component_utils(cnn_uvm_closed_loop_ddr_test)
    function new(string name, uvm_component parent); super.new(name, parent); endfunction
    task run_phase(uvm_phase phase);
      byte unsigned input0[] = '{1, 2, 4, 5};
      byte unsigned input1[] = '{3, 6};
      byte unsigned final_tensor[] = '{1, 2, 3, 4, 5, 6};
      cnn_axis_packet expected;
      cnn_axis_packet gathered;
      bit [31:0] value;
      string reason;
      phase.raise_objection(this);
      load_two_layer_identity_model();
      env.ddr_model.configure_tensor(1, 64'h2000, 3, 2, 1, 3, 1);
      env.ddr_model.configure_tensor(2, 64'h3000, 3, 2, 1, 3, 1);
      preload_parameter_layer(0);
      preload_parameter_layer(1);
      expected = make_packet(4, 1, 0, 0, 2, input0);
      env.scoreboard.enqueue_expected(expected);
      expected = make_packet(4, 1, 0, 2, 1, input1);
      env.scoreboard.enqueue_expected(expected);
      expected = make_packet(4, 2, 1, 0, 2, input0);
      env.scoreboard.enqueue_expected(expected);
      expected = make_packet(4, 2, 1, 2, 1, input1);
      env.scoreboard.enqueue_expected(expected);
      axi_write(ADDR_CONTROL, 1);
      send_packet(make_packet(1, 0, 0, 0, 2, input0));
      send_packet(make_packet(1, 0, 0, 2, 1, input1));
      env.ddr_model.wait_for_tensor_packets(1, 2, 200us);
      gathered = env.ddr_model.gather_activation(1, 99, 1, 0, 0, 2, 2, 0, 1);
      send_packet(gathered);
      gathered = env.ddr_model.gather_activation(1, 99, 1, 2, 0, 1, 2, 0, 1);
      send_packet(gathered);
      env.scoreboard.wait_for_matches(4, 200us);
      if (!env.ddr_model.compare_tensor(2, final_tensor, reason))
        `uvm_fatal("DDR_COMPARE", reason)
      checked_read(ADDR_STATUS, value);
      if (value[2]) `uvm_fatal("RUNTIME", "closed-loop job reported error")
      checked_read(ADDR_COMPLETED_LAYERS, value);
      if (value != 2) `uvm_fatal("RUNTIME", "closed-loop layer count mismatch")
      phase.drop_objection(this);
    endtask
  endclass

  class cnn_uvm_register_access_test extends cnn_uvm_base_test;
    `uvm_component_utils(cnn_uvm_register_access_test)
    function new(string name, uvm_component parent); super.new(name, parent); endfunction
    task run_phase(uvm_phase phase);
      bit [31:0] value;
      bit [1:0] response;
      phase.raise_objection(this);
      checked_read(ADDR_VERSION, value);
      axi_write(ADDR_JOB_ID, 32'hA5A5_1234);
      checked_read(ADDR_JOB_ID, value);
      if (value != 32'hA5A5_1234) `uvm_fatal("REGISTER", "JOB_ID mirror mismatch")
      axi_read(12'hFFC, value, response);
      if (response != 2) `uvm_fatal("REGISTER", "invalid read did not return SLVERR")
      phase.drop_objection(this);
    endtask
  endclass

endpackage
