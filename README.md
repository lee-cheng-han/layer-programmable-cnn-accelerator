# Zynq-7000 Image-to-Image CNN Accelerator

[![CI](https://github.com/lee-cheng-han/cnn-accelerator/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/lee-cheng-han/cnn-accelerator/actions/workflows/ci.yml)
[![Vivado FPGA](https://github.com/lee-cheng-han/cnn-accelerator/actions/workflows/vivado-xsim.yml/badge.svg?branch=main)](https://github.com/lee-cheng-han/cnn-accelerator/actions/workflows/vivado-xsim.yml)
[![License](https://img.shields.io/github/license/lee-cheng-han/cnn-accelerator)](LICENSE)
![Target](https://img.shields.io/badge/target-Zybo%20Z7--20-1f6feb)
![Clock](https://img.shields.io/badge/PL%20clock-125%20MHz-2ea44f)

A synthesizable SystemVerilog accelerator for packetized, multi-layer INT8
image processing on the AMD Zynq-7000 SoC. The programmable logic executes a
three-layer convolutional network while the ARM Cortex-A9 controls jobs through
AXI-Lite and transfers tensors between DDR and the accelerator through AXI DMA.

The repository includes the RTL, bit-accurate reference model, generated golden
tensors, self-checking testbenches, scripted Vivado block design, Vitis
bare-metal application, and boot-image packaging flow.

> **Validation status:** RTL regression, routed implementation, XSA export,
> bare-metal compilation, and boot-image generation are complete. Execution on
> physical Zybo Z7-20 hardware is pending.

## System Overview

```text
                              Zynq processing system
                         +------------------------------+
                         | ARM Cortex-A9                 |
                         | bare-metal control software  |
                         +-------------+----------------+
                                       |
                  +--------------------+--------------------+
                  | AXI-Lite                                | AXI DMA
                  v                                         v
        +----------------------+                 +---------------------+
        | control / status /   |                 | DDR packet buffers  |
        | diagnostics / perf   |                 +----------+----------+
        +----------+-----------+                            |
                   |                              AXI-Stream MM2S
                   |                                         v
                   |                              +---------------------+
                   +----------------------------->| tensor packet router|
                                                  +----------+----------+
                                                             |
                                                  +----------v----------+
                                                  | stream-loaded       |
                                                  | 3-layer CNN         |
                                                  | scheduler           |
                                                  +----------+----------+
                                                             |
                                                   AXI-Stream S2MM
                                                             v
                                                  +---------------------+
                                                  | DDR output buffer   |
                                                  +---------------------+
```

The datapath uses signed INT8 activations and weights, INT32 accumulation, and
signed INT8 outputs carried as sign-extended 32-bit AXI-Stream words. Local
banked scratchpads hold activations and weights while a reusable tiled engine
executes each network layer.

Final programmable V1 uses per-output-channel integer multiplier/shift
requantization with round-half-to-even and symmetric zero point zero. Its
compute scaling is bounded by the documented [DDR bandwidth budget](docs/bandwidth_budget.md),
not presented as arithmetic peak alone.

### Target Network

```text
RGB input
  -> 3x3 convolution, 3 -> 16 channels, padding 1, ReLU
  -> 3x3 convolution, 16 -> 16 channels, padding 1, ReLU
  -> 3x3 convolution, 16 -> 3 channels, padding 1
  -> residual reconstruction: output = input - predicted high-frequency noise
  -> RGB output
```

The generated default parameters implement a deterministic 3x3 Gaussian
low-pass denoiser. The 16 hidden channels are eight signed feature pairs:
channels `0/1` through `14/15` carry positive and negative RGB components so
ReLU does not discard signed information. All hidden channels contribute to a
Gaussian high-pass estimate, and residual subtraction removes that estimate
from the input. The resulting impulse response is:

```text
1  2  1
2  4  2   / 16
1  2  1
```

This is a useful, explainable startup preset rather than a trained model.
Weights and biases remain packet-loaded for every job; software may replace
the preset with trained INT8 parameters or another compatible filter bank
without rebuilding the FPGA bitstream.

### Layer-Programmable Runtime

The production PL architecture is descriptor-driven and layer-programmable;
the fixed three-layer design remains only as a regression baseline. The V1
model-package ABI supports one to eight convolution layers, runtime 1x1/3x3
kernels, 1-16 channels, stride 1/2, per-edge padding, NHWC INT8 tensors, and
dimensions up to 1024x1024 through DDR-backed spatial tiling.

See the normative [V1 model-package ABI](docs/model_package_abi.md) and the
[implementation roadmap](docs/layer_programmable_roadmap.md). The first
[model compiler and package executor](docs/model_compiler.md) now emit,
validate, inspect, and bit-accurately execute relocatable V1 packages; runtime
RTL now retains two complete metadata banks and atomically activates validated
model generations. A generalized controller now consumes the active metadata
view and executes one to eight mixed 1x1/3x3 layers. Two reusable,
scratchpad-backed parameter banks now enforce exact lengths and ABI CRC32,
retain layer-tagged bias/quantization state, and overlap prefetch with compute.
A packed, versioned DMA data plane now validates exact byte lengths,
`TKEEP`/`TLAST`, tile metadata, packet recovery, parameter loading, and packed
output generation. The first DDR-backed tiling slice now plans 16x16 output
tiles, derives clipped receptive fields, reconstructs zero-padded halos in a
local banked scratchpad, executes a layer through the reusable compute and
parameter interfaces, and emits packed output tiles under backpressure. Both
1x1 and 3x3 stride-2 multi-tile golden paths pass. A multi-layer tiled
controller now walks active descriptors, validates DDR tensor handoffs,
recycles parameter banks, and exposes software-visible tile requests and
progress. Its two-layer packed-DMA golden flow and invalid-chain rejection
pass. An integrated programmable runtime now connects atomic metadata,
descriptor-derived parameter validation, packed ingress, reusable banks, tiled
execution, and packed egress in one synthesizable top; its model-to-output
golden flow passes. Active quantization descriptors drive per-output-channel
multiplier/shift/zero-point requantization with round-half-to-even, and the
integrated final-layer residual path supports signed INT8 add/subtract with
saturation-event readback. See [tiled execution](docs/tiled_execution.md). DDR
gather/scatter software and final board-integrated regeneration remain. The
prioritized completion gates are tracked in the
[engineering completion plan](docs/layer_programmable_roadmap.md#engineering-completion-plan).

The programmable path now also has a versioned
[AXI-Lite control plane](docs/programmable_control_plane.md) and a
`TKEEP`-aware Vivado module-reference wrapper. Its golden system test performs
model lifecycle, metadata loading, parameter selection, job launch, and
progress readback through AXI-Lite while tensors use packed AXI-Stream.

The control plane also exposes versioned
[capability discovery and structured errors](docs/capability_and_errors.md),
model lifecycle state, tiled progress, packet errors, and numeric saturation
events.

### Target Platform

| Component | Configuration |
|---|---|
| Board | Digilent Zybo Z7-20 |
| SoC / device | Zynq-7000 / `xc7z020clg400-1` |
| Vivado board part | `digilentinc.com:zybo-z7-20:part0:1.2` |
| Processing system | Dual-core ARM Cortex-A9, 1 GB DDR3L |
| Control path | PS `M_AXI_GP0` to AXI-Lite interconnect |
| DMA memory path | AXI DMA through PS `S_AXI_HP0` |
| PL clock | 125 MHz from `FCLK_CLK0` |
| Console | UART1 on MIO 48-49, 115200 8N1 |
| Toolchain | Vivado and Vitis 2025.2 |

## Implementation Results

The checked-in evidence corresponds to the board-integrated configuration
`PC=2`, `PK=4`, `MAX_PIXELS=16`, implemented with Vivado 2025.2 for the
`xc7z020clg400-1` device.

### Timing

| Metric | Result |
|---|---:|
| PL clock | 125.000 MHz |
| Clock period | 8.000 ns |
| WNS | 0.036 ns |
| TNS | 0.000 ns |
| WHS | 0.027 ns |
| THS | 0.000 ns |
| Failing setup / hold endpoints | 0 / 0 |

### Utilization

| Resource | Used | Available | Utilization |
|---|---:|---:|---:|
| Slice LUTs | 7,501 | 53,200 | 14.10% |
| Slice registers | 7,673 | 106,400 | 7.21% |
| Block RAM tiles | 29 | 140 | 20.71% |
| DSPs | 4 | 220 | 1.82% |

The separate `PC=4`, `PK=8` synthesis experiment issues 32 MACs per cycle,
corresponding to a 4.0 GMAC/s arithmetic peak at 125 MHz. It is a scaling
experiment, not the board-integrated configuration. See
[synthesis_experiments.md](docs/synthesis_experiments.md) for the complete
configuration comparison.

The layer-programmable PL top, including per-channel requantization and
residual arithmetic, closes two out-of-context physical searches at 125 MHz.
The default and Explore routes have 0.023 ns and 0.013 ns setup slack,
respectively; both have 0.096 ns hold slack, zero failing endpoints, and no
congestion windows above level 5. See
[programmable_top_implementation.md](docs/programmable_top_implementation.md)
for the configuration, utilization, critical paths, and reproducible flow.

Source evidence:

- [Pre-board flow report](docs/logs/pre_board_flow_report.md)
- [Board implementation report](docs/board_implementation.md)
- [Programmable top implementation report](docs/programmable_top_implementation.md)
- [Performance results](docs/performance_results.md)
- [Vivado warning policy](docs/known_warnings.md)

## Hardware and Software Interfaces

### Address Map

| Base address | Interface |
|---:|---|
| `0x43C00000` | CNN AXI-Lite control and status registers |
| `0x40400000` | AXI DMA control registers |

### Register Summary

| Offset | Register | Description |
|---:|---|---|
| `0x000` | `CONTROL` | Start and clear command pulses |
| `0x004` | `STATUS` | Busy, done, error, and counter state |
| `0x008` | `IRQ_STATUS` | Sticky done and error status |
| `0x00C` | `IRQ_ENABLE` | Done and error interrupt enables |
| `0x010` | `IMAGE_WIDTH` | Runtime image width |
| `0x014` | `IMAGE_HEIGHT` | Runtime image height |
| `0x018` | `MODE_FLAGS` | Residual reconstruction enable |
| `0x01C` | `ERROR_CODE` | Packet or compute error code |
| `0x020` | `STREAM_STATE` | Active packet and layer readiness |
| `0x024` | `PACKET_WORDS` | Accepted words in the active packet |
| `0x028`-`0x054` | `MODEL_*`, `METADATA_*` | Metadata loading, validation, atomic activation, and model identity |
| `0x080`-`0x0A8` | `PERF_*` | Job, layer, transfer, overlap, and stall counters |
| `0x0FC` | `VERSION` | Interface version (`0x00040000`) |
| `0x100`-`0x17C` | `CAPABILITY_*` | Versioned implementation capability record |
| `0x180`-`0x1BC` | `ERROR_RECORD_*` | Sticky structured failure context |

The complete software contract is documented in
[register_map.md](docs/register_map.md) and
[performance_counters.md](docs/performance_counters.md).

### Tensor Stream Protocol

One job consists of seven ordered AXI-Stream packets:

| Packet | Payload |
|---:|---|
| 0 | Input activation tensor |
| 1 | Layer 0 biases |
| 2 | Layer 0 weights |
| 3 | Layer 1 biases |
| 4 | Layer 1 weights |
| 5 | Layer 2 biases |
| 6 | Layer 2 weights |

Each packet begins with `0xA5TT0000`, where `TT` identifies the packet type.
Activations and weights use signed INT8 payload values; biases use signed INT32
values. The router validates packet order, payload length, image dimensions,
and AXI end-of-packet signaling before allowing execution.

See [stream_interface.md](docs/stream_interface.md) for the wire-level format
and error behavior.

The layer-programmable path uses the implemented V1 packed protocol: an
eight-word versioned header followed by exact-length payload bytes, with four
INT8 elements per 32-bit beat, low-lane `TKEEP`, and `TLAST` on the final beat.
It carries tensor/layer IDs, tile coordinates, channel ranges, and job IDs.
See [packed_dma_protocol.md](docs/packed_dma_protocol.md). This path is
integrated through the programmable multi-layer tiled runtime in RTL; the
generated board bitstream continues to use the preserved seven-packet contract
until metadata-store and board integration are complete.

## Repository Layout

| Path | Contents |
|---|---|
| [`rtl/compute`](rtl/compute) | Parallel MAC array, accumulators, and tiled convolution engines |
| [`rtl/tensor`](rtl/tensor) | Activation/weight scratchpads and tensor load/store controllers |
| [`rtl/scheduler`](rtl/scheduler) | Layer scheduler, network controller, descriptors, and counters |
| [`rtl/stream`](rtl/stream) | Packet validation and stream routing |
| [`rtl/zynq`](rtl/zynq) | AXI-Lite, AXI-Stream, and board-integration wrappers |
| [`tb`](tb) | Directed, randomized, protocol, and golden-network testbenches |
| [`models`](models) | Dependency-free bit-accurate Python reference model |
| [`examples`](examples) | Human-readable model specifications and input tensors |
| [`rtl/include`](rtl/include) | Shared, versioned accelerator ABI constants |
| [`software/zynq_baremetal`](software/zynq_baremetal) | Bare-metal DMA application and generated golden job |
| [`scripts`](scripts) | Simulation, synthesis, Vivado, Vitis, reporting, and packaging automation |
| [`board_files`](board_files) | Vendored Digilent Zybo Z7-20 Vivado board definition |
| [`docs`](docs) | Interface specifications, verification evidence, and bring-up procedures |

Board-facing RTL entry points:

- [`cnn_image2image_system_top.sv`](rtl/zynq/cnn_image2image_system_top.sv)
- [`cnn_image2image_system_bd_wrapper.v`](rtl/zynq/cnn_image2image_system_bd_wrapper.v)
- [`create_zybo_z7_20_project.tcl`](scripts/zynq/create_zybo_z7_20_project.tcl)

## Prerequisites

- Linux development environment
- GNU Make and Bash
- Python 3.10 or later
- Verilator for standalone RTL lint
- AMD Vivado and Vitis 2025.2 for XSim and board builds
- A Vivado installation licensed for `xc7z020clg400-1`

The Makefile expects the 2025.2 tools below `$HOME/Xilinx/2025.2` by default.
The Digilent board definition is vendored in the repository; no global board
store installation is required.

## Verification

Run the model and complete self-checking RTL regression:

```bash
make regression
```

Run individual verification layers:

```bash
make model-test       # bit-accurate Python arithmetic tests
make model-package-example # compile and execute the V1 RGB identity package
make golden-test      # generated tensor fixtures against integrated RTL
make unit             # directed and randomized RTL testbenches
make lint             # Verilator lint
make docs-check       # checked-in result/evidence consistency
```

The integrated AXI test covers a complete seven-packet network job, output
backpressure, malformed lengths, invalid packet ordering, invalid dimensions,
and repeated starts. Golden outputs are generated independently by the Python
model and compared by the testbench.

Current coverage and known gaps are maintained in
[verification_matrix.md](docs/verification_matrix.md).

## Build Flows

### Golden Software Fixtures

```bash
make baremetal-headers
```

This regenerates the model fixtures and the C header consumed by the
bare-metal DMA application:

```text
build/golden/full_network_3layer/
software/zynq_baremetal/generated/golden_dma_job.h
```

### FPGA and Software Build

Run the complete pre-hardware qualification flow:

```bash
make full-preboard-proof
```

The target performs the following operations:

1. Runs the Python and RTL regressions.
2. Creates the Zybo Z7-20 Vivado project and block design.
3. Synthesizes, places, routes, and writes the bitstream.
4. Exports an XSA containing the implemented hardware.
5. Builds the Vitis platform, FSBL, and bare-metal application.
6. Enforces the documented Vivado warning budget.
7. Packages `BOOT.BIN` and emits the flow report.

Individual hardware targets are also available:

```bash
make zybo-z7-project
make zybo-z7-bitstream
make zybo-z7-xsa
make vitis-app
make boot-image
make check-warnings
make flow-report
```

Expected outputs:

```text
build/zybo_z7_20_cnn/zybo_z7_20_cnn.runs/impl_1/system_wrapper.bit
build/zybo_z7_20_cnn/zybo_z7_20_cnn.xsa
build/vitis_ws/zybo_z7_20_cnn_platform/zynq_fsbl/build/fsbl.elf
build/vitis_ws/cnn_baremetal/build/cnn_baremetal.elf
build/BOOT.BIN
build/flow_report.md
```

Generated build products are intentionally excluded from version control.

## Board Bring-Up

With the Zybo Z7-20 configured for JTAG boot and UART1 open at 115200 baud:

```bash
make program-zybo-z7
```

The command programs the FPGA, initializes the processing system from the
exported Zybo platform, downloads the bare-metal ELF, and starts execution.
The acceptance criterion is:

```text
[PASS] image-to-image DMA golden test passed
```

Until this result is captured from physical hardware, board-level DMA, DDR,
clocking, reset, and signal-integrity behavior should be treated as unverified.
Use [BOARD_BRINGUP.md](docs/BOARD_BRINGUP.md) for the complete procedure and
[board_arrival_runbook.md](docs/board_arrival_runbook.md) for the evidence to
record.

## Design Constraints

- The implemented board configuration uses `PC=2`, `PK=4`, and
  `MAX_PIXELS=16`; larger configurations require a new implementation run.
- Model metadata is atomically activated in retained PL memories; layer
  parameters are loaded from DDR into reusable active/prefetch banks.
- `make baremetal-headers` regenerates the Gaussian default packet. Alternative
  parameters must preserve the synthesized `3 -> 16 -> 16 -> 3` tensor shapes
  and the documented packet order.
- DMA completion is currently polled by software. Interrupt status exists in
  the register interface, but the application does not yet use interrupt-driven
  completion.
- Runtime descriptors select one to eight 1x1/3x3 convolution layers, tensor
  geometry, channel counts, activation, per-channel quantization, and optional
  final residual add/subtract within the V1 capability limits.
- Timing closure has 0.036 ns setup and 0.027 ns hold margin at 125 MHz, so any
  architectural or tool-version change requires timing to be re-qualified.

## Documentation

| Document | Scope |
|---|---|
| [Architecture](docs/architecture.md) | Processing system, DMA, datapath, and network structure |
| [Block diagrams](docs/block_diagram.md) | System and accelerator data-flow diagrams |
| [Stream interface](docs/stream_interface.md) | Tensor packet format and protocol errors |
| [Packed DMA protocol](docs/packed_dma_protocol.md) | Versioned programmable tile and parameter packet contract |
| [Register map](docs/register_map.md) | AXI-Lite software interface |
| [Runtime model lifecycle](docs/runtime_model_lifecycle.md) | Dual-bank metadata loading, validation, and atomic activation |
| [Descriptor-driven execution](docs/descriptor_driven_execution.md) | Active-bank layer sequencing, semantic checks, parameter handshake, and RTL evidence |
| [Runtime parameter banks](docs/runtime_parameter_banks.md) | Dual-bank loading, CRC validation, ownership, prefetch overlap, and integrated RTL evidence |
| [Performance counters](docs/performance_counters.md) | Counter definitions and interpretation |
| [Compute and bandwidth budget](docs/bandwidth_budget.md) | Tail efficiency and DDR roofline calculations |
| [Verification matrix](docs/verification_matrix.md) | Coverage, evidence, and outstanding hardware tests |
| [Synthesis experiments](docs/synthesis_experiments.md) | Parallelism and implementation tradeoffs |
| [Board implementation](docs/board_implementation.md) | Timing, utilization, and generated artifacts |
| [Bare-metal application](docs/baremetal_app.md) | DMA execution and golden comparison flow |
| [Known warnings](docs/known_warnings.md) | Explicit Vivado warning budget |
| [Board bring-up](docs/BOARD_BRINGUP.md) | Programming, UART, and debug procedure |

## License

This project is distributed under the terms in [LICENSE](LICENSE). Vendored
Digilent board-definition and reference-constraint files retain their upstream
license notices and provenance.
