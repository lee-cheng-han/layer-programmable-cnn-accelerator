`timescale 1ns/1ps

module ping_pong_weight_scratchpad #(
  parameter int PC       = 4,
  parameter int PK       = 8,
  parameter int MAX_CIN  = 64,
  parameter int MAX_COUT = 64,
  parameter int DATA_W   = 8,
  parameter int COUNT_W  = 8,
  parameter int ADDR_W   = 32
)(
  input  logic clk,

  input  logic write_bank,
  input  logic write_enable,
  input  logic [COUNT_W-1:0] write_out_channel,
  input  logic [COUNT_W-1:0] write_in_channel,
  input  logic [3:0] write_kernel_idx,
  input  logic signed [DATA_W-1:0] write_data,

  input  logic read_bank,
  input  logic [COUNT_W-1:0] read_k_base,
  input  logic [COUNT_W-1:0] read_c_base,
  input  logic [3:0] read_kernel_idx,
  input  logic [PK-1:0] out_lane_mask,
  input  logic [PC-1:0] in_lane_mask,
  output logic signed [DATA_W-1:0] weight_mat [PK][PC],

  input  logic debug_bank,
  input  logic [COUNT_W-1:0] debug_out_channel,
  input  logic [COUNT_W-1:0] debug_in_channel,
  input  logic [3:0] debug_kernel_idx,
  output logic signed [DATA_W-1:0] debug_read_data
);

  logic signed [DATA_W-1:0] bank0_weight_mat [PK][PC];
  logic signed [DATA_W-1:0] bank1_weight_mat [PK][PC];
  logic signed [DATA_W-1:0] bank0_debug_data;
  logic signed [DATA_W-1:0] bank1_debug_data;

  banked_weight_scratchpad #(
    .PC(PC),
    .PK(PK),
    .MAX_CIN(MAX_CIN),
    .MAX_COUT(MAX_COUT),
    .DATA_W(DATA_W),
    .COUNT_W(COUNT_W),
    .ADDR_W(ADDR_W)
  ) u_bank0 (
    .clk(clk),
    .write_enable(write_enable && (write_bank == 1'b0)),
    .write_out_channel(write_out_channel),
    .write_in_channel(write_in_channel),
    .write_kernel_idx(write_kernel_idx),
    .write_data(write_data),
    .read_k_base(read_k_base),
    .read_c_base(read_c_base),
    .read_kernel_idx(read_kernel_idx),
    .out_lane_mask(out_lane_mask),
    .in_lane_mask(in_lane_mask),
    .weight_mat(bank0_weight_mat),
    .debug_out_channel(debug_out_channel),
    .debug_in_channel(debug_in_channel),
    .debug_kernel_idx(debug_kernel_idx),
    .debug_read_data(bank0_debug_data)
  );

  banked_weight_scratchpad #(
    .PC(PC),
    .PK(PK),
    .MAX_CIN(MAX_CIN),
    .MAX_COUT(MAX_COUT),
    .DATA_W(DATA_W),
    .COUNT_W(COUNT_W),
    .ADDR_W(ADDR_W)
  ) u_bank1 (
    .clk(clk),
    .write_enable(write_enable && (write_bank == 1'b1)),
    .write_out_channel(write_out_channel),
    .write_in_channel(write_in_channel),
    .write_kernel_idx(write_kernel_idx),
    .write_data(write_data),
    .read_k_base(read_k_base),
    .read_c_base(read_c_base),
    .read_kernel_idx(read_kernel_idx),
    .out_lane_mask(out_lane_mask),
    .in_lane_mask(in_lane_mask),
    .weight_mat(bank1_weight_mat),
    .debug_out_channel(debug_out_channel),
    .debug_in_channel(debug_in_channel),
    .debug_kernel_idx(debug_kernel_idx),
    .debug_read_data(bank1_debug_data)
  );

  always_comb begin
    for (int pk = 0; pk < PK; pk++) begin
      for (int pc = 0; pc < PC; pc++) begin
        weight_mat[pk][pc] = read_bank ? bank1_weight_mat[pk][pc] : bank0_weight_mat[pk][pc];
      end
    end

    debug_read_data = debug_bank ? bank1_debug_data : bank0_debug_data;
  end

endmodule
