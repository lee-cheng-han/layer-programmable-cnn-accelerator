`timescale 1ns/1ps

module tb_packed_dma_runtime_router;
  import cnn_dma_packet_pkg::*;

  localparam int PC = 2;
  localparam int PK = 2;
  localparam int MAX_CIN = 2;
  localparam int MAX_COUT = 2;

  logic clk;
  logic rst_n;
  logic clear;
  logic clear_parameter_error;
  logic [31:0] s_axis_tdata;
  logic [3:0] s_axis_tkeep;
  logic s_axis_tvalid;
  logic s_axis_tready;
  logic s_axis_tlast;

  logic packet_start;
  logic packet_ready;
  logic [7:0] packet_type;
  logic [31:0] packet_job_id;
  logic [15:0] packet_tensor_id;
  logic [15:0] packet_layer_id;
  logic [15:0] packet_tile_x;
  logic [15:0] packet_tile_y;
  logic [15:0] packet_tile_width;
  logic [15:0] packet_tile_height;
  logic [15:0] packet_channel_offset;
  logic [15:0] packet_channel_count;
  logic [31:0] packet_payload_length;
  logic payload_valid;
  logic payload_ready;
  logic [31:0] payload_data;
  logic [3:0] payload_keep;
  logic payload_last;
  logic parser_error_valid;
  logic [7:0] parser_error_code;
  logic [31:0] parser_error_count;

  logic parameter_config_valid;
  logic [2:0] parameter_config_layer_id;
  logic [1:0] parameter_config_kernel_size;
  logic [7:0] parameter_config_cin;
  logic [7:0] parameter_config_cout;
  logic parameter_config_bias_enable;
  logic parameter_config_quant_enable;
  logic [4:0] parameter_config_quant_shift;
  logic [15:0] parameter_config_weight_bytes;
  logic [15:0] parameter_config_bias_bytes;
  logic [31:0] parameter_config_crc32;

  logic parameter_load_start;
  logic parameter_load_abort;
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

  logic activation_packet_start;
  logic activation_packet_ready;
  logic [31:0] activation_job_id;
  logic [15:0] activation_tensor_id;
  logic [15:0] activation_layer_id;
  logic [15:0] activation_tile_x;
  logic [15:0] activation_tile_y;
  logic [15:0] activation_tile_width;
  logic [15:0] activation_tile_height;
  logic [15:0] activation_channel_offset;
  logic [15:0] activation_channel_count;
  logic [31:0] activation_payload_length;
  logic activation_valid;
  logic activation_ready;
  logic [31:0] activation_data;
  logic [3:0] activation_keep;
  logic activation_last;
  logic router_error;
  logic [7:0] router_error_code;

  logic parameter_load_done;
  logic parameter_error;
  logic [7:0] parameter_error_code;
  logic parameter_request;
  logic [2:0] parameter_layer_id;
  logic parameter_ready;
  logic parameter_release;
  logic parameter_quant_enable;
  logic [4:0] parameter_quant_shift;
  logic signed [31:0] parameter_bias [MAX_COUT];
  logic signed [7:0] weight_mat_data [PK][PC];
  logic [1:0] bank_valid;

  logic [7:0] activation_bytes [0:15];
  int activation_byte_count;
  int activation_start_count;
  int checks;
  int errors;

  packed_dma_packet_parser #(
    .MAX_PAYLOAD_BYTES(1024)
  ) u_parser (
    .clk(clk),
    .rst_n(rst_n),
    .clear(clear),
    .s_axis_tdata(s_axis_tdata),
    .s_axis_tkeep(s_axis_tkeep),
    .s_axis_tvalid(s_axis_tvalid),
    .s_axis_tready(s_axis_tready),
    .s_axis_tlast(s_axis_tlast),
    .packet_start(packet_start),
    .packet_ready(packet_ready),
    .packet_done(),
    .packet_type(packet_type),
    .job_id(packet_job_id),
    .tensor_id(packet_tensor_id),
    .layer_id(packet_layer_id),
    .tile_x(packet_tile_x),
    .tile_y(packet_tile_y),
    .tile_width(packet_tile_width),
    .tile_height(packet_tile_height),
    .channel_offset(packet_channel_offset),
    .channel_count(packet_channel_count),
    .payload_length(packet_payload_length),
    .payload_valid(payload_valid),
    .payload_ready(payload_ready),
    .payload_data(payload_data),
    .payload_keep(payload_keep),
    .payload_last(payload_last),
    .packet_busy(),
    .recovering(),
    .error_valid(parser_error_valid),
    .error_code(parser_error_code),
    .error_count(parser_error_count)
  );

  packed_dma_runtime_router u_router (
    .clk(clk),
    .rst_n(rst_n),
    .clear(clear),
    .packet_start(packet_start),
    .packet_ready(packet_ready),
    .packet_type(packet_type),
    .packet_job_id(packet_job_id),
    .packet_tensor_id(packet_tensor_id),
    .packet_layer_id(packet_layer_id),
    .packet_tile_x(packet_tile_x),
    .packet_tile_y(packet_tile_y),
    .packet_tile_width(packet_tile_width),
    .packet_tile_height(packet_tile_height),
    .packet_channel_offset(packet_channel_offset),
    .packet_channel_count(packet_channel_count),
    .packet_payload_length(packet_payload_length),
    .packet_error_valid(parser_error_valid),
    .payload_valid(payload_valid),
    .payload_ready(payload_ready),
    .payload_data(payload_data),
    .payload_keep(payload_keep),
    .payload_last(payload_last),
    .parameter_config_valid(parameter_config_valid),
    .parameter_config_layer_id(parameter_config_layer_id),
    .parameter_config_kernel_size(parameter_config_kernel_size),
    .parameter_config_cin(parameter_config_cin),
    .parameter_config_cout(parameter_config_cout),
    .parameter_config_bias_enable(parameter_config_bias_enable),
    .parameter_config_quant_enable(parameter_config_quant_enable),
    .parameter_config_quant_shift(parameter_config_quant_shift),
    .parameter_config_weight_bytes(parameter_config_weight_bytes),
    .parameter_config_bias_bytes(parameter_config_bias_bytes),
    .parameter_config_crc32(parameter_config_crc32),
    .parameter_load_start(parameter_load_start),
    .parameter_load_abort(parameter_load_abort),
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
    .activation_packet_start(activation_packet_start),
    .activation_packet_ready(activation_packet_ready),
    .activation_job_id(activation_job_id),
    .activation_tensor_id(activation_tensor_id),
    .activation_layer_id(activation_layer_id),
    .activation_tile_x(activation_tile_x),
    .activation_tile_y(activation_tile_y),
    .activation_tile_width(activation_tile_width),
    .activation_tile_height(activation_tile_height),
    .activation_channel_offset(activation_channel_offset),
    .activation_channel_count(activation_channel_count),
    .activation_payload_length(activation_payload_length),
    .activation_valid(activation_valid),
    .activation_ready(activation_ready),
    .activation_data(activation_data),
    .activation_keep(activation_keep),
    .activation_last(activation_last),
    .error(router_error),
    .error_code(router_error_code)
  );

  cnn_runtime_parameter_banks #(
    .PC(PC),
    .PK(PK),
    .MAX_CIN(MAX_CIN),
    .MAX_COUT(MAX_COUT)
  ) u_parameter_banks (
    .clk(clk),
    .rst_n(rst_n),
    .clear(1'b0),
    .clear_error(clear_parameter_error),
    .load_start(parameter_load_start),
    .load_abort(parameter_load_abort),
    .load_ready(parameter_load_ready),
    .load_layer_id(parameter_load_layer_id),
    .load_kernel_size(parameter_load_kernel_size),
    .load_cin(parameter_load_cin),
    .load_cout(parameter_load_cout),
    .load_bias_enable(parameter_load_bias_enable),
    .load_quant_enable(parameter_load_quant_enable),
    .load_quant_shift(parameter_load_quant_shift),
    .load_weight_bytes(parameter_load_weight_bytes),
    .load_bias_bytes(parameter_load_bias_bytes),
    .load_expected_crc32(parameter_load_expected_crc32),
    .weight_valid(parameter_weight_valid),
    .weight_ready(parameter_weight_ready),
    .weight_data(parameter_weight_data),
    .bias_valid(parameter_bias_valid),
    .bias_ready(parameter_bias_ready),
    .bias_data(parameter_bias_data),
    .load_busy(),
    .load_done(parameter_load_done),
    .error(parameter_error),
    .error_code(parameter_error_code),
    .parameter_request(parameter_request),
    .parameter_layer_id(parameter_layer_id),
    .parameter_ready(parameter_ready),
    .parameter_release(parameter_release),
    .parameter_use_scratchpad_weights(),
    .parameter_quant_enable(parameter_quant_enable),
    .parameter_quant_shift(parameter_quant_shift),
    .parameter_bias(parameter_bias),
    .weight_read_k_base(8'd0),
    .weight_read_c_base(8'd0),
    .weight_read_kernel_idx(4'd0),
    .weight_out_lane_mask(2'b01),
    .weight_in_lane_mask(2'b01),
    .weight_mat_data(weight_mat_data),
    .bank_valid(bank_valid),
    .bank0_layer_id(),
    .bank1_layer_id(),
    .load_bank(),
    .compute_bank(),
    .compute_active(),
    .overlap_active()
  );

  initial begin
    clk = 1'b0;
    forever #5 clk = ~clk;
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      activation_byte_count <= 0;
      activation_start_count <= 0;
    end else begin
      if (activation_packet_start) activation_start_count <= activation_start_count + 1;
      if (activation_valid && activation_ready) begin
        for (int lane = 0; lane < 4; lane++) begin
          if (activation_keep[lane]) begin
            activation_bytes[activation_byte_count + lane] <=
              activation_data[(lane * 8) +: 8];
          end
        end
        activation_byte_count <=
          activation_byte_count + int'(bytes_for_keep(activation_keep));
      end
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
      do begin
        @(posedge clk);
      end while (!s_axis_tready);
      @(negedge clk);
      s_axis_tvalid = 1'b0;
      s_axis_tlast = 1'b0;
      s_axis_tkeep = '0;
      s_axis_tdata = '0;
    end
  endtask

  task automatic send_header(
    input logic [7:0] type_id,
    input int selected_layer_id,
    input int payload_bytes
  );
    begin
      send_beat(DMA_PACKET_MAGIC, 4'hF, 1'b0);
      send_beat({8'd0, 8'(type_id), DMA_PACKET_HEADER_WORDS,
                 DMA_PACKET_VERSION}, 4'hF, 1'b0);
      send_beat(32'd42, 4'hF, 1'b0);
      send_beat({16'(selected_layer_id), 16'd9}, 4'hF, 1'b0);
      send_beat({16'd6, 16'd5}, 4'hF, 1'b0);
      send_beat({16'd8, 16'd7}, 4'hF, 1'b0);
      send_beat({16'd3, 16'd1}, 4'hF, 1'b0);
      send_beat(32'(payload_bytes), 4'hF, 1'b0);
    end
  endtask

  task automatic configure_one_channel_layer(
    input int selected_layer_id,
    input logic bias_enable,
    input int weight_value,
    input int bias_value
  );
    logic [31:0] crc;
    begin
      crc = crc32_byte(32'hFFFF_FFFF, 8'(weight_value));
      if (bias_enable) crc = crc32_word_le(crc, 32'(bias_value));
      parameter_config_layer_id = 3'(selected_layer_id);
      parameter_config_kernel_size = 2'd1;
      parameter_config_cin = 8'd1;
      parameter_config_cout = 8'd1;
      parameter_config_bias_enable = bias_enable;
      parameter_config_quant_enable = 1'b1;
      parameter_config_quant_shift = 5'd2;
      parameter_config_weight_bytes = 16'd1;
      parameter_config_bias_bytes = bias_enable ? 16'd4 : 16'd0;
      parameter_config_crc32 = crc ^ 32'hFFFF_FFFF;
      parameter_config_valid = 1'b1;
    end
  endtask

  task automatic pulse_clear;
    begin
      @(negedge clk);
      clear = 1'b1;
      clear_parameter_error = 1'b1;
      @(negedge clk);
      clear = 1'b0;
      clear_parameter_error = 1'b0;
    end
  endtask

  initial begin
    checks = 0;
    errors = 0;
    rst_n = 1'b0;
    clear = 1'b0;
    clear_parameter_error = 1'b0;
    s_axis_tdata = '0;
    s_axis_tkeep = '0;
    s_axis_tvalid = 1'b0;
    s_axis_tlast = 1'b0;
    parameter_config_valid = 1'b0;
    parameter_config_layer_id = '0;
    parameter_config_kernel_size = '0;
    parameter_config_cin = '0;
    parameter_config_cout = '0;
    parameter_config_bias_enable = 1'b0;
    parameter_config_quant_enable = 1'b0;
    parameter_config_quant_shift = '0;
    parameter_config_weight_bytes = '0;
    parameter_config_bias_bytes = '0;
    parameter_config_crc32 = '0;
    activation_packet_ready = 1'b1;
    activation_ready = 1'b1;
    parameter_request = 1'b0;
    parameter_layer_id = '0;
    parameter_release = 1'b0;

    repeat (4) @(posedge clk);
    rst_n = 1'b1;
    repeat (2) @(posedge clk);

    send_header(DMA_PACKET_INPUT_TILE, 3, 6);
    activation_ready = 1'b0;
    fork
      begin
        send_beat(32'h0403_0201, 4'hF, 1'b0);
      end
      begin
        repeat (3) @(negedge clk);
        check_value("activation elastic capacity", int'(s_axis_tready), 1);
        check_value("activation buffered valid", int'(activation_valid), 1);
        check_value("activation stalled byte count", activation_byte_count, 0);
        check_value("activation buffered data", int'(activation_data),
                    int'(32'h0403_0201));
        activation_ready = 1'b1;
      end
    join
    send_beat(32'h0000_0605, 4'h3, 1'b1);
    repeat (3) @(posedge clk);
    check_value("activation start", activation_start_count, 1);
    check_value("activation job", int'(activation_job_id), 42);
    check_value("activation tensor", int'(activation_tensor_id), 9);
    check_value("activation layer", int'(activation_layer_id), 3);
    check_value("activation x", int'(activation_tile_x), 5);
    check_value("activation y", int'(activation_tile_y), 6);
    check_value("activation width", int'(activation_tile_width), 7);
    check_value("activation height", int'(activation_tile_height), 8);
    check_value("activation channel offset",
                int'(activation_channel_offset), 1);
    check_value("activation channels", int'(activation_channel_count), 3);
    check_value("activation length", int'(activation_payload_length), 6);
    check_value("activation bytes", activation_byte_count, 6);
    for (int index = 0; index < 6; index++) begin
      check_value("activation byte order",
                  int'(activation_bytes[index]), index + 1);
    end

    configure_one_channel_layer(0, 1'b1, 2, 3);
    send_header(DMA_PACKET_LAYER_WEIGHTS, 0, 1);
    send_beat(32'h0000_0002, 4'h1, 1'b1);
    send_header(DMA_PACKET_LAYER_BIASES, 0, 4);
    send_beat(32'h0000_0003, 4'hF, 1'b1);
    wait (parameter_load_done);
    @(negedge clk);
    check_value("parameter load valid", int'(bank_valid), 1);
    check_value("parameter load error", int'(parameter_error), 0);

    parameter_layer_id = 3'd0;
    parameter_request = 1'b1;
    #1;
    check_value("parameter acquire ready", int'(parameter_ready), 1);
    @(negedge clk);
    parameter_request = 1'b0;
    #1;
    check_value("loaded weight",
                int'($signed(weight_mat_data[0][0])), 2);
    check_value("loaded bias", int'(parameter_bias[0]), 3);
    check_value("loaded quant enable", int'(parameter_quant_enable), 1);
    check_value("loaded quant shift", int'(parameter_quant_shift), 2);
    parameter_release = 1'b1;
    @(negedge clk);
    parameter_release = 1'b0;

    pulse_clear();
    configure_one_channel_layer(1, 1'b0, 4, 0);
    send_header(DMA_PACKET_LAYER_WEIGHTS, 1, 2);
    send_beat(32'h0000_0404, 4'h3, 1'b1);
    repeat (3) @(posedge clk);
    check_value("semantic length error", int'(router_error), 1);
    check_value("semantic length code", int'(router_error_code), 3);
    check_value("semantic error did not load", int'(bank_valid), 0);

    pulse_clear();
    configure_one_channel_layer(1, 1'b0, 4, 0);
    send_header(DMA_PACKET_LAYER_WEIGHTS, 1, 1);
    send_beat(32'h0000_0404, 4'h3, 1'b1);
    wait (parameter_load_done);
    @(negedge clk);
    check_value("parser malformed error count",
                int'(parser_error_count), 1);
    check_value("parser malformed code",
                int'(parser_error_code),
                int'(DMA_PACKET_ERROR_PAYLOAD_KEEP));
    check_value("malformed load aborted", int'(parameter_error), 1);
    check_value("malformed load bank invalid", int'(bank_valid), 0);

    pulse_clear();
    configure_one_channel_layer(1, 1'b0, 4, 0);
    send_header(DMA_PACKET_LAYER_WEIGHTS, 1, 1);
    send_beat(32'h0000_0004, 4'h1, 1'b1);
    wait (parameter_load_done);
    @(negedge clk);
    check_value("recovery load valid", int'(bank_valid), 1);
    check_value("recovery load clean", int'(parameter_error), 0);

    if (errors == 0) begin
      $display("[PASS] tb_packed_dma_runtime_router tests=%0d", checks);
    end else begin
      $display("[FAIL] tb_packed_dma_runtime_router errors=%0d tests=%0d",
               errors, checks);
      $fatal(1);
    end
    $finish;
  end
endmodule
