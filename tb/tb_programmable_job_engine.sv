`timescale 1ns/1ps

module tb_programmable_job_engine;
  localparam int PC = 2;
  localparam int PK = 2;
  localparam int MAX_CIN = 2;
  localparam int MAX_COUT = 2;
  localparam int MAX_PIXELS = 1;

  logic clk;
  logic rst_n;
  logic start;
  logic [2:0] descriptor_layer_index;
  logic parameter_load_start;
  logic parameter_load_ready;
  logic [2:0] parameter_load_layer_id;
  logic [1:0] parameter_load_kernel_size;
  logic [7:0] parameter_load_cin;
  logic [7:0] parameter_load_cout;
  logic parameter_load_bias_enable;
  logic parameter_load_quant_enable;
  logic [4:0] parameter_load_quant_shift;
  logic [15:0] parameter_load_weight_bytes;
  logic [15:0] parameter_load_bias_bytes;
  logic [31:0] parameter_load_expected_crc32;
  logic parameter_weight_valid;
  logic parameter_weight_ready;
  logic signed [7:0] parameter_weight_data;
  logic parameter_bias_valid;
  logic parameter_bias_ready;
  logic signed [31:0] parameter_bias_data;
  logic parameter_load_busy;
  logic parameter_load_done;
  logic parameter_error;
  logic [7:0] parameter_error_code;
  logic [1:0] parameter_bank_valid;
  logic parameter_overlap_active;
  logic signed [7:0] input_tensor [MAX_PIXELS*MAX_CIN];
  logic signed [7:0] output_tensor [MAX_PIXELS*MAX_COUT];
  logic [2:0] active_layer;
  logic busy;
  logic done;
  logic error;
  logic [7:0] error_code;
  logic [2:0] error_layer;
  logic overlap_seen;

  int checks;
  int errors;

  cnn_programmable_job_engine #(
    .PC(PC),
    .PK(PK),
    .MAX_CIN(MAX_CIN),
    .MAX_COUT(MAX_COUT),
    .MAX_PIXELS(MAX_PIXELS)
  ) dut (
    .clk(clk),
    .rst_n(rst_n),
    .start(start),
    .model_active_valid(1'b1),
    .model_layer_count(16'd8),
    .descriptor_layer_index(descriptor_layer_index),
    .descriptor_valid(1'b1),
    .descriptor_layer_id({13'd0, descriptor_layer_index}),
    .descriptor_opcode(16'd1),
    .descriptor_last_layer(descriptor_layer_index == 3'd7),
    .descriptor_bias_enable(1'b0),
    .descriptor_input_tensor_id({13'd0, descriptor_layer_index}),
    .descriptor_output_tensor_id(16'(descriptor_layer_index) + 16'd1),
    .descriptor_residual_tensor_id(16'hFFFF),
    .descriptor_input_width(16'd1),
    .descriptor_input_height(16'd1),
    .descriptor_input_channels(16'd1),
    .descriptor_output_width(16'd1),
    .descriptor_output_height(16'd1),
    .descriptor_output_channels(16'd1),
    .descriptor_kernel_height(8'd1),
    .descriptor_kernel_width(8'd1),
    .descriptor_stride_y(8'd1),
    .descriptor_stride_x(8'd1),
    .descriptor_padding_top(8'd0),
    .descriptor_padding_bottom(8'd0),
    .descriptor_padding_left(8'd0),
    .descriptor_padding_right(8'd0),
    .descriptor_dilation_y(8'd1),
    .descriptor_dilation_x(8'd1),
    .descriptor_activation(8'd0),
    .descriptor_residual_mode(8'd0),
    .parameter_load_start(parameter_load_start),
    .parameter_load_ready(parameter_load_ready),
    .parameter_load_layer_id(parameter_load_layer_id),
    .parameter_load_kernel_size(parameter_load_kernel_size),
    .parameter_load_cin(parameter_load_cin),
    .parameter_load_cout(parameter_load_cout),
    .parameter_load_bias_enable(parameter_load_bias_enable),
    .parameter_load_quant_enable(parameter_load_quant_enable),
    .parameter_load_quant_shift(parameter_load_quant_shift),
    .parameter_load_weight_bytes(parameter_load_weight_bytes),
    .parameter_load_bias_bytes(parameter_load_bias_bytes),
    .parameter_load_expected_crc32(parameter_load_expected_crc32),
    .parameter_weight_valid(parameter_weight_valid),
    .parameter_weight_ready(parameter_weight_ready),
    .parameter_weight_data(parameter_weight_data),
    .parameter_bias_valid(parameter_bias_valid),
    .parameter_bias_ready(parameter_bias_ready),
    .parameter_bias_data(parameter_bias_data),
    .parameter_clear_error(1'b0),
    .parameter_load_busy(parameter_load_busy),
    .parameter_load_done(parameter_load_done),
    .parameter_error(parameter_error),
    .parameter_error_code(parameter_error_code),
    .parameter_bank_valid(parameter_bank_valid),
    .parameter_overlap_active(parameter_overlap_active),
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

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      overlap_seen <= 1'b0;
    end else if (parameter_overlap_active) begin
      overlap_seen <= 1'b1;
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

  task automatic load_identity_layer(input int layer_id);
    logic [31:0] crc;
    begin
      wait (parameter_load_ready);
      crc = crc32_byte(32'hFFFF_FFFF, 8'd1) ^ 32'hFFFF_FFFF;
      @(negedge clk);
      parameter_load_layer_id = 3'(layer_id);
      parameter_load_expected_crc32 = crc;
      parameter_load_start = 1'b1;
      @(negedge clk);
      parameter_load_start = 1'b0;
      wait (parameter_weight_ready);
      @(negedge clk);
      parameter_weight_data = 8'sd1;
      parameter_weight_valid = 1'b1;
      @(negedge clk);
      parameter_weight_valid = 1'b0;
      wait (parameter_load_done);
      @(negedge clk);
      check_value("parameter load error", int'(parameter_error), 0);
    end
  endtask

  initial begin
    checks = 0;
    errors = 0;
    rst_n = 1'b0;
    start = 1'b0;
    parameter_load_start = 1'b0;
    parameter_load_layer_id = '0;
    parameter_load_kernel_size = 2'd1;
    parameter_load_cin = 8'd1;
    parameter_load_cout = 8'd1;
    parameter_load_bias_enable = 1'b0;
    parameter_load_quant_enable = 1'b0;
    parameter_load_quant_shift = '0;
    parameter_load_weight_bytes = 16'd1;
    parameter_load_bias_bytes = 16'd0;
    parameter_load_expected_crc32 = '0;
    parameter_weight_valid = 1'b0;
    parameter_weight_data = '0;
    parameter_bias_valid = 1'b0;
    parameter_bias_data = '0;
    input_tensor[0] = 8'sd7;
    input_tensor[1] = 8'sd0;

    repeat (4) @(posedge clk);
    rst_n = 1'b1;
    repeat (2) @(posedge clk);

    load_identity_layer(0);
    load_identity_layer(1);
    check_value("initial banks full", int'(parameter_bank_valid), 3);

    @(negedge clk);
    start = 1'b1;
    @(negedge clk);
    start = 1'b0;

    for (int layer_id = 2; layer_id < 8; layer_id++) begin
      load_identity_layer(layer_id);
    end

    wait (done);
    @(negedge clk);
    check_value("job error", int'(error), 0);
    check_value("parameter error", int'(parameter_error), 0);
    check_value("all banks consumed", int'(parameter_bank_valid), 0);
    check_value("prefetch overlap observed", int'(overlap_seen), 1);
    check_value("eight-layer identity output", int'($signed(output_tensor[0])), 7);

    if (errors == 0) begin
      $display("[PASS] tb_programmable_job_engine tests=%0d", checks);
    end else begin
      $display("[FAIL] tb_programmable_job_engine errors=%0d tests=%0d", errors, checks);
      $fatal(1);
    end
    $finish;
  end
endmodule
