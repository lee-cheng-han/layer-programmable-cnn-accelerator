`timescale 1ns/1ps

module tb_parallel_requantizer;
  localparam int PK = 8;

  logic clk;
  logic rst_n;
  logic valid_in;
  logic signed [31:0] acc_in [PK];
  logic signed [31:0] quant_multiplier [PK];
  logic [5:0] quant_shift [PK];
  logic signed [7:0] output_zero_point [PK];
  logic [PK-1:0] lane_mask;
  logic signed [7:0] out_vec [PK];
  logic [PK-1:0] saturation_positive;
  logic [PK-1:0] saturation_negative;
  logic valid_out;
  int tests;

  parallel_requantizer #(.PK(PK)) dut (
    .clk(clk),
    .rst_n(rst_n),
    .valid_in(valid_in),
    .acc_in(acc_in),
    .quant_multiplier(quant_multiplier),
    .quant_shift(quant_shift),
    .output_zero_point(output_zero_point),
    .lane_mask(lane_mask),
    .out_vec(out_vec),
    .saturation_positive(saturation_positive),
    .saturation_negative(saturation_negative),
    .valid_out(valid_out)
  );

  always #5 clk = ~clk;

  task automatic expect_lane(
    input int lane,
    input int expected,
    input logic expected_positive,
    input logic expected_negative
  );
    begin
      tests++;
      if ((int'($signed(out_vec[lane])) !== expected) ||
          (saturation_positive[lane] !== expected_positive) ||
          (saturation_negative[lane] !== expected_negative)) begin
        $fatal(1, "[FAIL] lane=%0d got=%0d pos=%0b neg=%0b expected=%0d/%0b/%0b",
               lane, $signed(out_vec[lane]), saturation_positive[lane],
               saturation_negative[lane], expected, expected_positive,
               expected_negative);
      end
    end
  endtask

  initial begin
    tests = 0;
    clk = 1'b0;
    rst_n = 1'b0;
    valid_in = 1'b0;
    lane_mask = '1;
    for (int lane = 0; lane < PK; lane++) begin
      acc_in[lane] = '0;
      quant_multiplier[lane] = 32'sd1;
      quant_shift[lane] = 6'd0;
      output_zero_point[lane] = '0;
    end

    acc_in[0] = 32'sd1;  quant_shift[0] = 6'd1;
    acc_in[1] = 32'sd3;  quant_shift[1] = 6'd1;
    acc_in[2] = 32'sd5;  quant_shift[2] = 6'd1;
    acc_in[3] = -32'sd1; quant_shift[3] = 6'd1;
    acc_in[4] = -32'sd3; quant_shift[4] = 6'd1;
    acc_in[5] = -32'sd5; quant_shift[5] = 6'd1;
    acc_in[6] = 32'sd100; quant_multiplier[6] = 32'sd3; quant_shift[6] = 6'd1;
    acc_in[7] = -32'sd100; quant_multiplier[7] = 32'sd3; quant_shift[7] = 6'd1;
    repeat (2) @(posedge clk);
    rst_n = 1'b1;
    @(negedge clk);
    valid_in = 1'b1;
    @(posedge clk);
    @(negedge clk);
    valid_in = 1'b0;
    @(posedge valid_out);
    #1;
    if (!valid_out) $fatal(1, "[FAIL] missing valid_out");

    expect_lane(0, 0, 0, 0);
    expect_lane(1, 2, 0, 0);
    expect_lane(2, 2, 0, 0);
    expect_lane(3, 0, 0, 0);
    expect_lane(4, -2, 0, 0);
    expect_lane(5, -2, 0, 0);
    expect_lane(6, 127, 1, 0);
    expect_lane(7, -128, 0, 1);

    lane_mask[2] = 1'b0;
    @(negedge clk);
    valid_in = 1'b1;
    @(posedge clk);
    @(negedge clk);
    valid_in = 1'b0;
    @(posedge valid_out);
    #1;
    expect_lane(2, 0, 0, 0);

    $display("[PASS] tb_parallel_requantizer tests=%0d", tests);
    $finish;
  end
endmodule
