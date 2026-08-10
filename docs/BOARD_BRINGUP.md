# Zybo Z7-20 Board Bring-Up

## Required files

Bitstream:
build/zybo_z7_20_cnn/zybo_z7_20_cnn.runs/impl_1/system_wrapper.bit

ELF:
build/vitis_ws/cnn_baremetal/build/cnn_baremetal.elf

XSA:
build/zybo_z7_20_cnn/zybo_z7_20_cnn.xsa

Optional SD boot image:
build/BOOT.BIN

Generate all board-ready files:

make preboard-proof

## Hardware setup

1. Connect the Zybo Z7-20 board over USB.
2. Set boot mode to JTAG.
3. Power on the board.
4. Open a UART terminal.

UART settings:
- Baud: 115200
- Data bits: 8
- Parity: none
- Stop bits: 1
- Flow control: none

## Program and run

Run:

make program-zybo-z7

This uses:

xsct scripts/zynq/program_and_run_dma.tcl

## SD boot option

After JTAG passes, copy `build/BOOT.BIN` to a FAT32 microSD card, set the board boot mode to SD, and power-cycle the board.

## Optional ILA debug bitstream

A specific ILA/debug block-design variant is planned after first board bring-up if UART, DMA status, and performance counters are not enough visibility.

## Expected UART output

The test should print:

Zynq Image-to-Image CNN DMA Test
CNN base address: 0x43c00000
AXI DMA base address: 0x40400000
...
DMA+ transfer usec = <measured>
[PASS] image-to-image DMA golden test passed

## Important addresses

 AXI-Lite config base: 0x43C00000
AXI DMA base: 0x40400000

## DMA data path

DDR packet buffer
 ↓
AXI DMA MM2S
 ↓ packetized tensor AXI-Stream
 image-to-image CNN accelerator
 ↓ 32-bit output AXI-Stream
AXI DMA S2MM
 ↓
DDR output buffer

## Debug lines to check if it fails

Paste these UART lines when debugging:

DMA MM2S after reset status
DMA MM2S after reset status decode
DMA S2MM after reset status
DMA S2MM after reset status decode
DMA MM2S final status
DMA MM2S final status decode
DMA S2MM final status
DMA S2MM final status decode
DMA+ transfer cycles
DMA+ transfer usec
 status decode
 error_code
 perf input words
 perf output words
[FAIL] lines
