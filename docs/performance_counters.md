# Performance Counters

`performance_counters` records one snapshot for each accepted AXI job. Counting starts when the packet router accepts `start` and stops when the compute job completes or a protocol/core error aborts it.

All counters are unsigned 32-bit wrapping counters. They clear on reset, `clear`, or the next accepted job and retain their final values after counting stops.

## Counter Definitions

| Counter | Increment condition |
|---|---|
| `perf_job_cycles` | Every cycle while the accepted job is active |
| `perf_packet_cycles` | Packet router is receiving a header or payload |
| `perf_compute_cycles` | Multi-layer scheduler is active |
| `perf_prefetch_cycles` | Later-layer parameter loading overlaps scheduler activity |
| `perf_layer0_cycles` | Scheduler active with layer 0 selected |
| `perf_layer1_cycles` | Scheduler active with layer 1 selected |
| `perf_layer2_cycles` | Scheduler active with layer 2 selected |
| `perf_input_words` | Input `TVALID && TREADY`, including seven headers |
| `perf_input_stall_cycles` | Input `TVALID && !TREADY` |
| `perf_output_words` | Output `TVALID && TREADY` |
| `perf_output_stall_cycles` | Output `TVALID && !TREADY` |

`perf_counting` indicates that the counters currently belong to an active job.

The layer counters include scheduler transition and readiness-wait cycles because the multi-layer scheduler still owns the selected layer during those intervals. Therefore:

```text
perf_compute_cycles
 = perf_layer0_cycles
 + perf_layer1_cycles
 + perf_layer2_cycles
```

For the fixed default network, a complete input contains:

```text
7 packet headers
+ width * height * 3 activation words
+ 16 + (16 * 3 * 9) layer 0 parameter words
+ 16 + (16 * 16 * 9) layer 1 parameter words
+ 3 + (3 * 16 * 9) layer 2 parameter words
```

The counters are exposed directly by the stream top and through read-only
AXI-Lite registers in `cnn_axi_lite_slave`. See
[register_map.md](register_map.md) for offsets.

## Final V1 Observability

The programmable runtime now provides an independent snapshot at `0x080` and
retains it after completion or failure:

| Counter | Meaning |
|---|---|
| Job cycles | Accepted start through completion or failure |
| Controller cycles | Descriptor and layer-controller ownership time |
| Compute-active cycles | Tiled layer runtime busy cycles |
| Parameter stalls | Runtime requested a reusable parameter bank that was not ready |
| Input starvation | Runtime requested an activation packet or payload beat that was absent |
| Output backpressure | Output `TVALID && !TREADY` cycles |
| Input/output bytes | Exact accepted `TKEEP` byte lanes, including packet headers |
| Saturation events | Requantization and residual INT8 clipping events |
| Per-layer cycles | Controller ownership time for each of up to eight layers |

| Offset | Counter |
|---:|---|
| `0x080` | job cycles |
| `0x084` | controller cycles |
| `0x088` | compute-active cycles |
| `0x08C` | parameter-stall cycles |
| `0x090` | input-starvation cycles |
| `0x094` | output-backpressure cycles |
| `0x098` | input bytes |
| `0x09C` | output bytes |
| `0x0A0` | saturation events |
| `0x0A4` | completed layers |
| `0x0A8` | completed tiles |
| `0x0AC` | bit 0: snapshot currently counting |
| `0x0C0`-`0x0DC` | layer 0 through layer 7 cycles |

Saturation counters increment once per clipped tensor element, not once per
cycle. The bare-metal bring-up application prints job, controller, compute,
stall, byte, and per-layer cycle values after a passing run. Actual MAC issue
counting remains a separate refinement: it must use the compute engines' valid
and lane-mask signals rather than a geometry-derived estimate.
