`timescale 1ns/1ps

module tb_golden_tensor_flow;

 localparam int PC = 4;
 localparam int PK = 8;
 localparam int MAX_CIN = 16;
 localparam int MAX_COUT = 16;
 localparam int MAX_PIXELS = 64;
 localparam int DATA_W = 8;
 localparam int ACC_W = 32;
 localparam int OUT_W = 8;
 localparam int CFG_WORDS = 13;

 localparam int CFG_INPUT_WIDTH = 0;
 localparam int CFG_INPUT_HEIGHT = 1;
 localparam int CFG_OUTPUT_WIDTH = 2;
 localparam int CFG_OUTPUT_HEIGHT = 3;
 localparam int CFG_KERNEL_SIZE = 4;
 localparam int CFG_STRIDE = 5;
 localparam int CFG_PADDING = 6;
 localparam int CFG_CIN = 7;
 localparam int CFG_COUT = 8;
 localparam int CFG_BIAS_ENABLE = 9;
 localparam int CFG_RELU_ENABLE = 10;
 localparam int CFG_QUANT_ENABLE = 11;
 localparam int CFG_QUANT_SHIFT = 12;

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
 logic signed [OUT_W-1:0] output_tensor [MAX_PIXELS*MAX_COUT];
 logic [15:0] current_x;
 logic [15:0] current_y;
 logic busy;
 logic done;
 logic signed [DATA_W-1:0] scratch_activation_lane_data_zero [PC];
 logic signed [DATA_W-1:0] scratch_weight_mat_data_zero [PK][PC];

 logic [31:0] cfg_mem [CFG_WORDS];
 logic signed [DATA_W-1:0] activation_mem [MAX_PIXELS*MAX_CIN];
 logic signed [DATA_W-1:0] weights_1x1_mem [MAX_COUT*MAX_CIN];
 logic signed [DATA_W-1:0] weights_3x3_mem [MAX_COUT*MAX_CIN*9];
 logic signed [ACC_W-1:0] bias_mem [MAX_COUT];
 logic signed [OUT_W-1:0] expected_mem [MAX_PIXELS*MAX_COUT];

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
 .use_scratchpad_operands(1'b0),
 .use_scratchpad_weights(1'b0),
 .scratch_activation_read_pixel(),
 .scratch_activation_read_c_base(),
 .scratch_activation_lane_mask(),
 .scratch_activation_lane_data(scratch_activation_lane_data_zero),
 .scratch_weight_read_k_base(),
 .scratch_weight_read_c_base(),
 .scratch_weight_read_kernel_idx(),
 .scratch_weight_out_lane_mask(),
 .scratch_weight_in_lane_mask(),
 .scratch_weight_mat_data(scratch_weight_mat_data_zero),
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

 initial begin
 clk = 1'b0;
 forever #5 clk = ~clk;
 end

 always_comb begin
 for (int pc = 0; pc < PC; pc++) begin
 scratch_activation_lane_data_zero[pc] = '0;
 end

 for (int pk = 0; pk < PK; pk++) begin
 for (int pc = 0; pc < PC; pc++) begin
 scratch_weight_mat_data_zero[pk][pc] = '0;
 end
 end
 end

 function automatic string file_in_dir(input string dir, input string name);
 begin
 return {dir, "/", name};
 end
 endfunction

 task automatic clear_arrays;
 begin
 for (int i = 0; i < CFG_WORDS; i++) begin
 cfg_mem[i] = '0;
 end

 for (int i = 0; i < MAX_PIXELS*MAX_CIN; i++) begin
 activation_mem[i] = '0;
 activation[i] = '0;
 end

 for (int i = 0; i < MAX_COUT*MAX_CIN; i++) begin
 weights_1x1_mem[i] = '0;
 end

 for (int i = 0; i < MAX_COUT*MAX_CIN*9; i++) begin
 weights_3x3_mem[i] = '0;
 end

 for (int i = 0; i < MAX_COUT; i++) begin
 bias_mem[i] = '0;
 bias[i] = '0;
 end

 for (int i = 0; i < MAX_PIXELS*MAX_COUT; i++) begin
 expected_mem[i] = '0;
 end

 for (int co = 0; co < MAX_COUT; co++) begin
 for (int ci = 0; ci < MAX_CIN; ci++) begin
 weights_1x1[co][ci] = '0;

 for (int k = 0; k < 9; k++) begin
 weights_3x3[co][ci][k] = '0;
 end
 end
 end
 end
 endtask

 task automatic load_case(input string case_dir);
 begin
 clear_arrays();

 $readmemh(file_in_dir(case_dir, "config.mem"), cfg_mem);
 $readmemh(file_in_dir(case_dir, "activation.mem"), activation_mem);
 $readmemh(file_in_dir(case_dir, "weights_1x1.mem"), weights_1x1_mem);
 $readmemh(file_in_dir(case_dir, "weights_3x3.mem"), weights_3x3_mem);
 $readmemh(file_in_dir(case_dir, "bias.mem"), bias_mem);
 $readmemh(file_in_dir(case_dir, "expected.mem"), expected_mem);

 input_width = cfg_mem[CFG_INPUT_WIDTH][15:0];
 input_height = cfg_mem[CFG_INPUT_HEIGHT][15:0];
 output_width = cfg_mem[CFG_OUTPUT_WIDTH][15:0];
 output_height = cfg_mem[CFG_OUTPUT_HEIGHT][15:0];
 kernel_size = cfg_mem[CFG_KERNEL_SIZE][1:0];
 stride = cfg_mem[CFG_STRIDE][1:0];
 padding = cfg_mem[CFG_PADDING][1:0];
 cin = cfg_mem[CFG_CIN][7:0];
 cout = cfg_mem[CFG_COUT][7:0];
 bias_enable = cfg_mem[CFG_BIAS_ENABLE][0];
 relu_enable = cfg_mem[CFG_RELU_ENABLE][0];
 quant_enable = cfg_mem[CFG_QUANT_ENABLE][0];
 quant_shift = cfg_mem[CFG_QUANT_SHIFT][4:0];

 for (int i = 0; i < MAX_PIXELS*MAX_CIN; i++) begin
 activation[i] = activation_mem[i];
 end

 for (int co = 0; co < MAX_COUT; co++) begin
 bias[co] = bias_mem[co];

 for (int ci = 0; ci < MAX_CIN; ci++) begin
 weights_1x1[co][ci] = weights_1x1_mem[(co * MAX_CIN) + ci];

 for (int k = 0; k < 9; k++) begin
 weights_3x3[co][ci][k] = weights_3x3_mem[((co * MAX_CIN + ci) * 9) + k];
 end
 end
 end
 end
 endtask

 task automatic run_case(input string name, input string case_dir);
 int timeout;
 int out_idx;
 begin
 $display("[TEST] %s", name);
 load_case(case_dir);

 start = 1'b1;
 @(posedge clk);
 start = 1'b0;

 timeout = 0;
 while (!done && (timeout < 30000)) begin
 @(posedge clk);
 timeout++;
 end

 if (!done) begin
 $display("[FAIL] %s: timed out waiting for done", name);
 $finish;
 end

 for (int oy = 0; oy < output_height; oy++) begin
 for (int ox = 0; ox < output_width; ox++) begin
 for (int co = 0; co < cout; co++) begin
 out_idx = ((oy * output_width) + ox) * MAX_COUT + co;

 if (output_tensor[out_idx] !== expected_mem[out_idx]) begin
 $display("[FAIL] %s: pixel=(%0d,%0d) co=%0d expected=%0d got=%0d",
 name, ox, oy, co, expected_mem[out_idx], output_tensor[out_idx]);
 $finish;
 end
 end
 end
 end

 tests++;
 @(posedge clk);
 end
 endtask

 initial begin
 rst_n = 1'b0;
 start = 1'b0;
 input_width = '0;
 input_height = '0;
 output_width = '0;
 output_height = '0;
 kernel_size = '0;
 stride = '0;
 padding = '0;
 cin = '0;
 cout = '0;
 bias_enable = 1'b0;
 relu_enable = 1'b0;
 quant_enable = 1'b0;
 quant_shift = '0;
 tests = 0;

 clear_arrays();

 repeat (3) @(posedge clk);
 rst_n = 1'b1;
 @(posedge clk);

 run_case("python_golden_single_layer_1x1", "../../build/golden/single_layer_1x1");
 run_case("python_golden_single_layer_3x3", "../../build/golden/single_layer_3x3");

 $display("[PASS] tb_golden_tensor_flow tests=%0d", tests);
 $finish;
 end

endmodule
