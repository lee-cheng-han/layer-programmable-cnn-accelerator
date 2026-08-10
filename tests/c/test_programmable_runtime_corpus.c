#include "cnn_programmable_runtime.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define REQUIRE(condition, message) do { \
    if (!(condition)) { \
        fprintf(stderr, "[FAIL] %s: %s (line %d)\n", path, message, __LINE__); \
        goto fail; \
    } \
} while (0)

struct coverage {
    unsigned packages;
    unsigned layers;
    unsigned tiles;
    unsigned layer_count_mask;
    unsigned saw_kernel_1;
    unsigned saw_kernel_3;
    unsigned saw_stride_2;
    unsigned saw_bias_disabled;
    unsigned saw_partial_beat;
};

static uint8_t *read_file(const char *path, size_t *size)
{
    FILE *file = fopen(path, "rb");
    uint8_t *data;
    long length;
    if (file == NULL || fseek(file, 0, SEEK_END) != 0)
        return NULL;
    length = ftell(file);
    if (length <= 0 || fseek(file, 0, SEEK_SET) != 0) {
        fclose(file);
        return NULL;
    }
    data = malloc((size_t)length);
    if (data == NULL || fread(data, 1, (size_t)length, file) != (size_t)length) {
        free(data);
        fclose(file);
        return NULL;
    }
    fclose(file);
    *size = (size_t)length;
    return data;
}

static int check_packet_rejection(uint8_t *packet, size_t packet_size,
                                  const char *path)
{
    struct cnn_dma_packet parsed;
    uint8_t saved;

    saved = packet[0];
    packet[0] ^= 1u;
    REQUIRE(cnn_dma_packet_parse(packet, packet_size, &parsed) ==
            CNN_RUNTIME_BAD_PACKET, "bad magic accepted");
    packet[0] = saved;

    saved = packet[7];
    packet[7] = 1u;
    REQUIRE(cnn_dma_packet_parse(packet, packet_size, &parsed) ==
            CNN_RUNTIME_BAD_PACKET, "nonzero flags accepted");
    packet[7] = saved;

    saved = packet[6];
    packet[6] = 0xFFu;
    REQUIRE(cnn_dma_packet_parse(packet, packet_size, &parsed) ==
            CNN_RUNTIME_BAD_PACKET, "unknown packet type accepted");
    packet[6] = saved;

    packet[28] ^= 1u;
    REQUIRE(cnn_dma_packet_parse(packet, packet_size, &parsed) ==
            CNN_RUNTIME_BAD_PACKET, "wrong payload length accepted");
    packet[28] ^= 1u;
    return 0;

fail:
    return -1;
}

static int mark_output_coverage(const struct cnn_tensor_view *tensor,
                                const struct cnn_tile *tile,
                                uint8_t *covered, const char *path)
{
    for (uint32_t y = 0; y < tile->height; ++y) {
        for (uint32_t x = 0; x < tile->width; ++x) {
            uint64_t pixel = (uint64_t)(tile->y + y) * tensor->row_stride +
                             (uint64_t)(tile->x + x) * tensor->pixel_stride;
            for (uint32_t channel = 0; channel < tensor->channels; ++channel) {
                uint64_t offset = pixel + channel * tensor->channel_stride;
                REQUIRE(offset < tensor->allocation_size,
                        "tile coverage exceeded allocation");
                REQUIRE(covered[offset] == 0, "output tile overlap");
                covered[offset] = 1;
            }
        }
    }
    return 0;

fail:
    return -1;
}

static int verify_complete_coverage(const struct cnn_tensor_view *tensor,
                                    const uint8_t *covered, const char *path)
{
    for (uint32_t y = 0; y < tensor->height; ++y) {
        for (uint32_t x = 0; x < tensor->width; ++x) {
            uint64_t pixel = (uint64_t)y * tensor->row_stride +
                             (uint64_t)x * tensor->pixel_stride;
            for (uint32_t channel = 0; channel < tensor->channels; ++channel) {
                uint64_t offset = pixel + channel * tensor->channel_stride;
                REQUIRE(covered[offset] == 1, "output element not covered");
            }
        }
    }
    return 0;

fail:
    return -1;
}

static int exercise_package(const char *path, struct coverage *coverage)
{
    struct cnn_model_view model;
    uint8_t *package = NULL;
    uint8_t *corrupt = NULL;
    uint8_t *workspace = NULL;
    size_t package_size = 0;
    int result = -1;

    package = read_file(path, &package_size);
    REQUIRE(package != NULL, "could not read package");
    REQUIRE(cnn_model_open(&model, package, package_size) == CNN_RUNTIME_OK,
            "package validation failed");
    REQUIRE(model.layer_count >= 1 && model.layer_count <= CNN_MAX_LAYERS,
            "invalid layer count");
    coverage->packages++;
    coverage->layer_count_mask |= 1u << (model.layer_count - 1u);

    corrupt = malloc(package_size);
    REQUIRE(corrupt != NULL, "corruption buffer allocation failed");
    memcpy(corrupt, package, package_size);
    corrupt[package_size - 1u] ^= 0x80u;
    {
        struct cnn_model_view rejected;
        REQUIRE(cnn_model_open(&rejected, corrupt, package_size) ==
                CNN_RUNTIME_BAD_CHECKSUM, "corrupted package accepted");
    }

    workspace = malloc(model.workspace_size);
    REQUIRE(workspace != NULL, "workspace allocation failed");
    for (uint32_t byte = 0; byte < model.workspace_size; ++byte)
        workspace[byte] = (uint8_t)(byte * 17u + model.model_id);

    for (uint16_t layer_index = 0; layer_index < model.layer_count;
         ++layer_index) {
        struct cnn_layer_view layer;
        struct cnn_tensor_view input;
        struct cnn_tensor_view output;
        const uint8_t *weights;
        const uint8_t *biases;
        uint8_t *covered = NULL;
        uint32_t tile_width;
        uint32_t tile_height;
        uint32_t tile_count;

        REQUIRE(cnn_model_layer(&model, layer_index, &layer) == CNN_RUNTIME_OK,
                "layer decode failed");
        REQUIRE(cnn_model_tensor(&model, layer.input_tensor_id, &input) ==
                CNN_RUNTIME_OK, "input tensor decode failed");
        REQUIRE(cnn_model_tensor(&model, layer.output_tensor_id, &output) ==
                CNN_RUNTIME_OK, "output tensor decode failed");
        REQUIRE(cnn_model_parameter_data(&model, &layer, &weights, &biases) ==
                CNN_RUNTIME_OK, "parameter range validation failed");
        REQUIRE(weights != NULL && biases != NULL, "null parameter view");
        coverage->layers++;
        coverage->saw_kernel_1 |= layer.kernel_width == 1;
        coverage->saw_kernel_3 |= layer.kernel_width == 3;
        coverage->saw_stride_2 |= layer.stride_x == 2;
        coverage->saw_bias_disabled |= layer.bias_size == 0;

        covered = calloc(output.allocation_size, 1);
        REQUIRE(covered != NULL, "coverage allocation failed");
        tile_width = layer.tile_width_hint ? layer.tile_width_hint : 16u;
        tile_height = layer.tile_height_hint ? layer.tile_height_hint : 16u;
        tile_count = ((output.width + tile_width - 1u) / tile_width) *
                     ((output.height + tile_height - 1u) / tile_height);

        for (uint32_t tile_index = 0; tile_index < tile_count; ++tile_index) {
            struct cnn_tile output_tile;
            struct cnn_tile input_tile;
            struct cnn_dma_packet packet;
            struct cnn_dma_packet parsed;
            uint8_t *payload = NULL;
            uint8_t *wire = NULL;
            uint32_t payload_capacity;
            uint32_t output_bytes;
            int payload_bytes;
            int wire_bytes;

            REQUIRE(cnn_layer_tile(&layer, &output, tile_index, &output_tile) ==
                    CNN_RUNTIME_OK, "output tile planning failed");
            REQUIRE(cnn_layer_input_tile(&layer, &input, &output_tile,
                                         &input_tile) == CNN_RUNTIME_OK,
                    "input tile planning failed");
            payload_capacity = (uint32_t)input_tile.width * input_tile.height *
                               input.channels;
            payload = malloc(payload_capacity);
            REQUIRE(payload != NULL, "input payload allocation failed");
            payload_bytes = cnn_tensor_gather_tile(
                &input, workspace, &input_tile, payload, payload_capacity);
            REQUIRE(payload_bytes == (int)payload_capacity,
                    "input tile gather length mismatch");

            memset(&packet, 0, sizeof(packet));
            packet.type = CNN_DMA_PACKET_INPUT_TILE;
            packet.job_id = 0xC0000000u | coverage->tiles;
            packet.tensor_id = input.tensor_id;
            packet.layer_id = layer.layer_id;
            packet.tile = output_tile;
            packet.channel_count = input.channels;
            packet.payload_length = payload_capacity;
            packet.payload = payload;
            wire = malloc(cnn_dma_packet_size(payload_capacity));
            REQUIRE(wire != NULL, "input wire allocation failed");
            wire_bytes = cnn_dma_packet_build(
                wire, cnn_dma_packet_size(payload_capacity), &packet);
            REQUIRE(wire_bytes == (int)cnn_dma_packet_size(payload_capacity),
                    "input packet build failed");
            REQUIRE(cnn_dma_packet_parse(wire, (size_t)wire_bytes, &parsed) ==
                    CNN_RUNTIME_OK, "input packet parse failed");
            REQUIRE(parsed.job_id == packet.job_id &&
                    parsed.tensor_id == packet.tensor_id &&
                    parsed.layer_id == packet.layer_id &&
                    parsed.payload_length == packet.payload_length &&
                    memcmp(parsed.payload, payload, payload_capacity) == 0,
                    "input packet round-trip mismatch");
            if (tile_index == 0)
                REQUIRE(check_packet_rejection(wire, (size_t)wire_bytes, path) == 0,
                        "negative packet checks failed");
            free(wire);
            wire = NULL;
            free(payload);
            payload = NULL;

            output_bytes = (uint32_t)output_tile.width * output_tile.height *
                           output.channels;
            payload = malloc(output_bytes);
            wire = malloc(cnn_dma_packet_size(output_bytes));
            REQUIRE(payload != NULL && wire != NULL,
                    "output packet allocation failed");
            for (uint32_t byte = 0; byte < output_bytes; ++byte)
                payload[byte] = (uint8_t)(byte + tile_index + layer_index);
            packet.type = CNN_DMA_PACKET_OUTPUT_TILE;
            packet.tensor_id = output.tensor_id;
            packet.channel_count = output.channels;
            packet.payload_length = output_bytes;
            packet.payload = payload;
            wire_bytes = cnn_dma_packet_build(
                wire, cnn_dma_packet_size(output_bytes), &packet);
            REQUIRE(wire_bytes > 0 && cnn_dma_packet_parse(
                    wire, (size_t)wire_bytes, &parsed) == CNN_RUNTIME_OK,
                    "output packet round-trip failed");
            REQUIRE(cnn_tensor_scatter_tile(
                    &output, workspace, &output_tile, parsed.payload,
                    parsed.payload_length) == (int)output_bytes,
                    "output tile scatter failed");
            REQUIRE(mark_output_coverage(&output, &output_tile, covered, path) == 0,
                    "output coverage failed");
            coverage->saw_partial_beat |= (output_bytes & 3u) != 0;
            coverage->tiles++;
            free(wire);
            free(payload);
        }
        REQUIRE(verify_complete_coverage(&output, covered, path) == 0,
                "incomplete output coverage");
        free(covered);
    }
    result = 0;

fail:
    free(workspace);
    free(corrupt);
    free(package);
    return result;
}

int main(int argc, char **argv)
{
    struct coverage coverage = {0};
    if (argc < 9) {
        fprintf(stderr, "usage: %s package.cnn [...]\n", argv[0]);
        return 2;
    }
    for (int index = 1; index < argc; ++index) {
        if (exercise_package(argv[index], &coverage) != 0)
            return 1;
    }
    if (coverage.layer_count_mask != 0xFFu || !coverage.saw_kernel_1 ||
        !coverage.saw_kernel_3 || !coverage.saw_stride_2 ||
        !coverage.saw_bias_disabled || !coverage.saw_partial_beat) {
        fprintf(stderr, "[FAIL] incomplete randomized coverage mask=0x%02x\n",
                coverage.layer_count_mask);
        return 1;
    }
    printf("[PASS] runtime corpus packages=%u layers=%u tiles=%u "
           "layer_counts=0x%02x\n", coverage.packages, coverage.layers,
           coverage.tiles, coverage.layer_count_mask);
    return 0;
}
