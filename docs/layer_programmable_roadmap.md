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
| 8 | Implement DDR-backed spatial tiling and halo handling | Complete through portable software-managed DDR runtime |
| 9 | Complete residual and quantization behavior in runtime RTL | Complete |
| 10 | Build runtime software and connect interrupts | Polling runtime and board interrupt wiring complete; interrupt-driven scheduling remains |
| 11 | Add autonomous DDR fetching | Planned |
| 12 | Expand protocol, randomized, golden, and negative verification | Complete for pre-board scope |
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
The portable bare-metal library validates compiled packages, derives the same
clipped source geometry, gathers and scatters strided NHWC tensors, and
encodes and validates exact packed DMA packets. The seeded software corpus and
compiler-derived four-layer RTL flow now cover randomized multi-layer payloads;
the planner also has deterministic randomized geometry coverage. See
[tiled_execution.md](tiled_execution.md).

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
interrupts to the PS. The software-managed runtime now stages packages,
preloads and refills reusable parameter banks, schedules tiles through AXI DMA,
maintains cache ownership, and validates and scatters packed output. A rebuilt
XSA, target ELF, and physical board run remain before hardware regression
parity.

## Engineering Completion Plan

This table is the canonical remaining-work view. A status of **Implemented**
means the repository contains integrated evidence for that scope, not merely a
documented interface or an isolated module.

| Priority | Improvement | Current state | Completion gate |
|---:|---|---|---|
| 1 | Close actual RTL tensor chaining | Planned | A behavioral DDR/DMA model scatters each RTL output packet into tensor memory and gathers that stored tensor for the next layer; no Python intermediate tensor is injected after layer zero |
| 2 | Complete UVM verification and coverage closure | U0 foundation implemented and elaborated | U1-U5 gates cover executable regression, independent DDR/reference checking, mature agents and RAL, constrained-random faults, assertions, traceability, and documented coverage closure |
| 3 | Improve structured error propagation | Partial | First-failure records identify subsystem, model generation, layer, tensor, tile, packet field, observed value, and expected range for every programmable-runtime failure |
| 4 | Complete runtime observability | Partial | Per-layer and per-job cycles, MAC-active cycles, input starvation, output backpressure, parameter stalls, bytes, MACs, and saturation events are software-visible and tested |
| 5 | Expand measurable verification coverage | Baseline complete | CI records coverage across 1-8 layers, both kernels, both strides, all activations and residual modes, asymmetric boundaries, channel tails, partial beats, clipping, and multiple deterministic seeds |
| 6 | Complete memory and recovery fault campaign | Partial | Tests cover corrupted parameters, stale tensor IDs, packet reordering, aborted jobs, DMA timeout, active-model replacement, and successful rerun without reset |
| 7 | Harden the software ABI | Partial | One machine-readable schema generates Python, C, and SystemVerilog constants and records; CI checks generated files and compile-time sizes |
| 8 | Add interrupt-driven scheduling | Planned | DMA and accelerator interrupts advance parameter/tile work without polling, while timeout and error recovery remain deterministic |
| 9 | Regenerate the production board implementation | Pending current source baseline | The Zybo Z7-20 block design passes multiple clean 125 MHz implementation runs and archives bitstream, XSA, ELF, BOOT.BIN, timing, utilization, congestion, power, and warning reports with hashes |
| 10 | Validate physical hardware | Board required | UART, ILA, device view, correctness, recovery, and measured 224x224/512x512 performance evidence are archived |
| 11 | Retire the fixed-network compatibility path | Waiting for board parity | Legacy execution RTL, software, build targets, and documentation are removed only after programmable hardware regression parity |
| 12 | Add autonomous PL-side DDR fetching | Optional after board baseline | A descriptor-driven AXI master fetches parameters and tiles with bounded bursts, arbitration, timeout, structured recovery, and software fallback |
| 13 | Produce the final demonstration | Planned | 224x224 and 512x512 examples include input/output images, measured latency and throughput, device view, UART transcript, and ILA evidence |

### Existing Evidence Mapped To The Plan

- The integrated programmable runtime already closes atomic metadata,
  descriptor-derived parameter CRC validation, packed DMA routing, reusable
  banks, tiled execution, and packed output.
- The compiler, package executor, ABI records, metadata store, and integrated
  tiled runtime implement per-output-channel fixed-point math,
  round-half-to-even, zero points, signed saturation, and clipping counters.
- Directed and deterministic-randomized geometry, halo, protocol, controller,
  parameter-bank, software-corpus, and compiler-derived golden RTL tests cover
  the pre-board randomized campaign.
- Capability records, structured-error snapshots, performance counters,
  warning budgets, synthesis sweeps, separate CI workflows, and generated
  evidence reports already exist. They must be extended to the programmable
  board path rather than recreated.

## Remaining Major Milestones

1. **Closed-loop DDR/DMA simulation:** replace injected golden intermediate
   tensors with a behavioral memory path that consumes actual RTL output and
   supplies it to the next descriptor-driven layer.
2. **UVM execution and coverage closure:** run the implemented register,
   lifecycle, scoreboard, and recovery tests on a compatible simulator; then
   complete independent DDR/reference checking, protocol and RAL maturity,
   compiler-generated randomized 1-8-layer faults, SVA, traceability, and
   merged functional coverage closure through stages U1-U5.
3. **Diagnostics, counters, and ABI generation:** finish structured first-fault
   records, per-layer performance records, and one-source generation of Python,
   C, and SystemVerilog ABI definitions.
4. **Coverage and fault campaign:** run multiple deterministic model seeds and
   publish functional coverage for kernels, strides, residuals, boundaries,
   tails, packet faults, DMA timeout, abort, replacement, and recovery.
5. **Interrupt-driven runtime:** replace the polling-only scheduler path with
   DMA and accelerator interrupt progression while retaining bounded timeout
   and recovery behavior.
6. **Programmable board implementation closure:** rerun the complete Zybo Z7-20
   block design at 125 MHz and generate hashed bitstream, XSA, ELF, BOOT.BIN,
   timing, utilization, congestion, power, and warning artifacts.
7. **Physical-board validation and demonstration:** capture correctness,
   UART, ILA, device, recovery, and measured 224x224/512x512 evidence; then
   retire the fixed-network compatibility path.
8. **Optional autonomous fetching:** consider a PL-side DDR master only after
   the software-managed board baseline is measured and stable.

## Final Workflow

```text
network.yaml + signed INT8 weights
  -> Python model compiler
  -> relocatable V1 package in DDR
  -> load staging metadata
  -> validate checksums, capabilities, and references
  -> atomically activate model generation
  -> software schedules DDR-backed tiles through AXI DMA
  -> run multiple input images
  -> output tensors and per-layer performance records
```

The complete model package remains in DDR. Descriptors and tensor/quantization
metadata are retained in accelerator memory. Layer parameters are prefetched
from DDR into reusable banks as needed. The current V1 runtime uses the
Cortex-A9 to schedule each tile; autonomous PL-side DDR fetching remains the
optional Phase 11 optimization.

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
