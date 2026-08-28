#include "cnn_interrupt_runtime.h"

#include <stdio.h>

#define CHECK(condition) do { \
    if (!(condition)) { \
        fprintf(stderr, "check failed at line %d: %s\n", __LINE__, #condition); \
        return 1; \
    } \
} while (0)

int main(void)
{
    struct cnn_interrupt_state state;
    cnn_interrupt_init(&state);
    CHECK(cnn_interrupt_wait(&state, CNN_INTERRUPT_DMA_TX_DONE, 2) ==
          CNN_INTERRUPT_TIMEOUT);
    cnn_interrupt_dma_tx(&state, 0x00001000u);
    CHECK(cnn_interrupt_wait(&state, CNN_INTERRUPT_DMA_TX_DONE, 1) ==
          CNN_INTERRUPT_OK);
    CHECK((state.pending & CNN_INTERRUPT_DMA_TX_DONE) == 0u);

    cnn_interrupt_dma_rx(&state, 0x00001000u);
    cnn_interrupt_accelerator(&state, 1u);
    CHECK(cnn_interrupt_wait(&state, CNN_INTERRUPT_DMA_RX_DONE, 1) ==
          CNN_INTERRUPT_OK);
    CHECK(cnn_interrupt_wait(&state, CNN_INTERRUPT_ACCEL_DONE, 1) ==
          CNN_INTERRUPT_OK);

    cnn_interrupt_dma_tx(&state, 0x00004000u);
    CHECK(cnn_interrupt_wait(&state, CNN_INTERRUPT_DMA_TX_DONE, 1) ==
          CNN_INTERRUPT_DEVICE_ERROR);
    cnn_interrupt_discard(&state, CNN_INTERRUPT_DMA_ERROR);
    cnn_interrupt_accelerator(&state, 2u);
    CHECK(cnn_interrupt_wait(&state, CNN_INTERRUPT_ACCEL_DONE, 1) ==
          CNN_INTERRUPT_DEVICE_ERROR);
    cnn_interrupt_discard(&state, CNN_INTERRUPT_ACCEL_ERROR);
    CHECK(cnn_interrupt_wait(0, CNN_INTERRUPT_ACCEL_DONE, 1) ==
          CNN_INTERRUPT_BAD_ARGUMENT);
    puts("[PASS] interrupt runtime event, timeout, and error handling");
    return 0;
}
