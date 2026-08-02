`timescale 1ns/1ps

module tb_ping_pong_buffers;

 localparam int PC = 4;
 localparam int PK = 8;
 localparam int MAX_PIXELS = 8;
 localparam int MAX_CIN = 8;
 localparam int MAX_COUT = 8;
 localparam int DATA_W = 8;

 logic clk;
 logic rst_n;
 logic load_start;
 logic load_done;
 logic compute_start;
 logic compute_done;
 logic clear_error;
 logic load_ready;
 logic compute_ready;
 logic load_bank;
 logic compute_bank;
 logic [1:0] bank_valid;
 logic load_active;
 logic compute_active;
 logic overlap_active;
 logic error;

 logic act_write_enable;
 logic [31:0] act_write_pixel;
 logic [7:0] act_write_channel;
 logic signed [DATA_W-1:0] act_write_data;
 logic [31:0] act_read_pixel;
 logic [7:0] act_read_c_base;
 logic [PC-1:0] act_lane_mask;
 logic signed [DATA_W-1:0] act_lane_data [PC];
 logic act_debug_bank;
 logic signed [DATA_W-1:0] act_debug_data;

 logic weight_write_enable;
 logic [7:0] weight_write_out_channel;
 logic [7:0] weight_write_in_channel;
 logic [3:0] weight_write_kernel_idx;
 logic signed [DATA_W-1:0] weight_write_data;
 logic [7:0] weight_read_k_base;
 logic [7:0] weight_read_c_base;
 logic [3:0] weight_read_kernel_idx;
 logic [PK-1:0] weight_out_lane_mask;
 logic [PC-1:0] weight_in_lane_mask;
 logic signed [DATA_W-1:0] weight_mat [PK][PC];
 logic weight_debug_bank;
 logic signed [DATA_W-1:0] weight_debug_data;

 int tests;

 ping_pong_bank_controller u_ping_pong_bank_controller (
 .clk(clk),
 .rst_n(rst_n),
 .load_start(load_start),
 .load_done(load_done),
 .compute_start(compute_start),
 .compute_done(compute_done),
 .clear_error(clear_error),
 .load_ready(load_ready),
 .compute_ready(compute_ready),
 .load_bank(load_bank),
 .compute_bank(compute_bank),
 .bank_valid(bank_valid),
 .load_active(load_active),
 .compute_active(compute_active),
 .overlap_active(overlap_active),
 .error(error)
 );

 ping_pong_activation_scratchpad #(
 .PC(PC),
 .MAX_PIXELS(MAX_PIXELS),
 .MAX_C(MAX_CIN),
 .DATA_W(DATA_W)
 ) u_ping_pong_activation_scratchpad (
 .clk(clk),
 .write_bank(load_bank),
 .write_enable(act_write_enable),
 .write_pixel(act_write_pixel),
 .write_channel(act_write_channel),
 .write_data(act_write_data),
 .read_bank(compute_bank),
 .read_pixel(act_read_pixel),
 .read_c_base(act_read_c_base),
 .lane_mask(act_lane_mask),
 .lane_data(act_lane_data),
 .debug_bank(act_debug_bank),
 .debug_read_pixel(act_read_pixel),
 .debug_read_channel(act_read_c_base),
 .debug_read_data(act_debug_data)
 );

 ping_pong_weight_scratchpad #(
 .PC(PC),
 .PK(PK),
 .MAX_CIN(MAX_CIN),
 .MAX_COUT(MAX_COUT),
 .DATA_W(DATA_W)
 ) u_ping_pong_weight_scratchpad (
 .clk(clk),
 .write_bank(load_bank),
 .write_enable(weight_write_enable),
 .write_out_channel(weight_write_out_channel),
 .write_in_channel(weight_write_in_channel),
 .write_kernel_idx(weight_write_kernel_idx),
 .write_data(weight_write_data),
 .read_bank(compute_bank),
 .read_k_base(weight_read_k_base),
 .read_c_base(weight_read_c_base),
 .read_kernel_idx(weight_read_kernel_idx),
 .out_lane_mask(weight_out_lane_mask),
 .in_lane_mask(weight_in_lane_mask),
 .weight_mat(weight_mat),
 .debug_bank(weight_debug_bank),
 .debug_out_channel(weight_read_k_base),
 .debug_in_channel(weight_read_c_base),
 .debug_kernel_idx(weight_read_kernel_idx),
 .debug_read_data(weight_debug_data)
 );

 initial begin
 clk = 1'b0;
 forever #5 clk = ~clk;
 end

 task automatic pulse_load_start;
 begin
 @(negedge clk);
 load_start = 1'b1;
 @(posedge clk);
 @(negedge clk);
 load_start = 1'b0;
 end
 endtask

 task automatic pulse_load_done;
 begin
 @(negedge clk);
 load_done = 1'b1;
 @(posedge clk);
 @(negedge clk);
 load_done = 1'b0;
 end
 endtask

 task automatic pulse_compute_start;
 begin
 @(negedge clk);
 compute_start = 1'b1;
 @(posedge clk);
 @(negedge clk);
 compute_start = 1'b0;
 end
 endtask

 task automatic pulse_compute_done;
 begin
 @(negedge clk);
 compute_done = 1'b1;
 @(posedge clk);
 @(negedge clk);
 compute_done = 1'b0;
 end
 endtask

 task automatic pulse_clear_error;
 begin
 @(negedge clk);
 clear_error = 1'b1;
 @(posedge clk);
 @(negedge clk);
 clear_error = 1'b0;
 end
 endtask

 task automatic write_activation(input int pixel, input int channel, input int value);
 begin
 @(negedge clk);
 act_write_pixel = pixel[31:0];
 act_write_channel = channel[7:0];
 act_write_data = value[DATA_W-1:0];
 act_write_enable = 1'b1;
 @(posedge clk);
 @(negedge clk);
 act_write_enable = 1'b0;
 end
 endtask

 task automatic write_weight(input int co, input int ci, input int tap, input int value);
 begin
 @(negedge clk);
 weight_write_out_channel = co[7:0];
 weight_write_in_channel = ci[7:0];
 weight_write_kernel_idx = tap[3:0];
 weight_write_data = value[DATA_W-1:0];
 weight_write_enable = 1'b1;
 @(posedge clk);
 @(negedge clk);
 weight_write_enable = 1'b0;
 end
 endtask

 task automatic expect_control(
 input string name,
 input logic expected_load_bank,
 input logic expected_compute_bank,
 input logic [1:0] expected_valid,
 input logic expected_load_active,
 input logic expected_compute_active,
 input logic expected_overlap
 );
 begin
 #1;
 if ((load_bank !== expected_load_bank) ||
 (compute_bank !== expected_compute_bank) ||
 (bank_valid !== expected_valid) ||
 (load_active !== expected_load_active) ||
 (compute_active !== expected_compute_active) ||
 (overlap_active !== expected_overlap)) begin
 $display("[FAIL] %s: load_bank=%0b compute_bank=%0b valid=%b load_active=%0b compute_active=%0b overlap=%0b",
 name, load_bank, compute_bank, bank_valid, load_active, compute_active, overlap_active);
 $finish;
 end
 tests++;
 end
 endtask

 task automatic expect_activation(input string name, input int expected);
 begin
 #1;
 if (act_lane_data[0] !== expected[DATA_W-1:0]) begin
 $display("[FAIL] %s: activation expected=%0d got=%0d",
 name, expected, act_lane_data[0]);
 $finish;
 end
 tests++;
 end
 endtask

 task automatic expect_weight(input string name, input int expected);
 begin
 repeat (2) @(posedge clk);
 #1;
 if (weight_mat[0][0] !== expected[DATA_W-1:0]) begin
 $display("[FAIL] %s: weight expected=%0d got=%0d",
 name, expected, weight_mat[0][0]);
 $finish;
 end
 tests++;
 end
 endtask

 initial begin
 rst_n = 1'b0;
 load_start = 1'b0;
 load_done = 1'b0;
 compute_start = 1'b0;
 compute_done = 1'b0;
 clear_error = 1'b0;

 act_write_enable = 1'b0;
 act_write_pixel = '0;
 act_write_channel = '0;
 act_write_data = '0;
 act_read_pixel = 32'd2;
 act_read_c_base = 8'd1;
 act_lane_mask = 4'b0001;
 act_debug_bank = 1'b0;

 weight_write_enable = 1'b0;
 weight_write_out_channel = '0;
 weight_write_in_channel = '0;
 weight_write_kernel_idx = '0;
 weight_write_data = '0;
 weight_read_k_base = 8'd3;
 weight_read_c_base = 8'd2;
 weight_read_kernel_idx = 4'd4;
 weight_out_lane_mask = 8'b0000_0001;
 weight_in_lane_mask = 4'b0001;
 weight_debug_bank = 1'b0;
 tests = 0;

 repeat (3) @(posedge clk);
 rst_n = 1'b1;
 @(negedge clk);

 if (!load_ready || compute_ready || error) begin
 $display("[FAIL] reset readiness: load_ready=%0b compute_ready=%0b error=%0b",
 load_ready, compute_ready, error);
 $finish;
 end
 tests++;

 pulse_load_start();
 expect_control("load_bank0_started", 1'b0, 1'b0, 2'b00, 1'b1, 1'b0, 1'b0);

 write_activation(2, 1, 21);
 write_weight(3, 2, 4, -17);
 pulse_load_done();
 expect_control("load_bank0_complete", 1'b0, 1'b0, 2'b01, 1'b0, 1'b0, 1'b0);

 pulse_compute_start();
 expect_control("compute_bank0_started", 1'b0, 1'b0, 2'b01, 1'b0, 1'b1, 1'b0);
 expect_activation("compute_reads_bank0_activation", 21);
 expect_weight("compute_reads_bank0_weight", -17);

 pulse_load_start();
 expect_control("overlap_load_bank1_compute_bank0", 1'b1, 1'b0, 2'b01, 1'b1, 1'b1, 1'b1);

 write_activation(2, 1, -33);
 expect_activation("bank0_stable_during_bank1_activation_write", 21);
 write_weight(3, 2, 4, 45);
 expect_weight("bank0_stable_during_bank1_weight_write", -17);

 pulse_load_done();
 expect_control("load_bank1_complete", 1'b1, 1'b0, 2'b11, 1'b0, 1'b1, 1'b0);

 if (load_ready) begin
 $display("[FAIL] load_ready asserted while bank0 computes and bank1 is full");
 $finish;
 end
 tests++;

 pulse_load_start();
 if (!error) begin
 $display("[FAIL] illegal load_start did not set error");
 $finish;
 end
 tests++;
 pulse_clear_error();

 pulse_compute_done();
 expect_control("compute_bank0_complete", 1'b1, 1'b0, 2'b10, 1'b0, 1'b0, 1'b0);

 pulse_compute_start();
 expect_control("compute_bank1_started", 1'b1, 1'b1, 2'b10, 1'b0, 1'b1, 1'b0);
 expect_activation("compute_reads_bank1_activation", -33);
 expect_weight("compute_reads_bank1_weight", 45);

 pulse_compute_done();
 expect_control("compute_bank1_complete", 1'b1, 1'b1, 2'b00, 1'b0, 1'b0, 1'b0);

 pulse_compute_start();
 if (!error) begin
 $display("[FAIL] compute_start without valid bank did not set error");
 $finish;
 end
 tests++;
 pulse_clear_error();

 if (error || !load_ready || compute_ready) begin
 $display("[FAIL] final readiness: load_ready=%0b compute_ready=%0b error=%0b",
 load_ready, compute_ready, error);
 $finish;
 end
 tests++;

 $display("[PASS] tb_ping_pong_buffers tests=%0d", tests);
 $finish;
 end

endmodule
