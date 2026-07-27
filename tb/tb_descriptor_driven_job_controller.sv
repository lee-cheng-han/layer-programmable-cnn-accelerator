`timescale 1ns/1ps

module tb_descriptor_driven_job_controller;
  localparam int PC = 2;
  localparam int PK = 2;
  localparam int MAX_CIN = 2;
  localparam int MAX_COUT = 2;
  localparam int MAX_PIXELS = 4;

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
  logic metadata_write;
  logic metadata_commit;
  logic [1:0] metadata_kind;
  logic [5:0] metadata_record_index;
  logic [5:0] metadata_word_index;
  logic [31:0] metadata_write_data;
  logic [2:0] staging_state;
  logic active_valid;
  logic [15:0] active_layer_count;
  logic [7:0] lifecycle_error;

  logic start;
  logic [2:0] descriptor_layer_index;
  logic descriptor_valid;
  logic [15:0] descriptor_layer_id;
  logic [15:0] descriptor_opcode;
  logic descriptor_last_layer;
  logic descriptor_bias_enable;
  logic [15:0] descriptor_input_tensor_id;
  logic [15:0] descriptor_output_tensor_id;
  logic [15:0] descriptor_residual_tensor_id;
  logic [15:0] descriptor_input_width;
  logic [15:0] descriptor_input_height;
  logic [15:0] descriptor_input_channels;
  logic [15:0] descriptor_output_width;
  logic [15:0] descriptor_output_height;
  logic [15:0] descriptor_output_channels;
  logic [7:0] descriptor_kernel_height;
  logic [7:0] descriptor_kernel_width;
  logic [7:0] descriptor_stride_y;
  logic [7:0] descriptor_stride_x;
  logic [7:0] descriptor_padding_top;
  logic [7:0] descriptor_padding_bottom;
  logic [7:0] descriptor_padding_left;
  logic [7:0] descriptor_padding_right;
  logic [7:0] descriptor_dilation_y;
  logic [7:0] descriptor_dilation_x;
  logic [7:0] descriptor_activation;
  logic [7:0] descriptor_residual_mode;

  logic parameter_request;
  logic parameter_release;
  logic parameter_ready;
  logic parameter_quant_enable;
  logic [4:0] parameter_quant_shift;
  logic signed [7:0] parameter_weights_1x1 [MAX_COUT][MAX_CIN];
  logic signed [7:0] parameter_weights_3x3 [MAX_COUT][MAX_CIN][9];
  logic signed [31:0] parameter_bias [MAX_COUT];
  logic signed [7:0] parameter_weight_mat_data [PK][PC];
  logic signed [7:0] input_tensor [MAX_PIXELS*MAX_CIN];
  logic signed [7:0] output_tensor [MAX_PIXELS*MAX_COUT];
  logic [2:0] active_layer;
  logic busy;
  logic done;
  logic error;
  logic [7:0] error_code;
  logic [2:0] error_layer;

  logic [1:0] parameter_wait_cycles;
  logic [7:0] layer_seen;
  logic identity_parameters;
  int parameter_requests;
  int checks;
  int errors;

  cnn_model_metadata_store #(
    .MAX_LAYERS(8),
    .MAX_TENSORS(10),
    .MAX_QUANTIZATIONS(2)
  ) u_metadata_store (
    .clk(clk),
    .resetn(resetn),
    .begin_load(begin_load),
    .finish_load(finish_load),
    .validate_model(validate_model),
    .activate_model(activate_model),
    .retire_active(1'b0),
    .clear_error(1'b0),
    .job_busy(busy),
    .metadata_write(metadata_write),
    .metadata_commit(metadata_commit),
    .metadata_kind(metadata_kind),
    .metadata_record_index(metadata_record_index),
    .metadata_word_index(metadata_word_index),
    .metadata_write_data(metadata_write_data),
    .metadata_read_data(),
    .execution_layer_index(descriptor_layer_index),
    .execution_descriptor_valid(descriptor_valid),
    .execution_layer_id(descriptor_layer_id),
    .execution_opcode(descriptor_opcode),
    .execution_last_layer(descriptor_last_layer),
    .execution_bias_enable(descriptor_bias_enable),
    .execution_input_tensor_id(descriptor_input_tensor_id),
    .execution_output_tensor_id(descriptor_output_tensor_id),
    .execution_residual_tensor_id(descriptor_residual_tensor_id),
    .execution_quantization_id(),
    .execution_input_width(descriptor_input_width),
    .execution_input_height(descriptor_input_height),
    .execution_input_channels(descriptor_input_channels),
    .execution_output_width(descriptor_output_width),
    .execution_output_height(descriptor_output_height),
    .execution_output_channels(descriptor_output_channels),
    .execution_kernel_height(descriptor_kernel_height),
    .execution_kernel_width(descriptor_kernel_width),
    .execution_stride_y(descriptor_stride_y),
    .execution_stride_x(descriptor_stride_x),
    .execution_padding_top(descriptor_padding_top),
    .execution_padding_bottom(descriptor_padding_bottom),
    .execution_padding_left(descriptor_padding_left),
    .execution_padding_right(descriptor_padding_right),
    .execution_dilation_y(descriptor_dilation_y),
    .execution_dilation_x(descriptor_dilation_x),
    .execution_activation(descriptor_activation),
    .execution_residual_mode(descriptor_residual_mode),
    .execution_tile_height_hint(),
    .execution_tile_width_hint(),
    .execution_input_ddr_offset(),
    .execution_input_allocation_size(),
    .execution_input_row_stride(),
    .execution_input_pixel_stride(),
    .execution_input_channel_stride(),
    .execution_output_ddr_offset(),
    .execution_output_allocation_size(),
    .execution_output_row_stride(),
    .execution_output_pixel_stride(),
    .execution_output_channel_stride(),
    .staging_state(staging_state),
    .staging_bank(),
    .active_valid(active_valid),
    .active_bank(),
    .staging_model_id(),
    .staging_generation_id(),
    .active_model_id(),
    .active_generation_id(),
    .active_layer_count(active_layer_count),
    .staging_layer_count(),
    .staging_tensor_count(),
    .staging_quantization_count(),
    .lifecycle_error(lifecycle_error)
  );

  descriptor_driven_job_controller #(
    .PC(PC),
    .PK(PK),
    .MAX_CIN(MAX_CIN),
    .MAX_COUT(MAX_COUT),
    .MAX_PIXELS(MAX_PIXELS)
  ) dut (
    .clk(clk),
    .rst_n(resetn),
    .start(start),
    .model_active_valid(active_valid),
    .model_layer_count(active_layer_count),
    .descriptor_layer_index(descriptor_layer_index),
    .descriptor_valid(descriptor_valid),
    .descriptor_layer_id(descriptor_layer_id),
    .descriptor_opcode(descriptor_opcode),
    .descriptor_last_layer(descriptor_last_layer),
    .descriptor_bias_enable(descriptor_bias_enable),
    .descriptor_input_tensor_id(descriptor_input_tensor_id),
    .descriptor_output_tensor_id(descriptor_output_tensor_id),
    .descriptor_residual_tensor_id(descriptor_residual_tensor_id),
    .descriptor_input_width(descriptor_input_width),
    .descriptor_input_height(descriptor_input_height),
    .descriptor_input_channels(descriptor_input_channels),
    .descriptor_output_width(descriptor_output_width),
    .descriptor_output_height(descriptor_output_height),
    .descriptor_output_channels(descriptor_output_channels),
    .descriptor_kernel_height(descriptor_kernel_height),
    .descriptor_kernel_width(descriptor_kernel_width),
    .descriptor_stride_y(descriptor_stride_y),
    .descriptor_stride_x(descriptor_stride_x),
    .descriptor_padding_top(descriptor_padding_top),
    .descriptor_padding_bottom(descriptor_padding_bottom),
    .descriptor_padding_left(descriptor_padding_left),
    .descriptor_padding_right(descriptor_padding_right),
    .descriptor_dilation_y(descriptor_dilation_y),
    .descriptor_dilation_x(descriptor_dilation_x),
    .descriptor_activation(descriptor_activation),
    .descriptor_residual_mode(descriptor_residual_mode),
    .parameter_request(parameter_request),
    .parameter_release(parameter_release),
    .parameter_ready(parameter_ready),
    .parameter_use_scratchpad_weights(1'b0),
    .parameter_quant_enable(parameter_quant_enable),
    .parameter_quant_shift(parameter_quant_shift),
    .parameter_weights_1x1(parameter_weights_1x1),
    .parameter_weights_3x3(parameter_weights_3x3),
    .parameter_bias(parameter_bias),
    .parameter_weight_read_k_base(),
    .parameter_weight_read_c_base(),
    .parameter_weight_read_kernel_idx(),
    .parameter_weight_out_lane_mask(),
    .parameter_weight_in_lane_mask(),
    .parameter_weight_mat_data(parameter_weight_mat_data),
    .input_tensor(input_tensor),
    .output_tensor(output_tensor),
    .active_layer(active_layer),
    .busy(busy),
    .done(done),
    .error(error),
    .error_code(error_code),
    .error_layer(error_layer)
  );

  initial begin
    clk = 1'b0;
    forever #5 clk = ~clk;
  end

  always_comb begin
    parameter_quant_enable = !identity_parameters && (active_layer == 3'd2);
    parameter_quant_shift = parameter_quant_enable ? 5'd1 : 5'd0;
    for (int co = 0; co < MAX_COUT; co++) begin
      parameter_bias[co] = '0;
      for (int ci = 0; ci < MAX_CIN; ci++) begin
        parameter_weights_1x1[co][ci] = '0;
        for (int k = 0; k < 9; k++) begin
          parameter_weights_3x3[co][ci][k] = '0;
        end
      end
    end
    for (int pk = 0; pk < PK; pk++) begin
      for (int pc = 0; pc < PC; pc++) begin
        parameter_weight_mat_data[pk][pc] = '0;
      end
    end

    if (identity_parameters) begin
      parameter_weights_1x1[0][0] = 8'sd1;
    end else begin
      unique case (active_layer)
        3'd0: parameter_weights_1x1[0][0] = 8'sd2;
        3'd1: begin
          parameter_weights_3x3[0][0][4] = 8'sd1;
          parameter_bias[0] = 32'sd1;
        end
        3'd2: parameter_weights_1x1[0][0] = 8'sd1;
        3'd3: parameter_weights_3x3[0][0][4] = 8'sd1;
        default: begin
        end
      endcase
    end
  end

  always_ff @(posedge clk or negedge resetn) begin
    if (!resetn) begin
      parameter_wait_cycles <= '0;
      parameter_ready <= 1'b0;
      layer_seen <= '0;
      parameter_requests <= 0;
    end else begin
      parameter_ready <= 1'b0;
      if (parameter_request) begin
        layer_seen[active_layer] <= 1'b1;
        if (parameter_wait_cycles == 2) begin
          parameter_ready <= 1'b1;
          parameter_wait_cycles <= '0;
          parameter_requests <= parameter_requests + 1;
        end else begin
          parameter_wait_cycles <= parameter_wait_cycles + 2'd1;
        end
      end else begin
        parameter_wait_cycles <= '0;
      end
    end
  end

  task automatic pulse(input int command);
    begin
      @(negedge clk);
      if (command == 0) begin_load = 1'b1;
      if (command == 1) finish_load = 1'b1;
      if (command == 2) validate_model = 1'b1;
      if (command == 3) activate_model = 1'b1;
      if (command == 4) start = 1'b1;
      @(negedge clk);
      begin_load = 1'b0;
      finish_load = 1'b0;
      validate_model = 1'b0;
      activate_model = 1'b0;
      start = 1'b0;
    end
  endtask

  task automatic write_word(
    input logic [1:0] kind,
    input int record_index,
    input int word_index,
    input logic [31:0] data
  );
    begin
      @(negedge clk);
      metadata_kind = kind;
      metadata_record_index = 6'(record_index);
      metadata_word_index = 6'(word_index);
      metadata_write_data = data;
      metadata_write = 1'b1;
      @(negedge clk);
      metadata_write = 1'b0;
    end
  endtask

  task automatic commit_record(input logic [1:0] kind, input int record_index);
    begin
      @(negedge clk);
      metadata_kind = kind;
      metadata_record_index = 6'(record_index);
      metadata_word_index = '0;
      metadata_commit = 1'b1;
      @(negedge clk);
      metadata_commit = 1'b0;
    end
  endtask

  task automatic load_tensor(
    input int tensor_id,
    input int width,
    input int height
  );
    begin
      write_word(METADATA_TENSOR, tensor_id, 0, 32'h0040_0001);
      write_word(METADATA_TENSOR, tensor_id, 1, 32'(tensor_id));
      write_word(METADATA_TENSOR, tensor_id, 5, {16'(height), 16'(width)});
      write_word(METADATA_TENSOR, tensor_id, 6, 32'h0101_0001);
      commit_record(METADATA_TENSOR, tensor_id);
    end
  endtask

  task automatic load_layer(
    input int layer_id,
    input int kernel_size,
    input int padding,
    input logic bias_enable,
    input logic last_layer,
    input int residual_mode
  );
    logic [31:0] flags;
    logic [31:0] geometry;
    logic [31:0] padding_word;
    logic [31:0] postprocess;
    logic [15:0] residual_id;
    begin
      flags = {30'd0, last_layer, bias_enable};
      geometry = {8'd1, 8'd1, 8'(kernel_size), 8'(kernel_size)};
      padding_word = {4{8'(padding)}};
      postprocess = {8'(residual_mode), 8'd0, 8'd1, 8'd1};
      residual_id = (residual_mode == 0) ? 16'hFFFF : 16'd0;

      write_word(METADATA_LAYER, layer_id, 0, 32'h0080_0001);
      write_word(METADATA_LAYER, layer_id, 1, {16'd1, 16'(layer_id)});
      write_word(METADATA_LAYER, layer_id, 2, flags);
      write_word(METADATA_LAYER, layer_id, 3,
                 {16'(layer_id + 1), 16'(layer_id)});
      write_word(METADATA_LAYER, layer_id, 4, {16'd0, residual_id});
      write_word(METADATA_LAYER, layer_id, 10, geometry);
      write_word(METADATA_LAYER, layer_id, 11, padding_word);
      write_word(METADATA_LAYER, layer_id, 12, postprocess);
      commit_record(METADATA_LAYER, layer_id);
    end
  endtask

  task automatic wait_for_done(input int timeout_cycles);
    int cycles;
    begin
      cycles = 0;
      while (!done && (cycles < timeout_cycles)) begin
        @(posedge clk);
        cycles++;
      end
      if (!done) begin
        errors++;
        $error("controller timeout after %0d cycles", timeout_cycles);
      end
    end
  endtask

  task automatic check_value(input string name, input int got, input int expected);
    begin
      checks++;
      if (got != expected) begin
        errors++;
        $error("%s got=%0d expected=%0d", name, got, expected);
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
    metadata_write = 1'b0;
    metadata_commit = 1'b0;
    metadata_kind = '0;
    metadata_record_index = '0;
    metadata_word_index = '0;
    metadata_write_data = '0;
    start = 1'b0;
    identity_parameters = 1'b0;
    for (int i = 0; i < MAX_PIXELS*MAX_CIN; i++) begin
      input_tensor[i] = '0;
    end
    input_tensor[0] = 8'sd1;
    input_tensor[2] = 8'sd2;
    input_tensor[4] = 8'sd3;
    input_tensor[6] = 8'sd4;

    repeat (4) @(posedge clk);
    resetn = 1'b1;
    repeat (2) @(posedge clk);

    pulse(4);
    wait_for_done(20);
    check_value("inactive model error", int'(error), 1);
    check_value("inactive model error code", int'(error_code), 1);

    pulse(0);
    write_word(METADATA_HEADER, 0, 0, 32'h314E_4E43);
    write_word(METADATA_HEADER, 0, 1, 32'h0080_0001);
    write_word(METADATA_HEADER, 0, 4, 32'd100);
    write_word(METADATA_HEADER, 0, 5, 32'd1);
    write_word(METADATA_HEADER, 0, 6, 32'h0005_0004);
    write_word(METADATA_HEADER, 0, 7, 32'h0000_0001);
    commit_record(METADATA_HEADER, 0);

    load_layer(0, 1, 0, 1'b0, 1'b0, 0);
    load_layer(1, 3, 1, 1'b1, 1'b0, 0);
    load_layer(2, 1, 0, 1'b0, 1'b0, 0);
    load_layer(3, 3, 1, 1'b0, 1'b1, 1);
    for (int tensor_id = 0; tensor_id < 5; tensor_id++) begin
      load_tensor(tensor_id, 2, 2);
    end
    write_word(METADATA_QUANTIZATION, 0, 0, 32'h00C0_0001);
    write_word(METADATA_QUANTIZATION, 0, 1, 32'd0);
    commit_record(METADATA_QUANTIZATION, 0);

    pulse(1);
    pulse(2);
    check_value("validated staging state", int'(staging_state), 3);
    check_value("metadata lifecycle error", int'(lifecycle_error), 0);
    pulse(3);
    check_value("active model", int'(active_valid), 1);
    check_value("active layer count", int'(active_layer_count), 4);

    pulse(4);
    wait_for_done(5000);
    check_value("execution error", int'(error), 0);
    check_value("all layers requested", int'(layer_seen), 15);
    check_value("parameter handshakes", parameter_requests, 4);
    check_value("output pixel 0", int'($signed(output_tensor[0])), 2);
    check_value("output pixel 1", int'($signed(output_tensor[2])), 4);
    check_value("output pixel 2", int'($signed(output_tensor[4])), 6);
    check_value("output pixel 3", int'($signed(output_tensor[6])), 8);

    identity_parameters = 1'b1;
    pulse(0);
    write_word(METADATA_HEADER, 0, 0, 32'h314E_4E43);
    write_word(METADATA_HEADER, 0, 1, 32'h0080_0001);
    write_word(METADATA_HEADER, 0, 4, 32'd101);
    write_word(METADATA_HEADER, 0, 5, 32'd2);
    write_word(METADATA_HEADER, 0, 6, 32'h0009_0008);
    write_word(METADATA_HEADER, 0, 7, 32'h0000_0001);
    commit_record(METADATA_HEADER, 0);
    for (int layer_id = 0; layer_id < 8; layer_id++) begin
      load_layer(layer_id, 1, 0, 1'b0, layer_id == 7, 0);
    end
    for (int tensor_id = 0; tensor_id < 9; tensor_id++) begin
      load_tensor(tensor_id, 2, 2);
    end
    write_word(METADATA_QUANTIZATION, 0, 0, 32'h00C0_0001);
    write_word(METADATA_QUANTIZATION, 0, 1, 32'd0);
    commit_record(METADATA_QUANTIZATION, 0);
    pulse(1);
    pulse(2);
    pulse(3);
    pulse(4);
    wait_for_done(5000);
    check_value("eight-layer execution error", int'(error), 0);
    check_value("eight-layer coverage", int'(layer_seen), 255);
    check_value("eight-layer parameter handshakes", parameter_requests, 12);
    check_value("eight-layer output pixel 0", int'($signed(output_tensor[0])), 1);
    check_value("eight-layer output pixel 1", int'($signed(output_tensor[2])), 2);
    check_value("eight-layer output pixel 2", int'($signed(output_tensor[4])), 3);
    check_value("eight-layer output pixel 3", int'($signed(output_tensor[6])), 4);

    pulse(0);
    write_word(METADATA_HEADER, 0, 0, 32'h314E_4E43);
    write_word(METADATA_HEADER, 0, 1, 32'h0080_0001);
    write_word(METADATA_HEADER, 0, 4, 32'd102);
    write_word(METADATA_HEADER, 0, 5, 32'd3);
    write_word(METADATA_HEADER, 0, 6, 32'h0002_0001);
    write_word(METADATA_HEADER, 0, 7, 32'h0000_0001);
    commit_record(METADATA_HEADER, 0);
    load_layer(0, 1, 0, 1'b0, 1'b1, 0);
    load_tensor(0, 2, 2);
    load_tensor(1, 1, 1);
    write_word(METADATA_QUANTIZATION, 0, 0, 32'h00C0_0001);
    write_word(METADATA_QUANTIZATION, 0, 1, 32'd0);
    commit_record(METADATA_QUANTIZATION, 0);
    pulse(1);
    pulse(2);
    pulse(3);
    pulse(4);
    wait_for_done(20);
    check_value("bad geometry rejected", int'(error), 1);
    check_value("bad geometry error code", int'(error_code), 4);
    check_value("bad geometry error layer", int'(error_layer), 0);
    check_value("bad geometry requests no parameters", parameter_requests, 12);

    if (errors == 0) begin
      $display("[PASS] tb_descriptor_driven_job_controller tests=%0d", checks);
    end else begin
      $display("[FAIL] tb_descriptor_driven_job_controller errors=%0d tests=%0d",
               errors, checks);
      $fatal(1);
    end
    $finish;
  end
endmodule
