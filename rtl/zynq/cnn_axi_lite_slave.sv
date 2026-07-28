`timescale 1ns/1ps

module cnn_axi_lite_slave #(
 parameter int AXI_ADDR_WIDTH = 12,
 parameter int AXI_DATA_WIDTH = 32,
 parameter int DIM_W = 16,
 parameter int PC = 2,
 parameter int PK = 4,
 parameter int MAX_CIN = 16,
 parameter int MAX_COUT = 16,
 parameter int MAX_PIXELS = 16,
 parameter int CLOCK_HZ = 125_000_000
)(
 input logic s_axi_aclk,
 input logic s_axi_aresetn,

 input logic [AXI_ADDR_WIDTH-1:0] s_axi_awaddr,
 input logic s_axi_awvalid,
 output logic s_axi_awready,

 input logic [AXI_DATA_WIDTH-1:0] s_axi_wdata,
 input logic [(AXI_DATA_WIDTH/8)-1:0] s_axi_wstrb,
 input logic s_axi_wvalid,
 output logic s_axi_wready,

 output logic [1:0] s_axi_bresp,
 output logic s_axi_bvalid,
 input logic s_axi_bready,

 input logic [AXI_ADDR_WIDTH-1:0] s_axi_araddr,
 input logic s_axi_arvalid,
 output logic s_axi_arready,

 output logic [AXI_DATA_WIDTH-1:0] s_axi_rdata,
 output logic [1:0] s_axi_rresp,
 output logic s_axi_rvalid,
 input logic s_axi_rready,

 output logic start_pulse,
 output logic clear_pulse,
 output logic final_residual_enable,
 output logic [DIM_W-1:0] image_width,
 output logic [DIM_W-1:0] image_height,
 output logic irq,

 input logic core_busy,
 input logic core_done,
 input logic core_error,
 input logic [7:0] core_error_code,
 input logic [31:0] structured_error_code,
 input logic [7:0] structured_error_stage,
 input logic [7:0] structured_error_record_kind,
 input logic [15:0] structured_error_record_index,
 input logic [15:0] structured_error_field_id,
 input logic [63:0] structured_error_observed,
 input logic [63:0] structured_error_expected_min,
 input logic [63:0] structured_error_expected_max,
 input logic [31:0] structured_error_model_id,
 input logic [31:0] structured_error_model_generation_id,
 input logic [31:0] structured_error_detail,
 input logic [3:0] phase,
 input logic [1:0] active_layer,
 input logic [2:0] weight_layers_ready,
 input logic prefetch_active,
 input logic prefetch_seen,
 input logic [2:0] input_packet_type,
 input logic [31:0] input_packet_words,

 input logic perf_counting,
 input logic [31:0] perf_job_cycles,
 input logic [31:0] perf_packet_cycles,
 input logic [31:0] perf_compute_cycles,
 input logic [31:0] perf_prefetch_cycles,
 input logic [31:0] perf_layer0_cycles,
 input logic [31:0] perf_layer1_cycles,
 input logic [31:0] perf_layer2_cycles,
 input logic [31:0] perf_input_words,
 input logic [31:0] perf_input_stall_cycles,
 input logic [31:0] perf_output_words,
 input logic [31:0] perf_output_stall_cycles
);

 localparam logic [AXI_ADDR_WIDTH-1:0] ADDR_CONTROL = 12'h000;
 localparam logic [AXI_ADDR_WIDTH-1:0] ADDR_STATUS = 12'h004;
 localparam logic [AXI_ADDR_WIDTH-1:0] ADDR_IRQ_STATUS = 12'h008;
 localparam logic [AXI_ADDR_WIDTH-1:0] ADDR_IRQ_ENABLE = 12'h00C;
 localparam logic [AXI_ADDR_WIDTH-1:0] ADDR_IMAGE_WIDTH = 12'h010;
 localparam logic [AXI_ADDR_WIDTH-1:0] ADDR_IMAGE_HEIGHT = 12'h014;
 localparam logic [AXI_ADDR_WIDTH-1:0] ADDR_MODE_FLAGS = 12'h018;
 localparam logic [AXI_ADDR_WIDTH-1:0] ADDR_ERROR_CODE = 12'h01C;
 localparam logic [AXI_ADDR_WIDTH-1:0] ADDR_STREAM_STATE = 12'h020;
 localparam logic [AXI_ADDR_WIDTH-1:0] ADDR_PACKET_WORDS = 12'h024;
 localparam logic [AXI_ADDR_WIDTH-1:0] ADDR_MODEL_COMMAND = 12'h028;
 localparam logic [AXI_ADDR_WIDTH-1:0] ADDR_MODEL_STATUS = 12'h02C;
 localparam logic [AXI_ADDR_WIDTH-1:0] ADDR_STAGING_MODEL_ID = 12'h030;
 localparam logic [AXI_ADDR_WIDTH-1:0] ADDR_STAGING_GENERATION = 12'h034;
 localparam logic [AXI_ADDR_WIDTH-1:0] ADDR_ACTIVE_MODEL_ID = 12'h038;
 localparam logic [AXI_ADDR_WIDTH-1:0] ADDR_ACTIVE_GENERATION = 12'h03C;
 localparam logic [AXI_ADDR_WIDTH-1:0] ADDR_METADATA_ADDRESS = 12'h040;
 localparam logic [AXI_ADDR_WIDTH-1:0] ADDR_METADATA_DATA = 12'h044;
 localparam logic [AXI_ADDR_WIDTH-1:0] ADDR_METADATA_COMMIT = 12'h048;
 localparam logic [AXI_ADDR_WIDTH-1:0] ADDR_MODEL_ERROR = 12'h04C;
 localparam logic [AXI_ADDR_WIDTH-1:0] ADDR_STAGING_COUNTS0 = 12'h050;
 localparam logic [AXI_ADDR_WIDTH-1:0] ADDR_STAGING_COUNTS1 = 12'h054;
 localparam logic [AXI_ADDR_WIDTH-1:0] ADDR_PERF_JOB = 12'h080;
 localparam logic [AXI_ADDR_WIDTH-1:0] ADDR_PERF_PACKET = 12'h084;
 localparam logic [AXI_ADDR_WIDTH-1:0] ADDR_PERF_COMPUTE = 12'h088;
 localparam logic [AXI_ADDR_WIDTH-1:0] ADDR_PERF_PREFETCH = 12'h08C;
 localparam logic [AXI_ADDR_WIDTH-1:0] ADDR_PERF_LAYER0 = 12'h090;
 localparam logic [AXI_ADDR_WIDTH-1:0] ADDR_PERF_LAYER1 = 12'h094;
 localparam logic [AXI_ADDR_WIDTH-1:0] ADDR_PERF_LAYER2 = 12'h098;
 localparam logic [AXI_ADDR_WIDTH-1:0] ADDR_PERF_INPUT_WORDS = 12'h09C;
 localparam logic [AXI_ADDR_WIDTH-1:0] ADDR_PERF_INPUT_STALL = 12'h0A0;
 localparam logic [AXI_ADDR_WIDTH-1:0] ADDR_PERF_OUTPUT_WORDS = 12'h0A4;
 localparam logic [AXI_ADDR_WIDTH-1:0] ADDR_PERF_OUTPUT_STALL = 12'h0A8;
 localparam logic [AXI_ADDR_WIDTH-1:0] ADDR_VERSION = 12'h0FC;
 localparam logic [AXI_ADDR_WIDTH-1:0] ADDR_CAPABILITY_BASE = 12'h100;
 localparam logic [AXI_ADDR_WIDTH-1:0] ADDR_CAPABILITY_LAST = 12'h17C;
 localparam logic [AXI_ADDR_WIDTH-1:0] ADDR_ERROR_RECORD_BASE = 12'h180;
 localparam logic [AXI_ADDR_WIDTH-1:0] ADDR_ERROR_RECORD_LAST = 12'h1BC;

 localparam logic [1:0] AXI_RESP_OKAY = 2'b00;
 localparam logic [1:0] AXI_RESP_SLVERR = 2'b10;

 logic [AXI_ADDR_WIDTH-1:0] awaddr_q;
 logic [AXI_DATA_WIDTH-1:0] wdata_q;
 logic [(AXI_DATA_WIDTH/8)-1:0] wstrb_q;
 logic aw_have;
 logic w_have;

 logic [1:0] irq_status;
 logic [1:0] irq_enable;
 logic core_done_q;
 logic core_error_q;

 logic [31:0] width_merged;
 logic [31:0] height_merged;
 logic [31:0] mode_merged;
 logic [31:0] irq_enable_merged;
 logic [31:0] metadata_address_merged;
 logic [4:0] capability_word_index;
 logic [31:0] capability_word_data;
 logic [4:0] error_word_index;
 logic [31:0] error_word_data;
 logic model_begin_load;
 logic model_finish_load;
 logic model_validate;
 logic model_activate;
 logic model_retire;
 logic model_clear_error;
 logic metadata_write;
 logic metadata_commit;
 logic [31:0] metadata_address;
 logic [31:0] metadata_write_data_merged;
 logic [31:0] metadata_write_data_q;
 logic [31:0] metadata_read_data;
 logic [2:0] model_staging_state;
 logic model_staging_bank;
 logic model_active_valid;
 logic model_active_bank;
 logic [31:0] staging_model_id;
 logic [31:0] staging_generation_id;
 logic [31:0] active_model_id;
 logic [31:0] active_generation_id;
 logic [15:0] staging_layer_count;
 logic [15:0] staging_tensor_count;
 logic [15:0] staging_quantization_count;
 logic [7:0] model_lifecycle_error;

 function automatic logic [31:0] apply_wstrb(
 input logic [31:0] old_value,
 input logic [31:0] new_value,
 input logic [3:0] byte_strobe
 );
 logic [31:0] merged;
 begin
 merged = old_value;
 for (int b = 0; b < 4; b++) begin
 if (byte_strobe[b]) begin
 merged[b*8 +: 8] = new_value[b*8 +: 8];
 end
 end
 return merged;
 end
 endfunction

 assign width_merged =
 apply_wstrb({{(32-DIM_W){1'b0}}, image_width}, wdata_q, wstrb_q);
 assign height_merged =
 apply_wstrb({{(32-DIM_W){1'b0}}, image_height}, wdata_q, wstrb_q);
 assign mode_merged =
 apply_wstrb({31'd0, final_residual_enable}, wdata_q, wstrb_q);
 assign irq_enable_merged =
 apply_wstrb({30'd0, irq_enable}, wdata_q, wstrb_q);
 assign metadata_address_merged =
 apply_wstrb(metadata_address, wdata_q, wstrb_q);
 assign metadata_write_data_merged =
 apply_wstrb(metadata_read_data, wdata_q, wstrb_q);

 assign irq = |(irq_status & irq_enable);
 assign capability_word_index = s_axi_araddr[6:2];
 assign error_word_index = s_axi_araddr[6:2];

 cnn_runtime_capabilities #(
 .PC(PC),
 .PK(PK),
 .MAX_CIN(MAX_CIN),
 .MAX_COUT(MAX_COUT),
 .MAX_PIXELS(MAX_PIXELS),
 .CLOCK_HZ(CLOCK_HZ)
 ) u_cnn_runtime_capabilities (
 .word_index(capability_word_index),
 .word_data(capability_word_data)
 );

 cnn_model_metadata_store u_cnn_model_metadata_store (
 .clk(s_axi_aclk),
 .resetn(s_axi_aresetn),
 .begin_load(model_begin_load),
 .finish_load(model_finish_load),
 .validate_model(model_validate),
 .activate_model(model_activate),
 .retire_active(model_retire),
 .clear_error(model_clear_error || clear_pulse),
 .job_busy(core_busy),
 .metadata_write(metadata_write),
 .metadata_commit(metadata_commit),
 .metadata_kind(metadata_address[1:0]),
 .metadata_record_index(metadata_address[7:2]),
 .metadata_word_index(metadata_address[13:8]),
 .metadata_write_data(metadata_write_data_q),
 .metadata_read_data(metadata_read_data),
 .execution_layer_index(3'd0),
 .execution_descriptor_valid(),
 .execution_layer_id(),
 .execution_opcode(),
 .execution_last_layer(),
 .execution_bias_enable(),
 .execution_input_tensor_id(),
 .execution_output_tensor_id(),
 .execution_residual_tensor_id(),
 .execution_quantization_id(),
 .execution_weight_size(),
 .execution_bias_size(),
 .execution_parameter_crc32(),
 .execution_input_width(),
 .execution_input_height(),
 .execution_input_channels(),
 .execution_output_width(),
 .execution_output_height(),
 .execution_output_channels(),
 .execution_kernel_height(),
 .execution_kernel_width(),
 .execution_stride_y(),
 .execution_stride_x(),
 .execution_padding_top(),
 .execution_padding_bottom(),
 .execution_padding_left(),
 .execution_padding_right(),
 .execution_dilation_y(),
 .execution_dilation_x(),
 .execution_activation(),
 .execution_residual_mode(),
 .execution_tile_height_hint(),
 .execution_tile_width_hint(),
 .execution_input_ddr_offset(),
 .execution_input_allocation_size(),
 .execution_input_row_stride(),
 .execution_input_pixel_stride(),
 .execution_input_channel_stride(),
 .execution_output_ddr_offset(),
 .execution_output_allocation_size(),
 .execution_output_row_stride(),
 .execution_output_pixel_stride(),
 .execution_output_channel_stride(),
 .staging_state(model_staging_state),
 .staging_bank(model_staging_bank),
 .active_valid(model_active_valid),
 .active_bank(model_active_bank),
 .staging_model_id(staging_model_id),
 .staging_generation_id(staging_generation_id),
 .active_model_id(active_model_id),
 .active_generation_id(active_generation_id),
 .active_layer_count(),
 .staging_layer_count(staging_layer_count),
 .staging_tensor_count(staging_tensor_count),
 .staging_quantization_count(staging_quantization_count),
 .lifecycle_error(model_lifecycle_error)
 );

 cnn_structured_error_snapshot u_cnn_structured_error_snapshot (
 .clk(s_axi_aclk),
 .resetn(s_axi_aresetn),
 .clear(clear_pulse),
 .capture(core_error && !core_error_q),
 .error_code(structured_error_code),
 .error_stage(structured_error_stage),
 .record_kind(structured_error_record_kind),
 .record_index(structured_error_record_index),
 .field_id(structured_error_field_id),
 .observed_value(structured_error_observed),
 .expected_min(structured_error_expected_min),
 .expected_max(structured_error_expected_max),
 .model_id(structured_error_model_id),
 .model_generation_id(structured_error_model_generation_id),
 .detail(structured_error_detail),
 .word_index(error_word_index),
 .word_data(error_word_data)
 );

 always_ff @(posedge s_axi_aclk or negedge s_axi_aresetn) begin
 if (!s_axi_aresetn) begin
 s_axi_awready <= 1'b0;
 s_axi_wready <= 1'b0;
 s_axi_bresp <= AXI_RESP_OKAY;
 s_axi_bvalid <= 1'b0;
 awaddr_q <= '0;
 wdata_q <= '0;
 wstrb_q <= '0;
 aw_have <= 1'b0;
 w_have <= 1'b0;

 start_pulse <= 1'b0;
 clear_pulse <= 1'b0;
 model_begin_load <= 1'b0;
 model_finish_load <= 1'b0;
 model_validate <= 1'b0;
 model_activate <= 1'b0;
 model_retire <= 1'b0;
 model_clear_error <= 1'b0;
 metadata_write <= 1'b0;
 metadata_commit <= 1'b0;
 metadata_address <= 32'd0;
 metadata_write_data_q <= 32'd0;
 final_residual_enable <= 1'b0;
 image_width <= '0;
 image_height <= '0;
 irq_status <= '0;
 irq_enable <= '0;
 core_done_q <= 1'b0;
 core_error_q <= 1'b0;
 end else begin
 s_axi_awready <= 1'b0;
 s_axi_wready <= 1'b0;
 start_pulse <= 1'b0;
 clear_pulse <= 1'b0;
 model_begin_load <= 1'b0;
 model_finish_load <= 1'b0;
 model_validate <= 1'b0;
 model_activate <= 1'b0;
 model_retire <= 1'b0;
 model_clear_error <= 1'b0;
 metadata_write <= 1'b0;
 metadata_commit <= 1'b0;
 core_done_q <= core_done;
 core_error_q <= core_error;

 if (!aw_have && s_axi_awvalid) begin
 s_axi_awready <= 1'b1;
 awaddr_q <= s_axi_awaddr;
 aw_have <= 1'b1;
 end

 if (!w_have && s_axi_wvalid) begin
 s_axi_wready <= 1'b1;
 wdata_q <= s_axi_wdata;
 wstrb_q <= s_axi_wstrb;
 w_have <= 1'b1;
 end

 if (aw_have && w_have && !s_axi_bvalid) begin
 s_axi_bresp <= AXI_RESP_OKAY;

 unique case (awaddr_q)
 ADDR_CONTROL: begin
 if (wstrb_q[0]) begin
 start_pulse <= wdata_q[0];
 clear_pulse <= wdata_q[1];
 if (wdata_q[1]) begin
 irq_status <= '0;
 end
 end
 end

 ADDR_IRQ_STATUS: begin
 if (wstrb_q[0]) begin
 irq_status <= irq_status & ~wdata_q[1:0];
 end
 end

 ADDR_IRQ_ENABLE: begin
 irq_enable <= irq_enable_merged[1:0];
 end

 ADDR_IMAGE_WIDTH: begin
 image_width <= width_merged[DIM_W-1:0];
 end

 ADDR_IMAGE_HEIGHT: begin
 image_height <= height_merged[DIM_W-1:0];
 end

 ADDR_MODE_FLAGS: begin
 final_residual_enable <= mode_merged[0];
 end

 ADDR_MODEL_COMMAND: begin
 if (wstrb_q[0]) begin
 model_begin_load <= wdata_q[0];
 model_finish_load <= wdata_q[1];
 model_validate <= wdata_q[2];
 model_activate <= wdata_q[3];
 model_retire <= wdata_q[4];
 end
 end

 ADDR_METADATA_ADDRESS: begin
 metadata_address <= metadata_address_merged;
 end

 ADDR_METADATA_DATA: begin
 metadata_write_data_q <= metadata_write_data_merged;
 metadata_write <= |wstrb_q;
 end

 ADDR_METADATA_COMMIT: begin
 if (wstrb_q[0]) begin
 metadata_commit <= wdata_q[0];
 end
 end

 ADDR_MODEL_ERROR: begin
 if (wstrb_q[0]) begin
 model_clear_error <= wdata_q[0];
 end
 end

 default: begin
 s_axi_bresp <= AXI_RESP_SLVERR;
 end
 endcase

 aw_have <= 1'b0;
 w_have <= 1'b0;
 s_axi_bvalid <= 1'b1;
 end

 if (s_axi_bvalid && s_axi_bready) begin
 s_axi_bvalid <= 1'b0;
 end

 if (core_done && !core_done_q) begin
 irq_status[0] <= 1'b1;
 end
 if (core_error && !core_error_q) begin
 irq_status[1] <= 1'b1;
 end
 end
 end

 always_ff @(posedge s_axi_aclk or negedge s_axi_aresetn) begin
 if (!s_axi_aresetn) begin
 s_axi_arready <= 1'b0;
 s_axi_rdata <= '0;
 s_axi_rresp <= AXI_RESP_OKAY;
 s_axi_rvalid <= 1'b0;
 end else begin
 s_axi_arready <= 1'b0;

 if (!s_axi_rvalid && s_axi_arvalid) begin
 s_axi_arready <= 1'b1;
 s_axi_rvalid <= 1'b1;
 s_axi_rresp <= AXI_RESP_OKAY;

 if ((s_axi_araddr >= ADDR_CAPABILITY_BASE) &&
     (s_axi_araddr <= ADDR_CAPABILITY_LAST) &&
     (s_axi_araddr[1:0] == 2'b00)) begin
 s_axi_rdata <= capability_word_data;
 end else if ((s_axi_araddr >= ADDR_ERROR_RECORD_BASE) &&
              (s_axi_araddr <= ADDR_ERROR_RECORD_LAST) &&
              (s_axi_araddr[1:0] == 2'b00)) begin
 s_axi_rdata <= error_word_data;
 end else begin
 unique case (s_axi_araddr)
 ADDR_CONTROL: begin
 s_axi_rdata <= 32'd0;
 end
 ADDR_STATUS: begin
 s_axi_rdata <= {
 17'd0,
 prefetch_seen,
 prefetch_active,
 weight_layers_ready,
 active_layer,
 phase,
 perf_counting,
 core_error,
 core_done,
 core_busy
 };
 end
 ADDR_IRQ_STATUS: begin
 s_axi_rdata <= {30'd0, irq_status};
 end
 ADDR_IRQ_ENABLE: begin
 s_axi_rdata <= {30'd0, irq_enable};
 end
 ADDR_IMAGE_WIDTH: begin
 s_axi_rdata <= {{(32-DIM_W){1'b0}}, image_width};
 end
 ADDR_IMAGE_HEIGHT: begin
 s_axi_rdata <= {{(32-DIM_W){1'b0}}, image_height};
 end
 ADDR_MODE_FLAGS: begin
 s_axi_rdata <= {31'd0, final_residual_enable};
 end
 ADDR_ERROR_CODE: begin
 s_axi_rdata <= {24'd0, core_error_code};
 end
 ADDR_STREAM_STATE: begin
 s_axi_rdata <= {26'd0, weight_layers_ready, input_packet_type};
 end
 ADDR_PACKET_WORDS: begin
 s_axi_rdata <= input_packet_words;
 end
 ADDR_MODEL_COMMAND: begin
 s_axi_rdata <= 32'd0;
 end
 ADDR_MODEL_STATUS: begin
 s_axi_rdata <= {
 16'd0,
 model_lifecycle_error,
 2'd0,
 model_active_bank,
 model_staging_bank,
 model_active_valid,
 model_staging_state
 };
 end
 ADDR_STAGING_MODEL_ID: begin
 s_axi_rdata <= staging_model_id;
 end
 ADDR_STAGING_GENERATION: begin
 s_axi_rdata <= staging_generation_id;
 end
 ADDR_ACTIVE_MODEL_ID: begin
 s_axi_rdata <= active_model_id;
 end
 ADDR_ACTIVE_GENERATION: begin
 s_axi_rdata <= active_generation_id;
 end
 ADDR_METADATA_ADDRESS: begin
 s_axi_rdata <= metadata_address;
 end
 ADDR_METADATA_DATA: begin
 s_axi_rdata <= metadata_read_data;
 end
 ADDR_METADATA_COMMIT: begin
 s_axi_rdata <= 32'd0;
 end
 ADDR_MODEL_ERROR: begin
 s_axi_rdata <= {24'd0, model_lifecycle_error};
 end
 ADDR_STAGING_COUNTS0: begin
 s_axi_rdata <= {staging_tensor_count, staging_layer_count};
 end
 ADDR_STAGING_COUNTS1: begin
 s_axi_rdata <= {16'd0, staging_quantization_count};
 end
 ADDR_PERF_JOB: begin
 s_axi_rdata <= perf_job_cycles;
 end
 ADDR_PERF_PACKET: begin
 s_axi_rdata <= perf_packet_cycles;
 end
 ADDR_PERF_COMPUTE: begin
 s_axi_rdata <= perf_compute_cycles;
 end
 ADDR_PERF_PREFETCH: begin
 s_axi_rdata <= perf_prefetch_cycles;
 end
 ADDR_PERF_LAYER0: begin
 s_axi_rdata <= perf_layer0_cycles;
 end
 ADDR_PERF_LAYER1: begin
 s_axi_rdata <= perf_layer1_cycles;
 end
 ADDR_PERF_LAYER2: begin
 s_axi_rdata <= perf_layer2_cycles;
 end
 ADDR_PERF_INPUT_WORDS: begin
 s_axi_rdata <= perf_input_words;
 end
 ADDR_PERF_INPUT_STALL: begin
 s_axi_rdata <= perf_input_stall_cycles;
 end
 ADDR_PERF_OUTPUT_WORDS: begin
 s_axi_rdata <= perf_output_words;
 end
 ADDR_PERF_OUTPUT_STALL: begin
 s_axi_rdata <= perf_output_stall_cycles;
 end
 ADDR_VERSION: begin
 s_axi_rdata <= 32'h0004_0000;
 end
 default: begin
 s_axi_rdata <= 32'hDEAD_BEEF;
 s_axi_rresp <= AXI_RESP_SLVERR;
 end
 endcase
 end
 end

 if (s_axi_rvalid && s_axi_rready) begin
 s_axi_rvalid <= 1'b0;
 end
 end
 end

endmodule
