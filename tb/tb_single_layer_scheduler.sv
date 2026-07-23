`timescale 1ns/1ps

module tb_single_layer_scheduler;

 localparam int PC = 4;
 localparam int PK = 8;
 localparam int MAX_CIN = 16;
 localparam int MAX_COUT = 16;
 localparam int MAX_PIXELS = 64;
 localparam int DATA_W = 8;
 localparam int ACC_W = 32;
 localparam int OUT_W = 8;

 logic clk;
 logic rst_n;
 logic start;
 logic [15:0] input_width;
 logic [15:0] input_height;
 logic [15:0] output_width;
 logic [15:0] output_height;
 logic [1:0] kernel_size;
 logic [1:0] stride;
 logic [1:0] padding;
 logic [7:0] cin;
 logic [7:0] cout;
 logic bias_enable;
 logic relu_enable;
 logic quant_enable;
 logic [4:0] quant_shift;
 logic signed [DATA_W-1:0] activation [MAX_PIXELS*MAX_CIN];
 logic signed [DATA_W-1:0] weights_1x1 [MAX_COUT][MAX_CIN];
 logic signed [DATA_W-1:0] weights_3x3 [MAX_COUT][MAX_CIN][9];
 logic signed [ACC_W-1:0] bias [MAX_COUT];
 logic use_scratchpad_operands;
 logic scratch_activation_write_enable;
 logic [31:0] scratch_activation_write_pixel;
 logic [7:0] scratch_activation_write_channel;
 logic signed [DATA_W-1:0] scratch_activation_write_data;
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
 logic signed [OUT_W-1:0] output_tensor [MAX_PIXELS*MAX_COUT];
 logic [15:0] current_x;
 logic [15:0] current_y;
 logic busy;
 logic done;

 int tests;

 single_layer_scheduler #(
 .PC(PC),
 .PK(PK),
 .MAX_CIN(MAX_CIN),
 .MAX_COUT(MAX_COUT),
 .MAX_PIXELS(MAX_PIXELS),
 .DATA_W(DATA_W),
 .ACC_W(ACC_W),
 .BIAS_W(ACC_W),
 .OUT_W(OUT_W)
 ) dut (
 .clk(clk),
 .rst_n(rst_n),
 .start(start),
 .input_width(input_width),
 .input_height(input_height),
 .output_width(output_width),
 .output_height(output_height),
 .kernel_size(kernel_size),
 .stride(stride),
 .padding(padding),
 .cin(cin),
 .cout(cout),
 .bias_enable(bias_enable),
 .relu_enable(relu_enable),
 .quant_enable(quant_enable),
 .quant_shift(quant_shift),
 .activation(activation),
 .weights_1x1(weights_1x1),
 .weights_3x3(weights_3x3),
 .bias(bias),
 .use_scratchpad_operands(use_scratchpad_operands),
 .use_scratchpad_weights(use_scratchpad_operands),
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
 .output_tensor(output_tensor),
 .output_pixel_valid(),
 .output_pixel_ready(1'b1),
 .output_pixel_index(),
 .output_pixel_channels(),
 .output_pixel_data(),
 .output_pixel_last(),
 .current_x(current_x),
 .current_y(current_y),
 .busy(busy),
 .done(done)
 );

 banked_activation_scratchpad #(
 .PC(PC),
 .MAX_PIXELS(MAX_PIXELS),
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

 function automatic logic signed [DATA_W-1:0] activation_at(input int y, input int x, input int ci);
 int idx;
 begin
 if ((x < 0) || (y < 0) || (x >= input_width) || (y >= input_height)) begin
 return '0;
 end

 idx = ((y * input_width) + x) * MAX_CIN + ci;
 return activation[idx];
 end
 endfunction

 function automatic logic signed [OUT_W-1:0] expected_output(input int ox, input int oy, input int co);
 logic signed [ACC_W-1:0] acc;
 int in_x;
 int in_y;
 int k;
 begin
 acc = '0;

 if (kernel_size == 2'd1) begin
 in_x = ox * stride;
 in_y = oy * stride;
 for (int ci = 0; ci < cin; ci++) begin
 acc += $signed(activation_at(in_y, in_x, ci)) * $signed(weights_1x1[co][ci]);
 end
 end else begin
 for (int ky = 0; ky < 3; ky++) begin
 for (int kx = 0; kx < 3; kx++) begin
 in_x = (ox * stride) + kx - padding;
 in_y = (oy * stride) + ky - padding;
 k = ky * 3 + kx;

 for (int ci = 0; ci < cin; ci++) begin
 acc += $signed(activation_at(in_y, in_x, ci)) * $signed(weights_3x3[co][ci][k]);
 end
 end
 end
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
 for (int i = 0; i < MAX_PIXELS*MAX_CIN; i++) begin
 activation[i] = '0;
 end

 for (int co = 0; co < MAX_COUT; co++) begin
 bias[co] = '0;

 for (int ci = 0; ci < MAX_CIN; ci++) begin
 weights_1x1[co][ci] = '0;

 for (int k = 0; k < 9; k++) begin
 weights_3x3[co][ci][k] = '0;
 end
 end
 end
 end
 endtask

 task automatic fill_inputs(input int case_cin, input int case_cout);
 int idx;
 begin
 for (int y = 0; y < input_height; y++) begin
 for (int x = 0; x < input_width; x++) begin
 for (int ci = 0; ci < MAX_CIN; ci++) begin
 idx = ((y * input_width) + x) * MAX_CIN + ci;
 activation[idx] = $signed(((y * 7) + (x * 5) + (ci * 3) + case_cin) % 23) - 8'sd11;
 end
 end
 end

 for (int co = 0; co < MAX_COUT; co++) begin
 bias[co] = (co % 5) - 2;

 for (int ci = 0; ci < MAX_CIN; ci++) begin
 weights_1x1[co][ci] = $signed(((co * 3) + (ci * 5) + case_cout) % 13) - 8'sd6;

 for (int k = 0; k < 9; k++) begin
 weights_3x3[co][ci][k] =
 $signed(((co * 2) + (ci * 3) + (k * 5) + case_cin) % 17) - 8'sd8;
 end
 end
 end
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

 task automatic load_active_scratchpads(input int case_cin, input int case_cout);
 int pixel;
 begin
 for (int y = 0; y < input_height; y++) begin
 for (int x = 0; x < input_width; x++) begin
 pixel = (y * input_width) + x;
 for (int ci = 0; ci < case_cin; ci++) begin
 scratch_write_activation(pixel, ci, activation[(pixel * MAX_CIN) + ci]);
 end
 end
 end

 for (int co = 0; co < case_cout; co++) begin
 for (int ci = 0; ci < case_cin; ci++) begin
 if (kernel_size == 2'd1) begin
 scratch_write_weight(co, ci, 0, weights_1x1[co][ci]);
 end else begin
 for (int k = 0; k < 9; k++) begin
 scratch_write_weight(co, ci, k, weights_3x3[co][ci][k]);
 end
 end
 end
 end
 end
 endtask

 task automatic run_case(
 input string name,
 input int case_kernel_size,
 input int in_w,
 input int in_h,
 input int out_w,
 input int out_h,
 input int case_stride,
 input int case_padding,
 input int case_cin,
 input int case_cout
 );
 logic signed [OUT_W-1:0] expected;
 int timeout;
 int out_idx;
 begin
 input_width = in_w[15:0];
 input_height = in_h[15:0];
 output_width = out_w[15:0];
 output_height = out_h[15:0];
 kernel_size = case_kernel_size[1:0];
 stride = case_stride[1:0];
 padding = case_padding[1:0];
 cin = case_cin[7:0];
 cout = case_cout[7:0];

 fill_inputs(case_cin, case_cout);

 use_scratchpad_operands = 1'b0;
 @(negedge clk);
 start = 1'b1;
 @(posedge clk);
 @(negedge clk);
 start = 1'b0;

 timeout = 0;
 while (!done && (timeout < 20000)) begin
 @(posedge clk);
 timeout++;
 end

 if (!done) begin
 $display("[FAIL] %s: timed out waiting for done", name);
 $finish;
 end

 for (int oy = 0; oy < out_h; oy++) begin
 for (int ox = 0; ox < out_w; ox++) begin
 for (int co = 0; co < case_cout; co++) begin
 expected = expected_output(ox, oy, co);
 out_idx = ((oy * out_w) + ox) * MAX_COUT + co;

 if (output_tensor[out_idx] !== expected) begin
 $display("[FAIL] %s: pixel=(%0d,%0d) co=%0d expected=%0d got=%0d",
 name, ox, oy, co, expected, output_tensor[out_idx]);
 $finish;
 end
 end
 end
 end

 tests++;
 @(posedge clk);
 end
 endtask

 task automatic run_scratchpad_case(
 input string name,
 input int case_kernel_size,
 input int in_w,
 input int in_h,
 input int out_w,
 input int out_h,
 input int case_stride,
 input int case_padding,
 input int case_cin,
 input int case_cout
 );
 logic signed [OUT_W-1:0] expected;
 int timeout;
 int out_idx;
 begin
 input_width = in_w[15:0];
 input_height = in_h[15:0];
 output_width = out_w[15:0];
 output_height = out_h[15:0];
 kernel_size = case_kernel_size[1:0];
 stride = case_stride[1:0];
 padding = case_padding[1:0];
 cin = case_cin[7:0];
 cout = case_cout[7:0];

 fill_inputs(case_cin, case_cout);
 load_active_scratchpads(case_cin, case_cout);

 use_scratchpad_operands = 1'b1;
 @(negedge clk);
 start = 1'b1;
 @(posedge clk);
 @(negedge clk);
 start = 1'b0;

 timeout = 0;
 while (!done && (timeout < 20000)) begin
 @(posedge clk);
 timeout++;
 end

 if (!done) begin
 $display("[FAIL] %s: timed out waiting for done", name);
 $finish;
 end

 for (int oy = 0; oy < out_h; oy++) begin
 for (int ox = 0; ox < out_w; ox++) begin
 for (int co = 0; co < case_cout; co++) begin
 expected = expected_output(ox, oy, co);
 out_idx = ((oy * out_w) + ox) * MAX_COUT + co;

 if (output_tensor[out_idx] !== expected) begin
 $display("[FAIL] %s: pixel=(%0d,%0d) co=%0d expected=%0d got=%0d",
 name, ox, oy, co, expected, output_tensor[out_idx]);
 $finish;
 end
 end
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
 input_width = '0;
 input_height = '0;
 output_width = '0;
 output_height = '0;
 kernel_size = 2'd3;
 stride = 2'd1;
 padding = 2'd1;
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

 run_case("full_image_1x1_cin3_cout5", 1, 4, 3, 4, 3, 1, 0, 3, 5);
 run_case("full_image_3x3_cin7_cout13", 3, 5, 4, 5, 4, 1, 1, 7, 13);
 run_scratchpad_case("scratchpad_full_image_1x1_cin3_cout5", 1, 4, 3, 4, 3, 1, 0, 3, 5);
 run_scratchpad_case("scratchpad_full_image_3x3_cin7_cout13", 3, 5, 4, 5, 4, 1, 1, 7, 13);

 $display("[PASS] tb_single_layer_scheduler tests=%0d", tests);
 $finish;
 end

endmodule
