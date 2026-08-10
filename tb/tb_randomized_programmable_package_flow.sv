`timescale 1ns/1ps

module tb_randomized_programmable_package_flow;
  `include "fixture_constants.svh"

  logic clk = 1'b0;
  logic rst_n = 1'b0;
  logic clear = 1'b0;
  logic start = 1'b0;
  logic [31:0] job_id = FIXTURE_JOB_ID;
  logic begin_model_load = 1'b0;
  logic finish_model_load = 1'b0;
  logic validate_model = 1'b0;
  logic activate_model = 1'b0;
  logic retire_active_model = 1'b0;
  logic clear_model_error = 1'b0;
  logic metadata_write = 1'b0;
  logic metadata_commit = 1'b0;
  logic [1:0] metadata_kind = '0;
  logic [5:0] metadata_record_index = '0;
  logic [5:0] metadata_word_index = '0;
  logic [31:0] metadata_write_data = '0;
  logic [31:0] metadata_read_data;
  logic [2:0] parameter_layer_select = '0;
  logic [31:0] s_axis_tdata = '0;
  logic [3:0] s_axis_tkeep = '0;
  logic s_axis_tvalid = 1'b0;
  logic s_axis_tready;
  logic s_axis_tlast = 1'b0;
  logic [31:0] m_axis_tdata;
  logic [3:0] m_axis_tkeep;
  logic m_axis_tvalid;
  logic m_axis_tready;
  logic m_axis_tlast;
  logic [2:0] staging_state;
  logic model_active_valid;
  logic [31:0] active_model_id;
  logic [31:0] active_generation_id;
  logic [15:0] active_layer_count;
  logic [7:0] model_lifecycle_error;
  logic [2:0] active_layer;
  logic [15:0] active_input_tensor_id;
  logic [15:0] active_output_tensor_id;
  logic [63:0] active_input_ddr_offset;
  logic [63:0] active_output_ddr_offset;
  logic [15:0] current_tile_x;
  logic [15:0] current_tile_y;
  logic [31:0] completed_layer_count;
  logic [31:0] completed_tile_count;
  logic [31:0] saturation_event_count;
  logic layer_done;
  logic busy;
  logic done;
  logic error;
  logic [7:0] error_code;
  logic [2:0] error_layer;
  logic [31:0] packet_error_count;
  logic [1:0] parameter_bank_valid;
  logic [15:0] backpressure_lfsr = 16'h1ACE;

  logic metadata_action_mem [0:FIXTURE_METADATA_OP_COUNT-1];
  logic [1:0] metadata_kind_mem [0:FIXTURE_METADATA_OP_COUNT-1];
  logic [5:0] metadata_record_mem [0:FIXTURE_METADATA_OP_COUNT-1];
  logic [5:0] metadata_word_mem [0:FIXTURE_METADATA_OP_COUNT-1];
  logic [31:0] metadata_data_mem [0:FIXTURE_METADATA_OP_COUNT-1];
  logic [15:0] parameter_start_mem [0:FIXTURE_LAYER_COUNT-1];
  logic [15:0] parameter_count_mem [0:FIXTURE_LAYER_COUNT-1];
  logic [15:0] activation_start_mem [0:FIXTURE_LAYER_COUNT-1];
  logic [15:0] activation_count_mem [0:FIXTURE_LAYER_COUNT-1];
  logic [31:0] parameter_data_mem [0:FIXTURE_PARAMETER_BEAT_COUNT-1];
  logic [3:0] parameter_keep_mem [0:FIXTURE_PARAMETER_BEAT_COUNT-1];
  logic parameter_last_mem [0:FIXTURE_PARAMETER_BEAT_COUNT-1];
  logic [31:0] activation_data_mem [0:FIXTURE_ACTIVATION_BEAT_COUNT-1];
  logic [3:0] activation_keep_mem [0:FIXTURE_ACTIVATION_BEAT_COUNT-1];
  logic activation_last_mem [0:FIXTURE_ACTIVATION_BEAT_COUNT-1];
  logic [31:0] expected_data_mem [0:FIXTURE_EXPECTED_BEAT_COUNT-1];
  logic [3:0] expected_keep_mem [0:FIXTURE_EXPECTED_BEAT_COUNT-1];
  logic expected_last_mem [0:FIXTURE_EXPECTED_BEAT_COUNT-1];
  int captured_count = 0;

  always #4 clk = ~clk;

  cnn_programmable_runtime_top #(
    .PC(2), .PK(2), .MAX_CIN(4), .MAX_COUT(4),
    .MAX_LAYERS(4), .MAX_TENSORS(8), .MAX_QUANTIZATIONS(8),
    .MAX_TILE_WIDTH(2), .MAX_TILE_HEIGHT(2),
    .MAX_PAYLOAD_BYTES(4096)
  ) dut (.*);

  assign m_axis_tready = backpressure_lfsr[0] || backpressure_lfsr[3];

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      backpressure_lfsr <= 16'h1ACE;
      captured_count <= 0;
    end else begin
      backpressure_lfsr <= {
        backpressure_lfsr[14:0],
        backpressure_lfsr[15] ^ backpressure_lfsr[13] ^
        backpressure_lfsr[12] ^ backpressure_lfsr[10]
      };
      if (m_axis_tvalid && m_axis_tready) begin
        if (captured_count >= FIXTURE_EXPECTED_BEAT_COUNT)
          $fatal(1, "unexpected output beat %0d", captured_count);
        if ((m_axis_tdata !== expected_data_mem[captured_count]) ||
            (m_axis_tkeep !== expected_keep_mem[captured_count]) ||
            (m_axis_tlast !== expected_last_mem[captured_count])) begin
          $fatal(1,
                 "output mismatch beat=%0d got=%08x/%x/%0d expected=%08x/%x/%0d",
                 captured_count, m_axis_tdata, m_axis_tkeep, m_axis_tlast,
                 expected_data_mem[captured_count],
                 expected_keep_mem[captured_count],
                 expected_last_mem[captured_count]);
        end
        captured_count <= captured_count + 1;
      end
    end
  end

  task automatic pulse(input int command);
    begin
      @(negedge clk);
      case (command)
        0: begin_model_load = 1'b1;
        1: finish_model_load = 1'b1;
        2: validate_model = 1'b1;
        3: activate_model = 1'b1;
        default: start = 1'b1;
      endcase
      @(negedge clk);
      begin_model_load = 1'b0;
      finish_model_load = 1'b0;
      validate_model = 1'b0;
      activate_model = 1'b0;
      start = 1'b0;
    end
  endtask

  task automatic apply_metadata_op(input int index);
    begin
      @(negedge clk);
      metadata_kind = metadata_kind_mem[index];
      metadata_record_index = metadata_record_mem[index];
      metadata_word_index = metadata_word_mem[index];
      metadata_write_data = metadata_data_mem[index];
      if (metadata_action_mem[index]) metadata_commit = 1'b1;
      else metadata_write = 1'b1;
      @(negedge clk);
      metadata_write = 1'b0;
      metadata_commit = 1'b0;
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
      do @(posedge clk); while (!s_axis_tready);
      @(negedge clk);
      s_axis_tvalid = 1'b0;
      s_axis_tkeep = '0;
      s_axis_tlast = 1'b0;
    end
  endtask

  task automatic send_parameter_layer(input int layer);
    int first;
    int count;
    begin
      parameter_layer_select = 3'(layer);
      wait (dut.parameter_config_valid_q &&
            (dut.parameter_config_layer_id_q == 3'(layer)));
      first = parameter_start_mem[layer];
      count = parameter_count_mem[layer];
      for (int beat = first; beat < first + count; beat++) begin
        send_beat(parameter_data_mem[beat], parameter_keep_mem[beat],
                  parameter_last_mem[beat]);
      end
      wait ((dut.u_parameters.bank_valid[0] &&
             (dut.u_parameters.bank_layer_id[0] == 3'(layer))) ||
            (dut.u_parameters.bank_valid[1] &&
             (dut.u_parameters.bank_layer_id[1] == 3'(layer))));
    end
  endtask

  task automatic send_activation_layer(input int layer);
    int first;
    int count;
    begin
      wait (busy && (active_layer == 3'(layer)));
      first = activation_start_mem[layer];
      count = activation_count_mem[layer];
      for (int beat = first; beat < first + count; beat++) begin
        send_beat(activation_data_mem[beat], activation_keep_mem[beat],
                  activation_last_mem[beat]);
      end
    end
  endtask

  initial begin
    $readmemh("build/randomized_rtl_fixture/metadata_action.mem", metadata_action_mem);
    $readmemh("build/randomized_rtl_fixture/metadata_kind.mem", metadata_kind_mem);
    $readmemh("build/randomized_rtl_fixture/metadata_record.mem", metadata_record_mem);
    $readmemh("build/randomized_rtl_fixture/metadata_word.mem", metadata_word_mem);
    $readmemh("build/randomized_rtl_fixture/metadata_data.mem", metadata_data_mem);
    $readmemh("build/randomized_rtl_fixture/parameter_start.mem", parameter_start_mem);
    $readmemh("build/randomized_rtl_fixture/parameter_count.mem", parameter_count_mem);
    $readmemh("build/randomized_rtl_fixture/activation_start.mem", activation_start_mem);
    $readmemh("build/randomized_rtl_fixture/activation_count.mem", activation_count_mem);
    $readmemh("build/randomized_rtl_fixture/parameter_data.mem", parameter_data_mem);
    $readmemh("build/randomized_rtl_fixture/parameter_keep.mem", parameter_keep_mem);
    $readmemh("build/randomized_rtl_fixture/parameter_last.mem", parameter_last_mem);
    $readmemh("build/randomized_rtl_fixture/activation_data.mem", activation_data_mem);
    $readmemh("build/randomized_rtl_fixture/activation_keep.mem", activation_keep_mem);
    $readmemh("build/randomized_rtl_fixture/activation_last.mem", activation_last_mem);
    $readmemh("build/randomized_rtl_fixture/expected_data.mem", expected_data_mem);
    $readmemh("build/randomized_rtl_fixture/expected_keep.mem", expected_keep_mem);
    $readmemh("build/randomized_rtl_fixture/expected_last.mem", expected_last_mem);

    repeat (5) @(posedge clk);
    rst_n = 1'b1;
    repeat (3) @(posedge clk);

    pulse(0);
    for (int op = 0; op < FIXTURE_METADATA_OP_COUNT; op++)
      apply_metadata_op(op);
    pulse(1);
    pulse(2);
    pulse(3);
    repeat (4) @(posedge clk);
    if (!model_active_valid || (active_model_id != FIXTURE_MODEL_ID) ||
        (active_layer_count != FIXTURE_LAYER_COUNT) ||
        (model_lifecycle_error != 0)) begin
      $fatal(1, "compiler package activation failed model=%08x layers=%0d error=%0d",
             active_model_id, active_layer_count, model_lifecycle_error);
    end

    send_parameter_layer(0);
    send_parameter_layer(1);
    pulse(4);

    send_activation_layer(0);
    send_activation_layer(1);
    send_parameter_layer(2);
    send_activation_layer(2);
    send_parameter_layer(3);
    send_activation_layer(3);

    fork
      wait (done);
      begin
        repeat (300000) @(posedge clk);
        $fatal(1, "randomized programmable package flow timed out layer=%0d tile=%0d,%0d",
               active_layer, current_tile_x, current_tile_y);
      end
    join_any
    disable fork;
    repeat (5) @(posedge clk);

    if (error || (packet_error_count != 0) ||
        (completed_layer_count != FIXTURE_LAYER_COUNT) ||
        (completed_tile_count != FIXTURE_FINAL_LAYER_TILE_COUNT) ||
        (captured_count != FIXTURE_EXPECTED_BEAT_COUNT)) begin
      $fatal(1,
             "runtime status error=%0d/%0d layer=%0d packets=%0d layers=%0d tiles=%0d beats=%0d",
             error, error_code, error_layer, packet_error_count,
             completed_layer_count, completed_tile_count, captured_count);
    end

    $display("[PASS] compiler-derived randomized package-to-RTL flow layers=%0d tiles=%0d beats=%0d saturation=%0d",
             FIXTURE_LAYER_COUNT, FIXTURE_TILE_COUNT,
             FIXTURE_EXPECTED_BEAT_COUNT, saturation_event_count);
    $finish;
  end
endmodule
