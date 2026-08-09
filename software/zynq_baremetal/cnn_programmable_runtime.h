#ifndef CNN_PROGRAMMABLE_RUNTIME_H
#define CNN_PROGRAMMABLE_RUNTIME_H

#include <stddef.h>
#include <stdint.h>

#include "cnn_accel_abi.h"

enum cnn_runtime_result {
    CNN_RUNTIME_OK = 0,
    CNN_RUNTIME_BAD_ARGUMENT = -1,
    CNN_RUNTIME_BAD_PACKAGE = -2,
    CNN_RUNTIME_BAD_CHECKSUM = -3,
    CNN_RUNTIME_UNSUPPORTED = -4,
    CNN_RUNTIME_BUFFER_TOO_SMALL = -5,
    CNN_RUNTIME_BAD_PACKET = -6
};

struct cnn_model_view {
    const uint8_t *package;
    size_t package_size;
    uint32_t model_id;
    uint32_t generation_id;
    uint16_t layer_count;
    uint16_t tensor_count;
    uint16_t quantization_count;
    uint16_t input_tensor_id;
    uint16_t output_tensor_id;
    uint32_t layer_table_offset;
    uint32_t tensor_table_offset;
    uint32_t quantization_table_offset;
    uint32_t parameter_data_offset;
    uint32_t parameter_data_size;
    uint32_t workspace_size;
};

struct cnn_layer_view {
    const uint8_t *record;
    uint16_t layer_id;
    uint16_t input_tensor_id;
    uint16_t output_tensor_id;
    uint16_t residual_tensor_id;
    uint16_t quantization_id;
    uint32_t flags;
    uint32_t weight_offset;
    uint32_t weight_size;
    uint32_t bias_offset;
    uint32_t bias_size;
    uint32_t parameter_crc32;
    uint8_t kernel_height;
    uint8_t kernel_width;
    uint8_t stride_y;
    uint8_t stride_x;
    uint8_t padding_top;
    uint8_t padding_bottom;
    uint8_t padding_left;
    uint8_t padding_right;
    uint8_t activation;
    uint8_t residual_mode;
    uint16_t tile_height_hint;
    uint16_t tile_width_hint;
};

struct cnn_tensor_view {
    const uint8_t *record;
    uint16_t tensor_id;
    uint16_t flags;
    uint64_t ddr_offset;
    uint32_t allocation_size;
    uint16_t width;
    uint16_t height;
    uint16_t channels;
    uint16_t quantization_id;
    uint32_t row_stride;
    uint32_t pixel_stride;
    uint32_t channel_stride;
};

struct cnn_tile {
    uint16_t x;
    uint16_t y;
    uint16_t width;
    uint16_t height;
};

struct cnn_dma_packet {
    uint8_t type;
    uint32_t job_id;
    uint16_t tensor_id;
    uint16_t layer_id;
    struct cnn_tile tile;
    uint16_t channel_offset;
    uint16_t channel_count;
    uint32_t payload_length;
    const uint8_t *payload;
};

uint32_t cnn_runtime_crc32(const void *data, size_t size, uint32_t seed);
int cnn_model_open(struct cnn_model_view *model, const void *package,
                   size_t package_size);
int cnn_model_layer(const struct cnn_model_view *model, uint16_t index,
                    struct cnn_layer_view *layer);
int cnn_model_tensor(const struct cnn_model_view *model, uint16_t id,
                     struct cnn_tensor_view *tensor);
int cnn_model_parameter_data(const struct cnn_model_view *model,
                             const struct cnn_layer_view *layer,
                             const uint8_t **weights, const uint8_t **biases);
int cnn_layer_tile(const struct cnn_layer_view *layer,
                   const struct cnn_tensor_view *output, uint32_t tile_index,
                   struct cnn_tile *tile);
int cnn_layer_input_tile(const struct cnn_layer_view *layer,
                         const struct cnn_tensor_view *input,
                         const struct cnn_tile *output_tile,
                         struct cnn_tile *input_tile);
size_t cnn_dma_packet_size(uint32_t payload_length);
int cnn_dma_packet_build(uint8_t *destination, size_t capacity,
                         const struct cnn_dma_packet *packet);
int cnn_dma_packet_parse(const void *source, size_t size,
                         struct cnn_dma_packet *packet);
int cnn_tensor_gather_tile(const struct cnn_tensor_view *tensor,
                           const uint8_t *workspace,
                           const struct cnn_tile *tile, uint8_t *destination,
                           size_t capacity);
int cnn_tensor_scatter_tile(const struct cnn_tensor_view *tensor,
                            uint8_t *workspace, const struct cnn_tile *tile,
                            const uint8_t *source, size_t source_size);

#endif
