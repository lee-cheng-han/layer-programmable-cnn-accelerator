package cnn_uvm_tests_pkg;
  import uvm_pkg::*;
  import cnn_uvm_pkg::*;
  `include "uvm_macros.svh"
  `include "uvm_closed_loop_fixture.svh"

  class cnn_axi_single_sequence extends uvm_sequence #(cnn_axi_lite_item);
    `uvm_object_utils(cnn_axi_single_sequence)
    cnn_axi_kind_e kind;
    bit [11:0] address;
    bit [31:0] data;
    bit [3:0] strobe = 4'hF;
    int unsigned address_delay;
    int unsigned data_delay;
    int unsigned response_ready_delay;
    cnn_axi_lite_item response;
    function new(string name = "cnn_axi_single_sequence"); super.new(name); endfunction
    task body();
      cnn_axi_lite_item request = cnn_axi_lite_item::type_id::create("request");
      start_item(request);
      request.kind = kind;
      request.address = address;
      request.data = data;
      request.strobe = strobe;
      request.address_delay = address_delay;
      request.data_delay = data_delay;
      request.response_ready_delay = response_ready_delay;
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
                   bit [3:0] strobe = 4'hF,
                   int unsigned address_delay = 0,
                   int unsigned data_delay = 0,
                   int unsigned response_ready_delay = 0);
      cnn_axi_single_sequence seq =
        cnn_axi_single_sequence::type_id::create("axi_write_sequence");
      seq.kind = AXI_WRITE;
      seq.address = address;
      seq.data = data;
      seq.strobe = strobe;
      seq.address_delay = address_delay;
      seq.data_delay = data_delay;
      seq.response_ready_delay = response_ready_delay;
      seq.start(env.axi_agent.sequencer);
      if (seq.response.response != 0)
        `uvm_fatal("AXI_WRITE", $sformatf("write %03x response %0d",
                                          address, seq.response.response))
    endtask

    task axi_read(bit [11:0] address, output bit [31:0] data,
                  output bit [1:0] response,
                  input int unsigned address_delay = 0,
                  input int unsigned response_ready_delay = 0);
      cnn_axi_single_sequence seq =
        cnn_axi_single_sequence::type_id::create("axi_read_sequence");
      seq.kind = AXI_READ;
      seq.address = address;
      seq.address_delay = address_delay;
      seq.response_ready_delay = response_ready_delay;
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
      env.input_agent.monitor.expected_protocol_errors++;
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

  class cnn_uvm_compiler_reference_test extends cnn_uvm_base_test;
    `uvm_component_utils(cnn_uvm_compiler_reference_test)
    bit metadata_action_mem[UVM_FIXTURE_METADATA_OPS];
    bit [1:0] metadata_kind_mem[UVM_FIXTURE_METADATA_OPS];
    bit [5:0] metadata_record_mem[UVM_FIXTURE_METADATA_OPS];
    bit [5:0] metadata_word_mem[UVM_FIXTURE_METADATA_OPS];
    bit [31:0] metadata_data_mem[UVM_FIXTURE_METADATA_OPS];
    bit [7:0] parameter_type_mem[UVM_FIXTURE_PARAMETER_PACKETS];
    bit [15:0] parameter_tensor_mem[UVM_FIXTURE_PARAMETER_PACKETS];
    bit [15:0] parameter_layer_mem[UVM_FIXTURE_PARAMETER_PACKETS];
    bit [15:0] parameter_payload_start_mem[UVM_FIXTURE_PARAMETER_PACKETS];
    bit [15:0] parameter_payload_length_mem[UVM_FIXTURE_PARAMETER_PACKETS];
    byte unsigned parameter_payload_mem[UVM_FIXTURE_PARAMETER_BYTES];
    bit [7:0] input_type_mem[UVM_FIXTURE_INPUT_PACKETS];
    bit [15:0] input_tensor_mem[UVM_FIXTURE_INPUT_PACKETS];
    bit [15:0] input_layer_mem[UVM_FIXTURE_INPUT_PACKETS];
    bit [15:0] input_tile_x_mem[UVM_FIXTURE_INPUT_PACKETS];
    bit [15:0] input_tile_y_mem[UVM_FIXTURE_INPUT_PACKETS];
    bit [15:0] input_tile_width_mem[UVM_FIXTURE_INPUT_PACKETS];
    bit [15:0] input_tile_height_mem[UVM_FIXTURE_INPUT_PACKETS];
    bit [15:0] input_channels_mem[UVM_FIXTURE_INPUT_PACKETS];
    bit [15:0] input_payload_start_mem[UVM_FIXTURE_INPUT_PACKETS];
    bit [15:0] input_payload_length_mem[UVM_FIXTURE_INPUT_PACKETS];
    byte unsigned input_payload_mem[UVM_FIXTURE_INPUT_BYTES];
    bit [7:0] expected_type_mem[UVM_FIXTURE_EXPECTED_PACKETS];
    bit [15:0] expected_tensor_mem[UVM_FIXTURE_EXPECTED_PACKETS];
    bit [15:0] expected_layer_mem[UVM_FIXTURE_EXPECTED_PACKETS];
    bit [15:0] expected_tile_x_mem[UVM_FIXTURE_EXPECTED_PACKETS];
    bit [15:0] expected_tile_y_mem[UVM_FIXTURE_EXPECTED_PACKETS];
    bit [15:0] expected_tile_width_mem[UVM_FIXTURE_EXPECTED_PACKETS];
    bit [15:0] expected_tile_height_mem[UVM_FIXTURE_EXPECTED_PACKETS];
    bit [15:0] expected_channels_mem[UVM_FIXTURE_EXPECTED_PACKETS];
    bit [15:0] expected_payload_start_mem[UVM_FIXTURE_EXPECTED_PACKETS];
    bit [15:0] expected_payload_length_mem[UVM_FIXTURE_EXPECTED_PACKETS];
    byte unsigned expected_payload_mem[UVM_FIXTURE_EXPECTED_BYTES];
    byte unsigned final_tensor_mem[UVM_FIXTURE_FINAL_ELEMENTS];

    function new(string name, uvm_component parent); super.new(name, parent); endfunction

    function void load_fixture_files();
      $readmemh("uvm_fixture/metadata_action.mem", metadata_action_mem);
      $readmemh("uvm_fixture/metadata_kind.mem", metadata_kind_mem);
      $readmemh("uvm_fixture/metadata_record.mem", metadata_record_mem);
      $readmemh("uvm_fixture/metadata_word.mem", metadata_word_mem);
      $readmemh("uvm_fixture/metadata_data.mem", metadata_data_mem);
      $readmemh("uvm_fixture/parameter_type.mem", parameter_type_mem);
      $readmemh("uvm_fixture/parameter_tensor.mem", parameter_tensor_mem);
      $readmemh("uvm_fixture/parameter_layer.mem", parameter_layer_mem);
      $readmemh("uvm_fixture/parameter_payload_start.mem",
                parameter_payload_start_mem);
      $readmemh("uvm_fixture/parameter_payload_length.mem",
                parameter_payload_length_mem);
      $readmemh("uvm_fixture/parameter_payload.mem", parameter_payload_mem);
      $readmemh("uvm_fixture/input_type.mem", input_type_mem);
      $readmemh("uvm_fixture/input_tensor.mem", input_tensor_mem);
      $readmemh("uvm_fixture/input_layer.mem", input_layer_mem);
      $readmemh("uvm_fixture/input_tile_x.mem", input_tile_x_mem);
      $readmemh("uvm_fixture/input_tile_y.mem", input_tile_y_mem);
      $readmemh("uvm_fixture/input_tile_width.mem", input_tile_width_mem);
      $readmemh("uvm_fixture/input_tile_height.mem", input_tile_height_mem);
      $readmemh("uvm_fixture/input_channels.mem", input_channels_mem);
      $readmemh("uvm_fixture/input_payload_start.mem", input_payload_start_mem);
      $readmemh("uvm_fixture/input_payload_length.mem", input_payload_length_mem);
      $readmemh("uvm_fixture/input_payload.mem", input_payload_mem);
      $readmemh("uvm_fixture/expected_type.mem", expected_type_mem);
      $readmemh("uvm_fixture/expected_tensor.mem", expected_tensor_mem);
      $readmemh("uvm_fixture/expected_layer.mem", expected_layer_mem);
      $readmemh("uvm_fixture/expected_tile_x.mem", expected_tile_x_mem);
      $readmemh("uvm_fixture/expected_tile_y.mem", expected_tile_y_mem);
      $readmemh("uvm_fixture/expected_tile_width.mem", expected_tile_width_mem);
      $readmemh("uvm_fixture/expected_tile_height.mem", expected_tile_height_mem);
      $readmemh("uvm_fixture/expected_channels.mem", expected_channels_mem);
      $readmemh("uvm_fixture/expected_payload_start.mem",
                expected_payload_start_mem);
      $readmemh("uvm_fixture/expected_payload_length.mem",
                expected_payload_length_mem);
      $readmemh("uvm_fixture/expected_payload.mem", expected_payload_mem);
      $readmemh("uvm_fixture/final_tensor.mem", final_tensor_mem);
    endfunction

    function cnn_axis_packet build_fixture_packet(
      bit [7:0] packet_type,
      bit [15:0] tensor_id,
      bit [15:0] layer_id,
      bit [15:0] tile_x,
      bit [15:0] tile_y,
      bit [15:0] tile_width,
      bit [15:0] tile_height,
      bit [15:0] channels,
      byte unsigned payload[]
    );
      cnn_axis_packet packet = cnn_axis_packet::type_id::create("fixture_packet");
      packet.packet_type = packet_type;
      packet.job_id = UVM_FIXTURE_JOB_ID;
      packet.tensor_id = tensor_id;
      packet.layer_id = layer_id;
      packet.tile_x = tile_x;
      packet.tile_y = tile_y;
      packet.tile_width = tile_width;
      packet.tile_height = tile_height;
      packet.channel_offset = 0;
      packet.channel_count = channels;
      packet.payload = new[payload.size()](payload);
      return packet;
    endfunction

    function cnn_axis_packet parameter_packet(int index);
      byte unsigned payload[] = new[parameter_payload_length_mem[index]];
      for (int byte_index = 0; byte_index < payload.size(); byte_index++)
        payload[byte_index] = parameter_payload_mem[
          parameter_payload_start_mem[index] + byte_index];
      return build_fixture_packet(
        parameter_type_mem[index], parameter_tensor_mem[index],
        parameter_layer_mem[index], 0, 0, 0, 0, 0, payload);
    endfunction

    function cnn_axis_packet input_packet(int index);
      byte unsigned payload[] = new[input_payload_length_mem[index]];
      for (int byte_index = 0; byte_index < payload.size(); byte_index++)
        payload[byte_index] = input_payload_mem[
          input_payload_start_mem[index] + byte_index];
      return build_fixture_packet(
        input_type_mem[index], input_tensor_mem[index], input_layer_mem[index],
        input_tile_x_mem[index], input_tile_y_mem[index],
        input_tile_width_mem[index], input_tile_height_mem[index],
        input_channels_mem[index], payload);
    endfunction

    function cnn_axis_packet expected_packet(int index);
      byte unsigned payload[] = new[expected_payload_length_mem[index]];
      for (int byte_index = 0; byte_index < payload.size(); byte_index++)
        payload[byte_index] = expected_payload_mem[
          expected_payload_start_mem[index] + byte_index];
      return build_fixture_packet(
        expected_type_mem[index], expected_tensor_mem[index],
        expected_layer_mem[index], expected_tile_x_mem[index],
        expected_tile_y_mem[index], expected_tile_width_mem[index],
        expected_tile_height_mem[index], expected_channels_mem[index], payload);
    endfunction

    task load_compiler_model();
      axi_write(ADDR_JOB_ID, UVM_FIXTURE_JOB_ID);
      axi_write(ADDR_PARAMETER_LAYER, 0);
      axi_write(ADDR_MODEL_COMMAND, 1);
      for (int op = 0; op < UVM_FIXTURE_METADATA_OPS; op++) begin
        if (metadata_action_mem[op])
          commit_metadata(metadata_kind_mem[op], metadata_record_mem[op]);
        else
          write_metadata(metadata_kind_mem[op], metadata_record_mem[op],
                         metadata_word_mem[op], metadata_data_mem[op]);
      end
      axi_write(ADDR_MODEL_COMMAND, 2);
      axi_write(ADDR_MODEL_COMMAND, 4);
      axi_write(ADDR_MODEL_COMMAND, 8);
    endtask

    task preload_compiler_parameters();
      bit [31:0] value;
      for (int layer = 0; layer < 2; layer++) begin
        axi_write(ADDR_PARAMETER_LAYER, layer);
        for (int packet_index = 0;
             packet_index < UVM_FIXTURE_PARAMETER_PACKETS; packet_index++) begin
          if (parameter_layer_mem[packet_index] == layer)
            send_packet(parameter_packet(packet_index));
        end
        for (int poll = 0; poll < 100; poll++) begin
          checked_read(ADDR_PARAMETER_BANKS, value);
          if ((layer == 0 && value[1:0] != 0) ||
              (layer == 1 && value[1:0] == 2'b11)) break;
          if (poll == 99)
            `uvm_fatal("PARAMETER", $sformatf(
              "compiler parameter layer %0d did not become valid", layer))
        end
      end
    endtask

    task run_phase(uvm_phase phase);
      bit [31:0] value;
      string reason;
      phase.raise_objection(this);
      load_fixture_files();
      load_compiler_model();
      checked_read(ADDR_ACTIVE_MODEL_ID, value);
      if (value != UVM_FIXTURE_MODEL_ID)
        `uvm_fatal("MODEL", "compiler fixture model activation failed")
      env.ddr_model.configure_tensor(
        UVM_FIXTURE_INTERMEDIATE_ID, UVM_FIXTURE_INTERMEDIATE_BASE,
        UVM_FIXTURE_INTERMEDIATE_WIDTH, UVM_FIXTURE_INTERMEDIATE_HEIGHT,
        UVM_FIXTURE_INTERMEDIATE_CHANNELS,
        UVM_FIXTURE_INTERMEDIATE_ROW_STRIDE,
        UVM_FIXTURE_INTERMEDIATE_PIXEL_STRIDE);
      env.ddr_model.configure_tensor(
        UVM_FIXTURE_FINAL_ID, UVM_FIXTURE_FINAL_BASE,
        UVM_FIXTURE_FINAL_WIDTH, UVM_FIXTURE_FINAL_HEIGHT,
        UVM_FIXTURE_FINAL_CHANNELS, UVM_FIXTURE_FINAL_ROW_STRIDE,
        UVM_FIXTURE_FINAL_PIXEL_STRIDE);
      preload_compiler_parameters();
      for (int packet_index = 0;
           packet_index < UVM_FIXTURE_EXPECTED_PACKETS; packet_index++)
        env.scoreboard.enqueue_expected(expected_packet(packet_index));
      axi_write(ADDR_CONTROL, 1);
      for (int packet_index = 0;
           packet_index < UVM_FIXTURE_INPUT_PACKETS; packet_index++)
        send_packet(input_packet(packet_index));
      env.ddr_model.wait_for_tensor_packets(
        UVM_FIXTURE_INTERMEDIATE_ID, UVM_FIXTURE_LAYER_ZERO_OUTPUTS, 400us);
      for (int packet_index = 0;
           packet_index < UVM_FIXTURE_EXPECTED_PACKETS; packet_index++) begin
        cnn_axis_packet gathered;
        if (expected_layer_mem[packet_index] != 1) continue;
        gathered = env.ddr_model.gather_activation(
          UVM_FIXTURE_INTERMEDIATE_ID, UVM_FIXTURE_JOB_ID, 1,
          expected_tile_x_mem[packet_index], expected_tile_y_mem[packet_index],
          expected_tile_width_mem[packet_index],
          expected_tile_height_mem[packet_index], 0,
          UVM_FIXTURE_INTERMEDIATE_CHANNELS);
        send_packet(gathered);
      end
      env.scoreboard.wait_for_matches(UVM_FIXTURE_EXPECTED_PACKETS, 400us);
      if (!env.ddr_model.compare_tensor(
            UVM_FIXTURE_FINAL_ID, final_tensor_mem, reason))
        `uvm_fatal("PYTHON_REFERENCE", reason)
      checked_read(ADDR_STATUS, value);
      if (value[2]) `uvm_fatal("RUNTIME", "compiler-reference job reported error")
      checked_read(ADDR_COMPLETED_LAYERS, value);
      if (value != 2) `uvm_fatal("RUNTIME", "compiler-reference layer count mismatch")
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

  class cnn_uvm_protocol_ral_test extends cnn_uvm_base_test;
    `uvm_component_utils(cnn_uvm_protocol_ral_test)
    function new(string name, uvm_component parent); super.new(name, parent); endfunction

    task run_phase(uvm_phase phase);
      uvm_reg registers[$];
      uvm_status_e status;
      uvm_reg_data_t ral_value;
      bit [31:0] value;
      bit [1:0] response;
      phase.raise_objection(this);

      env.registers.get_registers(registers);
      if (registers.size() != 28)
        `uvm_fatal("RAL", $sformatf(
          "register map contains %0d registers expected 28", registers.size()))
      env.registers.reset();
      if (env.registers.version_reg.get_mirrored_value() != 32'h0005_0001)
        `uvm_fatal("RAL", "version reset value is incorrect")

      // Address-first write with a delayed write-data and response channel.
      axi_write(ADDR_JOB_ID, 32'h1122_3344, 4'hF, 0, 5, 4);
      if (env.registers.job_id.get_mirrored_value() != 32'h1122_3344)
        `uvm_fatal("RAL", "predictor missed address-first JOB_ID write")

      // Data-first partial write updates only byte lanes zero and two.
      axi_write(ADDR_JOB_ID, 32'hAABB_CCDD, 4'b0101, 6, 0, 3);
      if (env.registers.job_id.get_mirrored_value() != 32'h11BB_33DD)
        `uvm_fatal("RAL", $sformatf(
          "partial-write mirror=%08x expected=11bb33dd",
          env.registers.job_id.get_mirrored_value()))
      axi_read(ADDR_JOB_ID, value, response, 3, 5);
      if ((response != 0) || (value != 32'h11BB_33DD))
        `uvm_fatal("AXI_TIMING", "delayed JOB_ID readback mismatch")

      // A zero strobe is accepted but must not modify storage or its mirror.
      axi_write(ADDR_JOB_ID, 32'hFFFF_FFFF, 4'h0, 2, 0, 2);
      checked_read(ADDR_JOB_ID, value);
      if ((value != 32'h11BB_33DD) ||
          (env.registers.job_id.get_mirrored_value() != 32'h11BB_33DD))
        `uvm_fatal("BYTE_ENABLE", "zero-strobe write modified JOB_ID")

      env.registers.irq_enable.write(status, 32'h0000_0003);
      if (status != UVM_IS_OK) `uvm_fatal("RAL", "IRQ_ENABLE write failed")
      env.registers.irq_enable.read(status, ral_value);
      if ((status != UVM_IS_OK) || (ral_value != 3))
        `uvm_fatal("RAL", "IRQ_ENABLE frontdoor readback failed")
      env.registers.job_id.mirror(status, UVM_CHECK);
      if (status != UVM_IS_OK) `uvm_fatal("RAL", "JOB_ID mirror check failed")
      env.registers.version_reg.mirror(status, UVM_CHECK);
      if (status != UVM_IS_OK) `uvm_fatal("RAL", "VERSION mirror check failed")

      axi_read(12'hFFC, value, response, 4, 4);
      if ((response != 2) || (value != 32'hDEAD_BEEF))
        `uvm_fatal("AXI_ERROR", "invalid delayed read did not return SLVERR")
      phase.drop_objection(this);
    endtask
  endclass

endpackage
