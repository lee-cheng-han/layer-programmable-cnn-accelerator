`timescale 1ns/1ps

module cnn_structured_error_snapshot (
  input  logic        clk,
  input  logic        resetn,
  input  logic        clear,
  input  logic        capture,
  input  logic [31:0] error_code,
  input  logic [7:0]  error_stage,
  input  logic [7:0]  record_kind,
  input  logic [15:0] record_index,
  input  logic [15:0] field_id,
  input  logic [63:0] observed_value,
  input  logic [63:0] expected_min,
  input  logic [63:0] expected_max,
  input  logic [31:0] model_id,
  input  logic [31:0] model_generation_id,
  input  logic [31:0] detail,
  input  logic [4:0]  word_index,
  output logic [31:0] word_data
);
  import cnn_accel_abi_pkg::*;

  logic [31:0] error_code_q;
  logic [7:0] error_stage_q;
  logic [7:0] record_kind_q;
  logic [15:0] record_index_q;
  logic [15:0] field_id_q;
  logic [63:0] observed_value_q;
  logic [63:0] expected_min_q;
  logic [63:0] expected_max_q;
  logic [31:0] model_id_q;
  logic [31:0] model_generation_id_q;
  logic [31:0] detail_q;
  logic valid_q;

  always_ff @(posedge clk or negedge resetn) begin
    if (!resetn) begin
      error_code_q <= ERROR_NONE;
      error_stage_q <= ERROR_STAGE_NONE;
      record_kind_q <= ERROR_RECORD_NONE;
      record_index_q <= '0;
      field_id_q <= ERROR_FIELD_NONE;
      observed_value_q <= '0;
      expected_min_q <= '0;
      expected_max_q <= '0;
      model_id_q <= '0;
      model_generation_id_q <= '0;
      detail_q <= '0;
      valid_q <= 1'b0;
    end else if (clear) begin
      error_code_q <= ERROR_NONE;
      error_stage_q <= ERROR_STAGE_NONE;
      record_kind_q <= ERROR_RECORD_NONE;
      record_index_q <= '0;
      field_id_q <= ERROR_FIELD_NONE;
      observed_value_q <= '0;
      expected_min_q <= '0;
      expected_max_q <= '0;
      model_id_q <= '0;
      model_generation_id_q <= '0;
      detail_q <= '0;
      valid_q <= 1'b0;
    end else if (capture && !valid_q) begin
      error_code_q <= error_code;
      error_stage_q <= error_stage;
      record_kind_q <= record_kind;
      record_index_q <= record_index;
      field_id_q <= field_id;
      observed_value_q <= observed_value;
      expected_min_q <= expected_min;
      expected_max_q <= expected_max;
      model_id_q <= model_id;
      model_generation_id_q <= model_generation_id;
      detail_q <= detail;
      valid_q <= 1'b1;
    end
  end

  always_comb begin
    unique case (word_index)
      5'd0: word_data = {16'(ERROR_RECORD_BYTES), 16'(ABI_VERSION)};
      5'd1: word_data = error_code_q;
      5'd2: word_data = {16'd0, record_kind_q, error_stage_q};
      5'd3: word_data = {field_id_q, record_index_q};
      5'd4: word_data = observed_value_q[31:0];
      5'd5: word_data = observed_value_q[63:32];
      5'd6: word_data = expected_min_q[31:0];
      5'd7: word_data = expected_min_q[63:32];
      5'd8: word_data = expected_max_q[31:0];
      5'd9: word_data = expected_max_q[63:32];
      5'd10: word_data = model_id_q;
      5'd11: word_data = model_generation_id_q;
      5'd12: word_data = detail_q;
      default: word_data = 32'd0;
    endcase
  end
endmodule
