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
| 3 | Add capability discovery and structured errors | Programmable first-fault snapshot integrated; exact validator field/range propagation remains |
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
| 14 | Validate a learned model and build an ONNX import path | Planned after board baseline |
| 15 | Harden firmware, diagnostics, and recovery | Planned |
| 16 | Add formal, CDC/RDC, and long-duration verification | Planned |
| 17 | Evaluate command queues, scatter-gather DMA, and additional operators | Optional after profiling |
| 18 | Add deployment security and field-update safeguards | Optional deployment scope |

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
| 1 | Close actual RTL tensor chaining | Implemented | The UVM DDR model scatters observed RTL output packets into strided tensor memory and gathers that memory for the next layer; the two-layer test injects no intermediate golden tensor |
| 2 | Complete UVM verification and coverage closure | U4 complete; U5 functional target closed | Preserve the 96.72% functional result, obtain fresh code reports from a stable tool flow, review scoped exclusions, measure assertion coverage, and meet every remaining target |
| 3 | Improve structured error propagation | First-fault aperture and firmware decode complete; internal detail partial | First-failure records identify subsystem, model generation, layer, tensor, tile, packet field, observed value, and expected range for every programmable-runtime failure |
| 4 | Complete runtime observability | Partial | Per-layer and per-job cycles, MAC-active cycles, input starvation, output backpressure, parameter stalls, bytes, MACs, and saturation events are software-visible and tested |
| 5 | Expand measurable verification coverage | Baseline complete | CI records coverage across 1-8 layers, both kernels, both strides, all activations and residual modes, asymmetric boundaries, channel tails, partial beats, clipping, and multiple deterministic seeds |
| 6 | Complete memory and recovery fault campaign | Partial | Tests cover corrupted parameters, stale tensor IDs, packet reordering, aborted jobs, DMA timeout, active-model replacement, and successful rerun without reset |
| 7 | Harden the software ABI | Generated constants complete; record serializers remain language-native | One machine-readable schema generates Python, C, and SystemVerilog constants and register definitions; CI checks generated files and cross-language record sizes |
| 8 | Add interrupt-driven scheduling | Planned | DMA and accelerator interrupts advance parameter/tile work without polling, while timeout and error recovery remain deterministic |
| 9 | Regenerate the production board implementation | Pending current source baseline | The Zybo Z7-20 block design passes multiple clean 125 MHz implementation runs and archives bitstream, XSA, ELF, BOOT.BIN, timing, utilization, congestion, power, and warning reports with hashes |
| 10 | Validate physical hardware | Board required | UART, ILA, device view, correctness, recovery, and measured 224x224/512x512 performance evidence are archived |
| 11 | Retire the fixed-network compatibility path | Waiting for board parity | Legacy execution RTL, software, build targets, and documentation are removed only after programmable hardware regression parity |
| 12 | Add autonomous PL-side DDR fetching | Optional after board baseline | A descriptor-driven AXI master fetches parameters and tiles with bounded bursts, arbitration, timeout, structured recovery, and software fallback |
| 13 | Produce the final demonstration | Planned | 224x224 and 512x512 examples include input/output images, measured latency and throughput, device view, UART transcript, and ILA evidence |
| 14 | Validate a real learned workload | Planned after board baseline | A supported image-to-image ONNX model compiles reproducibly, matches the software reference within declared INT8 tolerances, and reports PSNR, SSIM, exact-match, and saturation metrics |
| 15 | Complete the model compiler toolchain | Planned | Import, shape inference, capability validation, tensor lifetime assignment, operator fusion, tile planning, package inspection, and deterministic package generation are tested end to end |
| 16 | Raise firmware quality to production discipline | Partial | Platform, DMA, scheduler, model-loader, and application layers have host tests, static analysis, sanitizers, overflow checks, typed errors, retained diagnostics, and documented memory/cache contracts |
| 17 | Add formal and static hardware signoff | Planned | Formal properties cover FIFO accounting, bank ownership, lifecycle atomicity, bounds, and forward progress; CDC/RDC, reset, latch, and synthesis/simulation checks have reviewed zero-error reports |
| 18 | Add long-duration and differential verification | Planned | Python, host C, RTL, and board outputs are compared over overnight randomized runs with reset, clock-startup, AXI-latency, packet-fragmentation, counter-wrap, and simultaneous IRQ/error injection |
| 19 | Optimize from measured bottlenecks | Board measurements required | Profiling attributes cycles to compute, parameter loading, DMA, backpressure, and software; tile size, bank overlap, lane utilization, and parallelism are changed only when measured results justify them |
| 20 | Evaluate advanced scheduling and operators | Optional after profiling | Scatter-gather DMA, command queues, autonomous fetching, depthwise convolution, and additional activations are accepted only with a target-model need and quantified cost/benefit |
| 21 | Add deployment security and resilience | Optional deployment scope | All DDR ranges and arithmetic are validated; authenticated packages, rollback policy, watchdog behavior, parameter integrity, and brownout/partial-transfer recovery are defined and tested where required |

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

1. **UVM coverage closure:** use the passing 22-case U4/U5 baseline to target
   uncovered functional bins, establish reviewed DUT code-coverage scope and
   exclusions, measure assertion coverage, and close every declared target.
2. **Diagnostics, counters, and ABI generation:** finish structured first-fault
   records, per-layer performance records, and one-source generation of Python,
   C, and SystemVerilog ABI definitions.
3. **Coverage and fault campaign:** run multiple deterministic model seeds and
   publish functional coverage for kernels, strides, residuals, boundaries,
   tails, packet faults, DMA timeout, abort, replacement, and recovery.
4. **Interrupt-driven runtime:** replace the polling-only scheduler path with
   DMA and accelerator interrupt progression while retaining bounded timeout
   and recovery behavior.
5. **Programmable board implementation closure:** rerun the complete Zybo Z7-20
   block design at 125 MHz and generate hashed bitstream, XSA, ELF, BOOT.BIN,
   timing, utilization, congestion, power, and warning artifacts.
6. **Physical-board validation and demonstration:** capture correctness,
   UART, ILA, device, recovery, and measured 224x224/512x512 evidence; then
   retire the fixed-network compatibility path.
7. **Optional autonomous fetching:** consider a PL-side DDR master only after
   the software-managed board baseline is measured and stable.
8. **Learned-model and compiler validation:** import one compatible
   image-to-image ONNX network, reject unsupported graphs precisely, generate
   a deterministic package and tile plan, and compare Python, host-C, RTL, and
   board outputs using exact-match, PSNR, SSIM, and saturation statistics.
9. **Firmware and hardware hardening:** complete typed errors, retained fault
   snapshots, host-testable hardware abstraction, static analysis, sanitizers,
   formal properties, CDC/RDC analysis, and long-duration recovery testing.
10. **Measurement-led architecture extensions:** use board profiles to decide
    whether scatter-gather DMA, a command queue, autonomous fetching, channel
    packing, more parallelism, or additional operators provide enough benefit
    to justify their area and verification cost.

## Post-Baseline Engineering Backlog

These items extend the required board baseline. They are ordered by dependency;
features in the optional groups are not completion requirements for the V1
accelerator unless a selected workload or deployment environment requires them.

### Real Models And Compiler

- Import the supported ONNX subset and provide exact diagnostics for unsupported
  operators, shapes, quantization records, and graph topology.
- Add shape inference, tensor lifetime analysis, automatic tensor identifiers,
  compatible convolution/bias/activation/residual fusion, and scratchpad-aware
  tile planning.
- Emit deterministic package manifests containing compiler version, source-model
  hash, ABI version, tensor allocation, MAC count, memory traffic, and estimated
  latency.
- Add package inspection, disassembly, ABI migration, and reproducibility tools.
- Establish a fixed benchmark corpus with known package and output hashes, then
  quantify INT8 accuracy using exact-match rate, PSNR, SSIM, and saturation.

### Firmware Quality And Runtime Behavior

- Separate platform, DMA, accelerator, model-loader, scheduler, and application
  ownership behind a host-testable hardware abstraction layer.
- Apply warnings-as-errors, `clang-tidy`, `cppcheck`, host sanitizers, and a
  documented CERT C or selected MISRA C policy to portable runtime code.
- Test descriptor arithmetic, pointer ranges, alignment, timeout wraparound,
  cache-line boundaries, malformed packages, and repeated model replacement.
- Provide typed status codes, first-fault snapshots retained across soft reset,
  structured UART records, boot-time known-answer tests, and an explicit runtime
  state machine for load, activate, submit, complete, abort, and recover.
- Complete interrupt-driven scheduling and deterministic DMA-channel recovery;
  consider watchdog and multicore ownership only when the deployment requires
  them. FreeRTOS or Linux integration remains a separate target-specific port,
  not part of the bare-metal baseline.

### RTL Robustness And Observability

- Extend assertions to descriptor bounds, tensor and bank ownership, packet
  accounting, legal lifecycle transitions, bounded completion, and interrupt
  rearming.
- Expose a capability block and version record containing ABI support, tensor
  limits, operators, parallelism, memory capacities, and optional features.
- Define atomic performance snapshots, counter-overflow behavior, per-layer
  timeout controls, and structured fault records with model, layer, tensor,
  tile, packet field, observed value, and expected range.
- Review reset behavior, BRAM initialization and integrity, illegal accesses,
  and every PS/PL clock or reset crossing with CDC/RDC tooling.

### Verification Signoff

- Prove FIFO accounting, parameter-bank exclusivity, atomic model activation,
  bounds safety, and selected forward-progress properties with formal methods.
- Collect statement, branch, toggle, FSM, assertion, and functional coverage;
  set explicit targets, review exclusions, and map requirements to tests and
  coverpoints.
- Differentially compare Python, host C, RTL, and board behavior over retained
  randomized seeds, including resets in every phase, AXI stalls, malformed
  packets, stale identifiers, CRC failures, counter wrap, and simultaneous
  completion/error events.
- Run overnight stress and mutation campaigns, minimize failures, and archive
  seeds, packages, logs, coverage databases, and waveforms in licensed CI.

### Measurement-Led Optimization

- Attribute board cycles and bytes to computation, parameter refill, input and
  output DMA, software setup, starvation, and backpressure before changing RTL.
- Measure parameter-bank overlap, halo overhead, realistic DDR bandwidth, RGB
  first-layer lane utilization, CPU load, recovery latency, power, and energy
  per image.
- Tune tile geometry and compare `PC`/`PK` configurations using routed timing,
  utilization, congestion, bandwidth, power, and measured throughput rather
  than arithmetic peak alone.
- Evaluate scatter-gather DMA, hardware command queues, autonomous PL fetching,
  and deterministic cancellation or preemption only after profiling identifies
  control overhead as a material bottleneck.
- Add depthwise convolution, extra activations, compression, or Winograd only
  when a chosen model needs them and the accuracy, area, bandwidth, and
  verification tradeoff is quantified.

### Deployment Security And Resilience

- Validate every package offset, size, multiplication, tensor range, and DMA
  address before hardware submission, and confine DMA to the reserved workspace.
- Add authenticated model packages, generation rollback policy, and field-update
  rules only when models can originate outside the trusted firmware image.
- Define and test parameter-memory integrity, processor/PL reset interaction,
  brownout behavior, partial-transfer cleanup, and preservation of the previous
  active model after failed replacement.

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
