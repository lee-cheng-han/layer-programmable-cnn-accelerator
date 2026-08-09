#ifndef TEST_XIL_CACHE_H
#define TEST_XIL_CACHE_H
#include <stdint.h>
typedef uintptr_t UINTPTR;
static inline void Xil_DCacheFlushRange(UINTPTR address, uint32_t size)
{
    (void)address;
    (void)size;
}
static inline void Xil_DCacheInvalidateRange(UINTPTR address, uint32_t size)
{
    (void)address;
    (void)size;
}
#endif
