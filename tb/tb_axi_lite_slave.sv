`timescale 1ns/1ps

module tb_axi_lite_slave;

 localparam int AXI_ADDR_WIDTH = 12;

 localparam logic [11:0] ADDR_CONTROL = 12'h000;
 localparam logic [11:0] ADDR_STATUS = 12'h004;
 localparam logic [11:0] ADDR_IRQ_STATUS = 12'h008;
 localparam logic [11:0] ADDR_IRQ_ENABLE = 12'h00C;
 localparam logic [11:0] ADDR_IMAGE_WIDTH = 12'h010;
 localparam logic [11:0] ADDR_IMAGE_HEIGHT = 12'h014;
 localparam logic [11:0] ADDR_MODE_FLAGS = 12'h018;
 localparam logic [11:0] ADDR_ERROR_CODE = 12'h01C;
 localparam logic [11:0] ADDR_STREAM_STATE = 12'h020;
 localparam logic [11:0] ADDR_PACKET_WORDS = 12'h024;
 localparam logic [11:0] ADDR_MODEL_COMMAND = 12'h028;
 localparam logic [11:0] ADDR_MODEL_STATUS = 12'h02C;
 localparam logic [11:0] ADDR_STAGING_MODEL_ID = 12'h030;
 localparam logic [11:0] ADDR_STAGING_GENERATION = 12'h034;
 localparam logic [11:0] ADDR_ACTIVE_MODEL_ID = 12'h038;
 localparam logic [11:0] ADDR_ACTIVE_GENERATION = 12'h03C;
 localparam logic [11:0] ADDR_METADATA_ADDRESS = 12'h040;
 localparam logic [11:0] ADDR_METADATA_DATA = 12'h044;
 localparam logic [11:0] ADDR_METADATA_COMMIT = 12'h048;
 localparam logic [11:0] ADDR_MODEL_ERROR = 12'h04C;
 localparam logic [11:0] ADDR_STAGING_COUNTS0 = 12'h050;
 localparam logic [11:0] ADDR_STAGING_COUNTS1 = 12'h054;
 localparam logic [11:0] ADDR_PERF_JOB = 12'h080;
 localparam logic [11:0] ADDR_PERF_PACKET = 12'h084;
 localparam logic [11:0] ADDR_PERF_COMPUTE = 12'h088;
 localparam logic [11:0] ADDR_PERF_PREFETCH = 12'h08C;
 localparam logic [11:0] ADDR_PERF_LAYER0 = 12'h090;
 localparam logic [11:0] ADDR_PERF_LAYER1 = 12'h094;
 localparam logic [11:0] ADDR_PERF_LAYER2 = 12'h098;
 localparam logic [11:0] ADDR_PERF_INPUT_WORDS = 12'h09C;
 localparam logic [11:0] ADDR_PERF_INPUT_STALL = 12'h0A0;
 localparam logic [11:0] ADDR_PERF_OUTPUT_WORDS = 12'h0A4;
 localparam logic [11:0] ADDR_PERF_OUTPUT_STALL = 12'h0A8;
 localparam logic [11:0] ADDR_VERSION = 12'h0FC;
 localparam logic [11:0] ADDR_CAP_HEADER = 12'h100;
 localparam logic [11:0] ADDR_CAP_HW_VERSION = 12'h104;
 localparam logic [11:0] ADDR_CAP_ABI_DMA = 12'h108;
 localparam logic [11:0] ADDR_CAP_FEATURES = 12'h10C;
 localparam logic [11:0] ADDR_CAP_LIMITS0 = 12'h12C;
 localparam logic [11:0] ADDR_CAP_LIMITS2 = 12'h134;
 localparam logic [11:0] ADDR_CAP_MAX_ELEMENTS = 12'h140;
 localparam logic [11:0] ADDR_CAP_PARALLELISM = 12'h158;
 localparam logic [11:0] ADDR_CAP_CLOCK_HZ = 12'h15C;
 localparam logic [11:0] ADDR_ERR_HEADER = 12'h180;
 localparam logic [11:0] ADDR_ERR_CODE = 12'h184;
 localparam logic [11:0] ADDR_ERR_CONTEXT = 12'h188;
 localparam logic [11:0] ADDR_ERR_RECORD_FIELD = 12'h18C;
 localparam logic [11:0] ADDR_ERR_OBSERVED_LO = 12'h190;
 localparam logic [11:0] ADDR_ERR_OBSERVED_HI = 12'h194;
 localparam logic [11:0] ADDR_ERR_EXPECTED_MIN_LO = 12'h198;
 localparam logic [11:0] ADDR_ERR_EXPECTED_MAX_LO = 12'h1A0;
 localparam logic [11:0] ADDR_ERR_MODEL_ID = 12'h1A8;
 localparam logic [11:0] ADDR_ERR_GENERATION = 12'h1AC;
 localparam logic [11:0] ADDR_ERR_DETAIL = 12'h1B0;

 logic clk;
 logic rst_n;
 logic [11:0] awaddr;
 logic awvalid;
 logic awready;
 logic [31:0] wdata;
 logic [3:0] wstrb;
 logic wvalid;
 logic wready;
 logic [1:0] bresp;
 logic bvalid;
 logic bready;
 logic [11:0] araddr;
 logic arvalid;
 logic arready;
 logic [31:0] rdata;
 logic [1:0] rresp;
 logic rvalid;
 logic rready;

 logic start_pulse;
 logic clear_pulse;
 logic final_residual_enable;
 logic [15:0] image_width;
 logic [15:0] image_height;
 logic irq;

 logic core_busy;
 logic core_done;
 logic core_error;
 logic [7:0] core_error_code;
 logic [31:0] structured_error_code;
 logic [7:0] structured_error_stage;
 logic [7:0] structured_error_record_kind;
 logic [15:0] structured_error_record_index;
 logic [15:0] structured_error_field_id;
 logic [63:0] structured_error_observed;
 logic [63:0] structured_error_expected_min;
 logic [63:0] structured_error_expected_max;
 logic [31:0] structured_error_model_id;
 logic [31:0] structured_error_model_generation_id;
 logic [31:0] structured_error_detail;
 logic [3:0] phase;
 logic [1:0] active_layer;
 logic [2:0] weight_layers_ready;
 logic prefetch_active;
 logic prefetch_seen;
 logic [2:0] input_packet_type;
 logic [31:0] input_packet_words;
 logic perf_counting;
 logic [31:0] perf_job_cycles;
 logic [31:0] perf_packet_cycles;
 logic [31:0] perf_compute_cycles;
 logic [31:0] perf_prefetch_cycles;
 logic [31:0] perf_layer0_cycles;
 logic [31:0] perf_layer1_cycles;
 logic [31:0] perf_layer2_cycles;
 logic [31:0] perf_input_words;
 logic [31:0] perf_input_stall_cycles;
 logic [31:0] perf_output_words;
 logic [31:0] perf_output_stall_cycles;

 int checks;
 int errors;
 int start_count;
 int clear_count;
 logic [31:0] rd;
 logic [1:0] resp;

 cnn_axi_lite_slave dut (
 .s_axi_aclk(clk),
 .s_axi_aresetn(rst_n),
 .s_axi_awaddr(awaddr),
 .s_axi_awvalid(awvalid),
 .s_axi_awready(awready),
 .s_axi_wdata(wdata),
 .s_axi_wstrb(wstrb),
 .s_axi_wvalid(wvalid),
 .s_axi_wready(wready),
 .s_axi_bresp(bresp),
 .s_axi_bvalid(bvalid),
 .s_axi_bready(bready),
 .s_axi_araddr(araddr),
 .s_axi_arvalid(arvalid),
 .s_axi_arready(arready),
 .s_axi_rdata(rdata),
 .s_axi_rresp(rresp),
 .s_axi_rvalid(rvalid),
 .s_axi_rready(rready),
 .start_pulse(start_pulse),
 .clear_pulse(clear_pulse),
 .final_residual_enable(final_residual_enable),
 .image_width(image_width),
 .image_height(image_height),
 .irq(irq),
 .core_busy(core_busy),
 .core_done(core_done),
 .core_error(core_error),
 .core_error_code(core_error_code),
 .structured_error_code(structured_error_code),
 .structured_error_stage(structured_error_stage),
 .structured_error_record_kind(structured_error_record_kind),
 .structured_error_record_index(structured_error_record_index),
 .structured_error_field_id(structured_error_field_id),
 .structured_error_observed(structured_error_observed),
 .structured_error_expected_min(structured_error_expected_min),
 .structured_error_expected_max(structured_error_expected_max),
 .structured_error_model_id(structured_error_model_id),
 .structured_error_model_generation_id(structured_error_model_generation_id),
 .structured_error_detail(structured_error_detail),
 .phase(phase),
 .active_layer(active_layer),
 .weight_layers_ready(weight_layers_ready),
 .prefetch_active(prefetch_active),
 .prefetch_seen(prefetch_seen),
 .input_packet_type(input_packet_type),
 .input_packet_words(input_packet_words),
 .perf_counting(perf_counting),
 .perf_job_cycles(perf_job_cycles),
 .perf_packet_cycles(perf_packet_cycles),
 .perf_compute_cycles(perf_compute_cycles),
 .perf_prefetch_cycles(perf_prefetch_cycles),
 .perf_layer0_cycles(perf_layer0_cycles),
 .perf_layer1_cycles(perf_layer1_cycles),
 .perf_layer2_cycles(perf_layer2_cycles),
 .perf_input_words(perf_input_words),
 .perf_input_stall_cycles(perf_input_stall_cycles),
 .perf_output_words(perf_output_words),
 .perf_output_stall_cycles(perf_output_stall_cycles)
 );

 initial begin
 clk = 1'b0;
 forever #5 clk = ~clk;
 end

 always_ff @(posedge clk or negedge rst_n) begin
 if (!rst_n) begin
 start_count <= 0;
 clear_count <= 0;
 end else begin
 if (start_pulse) begin
 start_count <= start_count + 1;
 end
 if (clear_pulse) begin
 clear_count <= clear_count + 1;
 end
 end
 end

 task automatic check_eq(
 input string name,
 input logic [31:0] got,
 input logic [31:0] expected
 );
 begin
 checks++;
 if (got !== expected) begin
 errors++;
 $error("%s got=0x%08h expected=0x%08h", name, got, expected);
 end
 end
 endtask

 task automatic axi_write(
 input logic [11:0] addr,
 input logic [31:0] data,
 input logic [3:0] strobes,
 output logic [1:0] response
 );
 begin
 @(negedge clk);
 awaddr = addr;
 awvalid = 1'b1;
 wdata = data;
 wstrb = strobes;
 wvalid = 1'b1;
 bready = 1'b1;

 fork
 wait (awready === 1'b1);
 wait (wready === 1'b1);
 join

 @(negedge clk);
 awvalid = 1'b0;
 wvalid = 1'b0;
 wait (bvalid === 1'b1);
 response = bresp;
 @(negedge clk);
 bready = 1'b0;
 end
 endtask

 task automatic axi_write_address_first(
 input logic [11:0] addr,
 input logic [31:0] data
 );
 begin
 @(negedge clk);
 awaddr = addr;
 awvalid = 1'b1;
 wait (awready === 1'b1);
 @(negedge clk);
 awvalid = 1'b0;

 repeat (2) @(negedge clk);
 wdata = data;
 wstrb = 4'hF;
 wvalid = 1'b1;
 bready = 1'b1;
 wait (wready === 1'b1);
 @(negedge clk);
 wvalid = 1'b0;
 wait (bvalid === 1'b1);
 check_eq("address-first BRESP", {30'd0, bresp}, 32'd0);
 @(negedge clk);
 bready = 1'b0;
 end
 endtask

 task automatic axi_read(
 input logic [11:0] addr,
 output logic [31:0] data,
 output logic [1:0] response
 );
 begin
 @(negedge clk);
 araddr = addr;
 arvalid = 1'b1;
 rready = 1'b1;
 wait (arready === 1'b1);
 @(negedge clk);
 arvalid = 1'b0;
 wait (rvalid === 1'b1);
 data = rdata;
 response = rresp;
 @(negedge clk);
 rready = 1'b0;
 end
 endtask

 function automatic logic [31:0] metadata_address_value(
 input logic [1:0] kind,
 input logic [5:0] record_index,
 input logic [5:0] word_index
 );
 begin
 return {18'd0, word_index, record_index, kind};
 end
 endfunction

 task automatic axi_metadata_write(
 input logic [1:0] kind,
 input logic [5:0] record_index,
 input logic [5:0] word_index,
 input logic [31:0] data
 );
 logic [1:0] write_response;
 begin
 axi_write(
 ADDR_METADATA_ADDRESS,
 metadata_address_value(kind, record_index, word_index),
 4'hF,
 write_response
 );
 axi_write(ADDR_METADATA_DATA, data, 4'hF, write_response);
 end
 endtask

 task automatic axi_metadata_commit(
 input logic [1:0] kind,
 input logic [5:0] record_index
 );
 logic [1:0] write_response;
 begin
 axi_write(
 ADDR_METADATA_ADDRESS,
 metadata_address_value(kind, record_index, 0),
 4'hF,
 write_response
 );
 axi_write(ADDR_METADATA_COMMIT, 32'd1, 4'h1, write_response);
 end
 endtask

 initial begin
 checks = 0;
 errors = 0;
 rst_n = 1'b0;
 awaddr = '0;
 awvalid = 1'b0;
 wdata = '0;
 wstrb = '0;
 wvalid = 1'b0;
 bready = 1'b0;
 araddr = '0;
 arvalid = 1'b0;
 rready = 1'b0;

 core_busy = 1'b0;
 core_done = 1'b0;
 core_error = 1'b0;
 core_error_code = 8'h00;
 structured_error_code = 32'h0000_0000;
 structured_error_stage = 8'd0;
 structured_error_record_kind = 8'd0;
 structured_error_record_index = 16'd0;
 structured_error_field_id = 16'd0;
 structured_error_observed = 64'd0;
 structured_error_expected_min = 64'd0;
 structured_error_expected_max = 64'd0;
 structured_error_model_id = 32'd0;
 structured_error_model_generation_id = 32'd0;
 structured_error_detail = 32'd0;
 phase = 4'h0;
 active_layer = 2'h0;
 weight_layers_ready = 3'h0;
 prefetch_active = 1'b0;
 prefetch_seen = 1'b0;
 input_packet_type = 3'h0;
 input_packet_words = 32'd0;
 perf_counting = 1'b0;
 perf_job_cycles = 32'd101;
 perf_packet_cycles = 32'd102;
 perf_compute_cycles = 32'd103;
 perf_prefetch_cycles = 32'd104;
 perf_layer0_cycles = 32'd105;
 perf_layer1_cycles = 32'd106;
 perf_layer2_cycles = 32'd107;
 perf_input_words = 32'd108;
 perf_input_stall_cycles = 32'd109;
 perf_output_words = 32'd110;
 perf_output_stall_cycles = 32'd111;

 repeat (4) @(posedge clk);
 rst_n = 1'b1;
 repeat (2) @(posedge clk);

 axi_read(ADDR_VERSION, rd, resp);
 check_eq("version", rd, 32'h0004_0000);
 check_eq("version RRESP", {30'd0, resp}, 32'd0);

 axi_read(ADDR_CAP_HEADER, rd, resp);
 check_eq("capability header", rd, 32'h0080_0001);
 axi_read(ADDR_CAP_HW_VERSION, rd, resp);
 check_eq("capability hardware version", rd, 32'h0004_0000);
 axi_read(ADDR_CAP_ABI_DMA, rd, resp);
 check_eq("capability ABI and DMA width", rd, 32'h0004_0001);
 axi_read(ADDR_CAP_FEATURES, rd, resp);
 check_eq("capability fixed features", rd, 32'h8000_008B);
 axi_read(ADDR_CAP_LIMITS0, rd, resp);
 check_eq("capability layer tensor limits", rd, 32'h0004_0003);
 axi_read(ADDR_CAP_LIMITS2, rd, resp);
 check_eq("capability output width limits", rd, 32'h0010_0010);
 axi_read(ADDR_CAP_MAX_ELEMENTS, rd, resp);
 check_eq("capability max elements", rd, 32'd16);
 axi_read(ADDR_CAP_PARALLELISM, rd, resp);
 check_eq("capability PC PK", rd, 32'h0004_0002);
 axi_read(ADDR_CAP_CLOCK_HZ, rd, resp);
 check_eq("capability clock", rd, 32'd125_000_000);

 axi_read(ADDR_MODEL_STATUS, rd, resp);
 check_eq("model status reset", rd, 32'h0000_0010);
 axi_write(ADDR_MODEL_COMMAND, 32'h0000_0001, 4'h1, resp);
 axi_read(ADDR_MODEL_STATUS, rd, resp);
 check_eq("model loading status", rd, 32'h0000_0011);

 axi_metadata_write(0, 0, 0, 32'h314E_4E43);
 axi_metadata_write(0, 0, 1, 32'h0080_0001);
 axi_metadata_write(0, 0, 4, 32'd55);
 axi_metadata_write(0, 0, 5, 32'd7);
 axi_metadata_write(0, 0, 6, 32'h0002_0001);
 axi_metadata_write(0, 0, 7, 32'h0000_0001);
 axi_metadata_commit(0, 0);
 axi_metadata_write(1, 0, 0, 32'h0080_0001);
 axi_metadata_write(1, 0, 1, 32'h0001_0000);
 axi_metadata_commit(1, 0);
 axi_metadata_write(2, 0, 0, 32'h0040_0001);
 axi_metadata_write(2, 0, 1, 32'h0001_0000);
 axi_metadata_write(2, 0, 7, 32'd0);
 axi_metadata_commit(2, 0);
 axi_metadata_write(2, 1, 0, 32'h0040_0001);
 axi_metadata_write(2, 1, 1, 32'h0002_0001);
 axi_metadata_write(2, 1, 7, 32'd0);
 axi_metadata_commit(2, 1);
 axi_metadata_write(3, 0, 0, 32'h00C0_0001);
 axi_metadata_write(3, 0, 1, 32'h0000_0000);
 axi_metadata_write(3, 0, 2, 32'h0001_0001);
 axi_metadata_write(3, 0, 16, 32'd1);
 axi_metadata_write(3, 0, 17, 32'd0);
 axi_metadata_commit(3, 0);

 axi_read(ADDR_STAGING_MODEL_ID, rd, resp);
 check_eq("staging model ID", rd, 32'd55);
 axi_read(ADDR_STAGING_GENERATION, rd, resp);
 check_eq("staging generation", rd, 32'd7);
 axi_read(ADDR_STAGING_COUNTS0, rd, resp);
 check_eq("staging layer tensor counts", rd, 32'h0002_0001);
 axi_read(ADDR_STAGING_COUNTS1, rd, resp);
 check_eq("staging quantization count", rd, 32'd1);
 axi_read(ADDR_METADATA_DATA, rd, resp);
 check_eq("metadata aperture readback", rd, 32'h00C0_0001);

 axi_write(ADDR_MODEL_COMMAND, 32'h0000_0002, 4'h1, resp);
 axi_write(ADDR_MODEL_COMMAND, 32'h0000_0004, 4'h1, resp);
 axi_read(ADDR_MODEL_STATUS, rd, resp);
 check_eq("model validated status", rd, 32'h0000_0013);
 axi_write(ADDR_MODEL_COMMAND, 32'h0000_0008, 4'h1, resp);
 axi_read(ADDR_MODEL_STATUS, rd, resp);
 check_eq("model active status", rd, 32'h0000_0038);
 axi_read(ADDR_ACTIVE_MODEL_ID, rd, resp);
 check_eq("active model ID", rd, 32'd55);
 axi_read(ADDR_ACTIVE_GENERATION, rd, resp);
 check_eq("active generation", rd, 32'd7);
 axi_read(ADDR_MODEL_ERROR, rd, resp);
 check_eq("model lifecycle error clear", rd, 32'd0);

 axi_write(ADDR_IMAGE_WIDTH, 32'd640, 4'hF, resp);
 check_eq("width BRESP", {30'd0, resp}, 32'd0);
 axi_write_address_first(ADDR_IMAGE_HEIGHT, 32'd480);
 axi_write(ADDR_MODE_FLAGS, 32'd1, 4'hF, resp);
 axi_read(ADDR_IMAGE_WIDTH, rd, resp);
 check_eq("width readback", rd, 32'd640);
 axi_read(ADDR_IMAGE_HEIGHT, rd, resp);
 check_eq("height readback", rd, 32'd480);
 axi_read(ADDR_MODE_FLAGS, rd, resp);
 check_eq("residual readback", rd, 32'd1);

 axi_write(ADDR_IMAGE_WIDTH, 32'h0000_0034, 4'b0001, resp);
 axi_read(ADDR_IMAGE_WIDTH, rd, resp);
 check_eq("width byte strobe", rd, 32'h0000_0234);

 axi_write(ADDR_CONTROL, 32'd1, 4'h1, resp);
 @(posedge clk);
 @(negedge clk);
 check_eq("start pulse count", start_count, 32'd1);
 check_eq("start pulse released", start_pulse, 32'd0);

 core_busy = 1'b1;
 core_done = 1'b1;
 core_error = 1'b1;
 core_error_code = 8'h42;
 structured_error_code = 32'h0000_0202;
 structured_error_stage = 8'd2;
 structured_error_record_kind = 8'd2;
 structured_error_record_index = 16'd5;
 structured_error_field_id = 16'd9;
 structured_error_observed = 64'h1122_3344_5566_7788;
 structured_error_expected_min = 64'd1;
 structured_error_expected_max = 64'd16;
 structured_error_model_id = 32'd7;
 structured_error_model_generation_id = 32'd9;
 structured_error_detail = 32'h0000_00A5;
 phase = 4'hA;
 active_layer = 2'h2;
 weight_layers_ready = 3'h5;
 prefetch_active = 1'b1;
 prefetch_seen = 1'b1;
 input_packet_type = 3'h6;
 input_packet_words = 32'd77;
 perf_counting = 1'b1;
 repeat (2) @(posedge clk);

 axi_read(ADDR_STATUS, rd, resp);
 check_eq("live status", rd, 32'h0000_76AF);
 axi_read(ADDR_ERROR_CODE, rd, resp);
 check_eq("error code", rd, 32'h0000_0042);
 axi_read(ADDR_STREAM_STATE, rd, resp);
 check_eq("stream state", rd, 32'h0000_002E);
 axi_read(ADDR_PACKET_WORDS, rd, resp);
 check_eq("packet words", rd, 32'd77);
 axi_read(ADDR_ERR_HEADER, rd, resp);
 check_eq("structured error header", rd, 32'h0040_0001);
 axi_read(ADDR_ERR_CODE, rd, resp);
 check_eq("structured error code", rd, 32'h0000_0202);
 axi_read(ADDR_ERR_CONTEXT, rd, resp);
 check_eq("structured error context", rd, 32'h0000_0202);
 axi_read(ADDR_ERR_RECORD_FIELD, rd, resp);
 check_eq("structured error record field", rd, 32'h0009_0005);
 axi_read(ADDR_ERR_OBSERVED_LO, rd, resp);
 check_eq("structured error observed low", rd, 32'h5566_7788);
 axi_read(ADDR_ERR_OBSERVED_HI, rd, resp);
 check_eq("structured error observed high", rd, 32'h1122_3344);
 axi_read(ADDR_ERR_EXPECTED_MIN_LO, rd, resp);
 check_eq("structured error expected min", rd, 32'd1);
 axi_read(ADDR_ERR_EXPECTED_MAX_LO, rd, resp);
 check_eq("structured error expected max", rd, 32'd16);
 axi_read(ADDR_ERR_MODEL_ID, rd, resp);
 check_eq("structured error model ID", rd, 32'd7);
 axi_read(ADDR_ERR_GENERATION, rd, resp);
 check_eq("structured error generation", rd, 32'd9);
 axi_read(ADDR_ERR_DETAIL, rd, resp);
 check_eq("structured error detail", rd, 32'h0000_00A5);

 axi_write(ADDR_IRQ_ENABLE, 32'd3, 4'hF, resp);
 check_eq("IRQ asserted", irq, 32'd1);
 axi_read(ADDR_IRQ_STATUS, rd, resp);
 check_eq("IRQ status", rd, 32'd3);
 axi_write(ADDR_IRQ_STATUS, 32'd1, 4'h1, resp);
 axi_read(ADDR_IRQ_STATUS, rd, resp);
 check_eq("IRQ done W1C", rd, 32'd2);

 axi_read(ADDR_PERF_JOB, rd, resp);
 check_eq("job cycles", rd, 32'd101);
 axi_read(ADDR_PERF_PACKET, rd, resp);
 check_eq("packet cycles", rd, 32'd102);
 axi_read(ADDR_PERF_COMPUTE, rd, resp);
 check_eq("compute cycles", rd, 32'd103);
 axi_read(ADDR_PERF_PREFETCH, rd, resp);
 check_eq("prefetch cycles", rd, 32'd104);
 axi_read(ADDR_PERF_LAYER0, rd, resp);
 check_eq("layer 0 cycles", rd, 32'd105);
 axi_read(ADDR_PERF_LAYER1, rd, resp);
 check_eq("layer 1 cycles", rd, 32'd106);
 axi_read(ADDR_PERF_LAYER2, rd, resp);
 check_eq("layer 2 cycles", rd, 32'd107);
 axi_read(ADDR_PERF_INPUT_WORDS, rd, resp);
 check_eq("input words", rd, 32'd108);
 axi_read(ADDR_PERF_INPUT_STALL, rd, resp);
 check_eq("input stalls", rd, 32'd109);
 axi_read(ADDR_PERF_OUTPUT_WORDS, rd, resp);
 check_eq("output words", rd, 32'd110);
 axi_read(ADDR_PERF_OUTPUT_STALL, rd, resp);
 check_eq("output stalls", rd, 32'd111);

 axi_write(ADDR_STATUS, 32'hFFFF_FFFF, 4'hF, resp);
 check_eq("read-only write SLVERR", {30'd0, resp}, 32'd2);
 axi_read(12'h3FC, rd, resp);
 check_eq("unknown read data", rd, 32'hDEAD_BEEF);
 check_eq("unknown read SLVERR", {30'd0, resp}, 32'd2);

 axi_write(ADDR_CONTROL, 32'd2, 4'h1, resp);
 @(posedge clk);
 @(negedge clk);
 check_eq("clear pulse count", clear_count, 32'd1);
 check_eq("IRQ cleared", irq, 32'd0);
 axi_read(ADDR_IRQ_STATUS, rd, resp);
 check_eq("IRQ status cleared", rd, 32'd0);
 axi_read(ADDR_ERR_CODE, rd, resp);
 check_eq("structured error cleared", rd, 32'd0);

 if (errors == 0) begin
 $display("[PASS] tb_axi_lite_slave tests=%0d", checks);
 end else begin
 $display("[FAIL] tb_axi_lite_slave errors=%0d checks=%0d", errors, checks);
 $fatal(1);
 end

 $finish;
 end

endmodule
