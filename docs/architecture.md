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
| Toolchain | Vivado / Vitis 2026.1 |
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


DDR model, parameter, and tile buffers
 |
 | AXI DMA MM2S
 v
packed_dma_packet_parser / packed_dma_runtime_router
 |
 | activation/residual tiles and parameter streams
 v
cnn_tiled_multi_layer_controller
 |
 | descriptor-driven 1x1/3x3 tiled execution
 v
packed OUTPUT_TILE stream
 |
 | 32-bit AXI-Stream with TKEEP/TLAST
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

The production board path uses `cnn_programmable_system_top`. It connects
the atomically active metadata view through `cnn_programmable_job_engine` to
two runtime parameter banks and the tiled multi-layer runtime. The generated
Zybo block design selects its `TKEEP`-aware wrapper and routes the CNN and both
DMA interrupts to the PS. DDR gather/scatter, cache maintenance, parameter-bank
refill, and package activation are implemented in the portable bare-metal
runtime; a rebuilt board implementation and target ELF remain. The numeric path resolves active per-channel
multiplier/shift/zero-point descriptors, performs pipelined round-half-to-even
requantization, supports final-layer residual add/subtract, and reports
saturation events. The fixed seven-packet path is retained only as a
regression baseline during the transition.

## Register Map

The accelerator uses AXI-Lite for control and observability. Tensor payloads are not register-loaded; they move through AXI DMA.

| Offset | Register | Description |
|---:|---|---|
| `0x000` | `CONTROL` | Start and clear pulses |
| `0x004` | `STATUS` | Runtime, layer, model, and parameter-bank state |
| `0x008` | `IRQ_STATUS` | Done/error sticky status |
| `0x00C` | `IRQ_ENABLE` | Done/error interrupt enables |
| `0x010` | `JOB_ID` | Expected packed-packet job ID |
| `0x014` | `PARAMETER_LAYER` | Descriptor selected for parameter loading |
| `0x018`-`0x038` | `MODEL_*`, `METADATA_*` | Staging, validation, atomic activation, and metadata aperture |
| `0x03C` | `RUNTIME_ERROR` | Failing layer and runtime error code |
| `0x040`-`0x04C` | `ACTIVE_*`, `CURRENT_*`, `COMPLETED_*` | Tensor, tile, layer, and tile progress |
| `0x050` | `PACKET_ERRORS` | Packed parser error count |
| `0x054` | `PARAMETER_BANKS` | Valid reusable parameter banks |
| `0x058`-`0x064` | `INPUT_DDR`, `OUTPUT_DDR` | Active tensor DDR offsets |
| `0x068` | `SATURATION_EVENTS` | Requantization and residual clipping events |
| `0x0FC` | `VERSION` | Register-map version, `0x00050001` |

## Software Interaction

The production bare-metal runtime loads a package into DDR, stages and
validates metadata, atomically activates the model, refills reusable parameter
banks, gathers halo-aware input/residual tiles, submits packed DMA transfers,
scatters output tiles, maintains caches, and recovers from DMA or accelerator
timeouts. The existing fixed-network application remains regression evidence.
