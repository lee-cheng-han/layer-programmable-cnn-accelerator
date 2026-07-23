`timescale 1ns/1ps

module tb_runtime_parameter_banks;
  localparam int PC = 2;
  localparam int PK = 2;
  localparam int MAX_CIN = 2;
  localparam int MAX_COUT = 2;

  logic clk;
  logic rst_n;
  logic clear_error;
  logic load_start;
  logic load_ready;
  logic [2:0] load_layer_id;
  logic [1:0] load_kernel_size;
  logic [7:0] load_cin;
  logic [7:0] load_cout;
  logic load_bias_enable;
  logic load_quant_enable;
  logic [4:0] load_quant_shift;
  logic [15:0] load_weight_bytes;
  logic [15:0] load_bias_bytes;
  logic [31:0] load_expected_crc32;
  logic weight_valid;
  logic weight_ready;
  logic signed [7:0] weight_data;
  logic bias_valid;
  logic bias_ready;
  logic signed [31:0] bias_data;
  logic load_busy;
  logic load_done;
  logic error;
  logic [7:0] error_code;
  logic parameter_request;
  logic [2:0] parameter_layer_id;
  logic parameter_ready;
  logic parameter_release;
  logic parameter_use_scratchpad_weights;
  logic parameter_quant_enable;
  logic [4:0] parameter_quant_shift;
  logic signed [31:0] parameter_bias [MAX_COUT];
  logic [7:0] weight_read_k_base;
  logic [7:0] weight_read_c_base;
  logic [3:0] weight_read_kernel_idx;
  logic [PK-1:0] weight_out_lane_mask;
  logic [PC-1:0] weight_in_lane_mask;
  logic signed [7:0] weight_mat_data [PK][PC];
  logic [1:0] bank_valid;
  logic [2:0] bank0_layer_id;
  logic [2:0] bank1_layer_id;
  logic load_bank;
  logic compute_bank;
  logic compute_active;
  logic overlap_active;

  int checks;
  int errors;

  cnn_runtime_parameter_banks #(
    .PC(PC),
    .PK(PK),
    .MAX_CIN(MAX_CIN),
    .MAX_COUT(MAX_COUT)
  ) dut (
    .clk(clk),
    .rst_n(rst_n),
    .clear_error(clear_error),
    .load_start(load_start),
    .load_ready(load_ready),
    .load_layer_id(load_layer_id),
    .load_kernel_size(load_kernel_size),
    .load_cin(load_cin),
    .load_cout(load_cout),
    .load_bias_enable(load_bias_enable),
    .load_quant_enable(load_quant_enable),
    .load_quant_shift(load_quant_shift),
    .load_weight_bytes(load_weight_bytes),
    .load_bias_bytes(load_bias_bytes),
    .load_expected_crc32(load_expected_crc32),
    .weight_valid(weight_valid),
    .weight_ready(weight_ready),
    .weight_data(weight_data),
    .bias_valid(bias_valid),
    .bias_ready(bias_ready),
    .bias_data(bias_data),
    .load_busy(load_busy),
    .load_done(load_done),
    .error(error),
    .error_code(error_code),
    .parameter_request(parameter_request),
    .parameter_layer_id(parameter_layer_id),
    .parameter_ready(parameter_ready),
    .parameter_release(parameter_release),
    .parameter_use_scratchpad_weights(parameter_use_scratchpad_weights),
    .parameter_quant_enable(parameter_quant_enable),
    .parameter_quant_shift(parameter_quant_shift),
    .parameter_bias(parameter_bias),
    .weight_read_k_base(weight_read_k_base),
    .weight_read_c_base(weight_read_c_base),
    .weight_read_kernel_idx(weight_read_kernel_idx),
    .weight_out_lane_mask(weight_out_lane_mask),
    .weight_in_lane_mask(weight_in_lane_mask),
    .weight_mat_data(weight_mat_data),
    .bank_valid(bank_valid),
    .bank0_layer_id(bank0_layer_id),
    .bank1_layer_id(bank1_layer_id),
    .load_bank(load_bank),
    .compute_bank(compute_bank),
    .compute_active(compute_active),
    .overlap_active(overlap_active)
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

  function automatic logic [31:0] crc32_word_le(
    input logic [31:0] crc_in,
    input logic [31:0] data
  );
    logic [31:0] value;
    begin
      value = crc32_byte(crc_in, data[7:0]);
      value = crc32_byte(value, data[15:8]);
      value = crc32_byte(value, data[23:16]);
      value = crc32_byte(value, data[31:24]);
      return value;
    end
  endfunction

  task automatic check_value(input string name, input int got, input int expected);
    begin
      checks++;
      if (got != expected) begin
        errors++;
        $error("%s got=%0d expected=%0d", name, got, expected);
      end
    end
  endtask

  task automatic pulse_clear_error;
    begin
      @(negedge clk);
      clear_error = 1'b1;
      @(negedge clk);
      clear_error = 1'b0;
    end
  endtask

  task automatic send_weight(input int value);
    begin
      @(negedge clk);
      while (!weight_ready) @(negedge clk);
      weight_data = 8'(value);
      weight_valid = 1'b1;
      @(negedge clk);
      weight_valid = 1'b0;
    end
  endtask

  task automatic send_bias(input int value);
    begin
      @(negedge clk);
      while (!bias_ready) @(negedge clk);
      bias_data = 32'(value);
      bias_valid = 1'b1;
      @(negedge clk);
      bias_valid = 1'b0;
    end
  endtask

  task automatic load_one_channel_layer(
    input int layer_id,
    input int kernel_size,
    input int center_weight,
    input logic bias_enable,
    input int bias_value,
    input logic quant_enable,
    input int quant_shift,
    input logic corrupt_crc
  );
    logic [31:0] crc;
    logic [31:0] final_crc;
    int tap_count;
    begin
      tap_count = (kernel_size == 1) ? 1 : 9;
      crc = 32'hFFFF_FFFF;
      for (int tap = 0; tap < tap_count; tap++) begin
        crc = crc32_byte(crc, 8'((kernel_size == 1 || tap == 4) ? center_weight : 0));
      end
      if (bias_enable) begin
        crc = crc32_word_le(crc, 32'(bias_value));
      end
      final_crc = crc ^ 32'hFFFF_FFFF;
      if (corrupt_crc) final_crc = final_crc ^ 32'd1;

      @(negedge clk);
      load_layer_id = 3'(layer_id);
      load_kernel_size = 2'(kernel_size);
      load_cin = 8'd1;
      load_cout = 8'd1;
      load_bias_enable = bias_enable;
      load_quant_enable = quant_enable;
      load_quant_shift = 5'(quant_shift);
      load_weight_bytes = 16'(tap_count);
      load_bias_bytes = bias_enable ? 16'd4 : 16'd0;
      load_expected_crc32 = final_crc;
      load_start = 1'b1;
      @(negedge clk);
      load_start = 1'b0;

      for (int tap = 0; tap < tap_count; tap++) begin
        send_weight((kernel_size == 1 || tap == 4) ? center_weight : 0);
      end
      if (bias_enable) send_bias(bias_value);
      wait (load_done);
      @(negedge clk);
    end
  endtask

  task automatic acquire_layer(input int layer_id);
    begin
      @(negedge clk);
      parameter_layer_id = 3'(layer_id);
      parameter_request = 1'b1;
      #1;
      check_value("parameter ready", int'(parameter_ready), 1);
      @(negedge clk);
      parameter_request = 1'b0;
      #1;
      check_value("compute active", int'(compute_active), 1);
    end
  endtask

  task automatic release_layer;
    begin
      @(negedge clk);
      parameter_release = 1'b1;
      @(negedge clk);
      parameter_release = 1'b0;
      #1;
      check_value("compute released", int'(compute_active), 0);
    end
  endtask

  initial begin
    checks = 0;
    errors = 0;
    rst_n = 1'b0;
    clear_error = 1'b0;
    load_start = 1'b0;
    load_layer_id = '0;
    load_kernel_size = '0;
    load_cin = '0;
    load_cout = '0;
    load_bias_enable = 1'b0;
    load_quant_enable = 1'b0;
    load_quant_shift = '0;
    load_weight_bytes = '0;
    load_bias_bytes = '0;
    load_expected_crc32 = '0;
    weight_valid = 1'b0;
    weight_data = '0;
    bias_valid = 1'b0;
    bias_data = '0;
    parameter_request = 1'b0;
    parameter_layer_id = '0;
    parameter_release = 1'b0;
    weight_read_k_base = '0;
    weight_read_c_base = '0;
    weight_read_kernel_idx = '0;
    weight_out_lane_mask = 2'b01;
    weight_in_lane_mask = 2'b01;

    repeat (4) @(posedge clk);
    rst_n = 1'b1;
    repeat (2) @(posedge clk);

    load_one_channel_layer(0, 1, 2, 1'b1, 3, 1'b1, 1, 1'b0);
    check_value("first bank valid", int'(bank_valid), 1);
    check_value("first bank layer", int'(bank0_layer_id), 0);
    load_one_channel_layer(1, 3, 1, 1'b0, 0, 1'b0, 0, 1'b0);
    check_value("both banks valid", int'(bank_valid), 3);
    check_value("second bank layer", int'(bank1_layer_id), 1);

    acquire_layer(0);
    check_value("layer 0 compute bank", int'(compute_bank), 0);
    check_value("layer 0 bias", int'(parameter_bias[0]), 3);
    check_value("layer 0 quant enable", int'(parameter_quant_enable), 1);
    check_value("layer 0 quant shift", int'(parameter_quant_shift), 1);
    #1;
    check_value("layer 0 weight", int'($signed(weight_mat_data[0][0])), 2);
    release_layer();

    acquire_layer(1);
    check_value("layer 1 compute bank", int'(compute_bank), 1);
    weight_read_kernel_idx = 4'd4;
    #1;
    check_value("layer 1 center weight", int'($signed(weight_mat_data[0][0])), 1);

    fork
      begin
        load_one_channel_layer(2, 1, 4, 1'b0, 0, 1'b0, 0, 1'b0);
      end
      begin
        wait (load_busy);
        #1;
        check_value("load compute overlap", int'(overlap_active), 1);
      end
    join
    check_value("prefetch bank valid", int'(bank_valid), 3);
    release_layer();

    weight_read_kernel_idx = 4'd0;
    acquire_layer(2);
    check_value("prefetched compute bank", int'(compute_bank), 0);
    #1;
    check_value("prefetched layer weight", int'($signed(weight_mat_data[0][0])), 4);
    release_layer();

    pulse_clear_error();
    load_one_channel_layer(3, 1, 5, 1'b0, 0, 1'b0, 0, 1'b1);
    check_value("CRC failure asserted", int'(error), 1);
    check_value("CRC failure code", int'(error_code), 3);
    check_value("CRC failure leaves bank invalid", int'(bank_valid), 0);

    pulse_clear_error();
    @(negedge clk);
    load_layer_id = 3'd4;
    load_kernel_size = 2'd1;
    load_cin = 8'd1;
    load_cout = 8'd1;
    load_bias_enable = 1'b0;
    load_weight_bytes = 16'd2;
    load_bias_bytes = 16'd0;
    load_expected_crc32 = '0;
    load_start = 1'b1;
    @(negedge clk);
    load_start = 1'b0;
    check_value("length failure asserted", int'(error), 1);
    check_value("length failure code", int'(error_code), 2);

    if (errors == 0) begin
      $display("[PASS] tb_runtime_parameter_banks tests=%0d", checks);
    end else begin
      $display("[FAIL] tb_runtime_parameter_banks errors=%0d tests=%0d", errors, checks);
      $fatal(1);
    end
    $finish;
  end
endmodule
