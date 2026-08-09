#ifndef TEST_XIL_IO_H
#define TEST_XIL_IO_H
#include <stdint.h>
static inline void Xil_Out32(uint32_t address, uint32_t value)
{
    (void)address;
    (void)value;
}
static inline uint32_t Xil_In32(uint32_t address)
{
    (void)address;
    return 0;
}
#endif
