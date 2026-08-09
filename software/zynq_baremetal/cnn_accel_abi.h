#ifndef CNN_ACCEL_ABI_H
#define CNN_ACCEL_ABI_H

#include <stdint.h>

/* Frozen V1 model-package ABI. Records are serialized explicitly; do not cast
 * untrusted package memory to native C structs. */
#define CNN_ABI_VERSION                    1u
#define CNN_MODEL_MAGIC                    0x314E4E43u
#define CNN_MODEL_HEADER_SIZE              128u
#define CNN_LAYER_DESCRIPTOR_SIZE          128u
#define CNN_TENSOR_DESCRIPTOR_SIZE          64u
#define CNN_QUANT_DESCRIPTOR_SIZE          192u
#define CNN_CAPABILITY_RECORD_SIZE         128u
#define CNN_ERROR_RECORD_SIZE               64u
#define CNN_ABI_RECORD_ALIGNMENT            64u
#define CNN_NO_TENSOR_ID                 0xFFFFu
#define CNN_REGISTER_MAP_VERSION      0x00050001u

/* Programmable runtime register map. */
#define CNN_REG_CONTROL                    0x000u
#define CNN_REG_STATUS                     0x004u
#define CNN_REG_IRQ_STATUS                 0x008u
#define CNN_REG_IRQ_ENABLE                 0x00Cu
#define CNN_REG_JOB_ID                     0x010u
#define CNN_REG_PARAMETER_LAYER            0x014u
#define CNN_REG_MODEL_COMMAND              0x018u
#define CNN_REG_MODEL_STATUS               0x01Cu
#define CNN_REG_ACTIVE_MODEL_ID            0x020u
#define CNN_REG_ACTIVE_GENERATION          0x024u
#define CNN_REG_ACTIVE_LAYER_COUNT         0x028u
#define CNN_REG_METADATA_ADDRESS           0x02Cu
#define CNN_REG_METADATA_DATA              0x030u
#define CNN_REG_METADATA_COMMIT            0x034u
#define CNN_REG_MODEL_ERROR                0x038u
#define CNN_REG_RUNTIME_ERROR              0x03Cu
#define CNN_REG_ACTIVE_TENSORS             0x040u
#define CNN_REG_CURRENT_TILE               0x044u
#define CNN_REG_COMPLETED_LAYERS            0x048u
#define CNN_REG_COMPLETED_TILES             0x04Cu
#define CNN_REG_PACKET_ERRORS               0x050u
#define CNN_REG_PARAMETER_BANKS             0x054u
#define CNN_REG_INPUT_DDR_LO                0x058u
#define CNN_REG_INPUT_DDR_HI                0x05Cu
#define CNN_REG_OUTPUT_DDR_LO               0x060u
#define CNN_REG_OUTPUT_DDR_HI               0x064u
#define CNN_REG_SATURATION_EVENTS           0x068u
#define CNN_REG_VERSION                     0x0FCu

#define CNN_CONTROL_START                   (1u << 0)
#define CNN_CONTROL_CLEAR                   (1u << 1)
#define CNN_STATUS_BUSY                     (1u << 0)
#define CNN_STATUS_DONE                     (1u << 1)
#define CNN_STATUS_ERROR                    (1u << 2)
#define CNN_STATUS_LAYER_DONE               (1u << 3)
#define CNN_STATUS_MODEL_ACTIVE             (1u << 4)
#define CNN_STATUS_ACTIVE_LAYER_SHIFT       5u
#define CNN_STATUS_ACTIVE_LAYER_MASK        (7u << CNN_STATUS_ACTIVE_LAYER_SHIFT)
#define CNN_STATUS_PARAMETER_BANK_SHIFT     12u
#define CNN_STATUS_PARAMETER_BANK_MASK      (3u << CNN_STATUS_PARAMETER_BANK_SHIFT)
#define CNN_IRQ_DONE                        (1u << 0)
#define CNN_IRQ_ERROR                       (1u << 1)

#define CNN_MAX_LAYERS                       8u
#define CNN_MAX_TENSORS                     32u
#define CNN_MAX_QUANTIZATIONS               32u
#define CNN_MAX_CHANNELS                    16u
#define CNN_MAX_TENSOR_WIDTH              1024u
#define CNN_MAX_TENSOR_HEIGHT             1024u
#define CNN_MAX_LAYER_WEIGHT_BYTES        2304u
#define CNN_MAX_LAYER_BIAS_BYTES            64u
#define CNN_WEIGHT_BANK_CAPACITY_BYTES    4096u
#define CNN_POSTPROCESS_BANK_CAPACITY_BYTES 256u
#define CNN_BIAS_BANK_CAPACITY_BYTES CNN_POSTPROCESS_BANK_CAPACITY_BYTES
#define CNN_POSTPROCESS_ENTRY_SIZE          16u

#define CNN_FEATURE_CAPABILITY_QUERY   (1u << 0)
#define CNN_FEATURE_STRUCTURED_ERRORS  (1u << 1)
#define CNN_FEATURE_MODEL_PACKAGES     (1u << 2)
#define CNN_FEATURE_RUNTIME_METADATA   (1u << 3)
#define CNN_FEATURE_PACKED_DMA         (1u << 4)
#define CNN_FEATURE_DDR_TILING         (1u << 5)
#define CNN_FEATURE_AUTONOMOUS_FETCH   (1u << 6)
#define CNN_FEATURE_INTERRUPTS         (1u << 7)
#define CNN_FEATURE_FIXED_NETWORK      (1u << 31)

#define CNN_MODEL_COMMAND_BEGIN_LOAD   (1u << 0)
#define CNN_MODEL_COMMAND_FINISH_LOAD  (1u << 1)
#define CNN_MODEL_COMMAND_VALIDATE     (1u << 2)
#define CNN_MODEL_COMMAND_ACTIVATE     (1u << 3)
#define CNN_MODEL_COMMAND_RETIRE       (1u << 4)
#define CNN_MODEL_COMMAND_CLEAR_ERROR  (1u << 5)

#define CNN_DMA_PACKET_MAGIC           0x31504E43u
#define CNN_DMA_PACKET_VERSION                  1u
#define CNN_DMA_PACKET_HEADER_WORDS             8u
#define CNN_DMA_PACKET_HEADER_BYTES             32u
#define CNN_DMA_PACKET_INPUT_TILE                 1u
#define CNN_DMA_PACKET_LAYER_WEIGHTS              2u
#define CNN_DMA_PACKET_LAYER_BIASES               3u
#define CNN_DMA_PACKET_OUTPUT_TILE                4u

enum cnn_model_staging_state {
    CNN_MODEL_STAGING_UNLOADED = 0,
    CNN_MODEL_STAGING_LOADING = 1,
    CNN_MODEL_STAGING_LOADED_UNVALIDATED = 2,
    CNN_MODEL_STAGING_VALIDATED = 3
};

enum cnn_model_lifecycle_error {
    CNN_MODEL_LIFECYCLE_OK = 0,
    CNN_MODEL_LIFECYCLE_BAD_STATE = 1,
    CNN_MODEL_LIFECYCLE_BUSY = 2,
    CNN_MODEL_LIFECYCLE_BAD_ADDRESS = 3,
    CNN_MODEL_LIFECYCLE_INCOMPLETE = 4,
    CNN_MODEL_LIFECYCLE_BAD_HEADER = 5,
    CNN_MODEL_LIFECYCLE_LIMIT = 6,
    CNN_MODEL_LIFECYCLE_BAD_DESCRIPTOR = 7
};

#define CNN_METADATA_KIND_HEADER        0u
#define CNN_METADATA_KIND_LAYER         1u
#define CNN_METADATA_KIND_TENSOR        2u
#define CNN_METADATA_KIND_QUANTIZATION  3u
#define CNN_METADATA_ADDRESS(kind, record, word) \
    ((((uint32_t)(word) & 0x3Fu) << 8) | \
     (((uint32_t)(record) & 0x3Fu) << 2) | ((uint32_t)(kind) & 0x3u))

enum cnn_error_code {
    CNN_ERROR_NONE = 0x0000,
    CNN_ERROR_PACKAGE_VALIDATION_FAILED = 0x0101,
    CNN_ERROR_MODEL_ABI_UNSUPPORTED = 0x0102,
    CNN_ERROR_CAPABILITY_FEATURE_MISSING = 0x0201,
    CNN_ERROR_CAPABILITY_LIMIT_EXCEEDED = 0x0202,
    CNN_ERROR_UNSUPPORTED_OPERATION = 0x0203,
    CNN_ERROR_DATA_PLANE_PROTOCOL = 0x0400
};

enum cnn_error_stage {
    CNN_ERROR_STAGE_NONE = 0,
    CNN_ERROR_STAGE_PACKAGE_LOAD = 1,
    CNN_ERROR_STAGE_PACKAGE_VALIDATE = 2,
    CNN_ERROR_STAGE_MODEL_ACTIVATE = 3,
    CNN_ERROR_STAGE_EXECUTE = 4,
    CNN_ERROR_STAGE_DATA_PLANE = 5
};

enum cnn_error_record_kind {
    CNN_ERROR_RECORD_NONE = 0,
    CNN_ERROR_RECORD_MODEL = 1,
    CNN_ERROR_RECORD_LAYER = 2,
    CNN_ERROR_RECORD_TENSOR = 3,
    CNN_ERROR_RECORD_QUANTIZATION = 4,
    CNN_ERROR_RECORD_PACKET = 5
};

enum cnn_error_field {
    CNN_ERROR_FIELD_NONE = 0,
    CNN_ERROR_FIELD_ABI_VERSION = 1,
    CNN_ERROR_FIELD_FEATURE_FLAGS = 2,
    CNN_ERROR_FIELD_LAYER_COUNT = 3,
    CNN_ERROR_FIELD_TENSOR_COUNT = 4,
    CNN_ERROR_FIELD_QUANTIZATION_COUNT = 5,
    CNN_ERROR_FIELD_WIDTH = 6,
    CNN_ERROR_FIELD_HEIGHT = 7,
    CNN_ERROR_FIELD_INPUT_CHANNELS = 8,
    CNN_ERROR_FIELD_OUTPUT_CHANNELS = 9,
    CNN_ERROR_FIELD_OPCODE = 10,
    CNN_ERROR_FIELD_KERNEL_SIZE = 11,
    CNN_ERROR_FIELD_STRIDE = 12,
    CNN_ERROR_FIELD_PADDING = 13,
    CNN_ERROR_FIELD_WEIGHT_BYTES = 14,
    CNN_ERROR_FIELD_BIAS_BYTES = 15,
    CNN_ERROR_FIELD_ELEMENT_TYPE = 16,
    CNN_ERROR_FIELD_ACTIVATION = 17,
    CNN_ERROR_FIELD_ROUNDING_MODE = 18,
    CNN_ERROR_FIELD_RESIDUAL_MODE = 19,
    CNN_ERROR_FIELD_PACKET_TYPE = 20,
    CNN_ERROR_FIELD_PAYLOAD_LENGTH = 21,
    CNN_ERROR_FIELD_TENSOR_ELEMENTS = 22,
    CNN_ERROR_FIELD_QUANT_MULTIPLIER = 23,
    CNN_ERROR_FIELD_QUANT_SHIFT = 24,
    CNN_ERROR_FIELD_OUTPUT_ZERO_POINT = 25
};

enum cnn_opcode {
    CNN_OPCODE_CONV2D = 1
};

enum cnn_activation {
    CNN_ACTIVATION_NONE = 0,
    CNN_ACTIVATION_RELU = 1
};

enum cnn_residual_mode {
    CNN_RESIDUAL_NONE = 0,
    CNN_RESIDUAL_POST_QUANT_ADD = 1,
    CNN_RESIDUAL_POST_QUANT_SUBTRACT = 2
};

enum cnn_rounding_mode {
    CNN_ROUND_ARITHMETIC_SHIFT = 0,
    CNN_ROUND_HALF_TO_EVEN = 1
};

enum cnn_element_type {
    CNN_ELEMENT_INT8 = 1
};

enum cnn_tensor_layout {
    CNN_LAYOUT_NHWC = 1
};

#define CNN_LAYER_FLAG_BIAS_ENABLE  (1u << 0)
#define CNN_LAYER_FLAG_LAST_LAYER   (1u << 1)
#define CNN_TENSOR_FLAG_MODEL_INPUT (1u << 0)
#define CNN_TENSOR_FLAG_MODEL_OUTPUT (1u << 1)
#define CNN_TENSOR_FLAG_CONSTANT    (1u << 2)

/* Byte offsets are the normative interface for software serializers. */
#define CNN_MH_PACKAGE_SIZE_OFS       8u
#define CNN_MH_LAYER_COUNT_OFS       24u
#define CNN_MH_LAYER_TABLE_OFS       32u
#define CNN_MH_TENSOR_TABLE_OFS      36u
#define CNN_MH_QUANT_TABLE_OFS       40u
#define CNN_MH_PARAMETER_DATA_OFS    44u
#define CNN_MH_PACKAGE_CRC32_OFS     56u
#define CNN_MH_INPUT_TENSOR_ID_OFS   60u
#define CNN_MH_PACKAGE_SHA256_OFS    64u

#define CNN_LD_LAYER_ID_OFS           4u
#define CNN_LD_INPUT_TENSOR_ID_OFS   12u
#define CNN_LD_WEIGHT_OFFSET_OFS     20u
#define CNN_LD_PARAMETER_CRC32_OFS   36u
#define CNN_LD_GEOMETRY_OFS          40u
#define CNN_LD_TILE_HINT_OFS         52u

#define CNN_TD_TENSOR_ID_OFS          4u
#define CNN_TD_DDR_OFFSET_OFS         8u
#define CNN_TD_WIDTH_OFS             20u
#define CNN_TD_ROW_STRIDE_OFS        36u

#define CNN_QD_QUANTIZATION_ID_OFS    4u
#define CNN_QD_CHANNEL_COUNT_OFS       8u
#define CNN_QD_ROUNDING_MODE_OFS      10u
#define CNN_QD_OUTPUT_ZERO_POINT_OFS  11u
#define CNN_QD_CHANNEL_PARAMS_OFS     64u
#define CNN_QD_CHANNEL_PARAM_SIZE      8u

#define CNN_CAP_HARDWARE_VERSION_OFS       4u
#define CNN_CAP_MODEL_ABI_VERSION_OFS      8u
#define CNN_CAP_FEATURE_FLAGS_OFS         12u
#define CNN_CAP_LIMITS_OFS                44u
#define CNN_CAP_MAX_TENSOR_ELEMENTS_OFS   64u
#define CNN_CAP_BANK_CAPACITY_OFS         68u
#define CNN_CAP_PARALLELISM_OFS           88u
#define CNN_CAP_CLOCK_HZ_OFS              92u

#define CNN_ERR_CODE_OFS                   4u
#define CNN_ERR_CONTEXT_OFS                8u
#define CNN_ERR_RECORD_INDEX_OFS          12u
#define CNN_ERR_OBSERVED_OFS              16u
#define CNN_ERR_EXPECTED_MIN_OFS          24u
#define CNN_ERR_EXPECTED_MAX_OFS          32u
#define CNN_ERR_MODEL_ID_OFS              40u
#define CNN_ERR_DETAIL_OFS                48u

#endif
