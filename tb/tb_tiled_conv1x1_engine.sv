`timescale 1ns/1ps

module tb_tiled_conv1x1_engine;

 localparam int PC = 4;
 localparam int PK = 8;
 localparam int MAX_CIN = 64;
 localparam int MAX_COUT = 64;
 localparam int DATA_W = 8;
 localparam int ACC_W = 32;
 localparam int OUT_W = 8;

 logic clk;
 logic rst_n;
 logic start;
 logic [7:0] cin;
 logic [7:0] cout;
 logic bias_enable;
 logic relu_enable;
 logic quant_enable;
 logic [4:0] quant_shift;

 logic signed [DATA_W-1:0] activation [MAX_CIN];
 logic signed [DATA_W-1:0] weights [MAX_COUT][MAX_CIN];
 logic signed [ACC_W-1:0] bias [MAX_COUT];
 logic use_scratchpad_operands;
 logic scratch_activation_write_enable;
 logic [31:0] scratch_activation_write_pixel;
 logic [7:0] scratch_activation_write_channel;
 logic signed [DATA_W-1:0] scratch_activation_write_data;
 logic [31:0] scratch_activation_pixel;
 logic [31:0] scratch_activation_read_pixel;
 logic [7:0] scratch_activation_read_c_base;
 logic [PC-1:0] scratch_activation_lane_mask;
 logic signed [DATA_W-1:0] scratch_activation_lane_data [PC];
 logic scratch_weight_write_enable;
 logic [7:0] scratch_weight_write_out_channel;
 logic [7:0] scratch_weight_write_in_channel;
 logic [3:0] scratch_weight_write_kernel_idx;
 logic signed [DATA_W-1:0] scratch_weight_write_data;
 logic [7:0] scratch_weight_read_k_base;
 logic [7:0] scratch_weight_read_c_base;
 logic [3:0] scratch_weight_read_kernel_idx;
 logic [PK-1:0] scratch_weight_out_lane_mask;
 logic [PC-1:0] scratch_weight_in_lane_mask;
 logic signed [DATA_W-1:0] scratch_weight_mat_data [PK][PC];
 logic signed [OUT_W-1:0] output_data [MAX_COUT];
 logic busy;
 logic done;

 int tests;

 tiled_conv1x1_engine #(
 .PC(PC),
 .PK(PK),
 .MAX_CIN(MAX_CIN),
 .MAX_COUT(MAX_COUT),
 .DATA_W(DATA_W),
 .ACC_W(ACC_W),
 .BIAS_W(ACC_W),
 .OUT_W(OUT_W)
 ) dut (
 .clk(clk),
 .rst_n(rst_n),
 .start(start),
 .cin(cin),
 .cout(cout),
 .bias_enable(bias_enable),
 .relu_enable(relu_enable),
 .quant_enable(quant_enable),
 .quant_shift(quant_shift),
 .activation(activation),
 .weights(weights),
 .bias(bias),
 .use_scratchpad_operands(use_scratchpad_operands),
 .use_scratchpad_weights(use_scratchpad_operands),
 .scratch_activation_pixel(scratch_activation_pixel),
 .scratch_activation_read_pixel(scratch_activation_read_pixel),
 .scratch_activation_read_c_base(scratch_activation_read_c_base),
 .scratch_activation_lane_mask(scratch_activation_lane_mask),
 .scratch_activation_lane_data(scratch_activation_lane_data),
 .scratch_weight_read_k_base(scratch_weight_read_k_base),
 .scratch_weight_read_c_base(scratch_weight_read_c_base),
 .scratch_weight_read_kernel_idx(scratch_weight_read_kernel_idx),
 .scratch_weight_out_lane_mask(scratch_weight_out_lane_mask),
 .scratch_weight_in_lane_mask(scratch_weight_in_lane_mask),
 .scratch_weight_mat_data(scratch_weight_mat_data),
 .output_data(output_data),
 .busy(busy),
 .done(done)
 );

 banked_activation_scratchpad #(
 .PC(PC),
 .MAX_PIXELS(4),
 .MAX_C(MAX_CIN),
 .DATA_W(DATA_W)
 ) u_activation_scratchpad (
 .clk(clk),
 .write_enable(scratch_activation_write_enable),
 .write_pixel(scratch_activation_write_pixel),
 .write_channel(scratch_activation_write_channel),
 .write_data(scratch_activation_write_data),
 .read_pixel(scratch_activation_read_pixel),
 .read_c_base(scratch_activation_read_c_base),
 .lane_mask(scratch_activation_lane_mask),
 .lane_data(scratch_activation_lane_data),
 .debug_read_pixel('0),
 .debug_read_channel('0),
 .debug_read_data()
 );

 banked_weight_scratchpad #(
 .PC(PC),
 .PK(PK),
 .MAX_CIN(MAX_CIN),
 .MAX_COUT(MAX_COUT),
 .DATA_W(DATA_W)
 ) u_weight_scratchpad (
 .clk(clk),
 .write_enable(scratch_weight_write_enable),
 .write_out_channel(scratch_weight_write_out_channel),
 .write_in_channel(scratch_weight_write_in_channel),
 .write_kernel_idx(scratch_weight_write_kernel_idx),
 .write_data(scratch_weight_write_data),
 .read_k_base(scratch_weight_read_k_base),
 .read_c_base(scratch_weight_read_c_base),
 .read_kernel_idx(scratch_weight_read_kernel_idx),
 .out_lane_mask(scratch_weight_out_lane_mask),
 .in_lane_mask(scratch_weight_in_lane_mask),
 .weight_mat(scratch_weight_mat_data),
 .debug_out_channel('0),
 .debug_in_channel('0),
 .debug_kernel_idx('0),
 .debug_read_data()
 );

 initial begin
 clk = 1'b0;
 forever #5 clk = ~clk;
 end

 function automatic logic signed [OUT_W-1:0] sat8(input logic signed [ACC_W-1:0] value);
 begin
 if (value > 32'sd127) begin
 return 8'sd127;
 end else if (value < -32'sd128) begin
 return -8'sd128;
 end else begin
 return value[OUT_W-1:0];
 end
 end
 endfunction

 function automatic logic signed [OUT_W-1:0] expected_output(input int co);
 logic signed [ACC_W-1:0] acc;
 begin
 acc = '0;

 for (int ci = 0; ci < cin; ci++) begin
 acc += $signed(activation[ci]) * $signed(weights[co][ci]);
 end

 if (bias_enable) begin
 acc += bias[co];
 end

 if (relu_enable && (acc < 0)) begin
 acc = '0;
 end

 if (quant_enable) begin
 acc = acc >>> quant_shift;
 end

 return sat8(acc);
 end
 endfunction

 task automatic clear_inputs;
 begin
 for (int ci = 0; ci < MAX_CIN; ci++) begin
 activation[ci] = '0;
 end

 for (int co = 0; co < MAX_COUT; co++) begin
 bias[co] = '0;

 for (int ci = 0; ci < MAX_CIN; ci++) begin
 weights[co][ci] = '0;
 end
 end
 end
 endtask

 task automatic run_case(input string name, input int case_cin, input int case_cout);
 logic signed [OUT_W-1:0] expected [MAX_COUT];
 int timeout;
 begin
 cin = case_cin[7:0];
 cout = case_cout[7:0];

 for (int ci = 0; ci < MAX_CIN; ci++) begin
 activation[ci] = $signed(((ci * 7) + case_cin) % 17) - 8'sd8;
 end

 for (int co = 0; co < MAX_COUT; co++) begin
 bias[co] = (co % 5) - 2;

 for (int ci = 0; ci < MAX_CIN; ci++) begin
 weights[co][ci] = $signed(((co * 3) + (ci * 5) + 1) % 9) - 8'sd4;
 end
 end

 for (int co = 0; co < case_cout; co++) begin
 expected[co] = expected_output(co);
 end

 @(negedge clk);
 start = 1'b1;
 @(posedge clk);
 @(negedge clk);
 start = 1'b0;

 timeout = 0;
 while (!done && (timeout < 1000)) begin
 @(posedge clk);
 timeout++;
 end

 if (!done) begin
 $display("[FAIL] %s: timed out waiting for done", name);
 $finish;
 end

 for (int co = 0; co < case_cout; co++) begin
 if (output_data[co] !== expected[co]) begin
 $display("[FAIL] %s: output[%0d] expected=%0d got=%0d",
 name, co, expected[co], output_data[co]);
 $finish;
 end
 end

 tests++;
 @(posedge clk);
 end
 endtask

 task automatic scratch_write_activation(
 input int pixel,
 input int channel,
 input logic signed [DATA_W-1:0] data
 );
 begin
 @(negedge clk);
 scratch_activation_write_pixel = pixel[31:0];
 scratch_activation_write_channel = channel[7:0];
 scratch_activation_write_data = data;
 scratch_activation_write_enable = 1'b1;
 @(posedge clk);
 @(negedge clk);
 scratch_activation_write_enable = 1'b0;
 end
 endtask

 task automatic scratch_write_weight(
 input int out_channel,
 input int in_channel,
 input int kernel_idx,
 input logic signed [DATA_W-1:0] data
 );
 begin
 @(negedge clk);
 scratch_weight_write_out_channel = out_channel[7:0];
 scratch_weight_write_in_channel = in_channel[7:0];
 scratch_weight_write_kernel_idx = kernel_idx[3:0];
 scratch_weight_write_data = data;
 scratch_weight_write_enable = 1'b1;
 @(posedge clk);
 @(negedge clk);
 scratch_weight_write_enable = 1'b0;
 end
 endtask

 task automatic run_scratchpad_case(input string name, input int case_cin, input int case_cout);
 logic signed [OUT_W-1:0] expected [MAX_COUT];
 int timeout;
 begin
 cin = case_cin[7:0];
 cout = case_cout[7:0];
 scratch_activation_pixel = 32'd2;

 for (int ci = 0; ci < MAX_CIN; ci++) begin
 activation[ci] = $signed(((ci * 11) + case_cin) % 23) - 8'sd11;
 if (ci < case_cin) begin
 scratch_write_activation(scratch_activation_pixel, ci, activation[ci]);
 end
 end

 for (int co = 0; co < MAX_COUT; co++) begin
 bias[co] = (co % 5) - 2;

 for (int ci = 0; ci < MAX_CIN; ci++) begin
 weights[co][ci] = $signed(((co * 7) + (ci * 3) + 2) % 13) - 8'sd6;
 if ((co < case_cout) && (ci < case_cin)) begin
 scratch_write_weight(co, ci, 0, weights[co][ci]);
 end
 end
 end

 for (int co = 0; co < case_cout; co++) begin
 expected[co] = expected_output(co);
 end

 use_scratchpad_operands = 1'b1;
 @(negedge clk);
 start = 1'b1;
 @(posedge clk);
 @(negedge clk);
 start = 1'b0;

 timeout = 0;
 while (!done && (timeout < 1000)) begin
 @(posedge clk);
 timeout++;
 end

 if (!done) begin
 $display("[FAIL] %s: timed out waiting for done", name);
 $finish;
 end

 for (int co = 0; co < case_cout; co++) begin
 if (output_data[co] !== expected[co]) begin
 $display("[FAIL] %s: output[%0d] expected=%0d got=%0d",
 name, co, expected[co], output_data[co]);
 $finish;
 end
 end

 use_scratchpad_operands = 1'b0;
 tests++;
 @(posedge clk);
 end
 endtask

 initial begin
 rst_n = 1'b0;
 start = 1'b0;
 use_scratchpad_operands = 1'b0;
 scratch_activation_write_enable = 1'b0;
 scratch_activation_write_pixel = '0;
 scratch_activation_write_channel = '0;
 scratch_activation_write_data = '0;
 scratch_weight_write_enable = 1'b0;
 scratch_weight_write_out_channel = '0;
 scratch_weight_write_in_channel = '0;
 scratch_weight_write_kernel_idx = '0;
 scratch_weight_write_data = '0;
 scratch_activation_pixel = '0;
 cin = '0;
 cout = '0;
 bias_enable = 1'b1;
 relu_enable = 1'b1;
 quant_enable = 1'b1;
 quant_shift = 5'd1;
 tests = 0;

 clear_inputs();

 repeat (3) @(posedge clk);
 rst_n = 1'b1;
 @(posedge clk);

 run_case("cin3_cout3_tail_both", 3, 3);
 run_case("cin7_cout13_tail_both", 7, 13);
 run_case("cin16_cout16_aligned", 16, 16);
 run_case("cin30_cout19_tail_both", 30, 19);

 relu_enable = 1'b0;
 quant_shift = 5'd0;
 run_case("cin15_cout31_no_relu_no_shift", 15, 31);

 bias_enable = 1'b1;
 relu_enable = 1'b1;
 quant_enable = 1'b1;
 quant_shift = 5'd1;
 run_scratchpad_case("scratchpad_cin7_cout13_tail_both", 7, 13);

 $display("[PASS] tb_tiled_conv1x1_engine tests=%0d", tests);
 $finish;
 end

endmodule
