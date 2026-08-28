#ifndef XSCUGIC_H
#define XSCUGIC_H

#include <stdint.h>

#define XST_SUCCESS 0

typedef void (*Xil_InterruptHandler)(void *);

typedef struct {
    uintptr_t CpuBaseAddress;
} XScuGic_Config;

typedef struct {
    unsigned unused;
} XScuGic;

static inline XScuGic_Config *XScuGic_LookupConfig(uintptr_t address)
{
    static XScuGic_Config config;
    config.CpuBaseAddress = address;
    return &config;
}

static inline int XScuGic_CfgInitialize(XScuGic *instance,
                                        XScuGic_Config *config,
                                        uintptr_t address)
{
    (void)instance;
    (void)config;
    (void)address;
    return XST_SUCCESS;
}

static inline int XScuGic_Connect(XScuGic *instance, uint32_t id,
                                  Xil_InterruptHandler handler, void *reference)
{
    (void)instance;
    (void)id;
    (void)handler;
    (void)reference;
    return XST_SUCCESS;
}

static inline void XScuGic_Enable(XScuGic *instance, uint32_t id)
{
    (void)instance;
    (void)id;
}

static inline void XScuGic_InterruptHandler(void *instance)
{
    (void)instance;
}

#endif
