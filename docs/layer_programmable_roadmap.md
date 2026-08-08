# Layer-Programmable Accelerator Roadmap

## Objective

The final system is a versioned, layer-programmable INT8 image accelerator on a
single 125 MHz Zybo Z7-20 bitstream. It executes fixed image-processing kernels
such as blur and edge detection as well as compatible learned image-to-image
CNNs. Models are compiled into relocatable packages, staged and validated,
atomically activated, and reused across multiple images.

## Milestones

| Phase | Deliverable | Status |
|---:|---|---|
| 0 | Preserve fixed-network board baseline and evidence | Complete; physical board validation pending |
| 1 | Freeze exact V1 model-package ABI | Complete; per-channel numeric contract frozen |
| 2 | Build model compiler and package-level bit-accurate executor | Complete |
| 3 | Add capability discovery and structured errors | Baseline complete; programmable-stage propagation remains |
| 4 | Add runtime metadata memories and atomic model lifecycle | Complete |
| 5 | Generalize descriptor-driven layer execution control | Complete |
| 6 | Add reusable active/prefetch parameter banks | Complete |
| 7 | Introduce packed, versioned DMA protocol | Complete |
| 8 | Implement DDR-backed spatial tiling and halo handling | RTL complete through integrated software-managed tile interface |
| 9 | Complete residual and quantization behavior in runtime RTL | Complete |
| 10 | Build runtime software and connect interrupts | AXI-Lite and board interrupt wiring complete; runtime software pending |
| 11 | Add autonomous DDR fetching | Planned |
| 12 | Expand protocol, randomized, golden, and negative verification | Planned |
| 13 | Optimize performance and validate physical hardware | Planned |

Phase 5 accepts descriptor-driven sequencing through a temporary or
software-reloaded parameter path. Phase 6 is the point at which networks of one
to eight mixed layers execute through reusable active and prefetch parameter
banks. The packed DMA protocol precedes full tiling because tile transfers
depend on tensor IDs, coordinates, byte counts, partial beats, and recovery
semantics.

V1 deliberately uses tail masking rather than cross-pixel channel packing.
It has two independent 4,096-byte weight banks and two independent 256-byte
postprocessing banks. The final parallelism choice remains gated by the
[compute and DDR bandwidth budget](bandwidth_budget.md).

Phase 4 now provides two complete metadata banks, a software-visible record
aperture, commit tracking, structural validation, busy-safe retirement, and
single-cycle active-bank switching. See
[runtime_model_lifecycle.md](runtime_model_lifecycle.md).

Phase 5 now decodes the atomically active metadata bank and sequences one to
eight mixed 1x1/3x3 layers through the reusable single-layer scheduler. It
checks geometry, tensor chaining, supported operations, final-layer flags, and
residual compatibility before requesting parameters. The temporary
request/ready parameter boundary is documented in
[descriptor_driven_execution.md](descriptor_driven_execution.md).

Phase 6 now provides two layer-tagged weight/postprocessing banks with exact
length validation, ABI-compatible CRC32, compute ownership, release, and
overlapped prefetch. `cnn_programmable_job_engine` connects the banked weight
read path directly to the descriptor controller and proves an eight-layer job
while recycling only two banks. See
[runtime_parameter_banks.md](runtime_parameter_banks.md).

Phase 7 now defines an eight-word versioned packet header, packed INT8 byte
lanes, natural INT32 bias beats, exact byte lengths, low-lane `TKEEP`, final
`TLAST`, context backpressure, malformed-packet draining, and parameter-load
abort. The ingress parser/router is integrated with the real reusable banks,
and the egress writer generates packed `OUTPUT_TILE` packets. See
[packed_dma_protocol.md](packed_dma_protocol.md).

Phase 8 now has a synthesizable output-tile planner, clipped receptive-field
geometry, explicit local halo zero fill, packed tile ingestion into a real
banked activation scratchpad, and a multi-layer controller that sequences
active descriptors through the tiled 1x1/3x3 runtime and reusable parameter
banks. Multi-tile golden tests cover 1x1 and 3x3 stride-2 output, clipped
boundaries, partial packets, and AXI backpressure. A two-layer packed flow also
proves tensor-ID preservation, software-managed DDR handoff, progress, and
invalid-chain rejection. The atomically active metadata view exports layer
tile hints and complete input/output DDR offset/allocation/stride records.
Software DDR gather/scatter, board integration, and randomized multi-layer
payload coverage remain. The planner itself has deterministic randomized
geometry coverage. See [tiled_execution.md](tiled_execution.md).

Phase 9 now resolves each active layer's quantization descriptor, supplies
per-output-channel signed multipliers, shifts, and zero points to a pipelined
round-half-to-even requantizer, and counts positive and negative INT8 clipping
events. Final-layer residual add and subtract consume a second packed tile,
operate on two post-requantization signed INT8 operands, and saturate the
result. Directed standalone and integrated runtime tests cover ties, channel
scales, lane tails, positive/negative clipping, residual modes, and saturation
counter readback.

The integrated programmable runtime top now closes the active metadata
store, packed parser/router, CRC-checked reusable parameter banks, and tiled
multi-layer controller into one synthesizable data path. Its golden test loads
and activates a model, streams parameters and tiles, and verifies packed
output. The Zybo block design now selects this top as its production stream
core, carries `TKEEP` end to end, and routes CNN, DMA MM2S, and DMA S2MM
interrupts to the PS. DDR gather/scatter runtime software remains before this
path reaches software regression parity with the fixed-network baseline.

## Engineering Completion Plan

This table is the canonical remaining-work view. A status of **Implemented**
means the repository contains integrated evidence for that scope, not merely a
documented interface or an isolated module.

| Priority | Improvement | Current state | Completion gate |
|---:|---|---|---|
| 1 | Converge on one production architecture | In progress; programmable runtime selected by the Zybo block design | Legacy execution RTL and software are retired after programmable bare-metal regression parity |
| 2 | Complete per-channel quantization | Implemented | Active quantization descriptors drive per-output-channel multiplier/shift, round-half-to-even, saturation, and zero-point checks through the integrated tiled runtime |
| 3 | Implement DDR tile scheduling | RTL interface implemented; software pending | Bare-metal software gathers clipped NHWC source rectangles, submits DMA packets, scatters outputs, manages intermediate tensors and caches, and times out safely |
| 4 | Strengthen integrated verification | Partial | Deterministic randomized 1-8-layer package-to-output tests cover mixed kernels, strides, padding, tails, backpressure, partial beats, CRC faults, malformed packets, and model replacement |
| 5 | Improve structured error propagation | Partial | First-failure records identify subsystem, model generation, layer, tensor, tile, field, observed value, and expected range for every programmable-runtime failure |
| 6 | Add runtime observability | Partial | Per-layer/tile cycles, compute utilization, DMA starvation, output stalls, parameter stalls, bytes, MACs, and saturation events are software-visible and tested |
| 7 | Run implementation experiments early | Programmable PL top closes two clean OOC physical searches at 125 MHz; board-integrated rerun pending | Programmable board top passes multiple implementation seeds at 125 MHz with positive timing margin and archived timing, utilization, congestion, and critical-path reports |
| 8 | Harden the software ABI | Partial | One machine-readable schema generates Python, C, and SystemVerilog constants/records; CI checks generated files and compile-time sizes |
| 9 | Separate fast and licensed CI | Implemented for current scope | Open-source lint/model/docs jobs run on each push; licensed Vivado proof runs separately and publishes simulation/flow evidence |
| 10 | Produce a final demonstration | Planned | 224x224 and 512x512 examples include input/output images, measured latency/throughput, device view, UART transcript, and ILA evidence |

### Existing Evidence Mapped To The Plan

- The integrated programmable runtime already closes atomic metadata,
  descriptor-derived parameter CRC validation, packed DMA routing, reusable
  banks, tiled execution, and packed output.
- The compiler, package executor, ABI records, metadata store, and integrated
  tiled runtime implement per-output-channel fixed-point math,
  round-half-to-even, zero points, signed saturation, and clipping counters.
- Directed and deterministic-randomized geometry, halo, protocol, controller,
  parameter-bank, and golden-network tests already provide the base for the
  expanded randomized campaign.
- Capability records, structured-error snapshots, performance counters,
  warning budgets, synthesis sweeps, separate CI workflows, and generated
  evidence reports already exist. They must be extended to the programmable
  board path rather than recreated.

## Remaining Major Milestones

1. **Programmable control and board integration:** the integrated runtime is
   bridged to AXI-Lite, selected as the Zybo stream core, connected to DMA with
   `TKEEP`, and wired to the PS interrupt input alongside both DMA channels.
   The programmable PL top now retains timing across default and Explore OOC
   implementations at 125 MHz. The board-integrated implementation remains the
   final gate for PS, DMA, clock, and external-constraint closure.
2. **DDR-backed runtime software:** load active packages and parameters, gather
   halo-aware tiles, operate AXI DMA, scatter outputs, maintain caches, and
   recover from timeouts.
3. **Verification and diagnostics hardening:** add randomized multi-layer
   package flows, fault recovery, structured programmable errors, and detailed
   performance counters.
4. **Programmable board implementation closure:** carry the closed programmable
   PL top into the Zynq block design, rerun full-board timing, and generate the
   final bitstream/XSA/BOOT.BIN baseline.
5. **Physical-board validation and demonstration:** capture correctness,
   UART/ILA/device evidence, and measured 224x224/512x512 performance.

## Final Workflow

```text
network.yaml + signed INT8 weights
  -> Python model compiler
  -> relocatable V1 package in DDR
  -> load staging metadata
  -> validate checksums, capabilities, and references
  -> atomically activate model generation
  -> run multiple input images
  -> output tensors and per-layer performance records
```

The complete model package remains in DDR. Descriptors and tensor/quantization
metadata are retained in accelerator memory. Layer parameters are prefetched
from DDR into reusable banks as needed. A final `RUN_IMAGE` launches a complete
job without CPU intervention for every tile or layer.

## Performance Framing

At eight issued MACs per cycle and 125 MHz, arithmetic peak is approximately
1 GMAC/s. An eight-layer 16-to-16-channel 3x3 network at 1024x1024 contains
approximately 19.3 billion MACs, so its ideal compute lower bound is roughly
19.3 seconds before transfer and control overhead. Accordingly:

- 224x224 is the primary recognizable CNN benchmark.
- 512x512 is the substantial image-processing demonstration.
- 1024x1024 is the functional maximum and stress test.

Claims about real-time operation will be based on post-route and physical-board
measurements, not the dimensional capability limit.
