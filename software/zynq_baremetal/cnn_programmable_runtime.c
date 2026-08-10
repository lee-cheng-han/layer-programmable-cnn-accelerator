#include "cnn_programmable_runtime.h"

#include <string.h>

static uint16_t read_u16(const uint8_t *p)
{
    return (uint16_t)p[0] | ((uint16_t)p[1] << 8);
}

static uint32_t read_u32(const uint8_t *p)
{
    return (uint32_t)p[0] | ((uint32_t)p[1] << 8) |
           ((uint32_t)p[2] << 16) | ((uint32_t)p[3] << 24);
}

static uint64_t read_u64(const uint8_t *p)
{
    return (uint64_t)read_u32(p) | ((uint64_t)read_u32(p + 4) << 32);
}

static void write_u32(uint8_t *p, uint32_t value)
{
    p[0] = (uint8_t)value;
    p[1] = (uint8_t)(value >> 8);
    p[2] = (uint8_t)(value >> 16);
    p[3] = (uint8_t)(value >> 24);
}

static int range_valid(size_t total, uint32_t offset, uint32_t count,
                       uint32_t record_size)
{
    uint64_t end = (uint64_t)offset + (uint64_t)count * record_size;
    return offset <= total && end <= total;
}

uint32_t cnn_runtime_crc32(const void *data, size_t size, uint32_t seed)
{
    const uint8_t *bytes = (const uint8_t *)data;
    uint32_t crc = seed ^ 0xFFFFFFFFu;

    for (size_t i = 0; i < size; ++i) {
        crc ^= bytes[i];
        for (unsigned bit = 0; bit < 8; ++bit) {
            uint32_t mask = 0u - (crc & 1u);
            crc = (crc >> 1) ^ (0xEDB88320u & mask);
        }
    }
    return crc ^ 0xFFFFFFFFu;
}

static uint32_t package_crc32(const uint8_t *package, size_t size)
{
    static const uint8_t zero_crc[4] = {0, 0, 0, 0};
    uint32_t crc = cnn_runtime_crc32(package, CNN_MH_PACKAGE_CRC32_OFS, 0);
    crc = cnn_runtime_crc32(zero_crc, sizeof(zero_crc), crc);
    return cnn_runtime_crc32(package + CNN_MH_PACKAGE_CRC32_OFS + 4,
                             size - CNN_MH_PACKAGE_CRC32_OFS - 4, crc);
}

static int record_header_valid(const uint8_t *record, uint16_t size)
{
    return read_u16(record) == CNN_ABI_VERSION && read_u16(record + 2) == size;
}

int cnn_model_open(struct cnn_model_view *model, const void *package_data,
                   size_t package_size)
{
    const uint8_t *package = (const uint8_t *)package_data;
    uint32_t declared_size;
    uint16_t layer_count;
    uint16_t tensor_count;
    uint16_t quantization_count;
    uint32_t layer_offset;
    uint32_t tensor_offset;
    uint32_t quantization_offset;
    uint32_t parameter_offset;
    uint32_t parameter_size;

    if (model == NULL || package == NULL || package_size < CNN_MODEL_HEADER_SIZE)
        return CNN_RUNTIME_BAD_ARGUMENT;
    if (read_u32(package) != CNN_MODEL_MAGIC ||
        !record_header_valid(package + 4, CNN_MODEL_HEADER_SIZE))
        return CNN_RUNTIME_BAD_PACKAGE;

    declared_size = read_u32(package + CNN_MH_PACKAGE_SIZE_OFS);
    layer_count = read_u16(package + CNN_MH_LAYER_COUNT_OFS);
    tensor_count = read_u16(package + CNN_MH_LAYER_COUNT_OFS + 2);
    quantization_count = read_u16(package + CNN_MH_LAYER_COUNT_OFS + 4);
    layer_offset = read_u32(package + CNN_MH_LAYER_TABLE_OFS);
    tensor_offset = read_u32(package + CNN_MH_TENSOR_TABLE_OFS);
    quantization_offset = read_u32(package + CNN_MH_QUANT_TABLE_OFS);
    parameter_offset = read_u32(package + CNN_MH_PARAMETER_DATA_OFS);
    parameter_size = read_u32(package + CNN_MH_PARAMETER_DATA_OFS + 4);

    if (declared_size != package_size || layer_count == 0 ||
        layer_count > CNN_MAX_LAYERS || tensor_count == 0 ||
        tensor_count > CNN_MAX_TENSORS || quantization_count == 0 ||
        quantization_count > CNN_MAX_QUANTIZATIONS ||
        !range_valid(package_size, layer_offset, layer_count,
                     CNN_LAYER_DESCRIPTOR_SIZE) ||
        !range_valid(package_size, tensor_offset, tensor_count,
                     CNN_TENSOR_DESCRIPTOR_SIZE) ||
        !range_valid(package_size, quantization_offset, quantization_count,
                     CNN_QUANT_DESCRIPTOR_SIZE) ||
        !range_valid(package_size, parameter_offset, parameter_size, 1))
        return CNN_RUNTIME_BAD_PACKAGE;
    if (package_crc32(package, package_size) !=
        read_u32(package + CNN_MH_PACKAGE_CRC32_OFS))
        return CNN_RUNTIME_BAD_CHECKSUM;

    memset(model, 0, sizeof(*model));
    model->package = package;
    model->package_size = package_size;
    model->model_id = read_u32(package + 16);
    model->generation_id = read_u32(package + 20);
    model->layer_count = layer_count;
    model->tensor_count = tensor_count;
    model->quantization_count = quantization_count;
    model->input_tensor_id = read_u16(package + CNN_MH_INPUT_TENSOR_ID_OFS);
    model->output_tensor_id = read_u16(package + CNN_MH_INPUT_TENSOR_ID_OFS + 2);
    model->layer_table_offset = layer_offset;
    model->tensor_table_offset = tensor_offset;
    model->quantization_table_offset = quantization_offset;
    model->parameter_data_offset = parameter_offset;
    model->parameter_data_size = parameter_size;
    model->workspace_size = read_u32(package + 52);

    for (uint16_t i = 0; i < layer_count; ++i) {
        struct cnn_layer_view layer;
        struct cnn_tensor_view input;
        struct cnn_tensor_view output;
        const uint8_t *weights;
        const uint8_t *biases;
        uint32_t crc;
        uint32_t expected_weights;
        uint32_t expected_biases;
        int result = cnn_model_layer(model, i, &layer);
        if (result != CNN_RUNTIME_OK)
            return result;
        if (layer.input_tensor_id >= tensor_count ||
            layer.output_tensor_id >= tensor_count ||
            layer.quantization_id >= quantization_count ||
            (layer.residual_mode != CNN_RESIDUAL_NONE &&
             layer.residual_tensor_id >= tensor_count) ||
            cnn_model_tensor(model, layer.input_tensor_id, &input) !=
                CNN_RUNTIME_OK ||
            cnn_model_tensor(model, layer.output_tensor_id, &output) !=
                CNN_RUNTIME_OK)
            return CNN_RUNTIME_BAD_PACKAGE;
        expected_weights = (uint32_t)layer.kernel_width * layer.kernel_height *
                           input.channels * output.channels;
        expected_biases = (layer.flags & CNN_LAYER_FLAG_BIAS_ENABLE) ?
                          (uint32_t)output.channels * 4u : 0u;
        if (layer.weight_size != expected_weights ||
            layer.bias_size != expected_biases)
            return CNN_RUNTIME_BAD_PACKAGE;
        result = cnn_model_parameter_data(model, &layer, &weights, &biases);
        if (result != CNN_RUNTIME_OK)
            return result;
        crc = cnn_runtime_crc32(weights, layer.weight_size, 0);
        crc = cnn_runtime_crc32(biases, layer.bias_size, crc);
        if (crc != layer.parameter_crc32)
            return CNN_RUNTIME_BAD_CHECKSUM;
    }
    for (uint16_t i = 0; i < tensor_count; ++i) {
        struct cnn_tensor_view tensor;
        if (cnn_model_tensor(model, i, &tensor) != CNN_RUNTIME_OK)
            return CNN_RUNTIME_BAD_PACKAGE;
    }
    for (uint16_t i = 0; i < quantization_count; ++i) {
        const uint8_t *record = package + quantization_offset +
                                (size_t)i * CNN_QUANT_DESCRIPTOR_SIZE;
        if (!record_header_valid(record, CNN_QUANT_DESCRIPTOR_SIZE) ||
            read_u16(record + 4) != i || read_u16(record + 8) == 0 ||
            read_u16(record + 8) > CNN_MAX_CHANNELS)
            return CNN_RUNTIME_BAD_PACKAGE;
    }
    return CNN_RUNTIME_OK;
}

int cnn_model_layer(const struct cnn_model_view *model, uint16_t index,
                    struct cnn_layer_view *layer)
{
    const uint8_t *r;
    if (model == NULL || layer == NULL || index >= model->layer_count)
        return CNN_RUNTIME_BAD_ARGUMENT;
    r = model->package + model->layer_table_offset +
        (size_t)index * CNN_LAYER_DESCRIPTOR_SIZE;
    if (!record_header_valid(r, CNN_LAYER_DESCRIPTOR_SIZE) ||
        read_u16(r + 4) != index || read_u16(r + 6) != CNN_OPCODE_CONV2D)
        return CNN_RUNTIME_BAD_PACKAGE;
    memset(layer, 0, sizeof(*layer));
    layer->record = r;
    layer->layer_id = read_u16(r + 4);
    layer->flags = read_u32(r + 8);
    layer->input_tensor_id = read_u16(r + 12);
    layer->output_tensor_id = read_u16(r + 14);
    layer->residual_tensor_id = read_u16(r + 16);
    layer->quantization_id = read_u16(r + 18);
    layer->weight_offset = read_u32(r + 20);
    layer->weight_size = read_u32(r + 24);
    layer->bias_offset = read_u32(r + 28);
    layer->bias_size = read_u32(r + 32);
    layer->parameter_crc32 = read_u32(r + 36);
    layer->kernel_height = r[40];
    layer->kernel_width = r[41];
    layer->stride_y = r[42];
    layer->stride_x = r[43];
    layer->padding_top = r[44];
    layer->padding_bottom = r[45];
    layer->padding_left = r[46];
    layer->padding_right = r[47];
    layer->activation = r[50];
    layer->residual_mode = r[51];
    layer->tile_height_hint = read_u16(r + 52);
    layer->tile_width_hint = read_u16(r + 54);
    if ((layer->flags & ~(CNN_LAYER_FLAG_BIAS_ENABLE |
                          CNN_LAYER_FLAG_LAST_LAYER)) != 0u ||
        (layer->kernel_width != 1 && layer->kernel_width != 3) ||
        layer->kernel_height != layer->kernel_width ||
        (layer->stride_x != 1 && layer->stride_x != 2) ||
        layer->stride_y != layer->stride_x ||
        r[48] != 1 || r[49] != 1 ||
        layer->padding_top > 1 || layer->padding_bottom > 1 ||
        layer->padding_left > 1 || layer->padding_right > 1 ||
        layer->activation > CNN_ACTIVATION_RELU ||
        layer->residual_mode > CNN_RESIDUAL_POST_QUANT_SUBTRACT ||
        layer->weight_size > CNN_MAX_LAYER_WEIGHT_BYTES ||
        layer->bias_size > CNN_MAX_LAYER_BIAS_BYTES)
        return CNN_RUNTIME_UNSUPPORTED;
    return CNN_RUNTIME_OK;
}

int cnn_model_tensor(const struct cnn_model_view *model, uint16_t id,
                     struct cnn_tensor_view *tensor)
{
    const uint8_t *r;
    uint64_t required;
    if (model == NULL || tensor == NULL || id >= model->tensor_count)
        return CNN_RUNTIME_BAD_ARGUMENT;
    r = model->package + model->tensor_table_offset +
        (size_t)id * CNN_TENSOR_DESCRIPTOR_SIZE;
    if (!record_header_valid(r, CNN_TENSOR_DESCRIPTOR_SIZE) ||
        read_u16(r + 4) != id || r[26] != CNN_ELEMENT_INT8 ||
        r[27] != CNN_LAYOUT_NHWC)
        return CNN_RUNTIME_BAD_PACKAGE;
    memset(tensor, 0, sizeof(*tensor));
    tensor->record = r;
    tensor->tensor_id = id;
    tensor->flags = read_u16(r + 6);
    tensor->ddr_offset = read_u64(r + 8);
    tensor->allocation_size = read_u32(r + 16);
    tensor->width = read_u16(r + 20);
    tensor->height = read_u16(r + 22);
    tensor->channels = read_u16(r + 24);
    tensor->quantization_id = read_u16(r + 28);
    tensor->row_stride = read_u32(r + 36);
    tensor->pixel_stride = read_u32(r + 40);
    tensor->channel_stride = read_u32(r + 44);
    if (tensor->width == 0 || tensor->height == 0 || tensor->channels == 0 ||
        tensor->width > CNN_MAX_TENSOR_WIDTH ||
        tensor->height > CNN_MAX_TENSOR_HEIGHT ||
        tensor->channels > CNN_MAX_CHANNELS || tensor->channel_stride != 1 ||
        tensor->pixel_stride < tensor->channels ||
        tensor->row_stride < (uint32_t)tensor->width * tensor->pixel_stride)
        return CNN_RUNTIME_UNSUPPORTED;
    required = (uint64_t)(tensor->height - 1) * tensor->row_stride +
               (uint64_t)(tensor->width - 1) * tensor->pixel_stride +
               tensor->channels;
    if (required > tensor->allocation_size ||
        tensor->ddr_offset > model->workspace_size ||
        tensor->allocation_size > model->workspace_size - tensor->ddr_offset)
        return CNN_RUNTIME_BAD_PACKAGE;
    return CNN_RUNTIME_OK;
}

int cnn_model_parameter_data(const struct cnn_model_view *model,
                             const struct cnn_layer_view *layer,
                             const uint8_t **weights, const uint8_t **biases)
{
    uint64_t parameter_end;
    uint64_t weight_end;
    uint64_t bias_end;
    if (model == NULL || layer == NULL || weights == NULL || biases == NULL ||
        !range_valid(model->package_size, layer->weight_offset,
                     layer->weight_size, 1) ||
        !range_valid(model->package_size, layer->bias_offset,
                     layer->bias_size, 1) ||
        layer->weight_offset < model->parameter_data_offset ||
        (layer->bias_size != 0 &&
         layer->bias_offset < model->parameter_data_offset))
        return CNN_RUNTIME_BAD_PACKAGE;
    parameter_end = (uint64_t)model->parameter_data_offset +
                    model->parameter_data_size;
    weight_end = (uint64_t)layer->weight_offset + layer->weight_size;
    bias_end = layer->bias_size == 0 ? model->parameter_data_offset :
               (uint64_t)layer->bias_offset + layer->bias_size;
    if (weight_end > parameter_end || bias_end > parameter_end)
        return CNN_RUNTIME_BAD_PACKAGE;
    *weights = model->package + layer->weight_offset;
    *biases = model->package +
              (layer->bias_size == 0 ? model->parameter_data_offset :
               layer->bias_offset);
    return CNN_RUNTIME_OK;
}

int cnn_layer_tile(const struct cnn_layer_view *layer,
                   const struct cnn_tensor_view *output, uint32_t tile_index,
                   struct cnn_tile *tile)
{
    uint32_t tile_width;
    uint32_t tile_height;
    uint32_t columns;
    uint32_t rows;
    uint32_t remaining_width;
    uint32_t remaining_height;
    if (layer == NULL || output == NULL || tile == NULL)
        return CNN_RUNTIME_BAD_ARGUMENT;
    tile_width = layer->tile_width_hint ? layer->tile_width_hint : 16u;
    tile_height = layer->tile_height_hint ? layer->tile_height_hint : 16u;
    if (tile_width > 16u || tile_height > 16u)
        return CNN_RUNTIME_UNSUPPORTED;
    columns = (output->width + tile_width - 1u) / tile_width;
    rows = (output->height + tile_height - 1u) / tile_height;
    if (tile_index >= columns * rows)
        return CNN_RUNTIME_BAD_ARGUMENT;
    tile->x = (uint16_t)((tile_index % columns) * tile_width);
    tile->y = (uint16_t)((tile_index / columns) * tile_height);
    remaining_width = (uint32_t)output->width - tile->x;
    remaining_height = (uint32_t)output->height - tile->y;
    tile->width = (uint16_t)((remaining_width < tile_width) ?
                             remaining_width : tile_width);
    tile->height = (uint16_t)((remaining_height < tile_height) ?
                              remaining_height : tile_height);
    return CNN_RUNTIME_OK;
}

int cnn_layer_input_tile(const struct cnn_layer_view *layer,
                         const struct cnn_tensor_view *input,
                         const struct cnn_tile *output_tile,
                         struct cnn_tile *input_tile)
{
    int32_t x0;
    int32_t y0;
    int32_t x1;
    int32_t y1;
    if (layer == NULL || input == NULL || output_tile == NULL ||
        input_tile == NULL)
        return CNN_RUNTIME_BAD_ARGUMENT;
    x0 = (int32_t)output_tile->x * layer->stride_x - layer->padding_left;
    y0 = (int32_t)output_tile->y * layer->stride_y - layer->padding_top;
    x1 = ((int32_t)output_tile->x + output_tile->width - 1) * layer->stride_x -
         layer->padding_left + layer->kernel_width;
    y1 = ((int32_t)output_tile->y + output_tile->height - 1) * layer->stride_y -
         layer->padding_top + layer->kernel_height;
    if (x0 < 0) x0 = 0;
    if (y0 < 0) y0 = 0;
    if (x1 > input->width) x1 = input->width;
    if (y1 > input->height) y1 = input->height;
    if (x1 <= x0 || y1 <= y0)
        return CNN_RUNTIME_BAD_PACKAGE;
    input_tile->x = (uint16_t)x0;
    input_tile->y = (uint16_t)y0;
    input_tile->width = (uint16_t)(x1 - x0);
    input_tile->height = (uint16_t)(y1 - y0);
    return CNN_RUNTIME_OK;
}

size_t cnn_dma_packet_size(uint32_t payload_length)
{
    return CNN_DMA_PACKET_HEADER_BYTES + payload_length;
}

int cnn_dma_packet_build(uint8_t *destination, size_t capacity,
                         const struct cnn_dma_packet *packet)
{
    size_t size;
    if (destination == NULL || packet == NULL || packet->payload == NULL ||
        packet->payload_length == 0 ||
        packet->type < CNN_DMA_PACKET_INPUT_TILE ||
        packet->type > CNN_DMA_PACKET_OUTPUT_TILE)
        return CNN_RUNTIME_BAD_ARGUMENT;
    size = cnn_dma_packet_size(packet->payload_length);
    if (capacity < size)
        return CNN_RUNTIME_BUFFER_TOO_SMALL;
    write_u32(destination, CNN_DMA_PACKET_MAGIC);
    write_u32(destination + 4, CNN_DMA_PACKET_VERSION |
              (CNN_DMA_PACKET_HEADER_WORDS << 8) |
              ((uint32_t)packet->type << 16));
    write_u32(destination + 8, packet->job_id);
    write_u32(destination + 12, packet->tensor_id |
              ((uint32_t)packet->layer_id << 16));
    write_u32(destination + 16, packet->tile.x |
              ((uint32_t)packet->tile.y << 16));
    write_u32(destination + 20, packet->tile.width |
              ((uint32_t)packet->tile.height << 16));
    write_u32(destination + 24, packet->channel_offset |
              ((uint32_t)packet->channel_count << 16));
    write_u32(destination + 28, packet->payload_length);
    memcpy(destination + CNN_DMA_PACKET_HEADER_BYTES, packet->payload,
           packet->payload_length);
    return (int)size;
}

int cnn_dma_packet_parse(const void *source_data, size_t size,
                         struct cnn_dma_packet *packet)
{
    const uint8_t *source = (const uint8_t *)source_data;
    uint32_t format;
    uint32_t payload_length;
    if (source == NULL || packet == NULL || size < CNN_DMA_PACKET_HEADER_BYTES)
        return CNN_RUNTIME_BAD_ARGUMENT;
    format = read_u32(source + 4);
    payload_length = read_u32(source + 28);
    if (read_u32(source) != CNN_DMA_PACKET_MAGIC ||
        (format & 0xFFu) != CNN_DMA_PACKET_VERSION ||
        ((format >> 8) & 0xFFu) != CNN_DMA_PACKET_HEADER_WORDS ||
        (format >> 24) != 0 || ((format >> 16) & 0xFFu) <
            CNN_DMA_PACKET_INPUT_TILE ||
        ((format >> 16) & 0xFFu) > CNN_DMA_PACKET_OUTPUT_TILE ||
        payload_length == 0 || size != cnn_dma_packet_size(payload_length))
        return CNN_RUNTIME_BAD_PACKET;
    memset(packet, 0, sizeof(*packet));
    packet->type = (uint8_t)(format >> 16);
    packet->job_id = read_u32(source + 8);
    packet->tensor_id = read_u16(source + 12);
    packet->layer_id = read_u16(source + 14);
    packet->tile.x = read_u16(source + 16);
    packet->tile.y = read_u16(source + 18);
    packet->tile.width = read_u16(source + 20);
    packet->tile.height = read_u16(source + 22);
    packet->channel_offset = read_u16(source + 24);
    packet->channel_count = read_u16(source + 26);
    packet->payload_length = payload_length;
    packet->payload = source + CNN_DMA_PACKET_HEADER_BYTES;
    return CNN_RUNTIME_OK;
}

static int tile_copy(const struct cnn_tensor_view *tensor, uint8_t *workspace,
                     const struct cnn_tile *tile, uint8_t *packed,
                     size_t packed_size, int gather)
{
    size_t required;
    size_t position = 0;
    if (tensor == NULL || workspace == NULL || tile == NULL || packed == NULL ||
        tile->x + tile->width > tensor->width ||
        tile->y + tile->height > tensor->height)
        return CNN_RUNTIME_BAD_ARGUMENT;
    required = (size_t)tile->width * tile->height * tensor->channels;
    if (packed_size < required)
        return CNN_RUNTIME_BUFFER_TOO_SMALL;
    for (uint32_t y = 0; y < tile->height; ++y) {
        for (uint32_t x = 0; x < tile->width; ++x) {
            uint8_t *pixel = workspace + tensor->ddr_offset +
                (uint64_t)(tile->y + y) * tensor->row_stride +
                (uint64_t)(tile->x + x) * tensor->pixel_stride;
            for (uint32_t channel = 0; channel < tensor->channels; ++channel) {
                uint8_t *element = pixel + channel * tensor->channel_stride;
                if (gather) packed[position] = *element;
                else *element = packed[position];
                ++position;
            }
        }
    }
    return (int)required;
}

int cnn_tensor_gather_tile(const struct cnn_tensor_view *tensor,
                           const uint8_t *workspace,
                           const struct cnn_tile *tile, uint8_t *destination,
                           size_t capacity)
{
    return tile_copy(tensor, (uint8_t *)(uintptr_t)workspace, tile,
                     destination, capacity, 1);
}

int cnn_tensor_scatter_tile(const struct cnn_tensor_view *tensor,
                            uint8_t *workspace, const struct cnn_tile *tile,
                            const uint8_t *source, size_t source_size)
{
    return tile_copy(tensor, workspace, tile, (uint8_t *)(uintptr_t)source,
                     source_size, 0);
}
