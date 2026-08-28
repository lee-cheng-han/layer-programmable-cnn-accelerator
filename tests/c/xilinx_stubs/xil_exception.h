#ifndef XIL_EXCEPTION_H
#define XIL_EXCEPTION_H

#define XIL_EXCEPTION_ID_INT 0

typedef void (*Xil_ExceptionHandler)(void *);

static inline void Xil_ExceptionInit(void) { }
static inline void Xil_ExceptionRegisterHandler(
    int id, Xil_ExceptionHandler handler, void *reference)
{
    (void)id;
    (void)handler;
    (void)reference;
}
static inline void Xil_ExceptionEnable(void) { }

#endif
