`timescale 1ns/1ps

module parallel_requantizer #(
  parameter int PK = 8,
  parameter int ACC_W = 32,
  parameter int OUT_W = 8
)(
  input  logic clk,
  input  logic rst_n,
  input  logic valid_in,
  input  logic signed [ACC_W-1:0] acc_in [PK],
  input  logic signed [31:0] quant_multiplier [PK],
  input  logic [5:0] quant_shift [PK],
  input  logic signed [7:0] output_zero_point [PK],
  input  logic [PK-1:0] lane_mask,
  output wire signed [OUT_W-1:0] out_vec [PK],
  output wire [PK-1:0] saturation_positive,
  output wire [PK-1:0] saturation_negative,
  output logic valid_out
);

  localparam logic signed [9:0] MAX_VAL =
    (10'sd1 <<< (OUT_W - 1)) - 10'sd1;
  localparam logic signed [9:0] MIN_VAL =
    -(10'sd1 <<< (OUT_W - 1));

  logic valid_q1;
  logic valid_q2;
  logic valid_q3;
  logic valid_q4;
  logic valid_q5;
  logic valid_q6;
  logic valid_q7;
  logic valid_q8;
  logic signed [ACC_W-1:0] acc_input_q [PK];
  logic signed [31:0] multiplier_input_q [PK];
  logic [5:0] shift_q0 [PK];
  logic signed [7:0] zero_point_q0 [PK];
  logic lane_mask_q0 [PK];
  logic signed [63:0] product_q [PK];
  logic [63:0] magnitude_q [PK];
  logic negative_q2 [PK];
  logic [5:0] shift_q1 [PK];
  logic [5:0] shift_q2 [PK];
  logic signed [7:0] zero_point_q1 [PK];
  logic signed [7:0] zero_point_q2 [PK];
  logic signed [7:0] zero_point_q3 [PK];
  logic signed [7:0] zero_point_q4 [PK];
  logic signed [7:0] zero_point_q5 [PK];
  logic signed [7:0] zero_point_q6 [PK];
  logic lane_mask_q1 [PK];
  logic lane_mask_q2 [PK];
  logic lane_mask_q3 [PK];
  logic lane_mask_q4 [PK];
  logic lane_mask_q5 [PK];
  logic lane_mask_q6 [PK];
  logic [63:0] quotient_q [PK];
  logic [63:0] remainder_q [PK];
  logic [63:0] half_q [PK];
  logic rounding_enable_q3 [PK];
  logic negative_q3 [PK];
  logic [63:0] quotient_q4 [PK];
  logic round_up_q4 [PK];
  logic negative_q4 [PK];
  logic [63:0] rounded_magnitude_q5 [PK];
  logic negative_q5 [PK];
  logic signed [63:0] rounded_q [PK];
  logic signed [9:0] rounded_narrow_q7 [PK];
  logic signed [7:0] zero_point_q7 [PK];
  logic lane_mask_q7 [PK];
  logic [OUT_W+1:0] result_q [PK];

  for (genvar pk = 0; pk < PK; pk++) begin : g_result_outputs
    assign out_vec[pk] = result_q[pk][OUT_W-1:0];
    assign saturation_negative[pk] = result_q[pk][OUT_W];
    assign saturation_positive[pk] = result_q[pk][OUT_W+1];
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      valid_q1 <= 1'b0;
      valid_q2 <= 1'b0;
      valid_q3 <= 1'b0;
      valid_q4 <= 1'b0;
      valid_q5 <= 1'b0;
      valid_q6 <= 1'b0;
      valid_q7 <= 1'b0;
      valid_q8 <= 1'b0;
      valid_out <= 1'b0;
    end else begin
      valid_q1 <= valid_in;
      valid_q2 <= valid_q1;
      valid_q3 <= valid_q2;
      valid_q4 <= valid_q3;
      valid_q5 <= valid_q4;
      valid_q6 <= valid_q5;
      valid_q7 <= valid_q6;
      valid_q8 <= valid_q7;
      valid_out <= valid_q8;
    end
  end

  // Datapath registers intentionally have no reset. The valid pipeline masks
  // their contents until a complete transaction reaches the output stage.
  always_ff @(posedge clk) begin
    for (int pk = 0; pk < PK; pk++) begin
      logic [63:0] remainder;
      logic [63:0] half;
      logic [63:0] remainder_mask;
      logic signed [9:0] shifted_value;

      acc_input_q[pk] <= acc_in[pk];
      multiplier_input_q[pk] <= quant_multiplier[pk];
      shift_q0[pk] <= quant_shift[pk];
      zero_point_q0[pk] <= output_zero_point[pk];
      lane_mask_q0[pk] <= lane_mask[pk];

      product_q[pk] <=
        $signed(acc_input_q[pk]) * $signed(multiplier_input_q[pk]);
      shift_q1[pk] <= shift_q0[pk];
      zero_point_q1[pk] <= zero_point_q0[pk];
      lane_mask_q1[pk] <= lane_mask_q0[pk];

      magnitude_q[pk] <= product_q[pk][63] ?
        $unsigned(-product_q[pk]) : $unsigned(product_q[pk]);
      negative_q2[pk] <= product_q[pk][63];
      shift_q2[pk] <= shift_q1[pk];
      zero_point_q2[pk] <= zero_point_q1[pk];
      lane_mask_q2[pk] <= lane_mask_q1[pk];

      remainder = '0;
      half = '0;
      remainder_mask = '0;
      quotient_q[pk] <= '0;
      remainder_q[pk] <= '0;
      half_q[pk] <= '0;
      rounding_enable_q3[pk] <= 1'b0;
      if (shift_q2[pk] == 0) begin
        quotient_q[pk] <= magnitude_q[pk];
      end else if (shift_q2[pk] <= 6'd62) begin
        quotient_q[pk] <= magnitude_q[pk] >> shift_q2[pk];
        remainder_mask = (64'h1 << shift_q2[pk]) - 64'd1;
        remainder = magnitude_q[pk] & remainder_mask;
        half = 64'h1 << (shift_q2[pk] - 6'd1);
        remainder_q[pk] <= remainder;
        half_q[pk] <= half;
        rounding_enable_q3[pk] <= 1'b1;
      end
      negative_q3[pk] <= negative_q2[pk];
      zero_point_q3[pk] <= zero_point_q2[pk];
      lane_mask_q3[pk] <= lane_mask_q2[pk];

      quotient_q4[pk] <= quotient_q[pk];
      round_up_q4[pk] <= rounding_enable_q3[pk] &&
        ((remainder_q[pk] > half_q[pk]) ||
         ((remainder_q[pk] == half_q[pk]) && quotient_q[pk][0]));
      negative_q4[pk] <= negative_q3[pk];
      zero_point_q4[pk] <= zero_point_q3[pk];
      lane_mask_q4[pk] <= lane_mask_q3[pk];

      rounded_magnitude_q5[pk] <= quotient_q4[pk] +
        {{63{1'b0}}, round_up_q4[pk]};
      negative_q5[pk] <= negative_q4[pk];
      zero_point_q5[pk] <= zero_point_q4[pk];
      lane_mask_q5[pk] <= lane_mask_q4[pk];

      rounded_q[pk] <= negative_q5[pk] ?
        -$signed(rounded_magnitude_q5[pk]) :
        $signed(rounded_magnitude_q5[pk]);
      zero_point_q6[pk] <= zero_point_q5[pk];
      lane_mask_q6[pk] <= lane_mask_q5[pk];

      if (!rounded_q[pk][63] && (|rounded_q[pk][62:8])) begin
        rounded_narrow_q7[pk] <= 10'sd256;
      end else if (rounded_q[pk][63] && !(&rounded_q[pk][62:8])) begin
        rounded_narrow_q7[pk] <= -10'sd256;
      end else begin
        rounded_narrow_q7[pk] <= rounded_q[pk][9:0];
      end
      zero_point_q7[pk] <= zero_point_q6[pk];
      lane_mask_q7[pk] <= lane_mask_q6[pk];

      shifted_value = rounded_narrow_q7[pk] +
        $signed({{2{zero_point_q7[pk][7]}}, zero_point_q7[pk]});
      if (!lane_mask_q7[pk]) begin
        result_q[pk] <= '0;
      end else if (shifted_value > MAX_VAL) begin
        result_q[pk] <= {1'b1, 1'b0, 1'b0, {(OUT_W-1){1'b1}}};
      end else if (shifted_value < MIN_VAL) begin
        result_q[pk] <= {1'b0, 1'b1, 1'b1, {(OUT_W-1){1'b0}}};
      end else begin
        result_q[pk] <= {2'b00, shifted_value[OUT_W-1:0]};
      end
    end
  end
endmodule
