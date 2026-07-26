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
| 1 | Freeze exact V1 model-package ABI | Complete, including per-channel requantization |
| 2 | Build model compiler and package-level bit-accurate executor | Complete |
| 3 | Add capability discovery and structured errors | Complete |
| 4 | Add runtime metadata memories and atomic model lifecycle | Complete |
| 5 | Generalize descriptor-driven layer execution control | Complete |
| 6 | Add reusable active/prefetch parameter banks | Complete |
| 7 | Introduce packed, versioned DMA protocol | Complete |
| 8 | Implement DDR-backed spatial tiling and halo handling | Next |
| 9 | Complete residual and quantization behavior in runtime RTL | Planned |
| 10 | Build runtime software and connect interrupts | Planned |
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
