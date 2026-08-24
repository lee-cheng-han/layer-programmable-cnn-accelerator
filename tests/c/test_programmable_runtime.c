#include "cnn_programmable_runtime.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define CHECK(condition) do { \
    if (!(condition)) { \
        fprintf(stderr, "check failed at line %d: %s\n", __LINE__, #condition); \
        return 1; \
    } \
} while (0)

static uint8_t *read_file(const char *path, size_t *size)
{
    FILE *file = fopen(path, "rb");
    uint8_t *data;
    long length;
    if (file == NULL || fseek(file, 0, SEEK_END) != 0)
        return NULL;
    length = ftell(file);
    if (length < 0 || fseek(file, 0, SEEK_SET) != 0) {
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

int main(int argc, char **argv)
{
    struct cnn_model_view model;
    struct cnn_layer_view layer;
    struct cnn_tensor_view input;
    struct cnn_tensor_view output;
    struct cnn_tile output_tile;
    struct cnn_tile input_tile;
    struct cnn_dma_packet tx;
    struct cnn_dma_packet rx;
    uint8_t workspace[256] = {0};
    uint8_t payload[256];
    uint8_t packet[512];
    uint8_t *package;
    size_t package_size;
    int payload_size;
    int packet_size;

    {
        uint8_t encoded_error[CNN_ERROR_RECORD_SIZE] = {0};
        struct cnn_error_record_view decoded_error;
        encoded_error[0] = CNN_ABI_VERSION;
        encoded_error[2] = CNN_ERROR_RECORD_SIZE;
        encoded_error[CNN_ERR_CODE_OFS] = 0x00;
        encoded_error[CNN_ERR_CODE_OFS + 1] = 0x04;
        encoded_error[CNN_ERR_CONTEXT_OFS] = CNN_ERROR_STAGE_DATA_PLANE;
        encoded_error[CNN_ERR_CONTEXT_OFS + 1] = CNN_ERROR_RECORD_PACKET;
        encoded_error[CNN_ERR_RECORD_INDEX_OFS] = 7;
        encoded_error[CNN_ERR_RECORD_INDEX_OFS + 2] =
            CNN_ERROR_FIELD_PAYLOAD_LENGTH;
        encoded_error[CNN_ERR_OBSERVED_OFS] = 9;
        encoded_error[CNN_ERR_EXPECTED_MAX_OFS] = 8;
        encoded_error[CNN_ERR_MODEL_ID_OFS] = 0xF5;
        encoded_error[CNN_ERR_MODEL_ID_OFS + 1] = 0x01;
        encoded_error[CNN_ERR_MODEL_ID_OFS + 4] = 12;
        CHECK(cnn_error_record_decode(encoded_error, sizeof(encoded_error),
                                      &decoded_error) == CNN_RUNTIME_OK);
        CHECK(decoded_error.error_code == CNN_ERROR_DATA_PLANE_PROTOCOL);
        CHECK(decoded_error.stage == CNN_ERROR_STAGE_DATA_PLANE);
        CHECK(decoded_error.record_kind == CNN_ERROR_RECORD_PACKET);
        CHECK(decoded_error.record_index == 7);
        CHECK(decoded_error.field_id == CNN_ERROR_FIELD_PAYLOAD_LENGTH);
        CHECK(decoded_error.observed_value == 9);
        CHECK(decoded_error.expected_max == 8);
        CHECK(decoded_error.model_id == 501 &&
              decoded_error.generation_id == 12);
    }

    CHECK(argc == 2);
    package = read_file(argv[1], &package_size);
    CHECK(package != NULL);
    CHECK(cnn_model_open(&model, package, package_size) == CNN_RUNTIME_OK);
    CHECK(model.layer_count == 1 && model.tensor_count == 2);
    CHECK(cnn_model_layer(&model, 0, &layer) == CNN_RUNTIME_OK);
    CHECK(layer.kernel_width == 1 && layer.weight_size == 9);
    CHECK(cnn_model_tensor(&model, model.input_tensor_id, &input) ==
          CNN_RUNTIME_OK);
    CHECK(cnn_model_tensor(&model, model.output_tensor_id, &output) ==
          CNN_RUNTIME_OK);
    CHECK(input.width == 4 && input.height == 4 && input.channels == 3);

    for (unsigned i = 0; i < 48; ++i)
        workspace[input.ddr_offset + i] = (uint8_t)(i + 1);
    CHECK(cnn_layer_tile(&layer, &output, 0, &output_tile) == CNN_RUNTIME_OK);
    CHECK(output_tile.x == 0 && output_tile.y == 0 &&
          output_tile.width == 4 && output_tile.height == 4);
    CHECK(cnn_layer_input_tile(&layer, &input, &output_tile, &input_tile) ==
          CNN_RUNTIME_OK);
    payload_size = cnn_tensor_gather_tile(&input, workspace, &input_tile,
                                          payload, sizeof(payload));
    CHECK(payload_size == 48 && payload[0] == 1 && payload[47] == 48);

    {
        struct cnn_layer_view padded = layer;
        struct cnn_tensor_view source = input;
        struct cnn_tile destination = {0, 0, 2, 2};
        padded.kernel_height = 3;
        padded.kernel_width = 3;
        padded.stride_y = 2;
        padded.stride_x = 2;
        padded.padding_top = 1;
        padded.padding_left = 1;
        source.width = 5;
        source.height = 5;
        CHECK(cnn_layer_input_tile(&padded, &source, &destination,
                                   &input_tile) == CNN_RUNTIME_OK);
        CHECK(input_tile.x == 0 && input_tile.y == 0 &&
              input_tile.width == 4 && input_tile.height == 4);
    }

    memset(&tx, 0, sizeof(tx));
    tx.type = CNN_DMA_PACKET_INPUT_TILE;
    tx.job_id = 77;
    tx.tensor_id = input.tensor_id;
    tx.layer_id = layer.layer_id;
    tx.tile = output_tile;
    tx.channel_count = input.channels;
    tx.payload_length = (uint32_t)payload_size;
    tx.payload = payload;
    packet_size = cnn_dma_packet_build(packet, sizeof(packet), &tx);
    CHECK(packet_size == 80);
    CHECK(cnn_dma_packet_parse(packet, (size_t)packet_size, &rx) ==
          CNN_RUNTIME_OK);
    CHECK(rx.job_id == 77 && rx.payload_length == 48 &&
          memcmp(rx.payload, payload, 48) == 0);

    CHECK(cnn_tensor_scatter_tile(&output, workspace, &output_tile,
                                  rx.payload, rx.payload_length) == 48);
    CHECK(memcmp(workspace + output.ddr_offset, payload, 48) == 0);

    package[package_size - 1] ^= 1u;
    CHECK(cnn_model_open(&model, package, package_size) ==
          CNN_RUNTIME_BAD_CHECKSUM);
    free(package);
    puts("[PASS] programmable bare-metal runtime host test");
    return 0;
}
