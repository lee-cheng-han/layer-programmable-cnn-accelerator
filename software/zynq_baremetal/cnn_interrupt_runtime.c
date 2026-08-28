#include "cnn_interrupt_runtime.h"

#include "cnn_accel_abi.h"

#define DMA_STATUS_IOC_IRQ 0x00001000u
#define DMA_STATUS_ERROR_MASK 0x00004770u

void cnn_interrupt_init(struct cnn_interrupt_state *state)
{
    if (state == 0)
        return;
    state->pending = 0;
    state->accelerator_status = 0;
    state->dma_tx_status = 0;
    state->dma_rx_status = 0;
}

void cnn_interrupt_accelerator(struct cnn_interrupt_state *state,
                               uint32_t irq_status)
{
    if (state == 0)
        return;
    state->accelerator_status = irq_status;
    if ((irq_status & CNN_IRQ_DONE) != 0u)
        state->pending |= CNN_INTERRUPT_ACCEL_DONE;
    if ((irq_status & CNN_IRQ_ERROR) != 0u)
        state->pending |= CNN_INTERRUPT_ACCEL_ERROR;
}

static void record_dma(struct cnn_interrupt_state *state, uint32_t status,
                       uint32_t completion_event, volatile uint32_t *snapshot)
{
    *snapshot = status;
    if ((status & DMA_STATUS_ERROR_MASK) != 0u)
        state->pending |= CNN_INTERRUPT_DMA_ERROR;
    if ((status & DMA_STATUS_IOC_IRQ) != 0u)
        state->pending |= completion_event;
}

void cnn_interrupt_dma_tx(struct cnn_interrupt_state *state,
                          uint32_t dma_status)
{
    if (state != 0)
        record_dma(state, dma_status, CNN_INTERRUPT_DMA_TX_DONE,
                   &state->dma_tx_status);
}

void cnn_interrupt_dma_rx(struct cnn_interrupt_state *state,
                          uint32_t dma_status)
{
    if (state != 0)
        record_dma(state, dma_status, CNN_INTERRUPT_DMA_RX_DONE,
                   &state->dma_rx_status);
}

void cnn_interrupt_discard(struct cnn_interrupt_state *state, uint32_t events)
{
    if (state != 0)
        state->pending &= ~events;
}

int cnn_interrupt_wait(struct cnn_interrupt_state *state, uint32_t events,
                       uint32_t timeout)
{
    if (state == 0 || events == 0u)
        return CNN_INTERRUPT_BAD_ARGUMENT;
    for (uint32_t count = 0; count < timeout; ++count) {
        uint32_t pending = state->pending;
        if ((pending & (CNN_INTERRUPT_ACCEL_ERROR |
                        CNN_INTERRUPT_DMA_ERROR)) != 0u)
            return CNN_INTERRUPT_DEVICE_ERROR;
        if ((pending & events) == events) {
            state->pending &= ~events;
            return CNN_INTERRUPT_OK;
        }
    }
    return CNN_INTERRUPT_TIMEOUT;
}
