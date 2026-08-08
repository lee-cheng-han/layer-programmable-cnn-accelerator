`timescale 1ns/1ps

module cnn_metadata_word_ram #(
  parameter int DEPTH = 64,
  parameter int ADDR_WIDTH = $clog2(DEPTH)
)(
  input  logic                  clk,
  input  logic                  write_enable,
  input  logic [ADDR_WIDTH-1:0] write_address,
  input  logic [31:0]           write_data,
  input  logic [ADDR_WIDTH-1:0] read_address,
  output logic [31:0]           read_data,
  input  logic [ADDR_WIDTH-1:0] execution_read_address,
  output logic [31:0]           execution_read_data
);
  logic [31:0] memory [0:DEPTH-1];

  always_ff @(posedge clk) begin
    if (write_enable) begin
      memory[write_address] <= write_data;
    end
    read_data <= memory[read_address];
    execution_read_data <= memory[execution_read_address];
  end
endmodule
