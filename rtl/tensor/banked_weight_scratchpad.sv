`timescale 1ns/1ps

module banked_weight_scratchpad #(
  parameter int PC       = 4,
  parameter int PK       = 8,
  parameter int MAX_CIN  = 64,
  parameter int MAX_COUT = 64,
  parameter int DATA_W   = 8,
  parameter int COUNT_W  = 8,
  parameter int ADDR_W   = 32
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

  localparam int DEPTH = MAX_COUT * MAX_CIN * 9;

  logic [ADDR_W-1:0] lane_read_addr [PK][PC];
  logic [ADDR_W-1:0] lane_read_addr_q [PK][PC];
  logic lane_read_enable [PK][PC];
  logic [ADDR_W-1:0] write_addr;
  logic write_valid;
  logic write_valid_q = 1'b0;
  logic [ADDR_W-1:0] write_addr_q = '0;
  logic signed [DATA_W-1:0] write_data_q = '0;
  logic [ADDR_W-1:0] debug_addr;
  logic debug_valid;
  logic lane_read_enable_q [PK][PC];
  logic lane_read_enable_qq [PK][PC];
  logic signed [DATA_W-1:0] lane_read_data_q [PK][PC];
  (* ram_style = "block" *) logic signed [DATA_W-1:0] debug_mem [0:DEPTH-1];
  logic signed [DATA_W-1:0] debug_read_data_q;

  assign debug_read_data = debug_read_data_q;
  assign write_addr = packed_addr(write_out_channel, write_in_channel, write_kernel_idx);
  assign write_valid =
    write_enable &&
    (write_out_channel < COUNT_W'(MAX_COUT)) &&
    (write_in_channel < COUNT_W'(MAX_CIN)) &&
    (write_kernel_idx < 4'd9) &&
    (write_addr < ADDR_W'(DEPTH));
  assign debug_addr =
    packed_addr(debug_out_channel, debug_in_channel, debug_kernel_idx);
  assign debug_valid =
    (debug_out_channel < COUNT_W'(MAX_COUT)) &&
    (debug_in_channel < COUNT_W'(MAX_CIN)) &&
    (debug_kernel_idx < 4'd9) &&
    (debug_addr < ADDR_W'(DEPTH));

  function automatic logic [ADDR_W-1:0] packed_addr(
    input logic [COUNT_W-1:0] out_channel,
    input logic [COUNT_W-1:0] in_channel,
    input logic [3:0] kernel_idx
  );
    begin
      packed_addr =
        (((ADDR_W'(out_channel) * ADDR_W'(MAX_CIN)) + ADDR_W'(in_channel)) *
         ADDR_W'(9)) + ADDR_W'(kernel_idx);
    end
  endfunction

  always_comb begin
    for (int pk = 0; pk < PK; pk++) begin
      for (int pc = 0; pc < PC; pc++) begin
        logic [COUNT_W-1:0] out_channel;
        logic [COUNT_W-1:0] in_channel;

        out_channel = read_k_base + COUNT_W'(pk);
        in_channel = read_c_base + COUNT_W'(pc);
        lane_read_addr[pk][pc] = packed_addr(out_channel, in_channel, read_kernel_idx);
        lane_read_enable[pk][pc] =
          out_lane_mask[pk] &&
          in_lane_mask[pc] &&
          (out_channel < COUNT_W'(MAX_COUT)) &&
          (in_channel < COUNT_W'(MAX_CIN)) &&
          (read_kernel_idx < 4'd9);
      end
    end
  end

  always_comb begin
    for (int pk = 0; pk < PK; pk++) begin
      for (int pc = 0; pc < PC; pc++) begin
        weight_mat[pk][pc] = lane_read_enable_qq[pk][pc] ?
                             lane_read_data_q[pk][pc] :
                             '0;
      end
    end
  end

  generate
    for (genvar pk = 0; pk < PK; pk++) begin : gen_pk_lane_ram
      for (genvar pc = 0; pc < PC; pc++) begin : gen_pc_lane_ram
        banked_weight_lane_ram #(
          .DEPTH(DEPTH),
          .DATA_W(DATA_W),
          .ADDR_W(ADDR_W)
        ) u_banked_weight_lane_ram (
          .clk(clk),
          .write_enable(write_valid_q),
          .write_addr(write_addr_q),
          .write_data(write_data_q),
          .read_addr(lane_read_addr_q[pk][pc]),
          .read_data(lane_read_data_q[pk][pc])
        );
      end
    end
  endgenerate

  always_ff @(posedge clk) begin
    if (write_valid_q) begin
      debug_mem[write_addr_q] <= write_data_q;
    end

    write_valid_q <= write_valid;
    write_addr_q <= write_addr;
    write_data_q <= write_data;

    for (int pk = 0; pk < PK; pk++) begin
      for (int pc = 0; pc < PC; pc++) begin
        lane_read_addr_q[pk][pc] <= lane_read_addr[pk][pc];
        lane_read_enable_q[pk][pc] <= lane_read_enable[pk][pc];
        lane_read_enable_qq[pk][pc] <= lane_read_enable_q[pk][pc];
      end
    end

    if (debug_valid) begin
      debug_read_data_q <= debug_mem[debug_addr];
    end else begin
      debug_read_data_q <= '0;
    end
  end

endmodule

module banked_weight_lane_ram #(
  parameter int DEPTH  = 2304,
  parameter int DATA_W = 8,
  parameter int ADDR_W = 32
)(
  input  logic clk,
  input  logic write_enable,
  input  logic [ADDR_W-1:0] write_addr,
  input  logic signed [DATA_W-1:0] write_data,
  input  logic [ADDR_W-1:0] read_addr,
  output logic signed [DATA_W-1:0] read_data
);

  (* ram_style = "block" *) logic signed [DATA_W-1:0] mem [0:DEPTH-1];

  always_ff @(posedge clk) begin
    if (write_enable) begin
      mem[write_addr] <= write_data;
    end

    read_data <= mem[read_addr];
  end

endmodule
