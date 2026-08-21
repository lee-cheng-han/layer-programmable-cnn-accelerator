`timescale 1ns/1ps

module cnn_programmable_axi_lite_slave #(
  parameter int AXI_ADDR_WIDTH = 12
)(
  input  logic s_axi_aclk,
  input  logic s_axi_aresetn,
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

  output logic start_pulse,
  output logic clear_pulse,
  output logic begin_model_load,
  output logic finish_model_load,
  output logic validate_model,
  output logic activate_model,
  output logic retire_active_model,
  output logic clear_model_error,
  output logic metadata_write,
  output logic metadata_commit,
  output logic [1:0] metadata_kind,
  output logic [5:0] metadata_record_index,
  output logic [5:0] metadata_word_index,
  output logic [31:0] metadata_write_data,
  input  logic [31:0] metadata_read_data,
  output logic [31:0] job_id,
  output logic [2:0] parameter_layer_select,
  output logic irq,

  input  logic [2:0] staging_state,
  input  logic model_active_valid,
  input  logic [31:0] active_model_id,
  input  logic [31:0] active_generation_id,
  input  logic [15:0] active_layer_count,
  input  logic [7:0] model_lifecycle_error,
  input  logic [2:0] active_layer,
  input  logic [15:0] active_input_tensor_id,
  input  logic [15:0] active_output_tensor_id,
  input  logic [63:0] active_input_ddr_offset,
  input  logic [63:0] active_output_ddr_offset,
  input  logic [15:0] current_tile_x,
  input  logic [15:0] current_tile_y,
  input  logic [31:0] completed_layer_count,
  input  logic [31:0] completed_tile_count,
  input  logic [31:0] saturation_event_count,
  input  logic layer_done,
  input  logic core_busy,
  input  logic core_done,
  input  logic core_error,
  input  logic [7:0] core_error_code,
  input  logic [2:0] core_error_layer,
  input  logic [31:0] packet_error_count,
  input  logic [1:0] parameter_bank_valid
);
  import cnn_accel_abi_pkg::*;

  localparam logic [AXI_ADDR_WIDTH-1:0] ADDR_CONTROL = REG_CONTROL;
  localparam logic [AXI_ADDR_WIDTH-1:0] ADDR_STATUS = REG_STATUS;
  localparam logic [AXI_ADDR_WIDTH-1:0] ADDR_IRQ_STATUS = REG_IRQ_STATUS;
  localparam logic [AXI_ADDR_WIDTH-1:0] ADDR_IRQ_ENABLE = REG_IRQ_ENABLE;
  localparam logic [AXI_ADDR_WIDTH-1:0] ADDR_JOB_ID = REG_JOB_ID;
  localparam logic [AXI_ADDR_WIDTH-1:0] ADDR_PARAMETER_LAYER = REG_PARAMETER_LAYER;
  localparam logic [AXI_ADDR_WIDTH-1:0] ADDR_MODEL_COMMAND = REG_MODEL_COMMAND;
  localparam logic [AXI_ADDR_WIDTH-1:0] ADDR_MODEL_STATUS = REG_MODEL_STATUS;
  localparam logic [AXI_ADDR_WIDTH-1:0] ADDR_ACTIVE_MODEL_ID = REG_ACTIVE_MODEL_ID;
  localparam logic [AXI_ADDR_WIDTH-1:0] ADDR_ACTIVE_GENERATION = REG_ACTIVE_GENERATION;
  localparam logic [AXI_ADDR_WIDTH-1:0] ADDR_ACTIVE_LAYER_COUNT = REG_ACTIVE_LAYER_COUNT;
  localparam logic [AXI_ADDR_WIDTH-1:0] ADDR_METADATA_ADDRESS = REG_METADATA_ADDRESS;
  localparam logic [AXI_ADDR_WIDTH-1:0] ADDR_METADATA_DATA = REG_METADATA_DATA;
  localparam logic [AXI_ADDR_WIDTH-1:0] ADDR_METADATA_COMMIT = REG_METADATA_COMMIT;
  localparam logic [AXI_ADDR_WIDTH-1:0] ADDR_MODEL_ERROR = REG_MODEL_ERROR;
  localparam logic [AXI_ADDR_WIDTH-1:0] ADDR_RUNTIME_ERROR = REG_RUNTIME_ERROR;
  localparam logic [AXI_ADDR_WIDTH-1:0] ADDR_ACTIVE_TENSORS = REG_ACTIVE_TENSORS;
  localparam logic [AXI_ADDR_WIDTH-1:0] ADDR_CURRENT_TILE = REG_CURRENT_TILE;
  localparam logic [AXI_ADDR_WIDTH-1:0] ADDR_COMPLETED_LAYERS = REG_COMPLETED_LAYERS;
  localparam logic [AXI_ADDR_WIDTH-1:0] ADDR_COMPLETED_TILES = REG_COMPLETED_TILES;
  localparam logic [AXI_ADDR_WIDTH-1:0] ADDR_PACKET_ERRORS = REG_PACKET_ERRORS;
  localparam logic [AXI_ADDR_WIDTH-1:0] ADDR_PARAMETER_BANKS = REG_PARAMETER_BANKS;
  localparam logic [AXI_ADDR_WIDTH-1:0] ADDR_INPUT_DDR_LO = REG_INPUT_DDR_LO;
  localparam logic [AXI_ADDR_WIDTH-1:0] ADDR_INPUT_DDR_HI = REG_INPUT_DDR_HI;
  localparam logic [AXI_ADDR_WIDTH-1:0] ADDR_OUTPUT_DDR_LO = REG_OUTPUT_DDR_LO;
  localparam logic [AXI_ADDR_WIDTH-1:0] ADDR_OUTPUT_DDR_HI = REG_OUTPUT_DDR_HI;
  localparam logic [AXI_ADDR_WIDTH-1:0] ADDR_SATURATION_EVENTS = REG_SATURATION_EVENTS;
  localparam logic [AXI_ADDR_WIDTH-1:0] ADDR_VERSION = REG_VERSION;

  localparam logic [1:0] AXI_RESP_OKAY = 2'b00;
  localparam logic [1:0] AXI_RESP_SLVERR = 2'b10;

  logic [AXI_ADDR_WIDTH-1:0] awaddr_q;
  logic [31:0] wdata_q;
  logic [3:0] wstrb_q;
  logic aw_have;
  logic w_have;
  logic [1:0] irq_status;
  logic [1:0] irq_enable;
  logic core_done_q;
  logic core_error_q;
  logic [31:0] metadata_address;
  logic [31:0] irq_enable_merged;
  logic [31:0] parameter_layer_merged;

  function automatic logic [31:0] apply_wstrb(
    input logic [31:0] old_value,
    input logic [31:0] new_value,
    input logic [3:0] byte_strobe
  );
    logic [31:0] merged;
    begin
      merged = old_value;
      for (int lane = 0; lane < 4; lane++) begin
        if (byte_strobe[lane]) begin
          merged[lane*8 +: 8] = new_value[lane*8 +: 8];
        end
      end
      return merged;
    end
  endfunction

  assign metadata_kind = metadata_address[1:0];
  assign metadata_record_index = metadata_address[7:2];
  assign metadata_word_index = metadata_address[13:8];
  assign irq = |(irq_status & irq_enable);
  assign irq_enable_merged =
    apply_wstrb({30'd0, irq_enable}, wdata_q, wstrb_q);
  assign parameter_layer_merged =
    apply_wstrb({29'd0, parameter_layer_select}, wdata_q, wstrb_q);

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
      begin_model_load <= 1'b0;
      finish_model_load <= 1'b0;
      validate_model <= 1'b0;
      activate_model <= 1'b0;
      retire_active_model <= 1'b0;
      clear_model_error <= 1'b0;
      metadata_write <= 1'b0;
      metadata_commit <= 1'b0;
      metadata_write_data <= '0;
      metadata_address <= '0;
      job_id <= '0;
      parameter_layer_select <= '0;
      irq_status <= '0;
      irq_enable <= '0;
      core_done_q <= 1'b0;
      core_error_q <= 1'b0;
    end else begin
      s_axi_awready <= 1'b0;
      s_axi_wready <= 1'b0;
      start_pulse <= 1'b0;
      clear_pulse <= 1'b0;
      begin_model_load <= 1'b0;
      finish_model_load <= 1'b0;
      validate_model <= 1'b0;
      activate_model <= 1'b0;
      retire_active_model <= 1'b0;
      clear_model_error <= 1'b0;
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
              if (wdata_q[1]) irq_status <= '0;
            end
          end
          ADDR_IRQ_STATUS: begin
            if (wstrb_q[0]) irq_status <= irq_status & ~wdata_q[1:0];
          end
          ADDR_IRQ_ENABLE: irq_enable <= irq_enable_merged[1:0];
          ADDR_JOB_ID:
            job_id <= apply_wstrb(job_id, wdata_q, wstrb_q);
          ADDR_PARAMETER_LAYER:
            parameter_layer_select <= parameter_layer_merged[2:0];
          ADDR_MODEL_COMMAND: begin
            if (wstrb_q[0]) begin
              begin_model_load <= wdata_q[0];
              finish_model_load <= wdata_q[1];
              validate_model <= wdata_q[2];
              activate_model <= wdata_q[3];
              retire_active_model <= wdata_q[4];
              clear_model_error <= wdata_q[5];
            end
          end
          ADDR_METADATA_ADDRESS:
            metadata_address <=
              apply_wstrb(metadata_address, wdata_q, wstrb_q);
          ADDR_METADATA_DATA: begin
            metadata_write_data <= wdata_q;
            metadata_write <= |wstrb_q;
          end
          ADDR_METADATA_COMMIT: begin
            if (wstrb_q[0]) metadata_commit <= wdata_q[0];
          end
          ADDR_MODEL_ERROR: begin
            if (wstrb_q[0]) clear_model_error <= wdata_q[0];
          end
          default: s_axi_bresp <= AXI_RESP_SLVERR;
        endcase
        aw_have <= 1'b0;
        w_have <= 1'b0;
        s_axi_bvalid <= 1'b1;
      end

      if (s_axi_bvalid && s_axi_bready) s_axi_bvalid <= 1'b0;
      if (core_done && !core_done_q) irq_status[0] <= 1'b1;
      if (core_error && !core_error_q) irq_status[1] <= 1'b1;
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
        unique case (s_axi_araddr)
          ADDR_CONTROL: s_axi_rdata <= 32'd0;
          ADDR_STATUS:
            s_axi_rdata <= {16'd0, parameter_bank_valid, 4'd0,
                            active_layer, model_active_valid, layer_done,
                            core_error, core_done, core_busy};
          ADDR_IRQ_STATUS: s_axi_rdata <= {30'd0, irq_status};
          ADDR_IRQ_ENABLE: s_axi_rdata <= {30'd0, irq_enable};
          ADDR_JOB_ID: s_axi_rdata <= job_id;
          ADDR_PARAMETER_LAYER:
            s_axi_rdata <= {29'd0, parameter_layer_select};
          ADDR_MODEL_COMMAND: s_axi_rdata <= 32'd0;
          ADDR_MODEL_STATUS:
            s_axi_rdata <= {20'd0, model_lifecycle_error,
                            model_active_valid, staging_state};
          ADDR_ACTIVE_MODEL_ID: s_axi_rdata <= active_model_id;
          ADDR_ACTIVE_GENERATION: s_axi_rdata <= active_generation_id;
          ADDR_ACTIVE_LAYER_COUNT:
            s_axi_rdata <= {16'd0, active_layer_count};
          ADDR_METADATA_ADDRESS: s_axi_rdata <= metadata_address;
          ADDR_METADATA_DATA: s_axi_rdata <= metadata_read_data;
          ADDR_METADATA_COMMIT: s_axi_rdata <= 32'd0;
          ADDR_MODEL_ERROR:
            s_axi_rdata <= {24'd0, model_lifecycle_error};
          ADDR_RUNTIME_ERROR:
            s_axi_rdata <= {21'd0, core_error_layer, core_error_code};
          ADDR_ACTIVE_TENSORS:
            s_axi_rdata <= {active_output_tensor_id, active_input_tensor_id};
          ADDR_CURRENT_TILE:
            s_axi_rdata <= {current_tile_y, current_tile_x};
          ADDR_COMPLETED_LAYERS: s_axi_rdata <= completed_layer_count;
          ADDR_COMPLETED_TILES: s_axi_rdata <= completed_tile_count;
          ADDR_PACKET_ERRORS: s_axi_rdata <= packet_error_count;
          ADDR_PARAMETER_BANKS:
            s_axi_rdata <= {30'd0, parameter_bank_valid};
          ADDR_INPUT_DDR_LO: s_axi_rdata <= active_input_ddr_offset[31:0];
          ADDR_INPUT_DDR_HI: s_axi_rdata <= active_input_ddr_offset[63:32];
          ADDR_OUTPUT_DDR_LO: s_axi_rdata <= active_output_ddr_offset[31:0];
          ADDR_OUTPUT_DDR_HI: s_axi_rdata <= active_output_ddr_offset[63:32];
          ADDR_SATURATION_EVENTS: s_axi_rdata <= saturation_event_count;
          ADDR_VERSION: s_axi_rdata <= REGISTER_MAP_VERSION;
          default: begin
            s_axi_rdata <= 32'hDEAD_BEEF;
            s_axi_rresp <= AXI_RESP_SLVERR;
          end
        endcase
      end
      if (s_axi_rvalid && s_axi_rready) s_axi_rvalid <= 1'b0;
    end
  end
endmodule
