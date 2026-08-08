`timescale 1ns/1ps

module cnn_programmable_system_top #(
  parameter int PC = 2,
  parameter int PK = 4,
  parameter int MAX_CIN = 16,
  parameter int MAX_COUT = 16,
  parameter int MAX_LAYERS = 8,
  parameter int MAX_TENSORS = 32,
  parameter int MAX_QUANTIZATIONS = 32,
  parameter int MAX_TILE_WIDTH = 16,
  parameter int MAX_TILE_HEIGHT = 16,
  parameter int AXI_ADDR_WIDTH = 12
)(
  input  logic aclk,
  input  logic aresetn,
  input  logic [AXI_ADDR_WIDTH-1:0] s_axi_awaddr,
  input  logic s_axi_awvalid,
  output logic s_axi_awready,
  input  logic [31:0] s_axi_wdata,
  input  logic [3:0] s_axi_wstrb,
  input  logic s_axi_wvalid,
  output logic s_axi_wready,
  output logic [1:0] s_axi_bresp,
  output logic s_axi_bvalid,
  input  logic s_axi_bready,
  input  logic [AXI_ADDR_WIDTH-1:0] s_axi_araddr,
  input  logic s_axi_arvalid,
  output logic s_axi_arready,
  output logic [31:0] s_axi_rdata,
  output logic [1:0] s_axi_rresp,
  output logic s_axi_rvalid,
  input  logic s_axi_rready,
  input  logic [31:0] s_axis_tdata,
  input  logic [3:0] s_axis_tkeep,
  input  logic s_axis_tvalid,
  output logic s_axis_tready,
  input  logic s_axis_tlast,
  output logic [31:0] m_axis_tdata,
  output logic [3:0] m_axis_tkeep,
  output logic m_axis_tvalid,
  input  logic m_axis_tready,
  output logic m_axis_tlast,
  output logic irq,
  output logic busy,
  output logic done,
  output logic error
);
  logic start_pulse;
  logic clear_pulse;
  logic begin_model_load;
  logic finish_model_load;
  logic validate_model;
  logic activate_model;
  logic retire_active_model;
  logic clear_model_error;
  logic metadata_write;
  logic metadata_commit;
  logic [1:0] metadata_kind;
  logic [5:0] metadata_record_index;
  logic [5:0] metadata_word_index;
  logic [31:0] metadata_write_data;
  logic [31:0] metadata_read_data;
  logic [31:0] job_id;
  logic [2:0] parameter_layer_select;
  logic [2:0] staging_state;
  logic model_active_valid;
  logic [31:0] active_model_id;
  logic [31:0] active_generation_id;
  logic [15:0] active_layer_count;
  logic [7:0] model_lifecycle_error;
  logic [2:0] active_layer;
  logic [15:0] active_input_tensor_id;
  logic [15:0] active_output_tensor_id;
  logic [63:0] active_input_ddr_offset;
  logic [63:0] active_output_ddr_offset;
  logic [15:0] current_tile_x;
  logic [15:0] current_tile_y;
  logic [31:0] completed_layer_count;
  logic [31:0] completed_tile_count;
  logic [31:0] saturation_event_count;
  logic layer_done;
  logic [7:0] error_code;
  logic [2:0] error_layer;
  logic [31:0] packet_error_count;
  logic [1:0] parameter_bank_valid;

  cnn_programmable_axi_lite_slave #(
    .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH)
  ) u_control (
    .s_axi_aclk(aclk), .s_axi_aresetn(aresetn),
    .s_axi_awaddr(s_axi_awaddr), .s_axi_awvalid(s_axi_awvalid),
    .s_axi_awready(s_axi_awready), .s_axi_wdata(s_axi_wdata),
    .s_axi_wstrb(s_axi_wstrb), .s_axi_wvalid(s_axi_wvalid),
    .s_axi_wready(s_axi_wready), .s_axi_bresp(s_axi_bresp),
    .s_axi_bvalid(s_axi_bvalid), .s_axi_bready(s_axi_bready),
    .s_axi_araddr(s_axi_araddr), .s_axi_arvalid(s_axi_arvalid),
    .s_axi_arready(s_axi_arready), .s_axi_rdata(s_axi_rdata),
    .s_axi_rresp(s_axi_rresp), .s_axi_rvalid(s_axi_rvalid),
    .s_axi_rready(s_axi_rready),
    .start_pulse(start_pulse), .clear_pulse(clear_pulse),
    .begin_model_load(begin_model_load),
    .finish_model_load(finish_model_load),
    .validate_model(validate_model), .activate_model(activate_model),
    .retire_active_model(retire_active_model),
    .clear_model_error(clear_model_error),
    .metadata_write(metadata_write), .metadata_commit(metadata_commit),
    .metadata_kind(metadata_kind),
    .metadata_record_index(metadata_record_index),
    .metadata_word_index(metadata_word_index),
    .metadata_write_data(metadata_write_data),
    .metadata_read_data(metadata_read_data), .job_id(job_id),
    .parameter_layer_select(parameter_layer_select), .irq(irq),
    .staging_state(staging_state),
    .model_active_valid(model_active_valid),
    .active_model_id(active_model_id),
    .active_generation_id(active_generation_id),
    .active_layer_count(active_layer_count),
    .model_lifecycle_error(model_lifecycle_error),
    .active_layer(active_layer),
    .active_input_tensor_id(active_input_tensor_id),
    .active_output_tensor_id(active_output_tensor_id),
    .active_input_ddr_offset(active_input_ddr_offset),
    .active_output_ddr_offset(active_output_ddr_offset),
    .current_tile_x(current_tile_x), .current_tile_y(current_tile_y),
    .completed_layer_count(completed_layer_count),
    .completed_tile_count(completed_tile_count),
    .saturation_event_count(saturation_event_count),
    .layer_done(layer_done), .core_busy(busy), .core_done(done),
    .core_error(error), .core_error_code(error_code),
    .core_error_layer(error_layer),
    .packet_error_count(packet_error_count),
    .parameter_bank_valid(parameter_bank_valid)
  );

  cnn_programmable_runtime_top #(
    .PC(PC), .PK(PK), .MAX_CIN(MAX_CIN), .MAX_COUT(MAX_COUT),
    .MAX_LAYERS(MAX_LAYERS), .MAX_TENSORS(MAX_TENSORS),
    .MAX_QUANTIZATIONS(MAX_QUANTIZATIONS),
    .MAX_TILE_WIDTH(MAX_TILE_WIDTH),
    .MAX_TILE_HEIGHT(MAX_TILE_HEIGHT)
  ) u_runtime (
    .clk(aclk), .rst_n(aresetn), .clear(clear_pulse),
    .start(start_pulse), .job_id(job_id),
    .begin_model_load(begin_model_load),
    .finish_model_load(finish_model_load),
    .validate_model(validate_model), .activate_model(activate_model),
    .retire_active_model(retire_active_model),
    .clear_model_error(clear_model_error),
    .metadata_write(metadata_write), .metadata_commit(metadata_commit),
    .metadata_kind(metadata_kind),
    .metadata_record_index(metadata_record_index),
    .metadata_word_index(metadata_word_index),
    .metadata_write_data(metadata_write_data),
    .metadata_read_data(metadata_read_data),
    .parameter_layer_select(parameter_layer_select),
    .s_axis_tdata(s_axis_tdata), .s_axis_tkeep(s_axis_tkeep),
    .s_axis_tvalid(s_axis_tvalid), .s_axis_tready(s_axis_tready),
    .s_axis_tlast(s_axis_tlast), .m_axis_tdata(m_axis_tdata),
    .m_axis_tkeep(m_axis_tkeep), .m_axis_tvalid(m_axis_tvalid),
    .m_axis_tready(m_axis_tready), .m_axis_tlast(m_axis_tlast),
    .staging_state(staging_state),
    .model_active_valid(model_active_valid),
    .active_model_id(active_model_id),
    .active_generation_id(active_generation_id),
    .active_layer_count(active_layer_count),
    .model_lifecycle_error(model_lifecycle_error),
    .active_layer(active_layer),
    .active_input_tensor_id(active_input_tensor_id),
    .active_output_tensor_id(active_output_tensor_id),
    .active_input_ddr_offset(active_input_ddr_offset),
    .active_output_ddr_offset(active_output_ddr_offset),
    .current_tile_x(current_tile_x), .current_tile_y(current_tile_y),
    .completed_layer_count(completed_layer_count),
    .completed_tile_count(completed_tile_count),
    .saturation_event_count(saturation_event_count),
    .layer_done(layer_done), .busy(busy), .done(done), .error(error),
    .error_code(error_code), .error_layer(error_layer),
    .packet_error_count(packet_error_count),
    .parameter_bank_valid(parameter_bank_valid)
  );
endmodule
