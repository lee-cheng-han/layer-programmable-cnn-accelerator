`timescale 1ns/1ps

module tiled_conv1x1_engine #(
  parameter int PC       = 4,
  parameter int PK       = 8,
  parameter int MAX_CIN  = 64,
  parameter int MAX_COUT = 64,
  parameter int DATA_W   = 8,
  parameter int PROD_W   = 16,
  parameter int ACC_W    = 32,
  parameter int BIAS_W   = 32,
  parameter int OUT_W    = 8,
  parameter int COUNT_W  = 8,
  parameter int ADDR_W   = 32
)(
  input  logic clk,
  input  logic rst_n,

  input  logic start,
  input  logic [COUNT_W-1:0] cin,
  input  logic [COUNT_W-1:0] cout,

  input  logic bias_enable,
  input  logic relu_enable,
  input  logic quant_enable,
  input  logic [4:0] quant_shift,

  input  logic signed [DATA_W-1:0] activation [MAX_CIN],
  input  logic signed [DATA_W-1:0] weights [MAX_COUT][MAX_CIN],
  input  logic signed [BIAS_W-1:0] bias [MAX_COUT],

  input  logic use_scratchpad_operands,
  input  logic use_scratchpad_weights,
  input  logic [ADDR_W-1:0] scratch_activation_pixel,
  output logic [ADDR_W-1:0] scratch_activation_read_pixel,
  output logic [COUNT_W-1:0] scratch_activation_read_c_base,
  output logic [PC-1:0] scratch_activation_lane_mask,
  input  logic signed [DATA_W-1:0] scratch_activation_lane_data [PC],
  output logic [COUNT_W-1:0] scratch_weight_read_k_base,
  output logic [COUNT_W-1:0] scratch_weight_read_c_base,
  output logic [3:0] scratch_weight_read_kernel_idx,
  output logic [PK-1:0] scratch_weight_out_lane_mask,
  output logic [PC-1:0] scratch_weight_in_lane_mask,
  input  logic signed [DATA_W-1:0] scratch_weight_mat_data [PK][PC],

  output logic signed [OUT_W-1:0] output_data [MAX_COUT],
  output logic busy,
  output logic done
);

  typedef enum logic [3:0] {
    S_IDLE,
    S_CLEAR,
    S_FETCH,
    S_READ,
    S_READ_WAIT,
    S_CAPTURE,
    S_ISSUE,
    S_WAIT_MAC,
    S_NEXT_C,
    S_POST_RELU,
    S_POSTPROCESS,
    S_WRITE_TILE,
    S_DONE
  } state_t;

  state_t state;

  logic [COUNT_W-1:0] c_base;
  logic [COUNT_W-1:0] k_base;

  logic [PC-1:0] cin_lane_mask;
  logic [PK-1:0] cout_lane_mask;
  logic [ADDR_W-1:0] scratch_activation_read_pixel_q;
  logic [COUNT_W-1:0] scratch_activation_read_c_base_q;
  logic [PC-1:0] scratch_activation_lane_mask_q;
  logic [COUNT_W-1:0] scratch_weight_read_k_base_q;
  logic [COUNT_W-1:0] scratch_weight_read_c_base_q;
  logic [3:0] scratch_weight_read_kernel_idx_q;
  logic [PK-1:0] scratch_weight_out_lane_mask_q;
  logic [PC-1:0] scratch_weight_in_lane_mask_q;

  logic signed [DATA_W-1:0] mac_act_vec_comb [PC];
  logic signed [DATA_W-1:0] mac_weight_mat_comb [PK][PC];
  logic signed [DATA_W-1:0] operand_act_vec [PC];
  logic signed [DATA_W-1:0] operand_weight_mat [PK][PC];
  logic signed [DATA_W-1:0] mac_act_vec_q [PC];
  logic signed [DATA_W-1:0] mac_weight_mat_q [PK][PC];
  logic mac_valid_in;
  logic mac_valid_out;

  logic signed [ACC_W-1:0] dot_vec [PK];
  logic signed [ACC_W-1:0] psum_vec [PK];
  logic psum_clear;
  logic psum_accumulate;

  logic signed [BIAS_W-1:0] bias_vec_comb [PK];
  logic signed [BIAS_W-1:0] bias_vec_q [PK];
  logic signed [ACC_W-1:0] bias_acc_vec [PK];
  logic signed [ACC_W-1:0] relu_acc_vec [PK];
  logic signed [ACC_W-1:0] relu_acc_vec_q [PK];
  logic signed [ACC_W-1:0] quant_acc_vec [PK];
  logic signed [OUT_W-1:0] post_out_vec [PK];
  logic signed [OUT_W-1:0] post_out_vec_q [PK];

  tail_mask_generator #(
    .LANES(PC),
    .COUNT_W(COUNT_W)
  ) u_cin_tail_mask (
    .base(c_base),
    .count(cin),
    .lane_mask(cin_lane_mask)
  );

  tail_mask_generator #(
    .LANES(PK),
    .COUNT_W(COUNT_W)
  ) u_cout_tail_mask (
    .base(k_base),
    .count(cout),
    .lane_mask(cout_lane_mask)
  );

  always_comb begin
    for (int pc = 0; pc < PC; pc++) begin
      if (cin_lane_mask[pc]) begin
        mac_act_vec_comb[pc] = activation[int'(c_base) + pc];
      end else begin
        mac_act_vec_comb[pc] = '0;
      end
    end

    for (int pk = 0; pk < PK; pk++) begin
      if (cout_lane_mask[pk]) begin
        bias_vec_comb[pk] = bias[int'(k_base) + pk];
      end else begin
        bias_vec_comb[pk] = '0;
      end

      for (int pc = 0; pc < PC; pc++) begin
        if (cout_lane_mask[pk] && cin_lane_mask[pc]) begin
          mac_weight_mat_comb[pk][pc] =
            weights[int'(k_base) + pk][int'(c_base) + pc];
        end else begin
          mac_weight_mat_comb[pk][pc] = '0;
        end
      end
    end
  end

  assign scratch_activation_read_pixel   = scratch_activation_read_pixel_q;
  assign scratch_activation_read_c_base  = scratch_activation_read_c_base_q;
  assign scratch_activation_lane_mask    = scratch_activation_lane_mask_q;
  assign scratch_weight_read_k_base      = scratch_weight_read_k_base_q;
  assign scratch_weight_read_c_base      = scratch_weight_read_c_base_q;
  assign scratch_weight_read_kernel_idx  = scratch_weight_read_kernel_idx_q;
  assign scratch_weight_out_lane_mask    = scratch_weight_out_lane_mask_q;
  assign scratch_weight_in_lane_mask     = scratch_weight_in_lane_mask_q;

  always_comb begin
    for (int pc = 0; pc < PC; pc++) begin
      operand_act_vec[pc] = use_scratchpad_operands ?
                            scratch_activation_lane_data[pc] :
                            mac_act_vec_comb[pc];
    end

    for (int pk = 0; pk < PK; pk++) begin
      for (int pc = 0; pc < PC; pc++) begin
        operand_weight_mat[pk][pc] = use_scratchpad_weights ?
                                     scratch_weight_mat_data[pk][pc] :
                                     mac_weight_mat_comb[pk][pc];
      end
    end
  end

  parallel_mac_array #(
    .PC(PC),
    .PK(PK),
    .DATA_W(DATA_W),
    .PROD_W(PROD_W),
    .ACC_W(ACC_W)
  ) u_parallel_mac_array (
    .clk(clk),
    .rst_n(rst_n),
    .act_vec(mac_act_vec_q),
    .weight_mat(mac_weight_mat_q),
    .valid_in(mac_valid_in),
    .dot_vec(dot_vec),
    .valid_out(mac_valid_out)
  );

  psum_accumulator #(
    .PK(PK),
    .ACC_W(ACC_W)
  ) u_psum_accumulator (
    .clk(clk),
    .rst_n(rst_n),
    .clear(psum_clear),
    .accumulate(psum_accumulate),
    .lane_mask(cout_lane_mask),
    .add_vec(dot_vec),
    .psum_vec(psum_vec)
  );

  parallel_bias_add #(
    .PK(PK),
    .ACC_W(ACC_W),
    .BIAS_W(BIAS_W)
  ) u_parallel_bias_add (
    .psum_in(psum_vec),
    .bias_in(bias_vec_q),
    .bias_enable(bias_enable),
    .lane_mask(cout_lane_mask),
    .acc_out(bias_acc_vec)
  );

  parallel_relu #(
    .PK(PK),
    .ACC_W(ACC_W)
  ) u_parallel_relu (
    .acc_in(bias_acc_vec),
    .relu_enable(relu_enable),
    .lane_mask(cout_lane_mask),
    .acc_out(relu_acc_vec)
  );

  parallel_quantizer #(
    .PK(PK),
    .ACC_W(ACC_W)
  ) u_parallel_quantizer (
    .acc_in(relu_acc_vec_q),
    .quant_enable(quant_enable),
    .quant_shift(quant_shift),
    .lane_mask(cout_lane_mask),
    .acc_out(quant_acc_vec)
  );

  parallel_saturate #(
    .PK(PK),
    .ACC_W(ACC_W),
    .OUT_W(OUT_W)
  ) u_parallel_saturate (
    .acc_in(quant_acc_vec),
    .lane_mask(cout_lane_mask),
    .out_vec(post_out_vec)
  );

  assign mac_valid_in    = (state == S_ISSUE);
  assign psum_clear      = (state == S_CLEAR);
  assign psum_accumulate = (state == S_WAIT_MAC) && mac_valid_out;
  assign busy            = (state != S_IDLE) && (state != S_DONE);

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state  <= S_IDLE;
      c_base <= '0;
      k_base <= '0;
      done   <= 1'b0;
      scratch_activation_read_pixel_q <= '0;
      scratch_activation_read_c_base_q <= '0;
      scratch_activation_lane_mask_q <= '0;
      scratch_weight_read_k_base_q <= '0;
      scratch_weight_read_c_base_q <= '0;
      scratch_weight_read_kernel_idx_q <= '0;
      scratch_weight_out_lane_mask_q <= '0;
      scratch_weight_in_lane_mask_q <= '0;

      for (int co = 0; co < MAX_COUT; co++) begin
        output_data[co] <= '0;
      end
      for (int pc = 0; pc < PC; pc++) begin
        mac_act_vec_q[pc] <= '0;
      end
      for (int pk = 0; pk < PK; pk++) begin
        bias_vec_q[pk] <= '0;
        relu_acc_vec_q[pk] <= '0;
        post_out_vec_q[pk] <= '0;
        for (int pc = 0; pc < PC; pc++) begin
          mac_weight_mat_q[pk][pc] <= '0;
        end
      end
    end else begin
      done <= 1'b0;

      case (state)
        S_IDLE: begin
          if (start) begin
            c_base <= '0;
            k_base <= '0;
            state  <= (cout == '0) ? S_DONE : S_CLEAR;
          end
        end

        S_CLEAR: begin
          c_base <= '0;
          state  <= (cin == '0) ? S_POST_RELU : S_FETCH;
        end

        S_FETCH: begin
          scratch_activation_read_pixel_q <= scratch_activation_pixel;
          scratch_activation_read_c_base_q <= c_base;
          scratch_activation_lane_mask_q <= cin_lane_mask;
          scratch_weight_read_k_base_q <= k_base;
          scratch_weight_read_c_base_q <= c_base;
          scratch_weight_read_kernel_idx_q <= 4'd0;
          scratch_weight_out_lane_mask_q <= cout_lane_mask;
          scratch_weight_in_lane_mask_q <= cin_lane_mask;
          state <= S_READ;
        end

        S_READ: begin
          state <= S_READ_WAIT;
        end

        S_READ_WAIT: begin
          state <= S_CAPTURE;
        end

        S_CAPTURE: begin
          for (int pc = 0; pc < PC; pc++) begin
            mac_act_vec_q[pc] <= operand_act_vec[pc];
          end
          for (int pk = 0; pk < PK; pk++) begin
            bias_vec_q[pk] <= bias_vec_comb[pk];
            for (int pc = 0; pc < PC; pc++) begin
              mac_weight_mat_q[pk][pc] <= operand_weight_mat[pk][pc];
            end
          end
          state <= S_ISSUE;
        end

        S_ISSUE: begin
          state <= S_WAIT_MAC;
        end

        S_WAIT_MAC: begin
          if (mac_valid_out) begin
            state <= S_NEXT_C;
          end
        end

        S_NEXT_C: begin
          if ((c_base + COUNT_W'(PC)) < cin) begin
            c_base <= c_base + COUNT_W'(PC);
            state  <= S_FETCH;
          end else begin
            state <= S_POST_RELU;
          end
        end

        S_POST_RELU: begin
          for (int pk = 0; pk < PK; pk++) begin
            relu_acc_vec_q[pk] <= relu_acc_vec[pk];
          end
          state <= S_POSTPROCESS;
        end

        S_POSTPROCESS: begin
          for (int pk = 0; pk < PK; pk++) begin
            post_out_vec_q[pk] <= post_out_vec[pk];
          end
          state <= S_WRITE_TILE;
        end

        S_WRITE_TILE: begin
          for (int pk = 0; pk < PK; pk++) begin
            if (cout_lane_mask[pk]) begin
              output_data[int'(k_base) + pk] <= post_out_vec_q[pk];
            end
          end

          if ((k_base + COUNT_W'(PK)) < cout) begin
            k_base <= k_base + COUNT_W'(PK);
            c_base <= '0;
            state  <= S_CLEAR;
          end else begin
            state <= S_DONE;
          end
        end

        S_DONE: begin
          done  <= 1'b1;
          state <= S_IDLE;
        end

        default: begin
          state <= S_IDLE;
        end
      endcase
    end
  end

endmodule
