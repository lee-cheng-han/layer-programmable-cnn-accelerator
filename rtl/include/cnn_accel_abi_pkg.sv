`default_nettype none
`timescale 1ns/1ps

package cnn_accel_abi_pkg;
  `include "cnn_accel_abi_constants.svh"

  typedef enum logic [31:0] {
    ERROR_NONE = 32'h0000_0000,
    ERROR_PACKAGE_VALIDATION_FAILED = 32'h0000_0101,
    ERROR_MODEL_ABI_UNSUPPORTED = 32'h0000_0102,
    ERROR_CAPABILITY_FEATURE_MISSING = 32'h0000_0201,
    ERROR_CAPABILITY_LIMIT_EXCEEDED = 32'h0000_0202,
    ERROR_UNSUPPORTED_OPERATION = 32'h0000_0203,
    ERROR_DATA_PLANE_PROTOCOL = 32'h0000_0400
  } error_code_e;

  typedef enum logic [7:0] {
    ERROR_STAGE_NONE = 8'd0,
    ERROR_STAGE_PACKAGE_LOAD = 8'd1,
    ERROR_STAGE_PACKAGE_VALIDATE = 8'd2,
    ERROR_STAGE_MODEL_ACTIVATE = 8'd3,
    ERROR_STAGE_EXECUTE = 8'd4,
    ERROR_STAGE_DATA_PLANE = 8'd5
  } error_stage_e;

  typedef enum logic [7:0] {
    ERROR_RECORD_NONE = 8'd0,
    ERROR_RECORD_MODEL = 8'd1,
    ERROR_RECORD_LAYER = 8'd2,
    ERROR_RECORD_TENSOR = 8'd3,
    ERROR_RECORD_QUANTIZATION = 8'd4,
    ERROR_RECORD_PACKET = 8'd5
  } error_record_kind_e;

  typedef enum logic [15:0] {
    ERROR_FIELD_NONE = 16'd0,
    ERROR_FIELD_ABI_VERSION = 16'd1,
    ERROR_FIELD_FEATURE_FLAGS = 16'd2,
    ERROR_FIELD_LAYER_COUNT = 16'd3,
    ERROR_FIELD_TENSOR_COUNT = 16'd4,
    ERROR_FIELD_QUANTIZATION_COUNT = 16'd5,
    ERROR_FIELD_WIDTH = 16'd6,
    ERROR_FIELD_HEIGHT = 16'd7,
    ERROR_FIELD_INPUT_CHANNELS = 16'd8,
    ERROR_FIELD_OUTPUT_CHANNELS = 16'd9,
    ERROR_FIELD_OPCODE = 16'd10,
    ERROR_FIELD_KERNEL_SIZE = 16'd11,
    ERROR_FIELD_STRIDE = 16'd12,
    ERROR_FIELD_PADDING = 16'd13,
    ERROR_FIELD_WEIGHT_BYTES = 16'd14,
    ERROR_FIELD_BIAS_BYTES = 16'd15,
    ERROR_FIELD_ELEMENT_TYPE = 16'd16,
    ERROR_FIELD_ACTIVATION = 16'd17,
    ERROR_FIELD_ROUNDING_MODE = 16'd18,
    ERROR_FIELD_RESIDUAL_MODE = 16'd19,
    ERROR_FIELD_PACKET_TYPE = 16'd20,
    ERROR_FIELD_PAYLOAD_LENGTH = 16'd21,
    ERROR_FIELD_TENSOR_ELEMENTS = 16'd22,
    ERROR_FIELD_QUANT_MULTIPLIER = 16'd23,
    ERROR_FIELD_QUANT_SHIFT = 16'd24,
    ERROR_FIELD_OUTPUT_ZERO_POINT = 16'd25
  } error_field_e;

  typedef enum logic [15:0] {
    OPCODE_CONV2D = 16'd1
  } opcode_e;

  typedef enum logic [7:0] {
    ACTIVATION_NONE = 8'd0,
    ACTIVATION_RELU = 8'd1
  } activation_e;

  typedef enum logic [7:0] {
    RESIDUAL_NONE = 8'd0,
    RESIDUAL_POST_QUANT_ADD = 8'd1,
    RESIDUAL_POST_QUANT_SUBTRACT = 8'd2
  } residual_mode_e;

  typedef enum logic [7:0] {
    ROUND_ARITHMETIC_SHIFT = 8'd0,
    ROUND_HALF_TO_EVEN = 8'd1
  } rounding_mode_e;

  typedef enum logic [2:0] {
    MODEL_STAGING_UNLOADED = 3'd0,
    MODEL_STAGING_LOADING = 3'd1,
    MODEL_STAGING_LOADED_UNVALIDATED = 3'd2,
    MODEL_STAGING_VALIDATED = 3'd3
  } model_staging_state_e;

  typedef enum logic [7:0] {
    MODEL_LIFECYCLE_OK = 8'd0,
    MODEL_LIFECYCLE_BAD_STATE = 8'd1,
    MODEL_LIFECYCLE_BUSY = 8'd2,
    MODEL_LIFECYCLE_BAD_ADDRESS = 8'd3,
    MODEL_LIFECYCLE_INCOMPLETE = 8'd4,
    MODEL_LIFECYCLE_BAD_HEADER = 8'd5,
    MODEL_LIFECYCLE_LIMIT = 8'd6,
    MODEL_LIFECYCLE_BAD_DESCRIPTOR = 8'd7
  } model_lifecycle_error_e;

  localparam logic [31:0] LAYER_FLAG_BIAS_ENABLE = 32'h0000_0001;
  localparam logic [31:0] LAYER_FLAG_LAST_LAYER = 32'h0000_0002;
  localparam logic [15:0] TENSOR_FLAG_MODEL_INPUT = 16'h0001;
  localparam logic [15:0] TENSOR_FLAG_MODEL_OUTPUT = 16'h0002;
  localparam logic [15:0] TENSOR_FLAG_CONSTANT = 16'h0004;

  localparam int unsigned MH_PACKAGE_SIZE_OFS = 8;
  localparam int unsigned MH_LAYER_COUNT_OFS = 24;
  localparam int unsigned MH_LAYER_TABLE_OFS = 32;
  localparam int unsigned MH_TENSOR_TABLE_OFS = 36;
  localparam int unsigned MH_QUANT_TABLE_OFS = 40;
  localparam int unsigned MH_PARAMETER_DATA_OFS = 44;
  localparam int unsigned MH_PACKAGE_CRC32_OFS = 56;
  localparam int unsigned MH_INPUT_TENSOR_ID_OFS = 60;
  localparam int unsigned MH_PACKAGE_SHA256_OFS = 64;

  localparam int unsigned LD_LAYER_ID_OFS = 4;
  localparam int unsigned LD_INPUT_TENSOR_ID_OFS = 12;
  localparam int unsigned LD_WEIGHT_OFFSET_OFS = 20;
  localparam int unsigned LD_PARAMETER_CRC32_OFS = 36;
  localparam int unsigned LD_GEOMETRY_OFS = 40;
  localparam int unsigned LD_TILE_HINT_OFS = 52;

  localparam int unsigned TD_TENSOR_ID_OFS = 4;
  localparam int unsigned TD_DDR_OFFSET_OFS = 8;
  localparam int unsigned TD_WIDTH_OFS = 20;
  localparam int unsigned TD_ROW_STRIDE_OFS = 36;

  localparam int unsigned QD_QUANTIZATION_ID_OFS = 4;
  localparam int unsigned QD_CHANNEL_COUNT_OFS = 8;
  localparam int unsigned QD_ROUNDING_MODE_OFS = 10;
  localparam int unsigned QD_OUTPUT_ZERO_POINT_OFS = 11;
  localparam int unsigned QD_CHANNEL_PARAMS_OFS = 64;
  localparam int unsigned QD_CHANNEL_PARAM_BYTES = 8;

  localparam int unsigned CAP_HARDWARE_VERSION_OFS = 4;
  localparam int unsigned CAP_MODEL_ABI_VERSION_OFS = 8;
  localparam int unsigned CAP_FEATURE_FLAGS_OFS = 12;
  localparam int unsigned CAP_LIMITS_OFS = 44;
  localparam int unsigned CAP_MAX_TENSOR_ELEMENTS_OFS = 64;
  localparam int unsigned CAP_BANK_CAPACITY_OFS = 68;
  localparam int unsigned CAP_PARALLELISM_OFS = 88;
  localparam int unsigned CAP_CLOCK_HZ_OFS = 92;

  localparam int unsigned ERR_CODE_OFS = 4;
  localparam int unsigned ERR_CONTEXT_OFS = 8;
  localparam int unsigned ERR_RECORD_INDEX_OFS = 12;
  localparam int unsigned ERR_OBSERVED_OFS = 16;
  localparam int unsigned ERR_EXPECTED_MIN_OFS = 24;
  localparam int unsigned ERR_EXPECTED_MAX_OFS = 32;
  localparam int unsigned ERR_MODEL_ID_OFS = 40;
  localparam int unsigned ERR_DETAIL_OFS = 48;
endpackage

`default_nettype wire
