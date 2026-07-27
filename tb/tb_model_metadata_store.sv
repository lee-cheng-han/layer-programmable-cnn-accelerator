`timescale 1ns/1ps

module tb_model_metadata_store;
  localparam logic [1:0] METADATA_HEADER = 2'd0;
  localparam logic [1:0] METADATA_LAYER = 2'd1;
  localparam logic [1:0] METADATA_TENSOR = 2'd2;
  localparam logic [1:0] METADATA_QUANTIZATION = 2'd3;

  logic clk;
  logic resetn;
  logic begin_load;
  logic finish_load;
  logic validate_model;
  logic activate_model;
  logic retire_active;
  logic clear_error;
  logic job_busy;
  logic metadata_write;
  logic metadata_commit;
  logic [1:0] metadata_kind;
  logic [5:0] metadata_record_index;
  logic [5:0] metadata_word_index;
  logic [31:0] metadata_write_data;
  logic [31:0] metadata_read_data;
  logic [2:0] staging_state;
  logic staging_bank;
  logic active_valid;
  logic active_bank;
  logic [31:0] staging_model_id;
  logic [31:0] staging_generation_id;
  logic [31:0] active_model_id;
  logic [31:0] active_generation_id;
  logic [15:0] active_layer_count;
  logic [15:0] staging_layer_count;
  logic [15:0] staging_tensor_count;
  logic [15:0] staging_quantization_count;
  logic [7:0] lifecycle_error;
  logic execution_descriptor_valid;
  logic [15:0] execution_tile_height_hint;
  logic [15:0] execution_tile_width_hint;
  logic [63:0] execution_input_ddr_offset;
  logic [31:0] execution_input_allocation_size;
  logic [31:0] execution_input_row_stride;
  logic [31:0] execution_input_pixel_stride;
  logic [31:0] execution_input_channel_stride;
  logic [63:0] execution_output_ddr_offset;
  logic [31:0] execution_output_allocation_size;
  logic [31:0] execution_output_row_stride;
  logic [31:0] execution_output_pixel_stride;
  logic [31:0] execution_output_channel_stride;

  int checks;
  int errors;

  cnn_model_metadata_store #(
    .MAX_LAYERS(2),
    .MAX_TENSORS(4),
    .MAX_QUANTIZATIONS(4)
  ) dut (
    .clk(clk),
    .resetn(resetn),
    .begin_load(begin_load),
    .finish_load(finish_load),
    .validate_model(validate_model),
    .activate_model(activate_model),
    .retire_active(retire_active),
    .clear_error(clear_error),
    .job_busy(job_busy),
    .metadata_write(metadata_write),
    .metadata_commit(metadata_commit),
    .metadata_kind(metadata_kind),
    .metadata_record_index(metadata_record_index),
    .metadata_word_index(metadata_word_index),
    .metadata_write_data(metadata_write_data),
    .metadata_read_data(metadata_read_data),
    .execution_layer_index(3'd0),
    .execution_descriptor_valid(execution_descriptor_valid),
    .execution_layer_id(),
    .execution_opcode(),
    .execution_last_layer(),
    .execution_bias_enable(),
    .execution_input_tensor_id(),
    .execution_output_tensor_id(),
    .execution_residual_tensor_id(),
    .execution_quantization_id(),
    .execution_input_width(),
    .execution_input_height(),
    .execution_input_channels(),
    .execution_output_width(),
    .execution_output_height(),
    .execution_output_channels(),
    .execution_kernel_height(),
    .execution_kernel_width(),
    .execution_stride_y(),
    .execution_stride_x(),
    .execution_padding_top(),
    .execution_padding_bottom(),
    .execution_padding_left(),
    .execution_padding_right(),
    .execution_dilation_y(),
    .execution_dilation_x(),
    .execution_activation(),
    .execution_residual_mode(),
    .execution_tile_height_hint(execution_tile_height_hint),
    .execution_tile_width_hint(execution_tile_width_hint),
    .execution_input_ddr_offset(execution_input_ddr_offset),
    .execution_input_allocation_size(execution_input_allocation_size),
    .execution_input_row_stride(execution_input_row_stride),
    .execution_input_pixel_stride(execution_input_pixel_stride),
    .execution_input_channel_stride(execution_input_channel_stride),
    .execution_output_ddr_offset(execution_output_ddr_offset),
    .execution_output_allocation_size(execution_output_allocation_size),
    .execution_output_row_stride(execution_output_row_stride),
    .execution_output_pixel_stride(execution_output_pixel_stride),
    .execution_output_channel_stride(execution_output_channel_stride),
    .staging_state(staging_state),
    .staging_bank(staging_bank),
    .active_valid(active_valid),
    .active_bank(active_bank),
    .staging_model_id(staging_model_id),
    .staging_generation_id(staging_generation_id),
    .active_model_id(active_model_id),
    .active_generation_id(active_generation_id),
    .active_layer_count(active_layer_count),
    .staging_layer_count(staging_layer_count),
    .staging_tensor_count(staging_tensor_count),
    .staging_quantization_count(staging_quantization_count),
    .lifecycle_error(lifecycle_error)
  );

  initial begin
    clk = 1'b0;
    forever #5 clk = ~clk;
  end

  task automatic check_eq(
    input string name,
    input logic [31:0] got,
    input logic [31:0] expected
  );
    begin
      checks++;
      if (got !== expected) begin
        errors++;
        $error("%s got=0x%08h expected=0x%08h", name, got, expected);
      end
    end
  endtask

  task automatic pulse_command(input int command);
    begin
      @(negedge clk);
      unique case (command)
        0: begin_load = 1'b1;
        1: finish_load = 1'b1;
        2: validate_model = 1'b1;
        3: activate_model = 1'b1;
        4: retire_active = 1'b1;
        5: clear_error = 1'b1;
        default: begin end
      endcase
      @(negedge clk);
      begin_load = 1'b0;
      finish_load = 1'b0;
      validate_model = 1'b0;
      activate_model = 1'b0;
      retire_active = 1'b0;
      clear_error = 1'b0;
    end
  endtask

  task automatic write_word(
    input logic [1:0] kind,
    input logic [5:0] record_index,
    input logic [5:0] word_index,
    input logic [31:0] data
  );
    begin
      @(negedge clk);
      metadata_kind = kind;
      metadata_record_index = record_index;
      metadata_word_index = word_index;
      metadata_write_data = data;
      metadata_write = 1'b1;
      @(negedge clk);
      metadata_write = 1'b0;
    end
  endtask

  task automatic commit_record(
    input logic [1:0] kind,
    input logic [5:0] record_index
  );
    begin
      @(negedge clk);
      metadata_kind = kind;
      metadata_record_index = record_index;
      metadata_word_index = 0;
      metadata_commit = 1'b1;
      @(negedge clk);
      metadata_commit = 1'b0;
    end
  endtask

  task automatic load_minimal_model(
    input logic [31:0] model_id,
    input logic [31:0] generation_id,
    input logic commit_quantization,
    input logic corrupt_layer_header
  );
    begin
      write_word(METADATA_HEADER, 0, 0, 32'h314E_4E43);
      write_word(METADATA_HEADER, 0, 1, 32'h0080_0001);
      write_word(METADATA_HEADER, 0, 4, model_id);
      write_word(METADATA_HEADER, 0, 5, generation_id);
      write_word(METADATA_HEADER, 0, 6, 32'h0002_0001);
      write_word(METADATA_HEADER, 0, 7, 32'h0000_0001);
      commit_record(METADATA_HEADER, 0);

      write_word(
        METADATA_LAYER, 0, 0,
        corrupt_layer_header ? 32'h0040_0001 : 32'h0080_0001
      );
      write_word(METADATA_LAYER, 0, 1, 32'h0001_0000);
      write_word(METADATA_LAYER, 0, 2, 32'h0000_0002);
      write_word(METADATA_LAYER, 0, 3, 32'h0001_0000);
      write_word(METADATA_LAYER, 0, 4, 32'h0000_FFFF);
      write_word(METADATA_LAYER, 0, 10, 32'h0101_0303);
      write_word(METADATA_LAYER, 0, 11, 32'h0101_0101);
      write_word(METADATA_LAYER, 0, 12, 32'h0000_0101);
      write_word(
        METADATA_LAYER, 0, 13,
        {16'(generation_id + 6), 16'(generation_id + 4)}
      );
      commit_record(METADATA_LAYER, 0);

      write_word(METADATA_TENSOR, 0, 0, 32'h0040_0001);
      write_word(METADATA_TENSOR, 0, 1, 32'h0001_0000);
      write_word(METADATA_TENSOR, 0, 2, 32'h0000_1000 + (generation_id << 8));
      write_word(METADATA_TENSOR, 0, 3, 32'd0);
      write_word(METADATA_TENSOR, 0, 4, 32'd4096);
      write_word(METADATA_TENSOR, 0, 5, 32'h0005_0005);
      write_word(METADATA_TENSOR, 0, 6, 32'h0101_0001);
      write_word(METADATA_TENSOR, 0, 9, 32'd5);
      write_word(METADATA_TENSOR, 0, 10, 32'd1);
      write_word(METADATA_TENSOR, 0, 11, 32'd1);
      commit_record(METADATA_TENSOR, 0);
      write_word(METADATA_TENSOR, 1, 0, 32'h0040_0001);
      write_word(METADATA_TENSOR, 1, 1, 32'h0002_0001);
      write_word(METADATA_TENSOR, 1, 2, 32'h0000_2000 + (generation_id << 8));
      write_word(METADATA_TENSOR, 1, 3, 32'd0);
      write_word(METADATA_TENSOR, 1, 4, 32'd8192);
      write_word(METADATA_TENSOR, 1, 5, 32'h0005_0005);
      write_word(METADATA_TENSOR, 1, 6, 32'h0101_0001);
      write_word(METADATA_TENSOR, 1, 9, 32'd5);
      write_word(METADATA_TENSOR, 1, 10, 32'd1);
      write_word(METADATA_TENSOR, 1, 11, 32'd1);
      commit_record(METADATA_TENSOR, 1);

      write_word(METADATA_QUANTIZATION, 0, 0, 32'h00C0_0001);
      write_word(METADATA_QUANTIZATION, 0, 1, 32'h0000_0000);
      if (commit_quantization) begin
        commit_record(METADATA_QUANTIZATION, 0);
      end
    end
  endtask

  initial begin
    checks = 0;
    errors = 0;
    resetn = 1'b0;
    begin_load = 1'b0;
    finish_load = 1'b0;
    validate_model = 1'b0;
    activate_model = 1'b0;
    retire_active = 1'b0;
    clear_error = 1'b0;
    job_busy = 1'b0;
    metadata_write = 1'b0;
    metadata_commit = 1'b0;
    metadata_kind = '0;
    metadata_record_index = '0;
    metadata_word_index = '0;
    metadata_write_data = '0;

    repeat (4) @(posedge clk);
    resetn = 1'b1;
    repeat (2) @(posedge clk);

    check_eq("reset staging state", staging_state, 0);
    check_eq("reset active valid", active_valid, 0);

    pulse_command(0);
    check_eq("first load state", staging_state, 1);
    check_eq("first staging bank", staging_bank, 1);
    load_minimal_model(32'd11, 32'd1, 1'b1, 1'b0);
    check_eq("staging model readback", staging_model_id, 11);
    check_eq("staging generation readback", staging_generation_id, 1);
    check_eq("staging layer count", staging_layer_count, 1);
    check_eq("staging tensor count", staging_tensor_count, 2);
    check_eq("staging quantization count", staging_quantization_count, 1);
    @(posedge clk);
    @(negedge clk);
    check_eq("selected metadata readback", metadata_read_data, 32'h00C0_0001);
    pulse_command(1);
    check_eq("loaded state", staging_state, 2);
    pulse_command(2);
    check_eq("validated state", staging_state, 3);
    pulse_command(3);
    check_eq("first active valid", active_valid, 1);
    check_eq("first active bank", active_bank, 1);
    check_eq("first active model", active_model_id, 11);
    check_eq("first active generation", active_generation_id, 1);
    check_eq("first descriptor valid", execution_descriptor_valid, 1);
    check_eq("first tile height hint", execution_tile_height_hint, 5);
    check_eq("first tile width hint", execution_tile_width_hint, 7);
    check_eq("first input DDR offset low", execution_input_ddr_offset[31:0],
             32'h0000_1100);
    check_eq("first input DDR offset high", execution_input_ddr_offset[63:32], 0);
    check_eq("first input allocation", execution_input_allocation_size, 4096);
    check_eq("first input row stride", execution_input_row_stride, 5);
    check_eq("first input pixel stride", execution_input_pixel_stride, 1);
    check_eq("first input channel stride", execution_input_channel_stride, 1);
    check_eq("first output DDR offset low", execution_output_ddr_offset[31:0],
             32'h0000_2100);
    check_eq("first output allocation", execution_output_allocation_size, 8192);
    check_eq("first output row stride", execution_output_row_stride, 5);
    check_eq("first output pixel stride", execution_output_pixel_stride, 1);
    check_eq("first output channel stride", execution_output_channel_stride, 1);

    pulse_command(0);
    check_eq("replacement uses other bank", staging_bank, 0);
    load_minimal_model(32'd22, 32'd2, 1'b0, 1'b0);
    pulse_command(1);
    pulse_command(2);
    check_eq("incomplete validation error", lifecycle_error, 4);
    check_eq("incomplete replacement leaves active model", active_model_id, 11);
    check_eq("incomplete replacement leaves active generation", active_generation_id, 1);
    check_eq("incomplete replacement leaves tile hint",
             execution_tile_width_hint, 7);
    check_eq("incomplete replacement leaves input offset",
             execution_input_ddr_offset[31:0], 32'h0000_1100);

    pulse_command(0);
    load_minimal_model(32'd22, 32'd2, 1'b1, 1'b0);
    pulse_command(1);
    pulse_command(2);
    job_busy = 1'b1;
    pulse_command(3);
    check_eq("busy activation error", lifecycle_error, 2);
    check_eq("busy activation leaves active model", active_model_id, 11);
    job_busy = 1'b0;
    pulse_command(5);
    pulse_command(3);
    check_eq("replacement active bank", active_bank, 0);
    check_eq("replacement active model", active_model_id, 22);
    check_eq("replacement active generation", active_generation_id, 2);
    check_eq("replacement tile height", execution_tile_height_hint, 6);
    check_eq("replacement tile width", execution_tile_width_hint, 8);
    check_eq("replacement input offset", execution_input_ddr_offset[31:0],
             32'h0000_1200);
    check_eq("replacement output offset", execution_output_ddr_offset[31:0],
             32'h0000_2200);

    pulse_command(0);
    load_minimal_model(32'd33, 32'd3, 1'b1, 1'b1);
    pulse_command(1);
    pulse_command(2);
    check_eq("bad descriptor error", lifecycle_error, 7);
    check_eq("bad descriptor leaves active model", active_model_id, 22);

    job_busy = 1'b1;
    pulse_command(4);
    check_eq("busy retire error", lifecycle_error, 2);
    check_eq("busy retire preserves active", active_valid, 1);
    job_busy = 1'b0;
    pulse_command(4);
    check_eq("retire clears active", active_valid, 0);
    check_eq("retire clears active ID", active_model_id, 0);

    if (errors == 0) begin
      $display("[PASS] tb_model_metadata_store tests=%0d", checks);
    end else begin
      $display("[FAIL] tb_model_metadata_store errors=%0d checks=%0d", errors, checks);
      $fatal(1);
    end
    $finish;
  end
endmodule
