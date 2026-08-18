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
    virtual cnn_reset_if reset_vif;
    virtual cnn_status_if status_vif;

    localparam bit [11:0] ADDR_CONTROL = 12'h000;
    localparam bit [11:0] ADDR_STATUS = 12'h004;
    localparam bit [11:0] ADDR_IRQ_STATUS = 12'h008;
    localparam bit [11:0] ADDR_IRQ_ENABLE = 12'h00C;
    localparam bit [11:0] ADDR_JOB_ID = 12'h010;
    localparam bit [11:0] ADDR_PARAMETER_LAYER = 12'h014;
    localparam bit [11:0] ADDR_MODEL_COMMAND = 12'h018;
    localparam bit [11:0] ADDR_MODEL_STATUS = 12'h01C;
    localparam bit [11:0] ADDR_ACTIVE_MODEL_ID = 12'h020;
    localparam bit [11:0] ADDR_ACTIVE_GENERATION = 12'h024;
    localparam bit [11:0] ADDR_METADATA_ADDRESS = 12'h02C;
    localparam bit [11:0] ADDR_METADATA_DATA = 12'h030;
    localparam bit [11:0] ADDR_METADATA_COMMIT = 12'h034;
    localparam bit [11:0] ADDR_MODEL_ERROR = 12'h038;
    localparam bit [11:0] ADDR_RUNTIME_ERROR = 12'h03C;
    localparam bit [11:0] ADDR_COMPLETED_LAYERS = 12'h048;
    localparam bit [11:0] ADDR_PACKET_ERRORS = 12'h050;
    localparam bit [11:0] ADDR_PARAMETER_BANKS = 12'h054;
    localparam bit [11:0] ADDR_SATURATION_EVENTS = 12'h068;
    localparam bit [11:0] ADDR_VERSION = 12'h0FC;

    function new(string name, uvm_component parent); super.new(name, parent); endfunction
    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      env = cnn_uvm_env::type_id::create("env", this);
      if (!uvm_config_db#(virtual cnn_reset_if)::get(this, "", "reset_vif",
                                                       reset_vif))
        `uvm_fatal("NOVIF", "test has no reset interface")
      if (!uvm_config_db#(virtual cnn_status_if)::get(this, "", "status_vif",
                                                        status_vif))
        `uvm_fatal("NOVIF", "test has no status interface")
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

    task axi_write_expect_response(bit [11:0] address, bit [31:0] data,
                                   bit [1:0] expected_response);
      cnn_axi_single_sequence seq =
        cnn_axi_single_sequence::type_id::create("axi_write_response_sequence");
      seq.kind = AXI_WRITE;
      seq.address = address;
      seq.data = data;
      seq.strobe = 4'hF;
      seq.start(env.axi_agent.sequencer);
      if (seq.response.response != expected_response)
        `uvm_fatal("AXI_WRITE", $sformatf(
          "write %03x response %0d expected %0d", address,
          seq.response.response, expected_response))
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
      byte unsigned malformed[] = '{1, 1, 1};
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
      env.fault_coverage.sample(FAULT_PROTOCOL, 0);
      checked_read(ADDR_ACTIVE_MODEL_ID, value);
      if (value != 501) `uvm_fatal("RECOVERY", "active model was corrupted")
      axi_write(ADDR_CONTROL, 2);
      preload_parameters();
      run_valid_job();
      env.fault_coverage.sample(FAULT_PROTOCOL, 1);
      phase.drop_objection(this);
    endtask
  endclass

  class cnn_uvm_reset_recovery_test extends cnn_uvm_base_test;
    `uvm_component_utils(cnn_uvm_reset_recovery_test)
    function new(string name, uvm_component parent); super.new(name, parent); endfunction
    task run_phase(uvm_phase phase);
      bit [31:0] value;
      phase.raise_objection(this);
      load_smoke_model();
      preload_parameters();
      axi_write(ADDR_CONTROL, 1);
      repeat (12) @(posedge status_vif.aclk);
      if (!status_vif.busy)
        `uvm_fatal("RESET", "runtime was not active before reset injection")
      reset_vif.assert_reset(5);
      env.fault_coverage.sample(FAULT_RESET, 0);
      repeat (4) @(posedge status_vif.aclk);
      checked_read(ADDR_STATUS, value);
      if (value != 0) `uvm_fatal("RESET", "status did not return to reset state")
      checked_read(ADDR_VERSION, value);
      if (value != 32'h0005_0001)
        `uvm_fatal("RESET", "register interface did not recover after reset")
      load_smoke_model();
      preload_parameters();
      run_valid_job();
      env.fault_coverage.sample(FAULT_RESET, 1);
      phase.drop_objection(this);
    endtask
  endclass

  class cnn_uvm_starvation_abort_test extends cnn_uvm_base_test;
    `uvm_component_utils(cnn_uvm_starvation_abort_test)
    function new(string name, uvm_component parent); super.new(name, parent); endfunction
    task run_phase(uvm_phase phase);
      bit [31:0] value;
      phase.raise_objection(this);
      load_smoke_model();
      preload_parameters();
      axi_write(ADDR_CONTROL, 1);
      repeat (64) @(posedge status_vif.aclk);
      checked_read(ADDR_STATUS, value);
      if (!value[0] || value[1] || value[2])
        `uvm_fatal("STARVATION", "runtime did not remain cleanly input-starved")
      env.fault_coverage.sample(FAULT_STARVATION_ABORT, 0);
      axi_write(ADDR_CONTROL, 2);
      checked_read(ADDR_STATUS, value);
      if (value[2:0] != 0)
        `uvm_fatal("ABORT", "clear did not return runtime to idle")
      checked_read(ADDR_PARAMETER_BANKS, value);
      if (value[1:0] != 0)
        `uvm_fatal("ABORT", "clear did not release parameter ownership")
      preload_parameters();
      run_valid_job();
      env.fault_coverage.sample(FAULT_STARVATION_ABORT, 1);
      phase.drop_objection(this);
    endtask
  endclass

  class cnn_uvm_ordering_recovery_test extends cnn_uvm_base_test;
    `uvm_component_utils(cnn_uvm_ordering_recovery_test)
    function new(string name, uvm_component parent); super.new(name, parent); endfunction
    task run_phase(uvm_phase phase);
      byte unsigned stale_payload[] = '{1, 2, 4, 5};
      byte unsigned early_bias[] = '{0, 0, 0, 0};
      cnn_axis_packet packet;
      bit [31:0] value;
      phase.raise_objection(this);
      load_smoke_model();
      axi_write(ADDR_IRQ_ENABLE, 2);
      preload_parameters();
      axi_write(ADDR_CONTROL, 1);
      packet = make_packet(1, 1, 0, 0, 2, stale_payload);
      send_packet(packet);
      for (int poll = 0; poll < 100; poll++) begin
        checked_read(ADDR_STATUS, value);
        if (value[2]) break;
        if (poll == 99)
          `uvm_fatal("STALE_PACKET", "stale tensor ID was not rejected")
      end
      if (!status_vif.irq)
        `uvm_fatal("ERROR_IRQ", "runtime error did not assert IRQ")
      checked_read(ADDR_RUNTIME_ERROR, value);
      if (value[7:0] == 0)
        `uvm_fatal("STALE_PACKET", "runtime error code was not captured")
      env.fault_coverage.sample(FAULT_STALE_TENSOR, 0);
      axi_write(ADDR_CONTROL, 2);
      packet = make_packet(3, 1, 0, 0, 0, early_bias);
      send_packet(packet);
      repeat (8) @(posedge status_vif.aclk);
      checked_read(ADDR_STATUS, value);
      if (!value[2])
        `uvm_fatal("REORDER", "bias-before-weight packet was not rejected")
      env.fault_coverage.sample(FAULT_PACKET_ORDER, 0);
      axi_write(ADDR_CONTROL, 2);
      axi_write(ADDR_IRQ_ENABLE, 0);
      preload_parameters();
      run_valid_job();
      env.fault_coverage.sample(FAULT_STALE_TENSOR, 1);
      env.fault_coverage.sample(FAULT_PACKET_ORDER, 1);
      phase.drop_objection(this);
    endtask
  endclass

  class cnn_uvm_model_replacement_test extends cnn_uvm_base_test;
    `uvm_component_utils(cnn_uvm_model_replacement_test)
    function new(string name, uvm_component parent); super.new(name, parent); endfunction
    task run_phase(uvm_phase phase);
      bit [31:0] value;
      phase.raise_objection(this);
      load_smoke_model();
      checked_read(ADDR_ACTIVE_MODEL_ID, value);
      if (value != 501) `uvm_fatal("REPLACE", "baseline model is not active")
      axi_write(ADDR_MODEL_COMMAND, 1);
      write_metadata(0, 0, 0, 32'hDEAD_BEEF);
      commit_metadata(0, 0);
      axi_write(ADDR_MODEL_COMMAND, 2);
      axi_write(ADDR_MODEL_COMMAND, 4);
      checked_read(ADDR_MODEL_STATUS, value);
      if (value[11:4] == 0)
        `uvm_fatal("REPLACE", "invalid staging replacement was accepted")
      checked_read(ADDR_ACTIVE_MODEL_ID, value);
      if (value != 501)
        `uvm_fatal("REPLACE", "failed replacement damaged active model")
      env.fault_coverage.sample(FAULT_MODEL_REPLACEMENT, 0);
      axi_write(ADDR_MODEL_COMMAND, 32);
      preload_parameters();
      run_valid_job();
      env.fault_coverage.sample(FAULT_MODEL_REPLACEMENT, 1);
      phase.drop_objection(this);
    endtask
  endclass

  class cnn_uvm_interrupt_test extends cnn_uvm_base_test;
    `uvm_component_utils(cnn_uvm_interrupt_test)
    function new(string name, uvm_component parent); super.new(name, parent); endfunction
    task run_phase(uvm_phase phase);
      bit [31:0] value;
      phase.raise_objection(this);
      load_smoke_model();
      preload_parameters();
      axi_write(ADDR_IRQ_ENABLE, 1);
      run_valid_job();
      for (int poll = 0; poll < 100; poll++) begin
        checked_read(ADDR_IRQ_STATUS, value);
        if (value[0]) break;
        if (poll == 99)
          `uvm_fatal("DONE_IRQ", "completion status was not latched")
      end
      if (!status_vif.irq) `uvm_fatal("DONE_IRQ", "completion IRQ did not assert")
      env.fault_coverage.sample(FAULT_DONE_INTERRUPT, 0);
      axi_write(ADDR_IRQ_STATUS, 1);
      repeat (2) @(posedge status_vif.aclk);
      if (status_vif.irq) `uvm_fatal("DONE_IRQ", "W1C did not deassert IRQ")
      env.fault_coverage.sample(FAULT_DONE_INTERRUPT, 1);
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
    bit [7:0] activation_type_mem[UVM_FIXTURE_ACTIVATION_PACKETS];
    bit [15:0] activation_tensor_mem[UVM_FIXTURE_ACTIVATION_PACKETS];
    bit [15:0] activation_layer_mem[UVM_FIXTURE_ACTIVATION_PACKETS];
    bit [15:0] activation_tile_x_mem[UVM_FIXTURE_ACTIVATION_PACKETS];
    bit [15:0] activation_tile_y_mem[UVM_FIXTURE_ACTIVATION_PACKETS];
    bit [15:0] activation_tile_width_mem[UVM_FIXTURE_ACTIVATION_PACKETS];
    bit [15:0] activation_tile_height_mem[UVM_FIXTURE_ACTIVATION_PACKETS];
    bit [15:0] activation_source_x_mem[UVM_FIXTURE_ACTIVATION_PACKETS];
    bit [15:0] activation_source_y_mem[UVM_FIXTURE_ACTIVATION_PACKETS];
    bit [15:0] activation_source_width_mem[UVM_FIXTURE_ACTIVATION_PACKETS];
    bit [15:0] activation_source_height_mem[UVM_FIXTURE_ACTIVATION_PACKETS];
    bit [15:0] activation_channels_mem[UVM_FIXTURE_ACTIVATION_PACKETS];
    bit [15:0] activation_payload_start_mem[UVM_FIXTURE_ACTIVATION_PACKETS];
    bit [15:0] activation_payload_length_mem[UVM_FIXTURE_ACTIVATION_PACKETS];
    byte unsigned activation_payload_mem[UVM_FIXTURE_ACTIVATION_BYTES];
    bit [7:0] residual_type_mem[UVM_FIXTURE_RESIDUAL_PACKET_STORAGE];
    bit [15:0] residual_tensor_mem[UVM_FIXTURE_RESIDUAL_PACKET_STORAGE];
    bit [15:0] residual_layer_mem[UVM_FIXTURE_RESIDUAL_PACKET_STORAGE];
    bit [15:0] residual_tile_x_mem[UVM_FIXTURE_RESIDUAL_PACKET_STORAGE];
    bit [15:0] residual_tile_y_mem[UVM_FIXTURE_RESIDUAL_PACKET_STORAGE];
    bit [15:0] residual_tile_width_mem[UVM_FIXTURE_RESIDUAL_PACKET_STORAGE];
    bit [15:0] residual_tile_height_mem[UVM_FIXTURE_RESIDUAL_PACKET_STORAGE];
    bit [15:0] residual_source_x_mem[UVM_FIXTURE_RESIDUAL_PACKET_STORAGE];
    bit [15:0] residual_source_y_mem[UVM_FIXTURE_RESIDUAL_PACKET_STORAGE];
    bit [15:0] residual_source_width_mem[UVM_FIXTURE_RESIDUAL_PACKET_STORAGE];
    bit [15:0] residual_source_height_mem[UVM_FIXTURE_RESIDUAL_PACKET_STORAGE];
    bit [15:0] residual_channels_mem[UVM_FIXTURE_RESIDUAL_PACKET_STORAGE];
    bit [15:0] residual_payload_start_mem[UVM_FIXTURE_RESIDUAL_PACKET_STORAGE];
    bit [15:0] residual_payload_length_mem[UVM_FIXTURE_RESIDUAL_PACKET_STORAGE];
    byte unsigned residual_payload_mem[UVM_FIXTURE_RESIDUAL_BYTES];
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
    bit [15:0] tensor_id_mem[UVM_FIXTURE_TENSORS];
    bit [63:0] tensor_base_mem[UVM_FIXTURE_TENSORS];
    bit [15:0] tensor_width_mem[UVM_FIXTURE_TENSORS];
    bit [15:0] tensor_height_mem[UVM_FIXTURE_TENSORS];
    bit [15:0] tensor_channels_mem[UVM_FIXTURE_TENSORS];
    bit [31:0] tensor_row_stride_mem[UVM_FIXTURE_TENSORS];
    bit [31:0] tensor_pixel_stride_mem[UVM_FIXTURE_TENSORS];
    bit [15:0] layer_output_count_mem[UVM_FIXTURE_LAYERS];
    bit [7:0] layer_kernel_mem[UVM_FIXTURE_LAYERS];
    bit [7:0] layer_stride_mem[UVM_FIXTURE_LAYERS];
    bit [15:0] layer_input_channels_mem[UVM_FIXTURE_LAYERS];
    bit [15:0] layer_output_channels_mem[UVM_FIXTURE_LAYERS];
    bit [7:0] layer_activation_mem[UVM_FIXTURE_LAYERS];
    bit [7:0] layer_residual_mem[UVM_FIXTURE_LAYERS];
    bit [7:0] layer_padding_mem[UVM_FIXTURE_LAYERS];

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
      $readmemh("uvm_fixture/activation_type.mem", activation_type_mem);
      $readmemh("uvm_fixture/activation_tensor.mem", activation_tensor_mem);
      $readmemh("uvm_fixture/activation_layer.mem", activation_layer_mem);
      $readmemh("uvm_fixture/activation_tile_x.mem", activation_tile_x_mem);
      $readmemh("uvm_fixture/activation_tile_y.mem", activation_tile_y_mem);
      $readmemh("uvm_fixture/activation_tile_width.mem", activation_tile_width_mem);
      $readmemh("uvm_fixture/activation_tile_height.mem", activation_tile_height_mem);
      $readmemh("uvm_fixture/activation_source_x.mem", activation_source_x_mem);
      $readmemh("uvm_fixture/activation_source_y.mem", activation_source_y_mem);
      $readmemh("uvm_fixture/activation_source_width.mem", activation_source_width_mem);
      $readmemh("uvm_fixture/activation_source_height.mem", activation_source_height_mem);
      $readmemh("uvm_fixture/activation_channels.mem", activation_channels_mem);
      $readmemh("uvm_fixture/activation_payload_start.mem", activation_payload_start_mem);
      $readmemh("uvm_fixture/activation_payload_length.mem", activation_payload_length_mem);
      $readmemh("uvm_fixture/activation_payload.mem", activation_payload_mem);
      $readmemh("uvm_fixture/residual_type.mem", residual_type_mem);
      $readmemh("uvm_fixture/residual_tensor.mem", residual_tensor_mem);
      $readmemh("uvm_fixture/residual_layer.mem", residual_layer_mem);
      $readmemh("uvm_fixture/residual_tile_x.mem", residual_tile_x_mem);
      $readmemh("uvm_fixture/residual_tile_y.mem", residual_tile_y_mem);
      $readmemh("uvm_fixture/residual_tile_width.mem", residual_tile_width_mem);
      $readmemh("uvm_fixture/residual_tile_height.mem", residual_tile_height_mem);
      $readmemh("uvm_fixture/residual_source_x.mem", residual_source_x_mem);
      $readmemh("uvm_fixture/residual_source_y.mem", residual_source_y_mem);
      $readmemh("uvm_fixture/residual_source_width.mem", residual_source_width_mem);
      $readmemh("uvm_fixture/residual_source_height.mem", residual_source_height_mem);
      $readmemh("uvm_fixture/residual_channels.mem", residual_channels_mem);
      $readmemh("uvm_fixture/residual_payload_start.mem", residual_payload_start_mem);
      $readmemh("uvm_fixture/residual_payload_length.mem", residual_payload_length_mem);
      $readmemh("uvm_fixture/residual_payload.mem", residual_payload_mem);
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
      $readmemh("uvm_fixture/tensor_id.mem", tensor_id_mem);
      $readmemh("uvm_fixture/tensor_base.mem", tensor_base_mem);
      $readmemh("uvm_fixture/tensor_width.mem", tensor_width_mem);
      $readmemh("uvm_fixture/tensor_height.mem", tensor_height_mem);
      $readmemh("uvm_fixture/tensor_channels.mem", tensor_channels_mem);
      $readmemh("uvm_fixture/tensor_row_stride.mem", tensor_row_stride_mem);
      $readmemh("uvm_fixture/tensor_pixel_stride.mem", tensor_pixel_stride_mem);
      $readmemh("uvm_fixture/layer_output_count.mem", layer_output_count_mem);
      $readmemh("uvm_fixture/layer_kernel.mem", layer_kernel_mem);
      $readmemh("uvm_fixture/layer_stride.mem", layer_stride_mem);
      $readmemh("uvm_fixture/layer_input_channels.mem", layer_input_channels_mem);
      $readmemh("uvm_fixture/layer_output_channels.mem", layer_output_channels_mem);
      $readmemh("uvm_fixture/layer_activation.mem", layer_activation_mem);
      $readmemh("uvm_fixture/layer_residual.mem", layer_residual_mem);
      $readmemh("uvm_fixture/layer_padding.mem", layer_padding_mem);
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

    function cnn_axis_packet activation_packet(int index);
      byte unsigned payload[] = new[activation_payload_length_mem[index]];
      for (int byte_index = 0; byte_index < payload.size(); byte_index++)
        payload[byte_index] = activation_payload_mem[
          activation_payload_start_mem[index] + byte_index];
      return build_fixture_packet(
        activation_type_mem[index], activation_tensor_mem[index],
        activation_layer_mem[index], activation_tile_x_mem[index],
        activation_tile_y_mem[index], activation_tile_width_mem[index],
        activation_tile_height_mem[index], activation_channels_mem[index], payload);
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

    function cnn_axis_packet residual_packet(int index);
      byte unsigned payload[] = new[residual_payload_length_mem[index]];
      for (int byte_index = 0; byte_index < payload.size(); byte_index++)
        payload[byte_index] = residual_payload_mem[
          residual_payload_start_mem[index] + byte_index];
      return build_fixture_packet(
        residual_type_mem[index], residual_tensor_mem[index],
        residual_layer_mem[index], residual_tile_x_mem[index],
        residual_tile_y_mem[index], residual_tile_width_mem[index],
        residual_tile_height_mem[index], residual_channels_mem[index], payload);
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

    task load_parameter_layer(int layer);
      bit [31:0] value;
      bit [31:0] runtime_error;
      axi_write(ADDR_PARAMETER_LAYER, layer);
      for (int packet_index = 0;
           packet_index < UVM_FIXTURE_PARAMETER_PACKETS; packet_index++) begin
        if (parameter_layer_mem[packet_index] == layer) begin
          send_packet(parameter_packet(packet_index));
          checked_read(ADDR_RUNTIME_ERROR, runtime_error);
          if (runtime_error[7:0] != 0)
            `uvm_fatal("PARAMETER_PACKET", $sformatf(
              "layer=%0d packet=%0d type=%0d runtime_error=%08x", layer,
              packet_index, parameter_type_mem[packet_index], runtime_error))
        end
      end
      for (int poll = 0; poll < 100; poll++) begin
        checked_read(ADDR_PARAMETER_BANKS, value);
        if (((layer == 0 || layer >= 2) && value[1:0] != 0) ||
            (layer == 1 && value[1:0] == 2'b11)) break;
        if (poll == 99) begin
          checked_read(ADDR_RUNTIME_ERROR, runtime_error);
          `uvm_fatal("PARAMETER", $sformatf(
            "compiler parameter layer %0d did not become valid banks=%02b runtime_error=%08x",
            layer, value[1:0], runtime_error))
        end
      end
    endtask

    task send_layer_activations(int layer);
      for (int packet_index = 0;
           packet_index < UVM_FIXTURE_ACTIVATION_PACKETS; packet_index++) begin
        cnn_axis_packet packet;
        if (activation_layer_mem[packet_index] != layer) continue;
        if (layer == 0) begin
          packet = activation_packet(packet_index);
        end else begin
          packet = env.ddr_model.gather_activation_region(
            activation_tensor_mem[packet_index], UVM_FIXTURE_JOB_ID, layer,
            activation_tile_x_mem[packet_index],
            activation_tile_y_mem[packet_index],
            activation_tile_width_mem[packet_index],
            activation_tile_height_mem[packet_index],
            activation_source_x_mem[packet_index],
            activation_source_y_mem[packet_index],
            activation_source_width_mem[packet_index],
            activation_source_height_mem[packet_index], 0,
            activation_channels_mem[packet_index]);
        end
        send_packet(packet);
        for (int residual_index = 0;
             residual_index < UVM_FIXTURE_RESIDUAL_PACKETS; residual_index++) begin
          cnn_axis_packet residual;
          if ((residual_layer_mem[residual_index] != layer) ||
              (residual_tile_x_mem[residual_index] !=
               activation_tile_x_mem[packet_index]) ||
              (residual_tile_y_mem[residual_index] !=
               activation_tile_y_mem[packet_index])) continue;
          if (residual_payload_length_mem[residual_index] != 0) begin
            residual = residual_packet(residual_index);
          end else begin
            residual = env.ddr_model.gather_activation_region(
              residual_tensor_mem[residual_index], UVM_FIXTURE_JOB_ID, layer,
              residual_tile_x_mem[residual_index],
              residual_tile_y_mem[residual_index],
              residual_tile_width_mem[residual_index],
              residual_tile_height_mem[residual_index],
              residual_source_x_mem[residual_index],
              residual_source_y_mem[residual_index],
              residual_source_width_mem[residual_index],
              residual_source_height_mem[residual_index], 0,
              residual_channels_mem[residual_index]);
            residual.tensor_id = residual_tensor_mem[residual_index];
          end
          send_packet(residual);
        end
      end
    endtask

    task run_phase(uvm_phase phase);
      bit [31:0] value;
      string reason;
      phase.raise_objection(this);
      load_fixture_files();
      for (int layer = 0; layer < UVM_FIXTURE_LAYERS; layer++) begin
        env.model_coverage.sample(
          UVM_FIXTURE_LAYERS, layer_kernel_mem[layer], layer_stride_mem[layer],
          layer_input_channels_mem[layer], layer_output_channels_mem[layer],
          layer_activation_mem[layer], layer_residual_mem[layer],
          layer_padding_mem[layer][3:0], UVM_FIXTURE_PROFILE_ID);
      end
      load_compiler_model();
      checked_read(ADDR_ACTIVE_MODEL_ID, value);
      if (value != UVM_FIXTURE_MODEL_ID)
        `uvm_fatal("MODEL", "compiler fixture model activation failed")
      for (int tensor = 0; tensor < UVM_FIXTURE_TENSORS; tensor++) begin
        env.ddr_model.configure_tensor(
          tensor_id_mem[tensor], tensor_base_mem[tensor],
          tensor_width_mem[tensor], tensor_height_mem[tensor],
          tensor_channels_mem[tensor], tensor_row_stride_mem[tensor],
          tensor_pixel_stride_mem[tensor]);
      end
      load_parameter_layer(0);
      if (UVM_FIXTURE_LAYERS > 1) load_parameter_layer(1);
      for (int packet_index = 0;
           packet_index < UVM_FIXTURE_EXPECTED_PACKETS; packet_index++)
        env.scoreboard.enqueue_expected(expected_packet(packet_index));
      axi_write(ADDR_CONTROL, 1);
      send_layer_activations(0);
      for (int layer = 0; layer < UVM_FIXTURE_LAYERS; layer++) begin
        env.ddr_model.wait_for_tensor_packets(
          tensor_id_mem[layer], layer_output_count_mem[layer], 400us);
        if (layer + 1 < UVM_FIXTURE_LAYERS) begin
          if (layer + 1 >= 2) load_parameter_layer(layer + 1);
          send_layer_activations(layer + 1);
        end
      end
      env.scoreboard.wait_for_matches(UVM_FIXTURE_EXPECTED_PACKETS, 400us);
      if (!env.ddr_model.compare_tensor(
            UVM_FIXTURE_FINAL_ID, final_tensor_mem, reason))
        `uvm_fatal("PYTHON_REFERENCE", reason)
      checked_read(ADDR_STATUS, value);
      if (value[2]) `uvm_fatal("RUNTIME", "compiler-reference job reported error")
      checked_read(ADDR_COMPLETED_LAYERS, value);
      if (value != UVM_FIXTURE_LAYERS)
        `uvm_fatal("RUNTIME", "compiler-reference layer count mismatch")
      checked_read(ADDR_SATURATION_EVENTS, value);
      if (UVM_FIXTURE_EXPECT_SATURATION && (value == 0))
        `uvm_fatal("SATURATION", "forced-clipping fixture recorded no events")
      if (UVM_FIXTURE_PROFILE_ID == 2)
        env.fault_coverage.sample(FAULT_RESIDUAL_ADD, 1);
      if (UVM_FIXTURE_PROFILE_ID == 3)
        env.fault_coverage.sample(FAULT_RESIDUAL_SUBTRACT, 1);
      if (UVM_FIXTURE_PROFILE_ID == 4)
        env.fault_coverage.sample(FAULT_SATURATION, 1);
      phase.drop_objection(this);
    endtask
  endclass

  class cnn_uvm_parameter_crc_recovery_test extends cnn_uvm_compiler_reference_test;
    `uvm_component_utils(cnn_uvm_parameter_crc_recovery_test)
    function new(string name, uvm_component parent); super.new(name, parent); endfunction

    task run_phase(uvm_phase phase);
      bit corrupted;
      bit [31:0] value;
      phase.raise_objection(this);
      load_fixture_files();
      load_compiler_model();
      axi_write(ADDR_PARAMETER_LAYER, 0);
      corrupted = 0;
      for (int packet_index = 0;
           packet_index < UVM_FIXTURE_PARAMETER_PACKETS; packet_index++) begin
        cnn_axis_packet packet;
        if (parameter_layer_mem[packet_index] != 0) continue;
        packet = parameter_packet(packet_index);
        if (!corrupted && packet.payload.size() != 0) begin
          packet.payload[0] ^= 8'h01;
          corrupted = 1;
        end
        send_packet(packet);
      end
      if (!corrupted) `uvm_fatal("CRC_FAULT", "fixture has no parameter payload")
      for (int poll = 0; poll < 100; poll++) begin
        checked_read(ADDR_STATUS, value);
        if (value[2]) break;
        if (poll == 99)
          `uvm_fatal("CRC_FAULT", "corrupted parameters were not rejected")
      end
      checked_read(ADDR_ACTIVE_MODEL_ID, value);
      if (value != UVM_FIXTURE_MODEL_ID)
        `uvm_fatal("CRC_FAULT", "parameter failure corrupted the active model")
      env.fault_coverage.sample(FAULT_PARAMETER_CRC, 0);
      axi_write(ADDR_CONTROL, 2);
      load_parameter_layer(0);
      checked_read(ADDR_PARAMETER_BANKS, value);
      if (value[1:0] == 0)
        `uvm_fatal("CRC_RECOVERY", "valid parameters did not load after clear")
      env.fault_coverage.sample(FAULT_PARAMETER_CRC, 1);
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

      // Close every byte-lane class and the long response-latency class.
      axi_write(ADDR_JOB_ID, 32'h0000_00A1, 4'b0001);
      axi_write(ADDR_JOB_ID, 32'h0000_B200, 4'b0010);
      axi_write(ADDR_JOB_ID, 32'h00C3_0000, 4'b0100);
      axi_write(ADDR_JOB_ID, 32'hD400_0000, 4'b1000);
      axi_write(ADDR_JOB_ID, 32'h5566_7788, 4'b0011, 0, 0, 40);

      // Sample write traffic in progress and version address regions.
      axi_write_expect_response(ADDR_COMPLETED_LAYERS, 32'h0, 2);
      axi_write_expect_response(ADDR_VERSION, 32'h0, 2);

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
