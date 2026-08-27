`timescale 1ns/1ps

module tb_programmable_performance_counters;
  logic clk = 1'b0;
  logic rst_n = 1'b0;
  logic clear = 1'b0;
  logic job_start = 1'b0;
  logic job_done = 1'b0;
  logic job_error = 1'b0;
  logic controller_active = 1'b0;
  logic compute_active = 1'b0;
  logic [2:0] active_layer = '0;
  logic parameter_stall = 1'b0;
  logic input_starved = 1'b0;
  logic input_valid = 1'b0;
  logic input_ready = 1'b0;
  logic [3:0] input_keep = '0;
  logic output_valid = 1'b0;
  logic output_ready = 1'b0;
  logic [3:0] output_keep = '0;
  logic [31:0] saturation_events = '0;
  logic [31:0] completed_layers = '0;
  logic [31:0] completed_tiles = '0;
  logic [4:0] word_index = '0;
  logic [31:0] word_data;

  always #5 clk <= ~clk;

  cnn_programmable_performance_counters dut (.*);

  task automatic check_word(input int index, input int expected);
    begin
      word_index = 5'(index);
      #1;
      if (word_data != 32'(expected))
        $fatal(1, "counter[%0d]=%0d expected=%0d", index, word_data, expected);
    end
  endtask

  initial begin
    repeat (3) @(posedge clk);
    rst_n = 1'b1;
    @(negedge clk);
    job_start = 1'b1;
    @(posedge clk);
    @(negedge clk);
    job_start = 1'b0;
    controller_active = 1'b1;
    compute_active = 1'b1;
    input_valid = 1'b1;
    input_ready = 1'b1;
    input_keep = 4'hF;
    @(posedge clk);
    @(negedge clk);
    active_layer = 3'd1;
    parameter_stall = 1'b1;
    input_starved = 1'b1;
    input_valid = 1'b0;
    input_ready = 1'b0;
    output_valid = 1'b1;
    output_ready = 1'b0;
    @(posedge clk);
    @(negedge clk);
    compute_active = 1'b0;
    parameter_stall = 1'b0;
    input_starved = 1'b0;
    output_ready = 1'b1;
    output_keep = 4'h3;
    saturation_events = 32'd2;
    completed_layers = 32'd2;
    completed_tiles = 32'd5;
    job_done = 1'b1;
    @(posedge clk);
    @(negedge clk);
    job_done = 1'b0;
    controller_active = 1'b0;
    output_valid = 1'b0;

    check_word(0, 3);
    check_word(1, 3);
    check_word(2, 2);
    check_word(3, 1);
    check_word(4, 1);
    check_word(5, 1);
    check_word(6, 4);
    check_word(7, 2);
    check_word(8, 2);
    check_word(9, 2);
    check_word(10, 5);
    check_word(11, 0);
    check_word(16, 1);
    check_word(17, 2);

    clear = 1'b1;
    @(posedge clk);
    @(negedge clk);
    clear = 1'b0;
    check_word(0, 0);
    check_word(16, 0);
    $display("[PASS] programmable performance counters");
    $finish;
  end
endmodule
