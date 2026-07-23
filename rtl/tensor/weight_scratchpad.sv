`timescale 1ns/1ps

module weight_scratchpad #(
  parameter int PC       = 4,
  parameter int PK       = 8,
  parameter int MAX_CIN  = 64,
  parameter int MAX_COUT = 64,
  parameter int DATA_W   = 8,
  parameter int COUNT_W  = 8
)(
  input  logic clk,

  input  logic write_enable,
  input  logic [COUNT_W-1:0] write_out_channel,
  input  logic [COUNT_W-1:0] write_in_channel,
  input  logic [3:0] write_kernel_idx,
  input  logic signed [DATA_W-1:0] write_data,

  input  logic [COUNT_W-1:0] read_k_base,
  input  logic [COUNT_W-1:0] read_c_base,
  input  logic [3:0] read_kernel_idx,
  input  logic [PK-1:0] out_lane_mask,
  input  logic [PC-1:0] in_lane_mask,
  output logic signed [DATA_W-1:0] weight_mat [PK][PC],

  input  logic [COUNT_W-1:0] debug_out_channel,
  input  logic [COUNT_W-1:0] debug_in_channel,
  input  logic [3:0] debug_kernel_idx,
  output logic signed [DATA_W-1:0] debug_read_data
);

  logic signed [DATA_W-1:0] mem [MAX_COUT][MAX_CIN][9];

  always_ff @(posedge clk) begin
    if (write_enable &&
        (write_out_channel < COUNT_W'(MAX_COUT)) &&
        (write_in_channel < COUNT_W'(MAX_CIN)) &&
        (write_kernel_idx < 4'd9)) begin
      mem[int'(write_out_channel)][int'(write_in_channel)][int'(write_kernel_idx)] <=
        write_data;
    end
  end

  always_comb begin
    for (int pk = 0; pk < PK; pk++) begin
      for (int pc = 0; pc < PC; pc++) begin
        if (out_lane_mask[pk] &&
            in_lane_mask[pc] &&
            ((read_k_base + COUNT_W'(pk)) < COUNT_W'(MAX_COUT)) &&
            ((read_c_base + COUNT_W'(pc)) < COUNT_W'(MAX_CIN)) &&
            (read_kernel_idx < 4'd9)) begin
          weight_mat[pk][pc] = mem[int'(read_k_base) + pk]
                                  [int'(read_c_base) + pc]
                                  [int'(read_kernel_idx)];
        end else begin
          weight_mat[pk][pc] = '0;
        end
      end
    end

    if ((debug_out_channel < COUNT_W'(MAX_COUT)) &&
        (debug_in_channel < COUNT_W'(MAX_CIN)) &&
        (debug_kernel_idx < 4'd9)) begin
      debug_read_data = mem[int'(debug_out_channel)]
                           [int'(debug_in_channel)]
                           [int'(debug_kernel_idx)];
    end else begin
      debug_read_data = '0;
    end
  end

endmodule
