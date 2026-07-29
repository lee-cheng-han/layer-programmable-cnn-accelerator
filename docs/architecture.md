# Architecture

## Overview

The current board-facing accelerator is the image-to-image CNN system. It runs in the Zynq-7000 programmable logic and is controlled by the ARM Cortex-A9 processing system.

The design uses:

- AXI-Lite for configuration, command, status, diagnostics, and performance counters.
- AXI DMA for tensor input and output movement through DDR.
- AXI-Stream between AXI DMA and the packetized CNN datapath.
- Local activation and weight scratchpads for stream-loaded multi-layer execution.

## Target Platform

| Item | Value |
|---|---|
| Board | Digilent Zybo Z7-20 |
| Vivado board part | `digilentinc.com:zybo-z7-20:part0:1.2` |
| SoC | Xilinx Zynq-7000 |
| FPGA part | `xc7z020clg400-1` |
| Processor | Dual-core ARM Cortex-A9 |
| PS reference clock | 33.333333 MHz |
| DDR | 1 GB DDR3L, address range `0x00000000`-`0x3FFFFFFF` |
| Console | UART1, MIO 48-49, 115200 8N1 |
| Boot media | QSPI or microSD on SD0 |
| PL clock | 125 MHz |
| Toolchain | Vivado / Vitis 2025.2 |
| AXI-Lite base | `0x43C00000` |
| AXI DMA base | `0x40400000` |

## System-Level Architecture

```text
ARM Cortex-A9
 |
 | AXI-Lite through M_AXI_GP0
 v
AXI-Lite interconnect
 |
 +--> CNN control/status/performance registers
 |
 +--> AXI DMA control registers


DDR tensor packet buffer
 |
 | AXI DMA MM2S
 v
tensor_packet_router
 |
 | activation, bias, weight streams
 v
stream_loaded_multi_layer_job_controller
 |
 | scratchpad-backed 3-layer CNN
 v
signed 8-bit RGB output stream
 |
 | sign-extended 32-bit AXI-Stream
 v
AXI DMA S2MM
 |
 v
DDR output buffer
```

## Target Network

```text
Input RGB tensor
 -> Conv 3x3, 3 -> 16, padding 1, ReLU
 -> Conv 3x3, 16 -> 16, padding 1, ReLU
 -> Conv 3x3, 16 -> 3, padding 1
 -> optional residual reconstruction
 -> Output RGB tensor
```

## Main Hardware Blocks

| Block | Purpose |
|---|---|
| `cnn_image2image_system_top` | AXI-Lite plus packetized AXI-Stream system top |
| `cnn_image2image_system_bd_wrapper` | Vivado block-design wrapper for Zynq integration |
| `cnn_axi_lite_slave` | Software-visible registers, status, interrupts, diagnostics, and counters |
| `cnn_model_metadata_store` | Dual-bank runtime descriptors, commit validation, and atomic model activation |
| `descriptor_driven_job_controller` | Validates and sequences one to eight active runtime layer descriptors through the reusable scheduler |
| `cnn_runtime_parameter_banks` | Validates, tags, owns, and overlaps two reusable weight/postprocessing banks |
| `cnn_programmable_job_engine` | Connects descriptor-driven execution to scratchpad-backed runtime parameters |
| `packed_dma_packet_parser` | Validates V1 packet headers, exact byte framing, `TKEEP`, `TLAST`, and recovery |
| `packed_dma_runtime_router` | Routes packed tiles and loads weight/bias packets into reusable parameter banks |
| `packed_dma_packet_writer` | Packs output bytes and generates versioned `OUTPUT_TILE` packets |
| `cnn_tiled_layer_runtime` | Loads halo-aware input tiles, runs a descriptor layer, and emits packed output tiles |
| `cnn_tiled_multi_layer_controller` | Validates descriptor chains and sequences tiled layers through reusable parameter banks |
| `cnn_programmable_runtime_top` | Integrates active metadata, packed DMA routing, reusable parameters, and tiled multi-layer execution |
| `cnn_programmable_axi_lite_slave` | Exposes programmable lifecycle, metadata, launch, progress, DDR context, IRQ, and errors |
| `cnn_programmable_system_top` | Joins the programmable control plane and packed tiled runtime |
| `tensor_packet_router` | Validates and routes the seven-packet tensor input stream |
| `stream_loaded_multi_layer_job_controller` | Loads tensors, overlaps parameter prefetch, and runs the 3-layer job |
| `single_layer_scheduler` | Reuses 1x1/3x3 tiled engines across image positions |
| `banked_activation_scratchpad` | BRAM-style activation storage with registered vector reads |
| `banked_weight_scratchpad` | BRAM-style weight storage with registered PK x PC reads |
| `performance_counters` | Counts job, packet, compute, layer, transfer, and stall cycles |
| AXI DMA | Moves tensor packets and output pixels between DDR and PL streams |

The current board path uses `stream_loaded_multi_layer_job_controller`. The
parallel layer-programmable path connects the active view from
`cnn_model_metadata_store` through `cnn_programmable_job_engine` to two runtime
parameter banks and has eight-layer controller plus two-layer tiled golden RTL
evidence. `cnn_programmable_system_top` now closes those standalone blocks
into one AXI-Lite-controlled model-to-output data path and has a `TKEEP`-aware
Vivado wrapper. It becomes the generated board path after the Zynq block design
selects that wrapper and implementation closes; DDR gather/scatter software
still remains.
The generated board bitstream still uses the preserved fixed-network
seven-packet path.

## Register Map

The accelerator uses AXI-Lite for control and observability. Tensor payloads are not register-loaded; they move through AXI DMA.

| Offset | Register | Description |
|---:|---|---|
| `0x000` | `CONTROL` | Start and clear pulses |
| `0x004` | `STATUS` | Busy, done, error, performance-counting |
| `0x008` | `IRQ_STATUS` | Done/error sticky status |
| `0x00C` | `IRQ_ENABLE` | Done/error interrupt enables |
| `0x010` | `IMAGE_WIDTH` | Input/output image width |
| `0x014` | `IMAGE_HEIGHT` | Input/output image height |
| `0x018` | `MODE_FLAGS` | Bit 0 enables final residual subtraction |
| `0x01C` | `ERROR_CODE` | Packet-router or compute error code |
| `0x020` | `STREAM_STATE` | Packet type and ready-layer state |
| `0x024` | `PACKET_WORDS` | Current packet payload words accepted |
| `0x028`-`0x054` | `MODEL_*`, `METADATA_*` | Runtime metadata loading, validation, activation, and identity |
| `0x080`-`0x0A8` | `PERF_*` | Latency, layer, transfer, and stall counters |
| `0x0FC` | `VERSION` | Register-map version, `0x00040000` |
| `0x100`-`0x17C` | `CAPABILITY_*` | Versioned hardware capability record |
| `0x180`-`0x1BC` | `ERROR_RECORD_*` | Sticky structured-error context |

## Software Interaction

The bare-metal app:

1. Verifies the register version and fixed-bitstream capability profile.
2. Resets AXI DMA.
3. Clears the accelerator.
4. Programs image dimensions and residual mode.
5. Starts S2MM and MM2S DMA channels.
6. Pulses `CONTROL.start`.
7. Sends seven tensor packets through MM2S.
8. Receives output pixels through S2MM.
9. Polls DMA and status completion.
10. Prints diagnostics and performance counters.
11. Compares DDR output against generated Python golden tensors.

Expected board result:

```text
[PASS] image-to-image DMA golden test passed
```
