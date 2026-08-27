`timescale 1ns/1ps

module cnn_programmable_performance_counters #(
  parameter int MAX_LAYERS = 8
)(
  input  logic clk,
  input  logic rst_n,
  input  logic clear,
  input  logic job_start,
  input  logic job_done,
  input  logic job_error,
  input  logic controller_active,
  input  logic compute_active,
  input  logic [2:0] active_layer,
  input  logic parameter_stall,
  input  logic input_starved,
  input  logic input_valid,
  input  logic input_ready,
  input  logic [3:0] input_keep,
  input  logic output_valid,
  input  logic output_ready,
  input  logic [3:0] output_keep,
  input  logic [31:0] saturation_events,
  input  logic [31:0] completed_layers,
  input  logic [31:0] completed_tiles,
  input  logic [4:0] word_index,
  output logic [31:0] word_data
);
  logic counting;
  logic [31:0] job_cycles;
  logic [31:0] controller_cycles;
  logic [31:0] compute_cycles;
  logic [31:0] parameter_stall_cycles;
  logic [31:0] input_starvation_cycles;
  logic [31:0] output_backpressure_cycles;
  logic [31:0] input_bytes;
  logic [31:0] output_bytes;
  logic [31:0] layer_cycles [MAX_LAYERS];

  function automatic logic [2:0] keep_bytes(input logic [3:0] keep);
    keep_bytes = 3'(keep[0]) + 3'(keep[1]) +
                 3'(keep[2]) + 3'(keep[3]);
  endfunction

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      counting <= 1'b0;
      job_cycles <= '0;
      controller_cycles <= '0;
      compute_cycles <= '0;
      parameter_stall_cycles <= '0;
      input_starvation_cycles <= '0;
      output_backpressure_cycles <= '0;
      input_bytes <= '0;
      output_bytes <= '0;
      for (int layer = 0; layer < MAX_LAYERS; layer++) begin
        layer_cycles[layer] <= '0;
      end
    end else if (clear || job_start) begin
      counting <= job_start;
      job_cycles <= '0;
      controller_cycles <= '0;
      compute_cycles <= '0;
      parameter_stall_cycles <= '0;
      input_starvation_cycles <= '0;
      output_backpressure_cycles <= '0;
      input_bytes <= '0;
      output_bytes <= '0;
      for (int layer = 0; layer < MAX_LAYERS; layer++) begin
        layer_cycles[layer] <= '0;
      end
    end else if (counting) begin
      job_cycles <= job_cycles + 32'd1;
      if (controller_active) begin
        controller_cycles <= controller_cycles + 32'd1;
        if (int'(active_layer) < MAX_LAYERS) begin
          layer_cycles[int'(active_layer)] <=
            layer_cycles[int'(active_layer)] + 32'd1;
        end
      end
      if (compute_active) compute_cycles <= compute_cycles + 32'd1;
      if (parameter_stall)
        parameter_stall_cycles <= parameter_stall_cycles + 32'd1;
      if (input_starved)
        input_starvation_cycles <= input_starvation_cycles + 32'd1;
      if (output_valid && !output_ready)
        output_backpressure_cycles <= output_backpressure_cycles + 32'd1;
      if (input_valid && input_ready)
        input_bytes <= input_bytes + 32'(keep_bytes(input_keep));
      if (output_valid && output_ready)
        output_bytes <= output_bytes + 32'(keep_bytes(output_keep));
      if (job_done || job_error) counting <= 1'b0;
    end
  end

  always_comb begin
    unique case (word_index)
      5'd0: word_data = job_cycles;
      5'd1: word_data = controller_cycles;
      5'd2: word_data = compute_cycles;
      5'd3: word_data = parameter_stall_cycles;
      5'd4: word_data = input_starvation_cycles;
      5'd5: word_data = output_backpressure_cycles;
      5'd6: word_data = input_bytes;
      5'd7: word_data = output_bytes;
      5'd8: word_data = saturation_events;
      5'd9: word_data = completed_layers;
      5'd10: word_data = completed_tiles;
      5'd11: word_data = {31'd0, counting};
      default: begin
        word_data = 32'd0;
        for (int layer = 0; layer < MAX_LAYERS; layer++) begin
          if (word_index == 5'(16 + layer)) word_data = layer_cycles[layer];
        end
      end
    endcase
  end
endmodule
