#include "sleep.h"
#include "xil_cache.h"
#include "xil_io.h"
#include "xil_printf.h"

#include <stddef.h>
#include <stdint.h>
#include <string.h>

#include "cnn_programmable_runtime.h"
#include "generated/programmable_demo.h"

#define CNN_BASE 0x43C00000U
#define DMA_BASE 0x40400000U

#define DMA_MM2S_DMACR 0x00U
#define DMA_MM2S_DMASR 0x04U
#define DMA_MM2S_SA 0x18U
#define DMA_MM2S_LENGTH 0x28U
#define DMA_S2MM_DMACR 0x30U
#define DMA_S2MM_DMASR 0x34U
#define DMA_S2MM_DA 0x48U
#define DMA_S2MM_LENGTH 0x58U
#define DMA_CR_RUNSTOP 0x00000001U
#define DMA_CR_RESET 0x00000004U
#define DMA_SR_IOC_IRQ 0x00001000U
#define DMA_SR_ERR_ALL 0x00004770U
#define DMA_SR_IRQ_ALL 0x00007000U

#define POLL_TIMEOUT 20000000U
#define PACKET_BUFFER_BYTES 8192U
#define CNN_WORKSPACE_BASE 0x10000000U
#define CNN_WORKSPACE_CAPACITY (256U * 1024U * 1024U)
#define DEMO_JOB_ID 1U

static uint8_t tx_packet[PACKET_BUFFER_BYTES] __attribute__((aligned(64)));
static uint8_t rx_packet[PACKET_BUFFER_BYTES] __attribute__((aligned(64)));
static uint8_t tile_payload[PACKET_BUFFER_BYTES - CNN_DMA_PACKET_HEADER_BYTES]
    __attribute__((aligned(64)));
static uint8_t *const workspace = (uint8_t *)(UINTPTR)CNN_WORKSPACE_BASE;

static inline void cnn_write(uint32_t offset, uint32_t value)
{
    Xil_Out32(CNN_BASE + offset, value);
}

static inline uint32_t cnn_read(uint32_t offset)
{
    return Xil_In32(CNN_BASE + offset);
}

static void print_structured_error(void)
{
    uint8_t bytes[CNN_ERROR_RECORD_SIZE];
    struct cnn_error_record_view record;

    for (uint32_t word = 0; word < CNN_ERROR_RECORD_SIZE / 4U; ++word) {
        uint32_t value = cnn_read(CNN_REG_STRUCTURED_ERROR_BASE + word * 4U);
        bytes[word * 4U] = (uint8_t)value;
        bytes[word * 4U + 1U] = (uint8_t)(value >> 8);
        bytes[word * 4U + 2U] = (uint8_t)(value >> 16);
        bytes[word * 4U + 3U] = (uint8_t)(value >> 24);
    }
    if (cnn_error_record_decode(bytes, sizeof(bytes), &record) != CNN_RUNTIME_OK)
        return;
    xil_printf(" error code=0x%08x stage=%u kind=%u index=%u field=%u\r\n",
               record.error_code, record.stage, record.record_kind,
               record.record_index, record.field_id);
    xil_printf(" error model=%u generation=%u observed=0x%08x%08x detail=0x%08x\r\n",
               record.model_id, record.generation_id,
               (uint32_t)(record.observed_value >> 32),
               (uint32_t)record.observed_value, record.detail);
}

static inline void dma_write(uint32_t offset, uint32_t value)
{
    Xil_Out32(DMA_BASE + offset, value);
}

static inline uint32_t dma_read(uint32_t offset)
{
    return Xil_In32(DMA_BASE + offset);
}

static int dma_wait(uint32_t status_offset)
{
    for (uint32_t count = 0; count < POLL_TIMEOUT; ++count) {
        uint32_t status = dma_read(status_offset);
        if ((status & DMA_SR_ERR_ALL) != 0U) {
            xil_printf("[FAIL] DMA error status=0x%08x\r\n", status);
            return -1;
        }
        if ((status & DMA_SR_IOC_IRQ) != 0U)
            return 0;
    }
    xil_printf("[FAIL] DMA timeout status=0x%08x\r\n",
               dma_read(status_offset));
    return -1;
}

static int dma_reset(void)
{
    dma_write(DMA_MM2S_DMACR, DMA_CR_RESET);
    dma_write(DMA_S2MM_DMACR, DMA_CR_RESET);
    for (uint32_t count = 0; count < POLL_TIMEOUT; ++count) {
        if (((dma_read(DMA_MM2S_DMACR) | dma_read(DMA_S2MM_DMACR)) &
             DMA_CR_RESET) == 0U) {
            dma_write(DMA_MM2S_DMACR, DMA_CR_RUNSTOP);
            dma_write(DMA_S2MM_DMACR, DMA_CR_RUNSTOP);
            return 0;
        }
    }
    return -1;
}

static int dma_send(const void *data, uint32_t size)
{
    Xil_DCacheFlushRange((UINTPTR)data, size);
    dma_write(DMA_MM2S_DMASR, DMA_SR_IRQ_ALL);
    dma_write(DMA_MM2S_SA, (uint32_t)(UINTPTR)data);
    dma_write(DMA_MM2S_LENGTH, size);
    return dma_wait(DMA_MM2S_DMASR);
}

static void dma_receive_start(void *data, uint32_t size)
{
    memset(data, 0xA5, size);
    Xil_DCacheFlushRange((UINTPTR)data, size);
    dma_write(DMA_S2MM_DMASR, DMA_SR_IRQ_ALL);
    dma_write(DMA_S2MM_DA, (uint32_t)(UINTPTR)data);
    dma_write(DMA_S2MM_LENGTH, size);
}

static int dma_receive_finish(void *data, uint32_t size)
{
    if (dma_wait(DMA_S2MM_DMASR) != 0)
        return -1;
    Xil_DCacheInvalidateRange((UINTPTR)data, size);
    return 0;
}

static int model_status_ok(void)
{
    uint32_t status = cnn_read(CNN_REG_MODEL_STATUS);
    uint32_t error = status >> 4;
    if (error != 0U) {
        xil_printf("[FAIL] model lifecycle error=%d status=0x%08x\r\n",
                   error, status);
        return -1;
    }
    return 0;
}

static void metadata_record(uint32_t kind, uint32_t index,
                            const uint8_t *record, uint32_t size)
{
    for (uint32_t word = 0; word < size / 4U; ++word) {
        uint32_t value = (uint32_t)record[word * 4U] |
                         ((uint32_t)record[word * 4U + 1U] << 8) |
                         ((uint32_t)record[word * 4U + 2U] << 16) |
                         ((uint32_t)record[word * 4U + 3U] << 24);
        cnn_write(CNN_REG_METADATA_ADDRESS,
                  CNN_METADATA_ADDRESS(kind, index, word));
        cnn_write(CNN_REG_METADATA_DATA, value);
    }
    cnn_write(CNN_REG_METADATA_ADDRESS,
              CNN_METADATA_ADDRESS(kind, index, 0));
    cnn_write(CNN_REG_METADATA_COMMIT, 1U);
}

static int activate_model(const struct cnn_model_view *model)
{
    cnn_write(CNN_REG_MODEL_COMMAND, CNN_MODEL_COMMAND_BEGIN_LOAD);
    metadata_record(CNN_METADATA_KIND_HEADER, 0, model->package,
                    CNN_MODEL_HEADER_SIZE);
    for (uint32_t i = 0; i < model->layer_count; ++i) {
        metadata_record(CNN_METADATA_KIND_LAYER, i,
                        model->package + model->layer_table_offset +
                            i * CNN_LAYER_DESCRIPTOR_SIZE,
                        CNN_LAYER_DESCRIPTOR_SIZE);
    }
    for (uint32_t i = 0; i < model->tensor_count; ++i) {
        metadata_record(CNN_METADATA_KIND_TENSOR, i,
                        model->package + model->tensor_table_offset +
                            i * CNN_TENSOR_DESCRIPTOR_SIZE,
                        CNN_TENSOR_DESCRIPTOR_SIZE);
    }
    for (uint32_t i = 0; i < model->quantization_count; ++i) {
        metadata_record(CNN_METADATA_KIND_QUANTIZATION, i,
                        model->package + model->quantization_table_offset +
                            i * CNN_QUANT_DESCRIPTOR_SIZE,
                        CNN_QUANT_DESCRIPTOR_SIZE);
    }
    if (model_status_ok() != 0)
        return -1;
    cnn_write(CNN_REG_MODEL_COMMAND, CNN_MODEL_COMMAND_FINISH_LOAD);
    cnn_write(CNN_REG_MODEL_COMMAND, CNN_MODEL_COMMAND_VALIDATE);
    cnn_write(CNN_REG_MODEL_COMMAND, CNN_MODEL_COMMAND_ACTIVATE);
    if (model_status_ok() != 0 ||
        cnn_read(CNN_REG_ACTIVE_MODEL_ID) != model->model_id ||
        cnn_read(CNN_REG_ACTIVE_GENERATION) != model->generation_id ||
        cnn_read(CNN_REG_ACTIVE_LAYER_COUNT) != model->layer_count) {
        xil_printf("[FAIL] model activation identity mismatch\r\n");
        return -1;
    }
    return 0;
}

static int send_packet(const struct cnn_dma_packet *packet)
{
    int packet_size = cnn_dma_packet_build(tx_packet, sizeof(tx_packet), packet);
    if (packet_size < 0) {
        xil_printf("[FAIL] packet build error=%d\r\n", packet_size);
        return -1;
    }
    return dma_send(tx_packet, (uint32_t)packet_size);
}

static int load_parameters(const struct cnn_model_view *model, uint16_t layer_index,
                           uint32_t job_id)
{
    struct cnn_layer_view layer;
    struct cnn_dma_packet packet;
    const uint8_t *weights;
    const uint8_t *biases;
    uint32_t banks_before = cnn_read(CNN_REG_PARAMETER_BANKS);

    if (cnn_model_layer(model, layer_index, &layer) != CNN_RUNTIME_OK ||
        cnn_model_parameter_data(model, &layer, &weights, &biases) !=
            CNN_RUNTIME_OK)
        return -1;
    cnn_write(CNN_REG_PARAMETER_LAYER, layer_index);
    for (volatile unsigned settle = 0; settle < 32U; ++settle) { }
    memset(&packet, 0, sizeof(packet));
    packet.type = CNN_DMA_PACKET_LAYER_WEIGHTS;
    packet.job_id = job_id;
    packet.layer_id = layer.layer_id;
    packet.payload_length = layer.weight_size;
    packet.payload = weights;
    if (send_packet(&packet) != 0)
        return -1;
    if (layer.bias_size != 0U) {
        packet.type = CNN_DMA_PACKET_LAYER_BIASES;
        packet.payload_length = layer.bias_size;
        packet.payload = biases;
        if (send_packet(&packet) != 0)
            return -1;
    }
    for (uint32_t count = 0; count < POLL_TIMEOUT; ++count) {
        uint32_t banks = cnn_read(CNN_REG_PARAMETER_BANKS);
        if (banks != banks_before)
            return 0;
        if ((cnn_read(CNN_REG_STATUS) & CNN_STATUS_ERROR) != 0U)
            break;
    }
    xil_printf("[FAIL] layer %d parameter bank did not become valid\r\n",
               layer_index);
    return -1;
}

static int wait_for_layer(uint16_t layer_index)
{
    for (uint32_t count = 0; count < POLL_TIMEOUT; ++count) {
        uint32_t status = cnn_read(CNN_REG_STATUS);
        uint32_t active = (status & CNN_STATUS_ACTIVE_LAYER_MASK) >>
                          CNN_STATUS_ACTIVE_LAYER_SHIFT;
        if ((status & CNN_STATUS_ERROR) != 0U) {
            xil_printf("[FAIL] runtime error=0x%08x\r\n",
                       cnn_read(CNN_REG_RUNTIME_ERROR));
            print_structured_error();
            return -1;
        }
        if ((status & CNN_STATUS_BUSY) != 0U && active == layer_index)
            return 0;
    }
    return -1;
}

static int transfer_activation(const struct cnn_model_view *model,
                               const struct cnn_layer_view *layer,
                               const struct cnn_tensor_view *input,
                               const struct cnn_tensor_view *output,
                               const struct cnn_tile *output_tile,
                               uint32_t job_id)
{
    struct cnn_tile source_tile;
    struct cnn_dma_packet packet;
    struct cnn_dma_packet result;
    uint32_t output_bytes = (uint32_t)output_tile->width * output_tile->height *
                            output->channels;
    uint32_t receive_bytes = (uint32_t)cnn_dma_packet_size(output_bytes);
    int input_bytes;

    if (cnn_layer_input_tile(layer, input, output_tile, &source_tile) !=
        CNN_RUNTIME_OK)
        return -1;
    input_bytes = cnn_tensor_gather_tile(input, workspace, &source_tile,
                                         tile_payload, sizeof(tile_payload));
    if (input_bytes < 0)
        return -1;
    memset(&packet, 0, sizeof(packet));
    packet.type = CNN_DMA_PACKET_INPUT_TILE;
    packet.job_id = job_id;
    packet.tensor_id = input->tensor_id;
    packet.layer_id = layer->layer_id;
    packet.tile = *output_tile;
    packet.channel_count = input->channels;
    packet.payload_length = (uint32_t)input_bytes;
    packet.payload = tile_payload;

    dma_receive_start(rx_packet, receive_bytes);
    if (send_packet(&packet) != 0)
        return -1;
    if (layer->residual_mode != CNN_RESIDUAL_NONE) {
        struct cnn_tensor_view residual;
        int residual_bytes;
        if (cnn_model_tensor(model, layer->residual_tensor_id, &residual) !=
            CNN_RUNTIME_OK)
            return -1;
        residual_bytes = cnn_tensor_gather_tile(&residual, workspace, output_tile,
                                                tile_payload,
                                                sizeof(tile_payload));
        if (residual_bytes < 0)
            return -1;
        packet.tensor_id = residual.tensor_id;
        packet.channel_count = residual.channels;
        packet.payload_length = (uint32_t)residual_bytes;
        packet.payload = tile_payload;
        if (send_packet(&packet) != 0)
            return -1;
    }
    if (dma_receive_finish(rx_packet, receive_bytes) != 0 ||
        cnn_dma_packet_parse(rx_packet, receive_bytes, &result) !=
            CNN_RUNTIME_OK ||
        result.type != CNN_DMA_PACKET_OUTPUT_TILE ||
        result.job_id != job_id || result.layer_id != layer->layer_id ||
        result.tensor_id != output->tensor_id ||
        result.tile.x != output_tile->x || result.tile.y != output_tile->y ||
        result.tile.width != output_tile->width ||
        result.tile.height != output_tile->height ||
        result.channel_count != output->channels ||
        result.payload_length != output_bytes) {
        xil_printf("[FAIL] invalid output packet for layer %d\r\n",
                   layer->layer_id);
        return -1;
    }
    return cnn_tensor_scatter_tile(output, workspace, output_tile,
                                   result.payload, result.payload_length) < 0 ?
           -1 : 0;
}

static int run_model(const struct cnn_model_view *model, const uint8_t *input_data,
                     size_t input_size, uint32_t job_id)
{
    struct cnn_tensor_view model_input;
    uint16_t preloaded = model->layer_count < 2U ? model->layer_count : 2U;

    if (model->workspace_size > CNN_WORKSPACE_CAPACITY ||
        cnn_model_tensor(model, model->input_tensor_id, &model_input) !=
            CNN_RUNTIME_OK || input_size > model_input.allocation_size)
        return -1;
    memset(workspace, 0, model->workspace_size);
    memcpy(workspace + model_input.ddr_offset, input_data, input_size);
    for (uint16_t layer = 0; layer < preloaded; ++layer) {
        if (load_parameters(model, layer, job_id) != 0)
            return -1;
    }

    cnn_write(CNN_REG_JOB_ID, job_id);
    cnn_write(CNN_REG_CONTROL, CNN_CONTROL_START);
    for (uint16_t index = 0; index < model->layer_count; ++index) {
        struct cnn_layer_view layer;
        struct cnn_tensor_view input;
        struct cnn_tensor_view output;
        uint32_t tile_count;
        uint32_t tile_width;
        uint32_t tile_height;
        if (wait_for_layer(index) != 0 ||
            cnn_model_layer(model, index, &layer) != CNN_RUNTIME_OK ||
            cnn_model_tensor(model, layer.input_tensor_id, &input) !=
                CNN_RUNTIME_OK ||
            cnn_model_tensor(model, layer.output_tensor_id, &output) !=
                CNN_RUNTIME_OK)
            return -1;
        if (index >= preloaded && load_parameters(model, index, job_id) != 0)
            return -1;
        tile_width = layer.tile_width_hint ? layer.tile_width_hint : 16U;
        tile_height = layer.tile_height_hint ? layer.tile_height_hint : 16U;
        tile_count = ((output.width + tile_width - 1U) / tile_width) *
                     ((output.height + tile_height - 1U) / tile_height);
        for (uint32_t tile_index = 0; tile_index < tile_count; ++tile_index) {
            struct cnn_tile tile;
            if (cnn_layer_tile(&layer, &output, tile_index, &tile) !=
                    CNN_RUNTIME_OK ||
                transfer_activation(model, &layer, &input, &output, &tile,
                                    job_id) != 0)
                return -1;
        }
    }
    for (uint32_t count = 0; count < POLL_TIMEOUT; ++count) {
        uint32_t status = cnn_read(CNN_REG_STATUS);
        if ((status & CNN_STATUS_ERROR) != 0U)
            return -1;
        if ((status & CNN_STATUS_DONE) != 0U)
            return 0;
    }
    return -1;
}

int main(void)
{
    struct cnn_model_view model;
    struct cnn_tensor_view output;
    int result;

    xil_printf("\r\n========================================\r\n");
    xil_printf(" Programmable CNN Runtime Bring-Up\r\n");
    xil_printf("========================================\r\n");
    if (cnn_read(CNN_REG_VERSION) != CNN_REGISTER_MAP_VERSION) {
        xil_printf("[FAIL] register map version=0x%08x expected=0x%08x\r\n",
                   cnn_read(CNN_REG_VERSION), CNN_REGISTER_MAP_VERSION);
        goto finished;
    }
    result = cnn_model_open(&model, cnn_demo_model_package,
                            sizeof(cnn_demo_model_package));
    if (result != CNN_RUNTIME_OK) {
        xil_printf("[FAIL] demo package validation error=%d\r\n", result);
        goto finished;
    }
    cnn_write(CNN_REG_CONTROL, CNN_CONTROL_CLEAR);
    cnn_write(CNN_REG_MODEL_COMMAND, CNN_MODEL_COMMAND_CLEAR_ERROR);
    if (dma_reset() != 0 || activate_model(&model) != 0 ||
        run_model(&model, cnn_demo_input, sizeof(cnn_demo_input),
                  DEMO_JOB_ID) != 0 ||
        cnn_model_tensor(&model, model.output_tensor_id, &output) !=
            CNN_RUNTIME_OK) {
        xil_printf("[FAIL] programmable runtime execution failed\r\n");
        goto finished;
    }
    if (memcmp(workspace + output.ddr_offset, cnn_demo_expected,
               sizeof(cnn_demo_expected)) != 0) {
        xil_printf("[FAIL] output does not match golden tensor\r\n");
        goto finished;
    }
    xil_printf("[PASS] programmable package-driven CNN test passed\r\n");
    xil_printf(" model=%d generation=%d layers=%d tiles=%d saturation=%d\r\n",
               model.model_id, model.generation_id, model.layer_count,
               cnn_read(CNN_REG_COMPLETED_TILES),
               cnn_read(CNN_REG_SATURATION_EVENTS));

finished:
    while (1)
        sleep(1);
    return 0;
}
