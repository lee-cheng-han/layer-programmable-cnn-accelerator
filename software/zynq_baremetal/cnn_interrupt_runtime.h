#ifndef CNN_INTERRUPT_RUNTIME_H
#define CNN_INTERRUPT_RUNTIME_H

#include <stdint.h>

enum cnn_interrupt_event {
    CNN_INTERRUPT_ACCEL_DONE = 1u << 0,
    CNN_INTERRUPT_ACCEL_ERROR = 1u << 1,
    CNN_INTERRUPT_DMA_TX_DONE = 1u << 2,
    CNN_INTERRUPT_DMA_RX_DONE = 1u << 3,
    CNN_INTERRUPT_DMA_ERROR = 1u << 4
};

enum cnn_interrupt_result {
    CNN_INTERRUPT_OK = 0,
    CNN_INTERRUPT_TIMEOUT = -1,
    CNN_INTERRUPT_DEVICE_ERROR = -2,
    CNN_INTERRUPT_BAD_ARGUMENT = -3
};

struct cnn_interrupt_state {
    volatile uint32_t pending;
    volatile uint32_t accelerator_status;
    volatile uint32_t dma_tx_status;
    volatile uint32_t dma_rx_status;
};

void cnn_interrupt_init(struct cnn_interrupt_state *state);
void cnn_interrupt_accelerator(struct cnn_interrupt_state *state,
                               uint32_t irq_status);
void cnn_interrupt_dma_tx(struct cnn_interrupt_state *state,
                          uint32_t dma_status);
void cnn_interrupt_dma_rx(struct cnn_interrupt_state *state,
                          uint32_t dma_status);
void cnn_interrupt_discard(struct cnn_interrupt_state *state, uint32_t events);
int cnn_interrupt_wait(struct cnn_interrupt_state *state, uint32_t events,
                       uint32_t timeout);

#endif
