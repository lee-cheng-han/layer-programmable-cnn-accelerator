# AXI-Lite Register Map

`cnn_axi_lite_slave` provides the software control plane for
`cnn_image2image_system_top`. Tensor payloads remain on AXI-Stream; AXI-Lite is
used for job configuration, commands, status, interrupts, diagnostics, and
performance snapshots.

All registers are 32 bits wide and word-aligned. Writable registers honor
`WSTRB`. Writes to read-only or unmapped addresses return `SLVERR`; unmapped
reads return `0xDEAD_BEEF` with `SLVERR`.

| Offset | Name | Access | Description |
|---:|---|---|---|
| `0x000` | `CONTROL` | WO | Bit 0: start pulse; bit 1: clear pulse |
| `0x004` | `STATUS` | RO | Live job and scheduler state |
| `0x008` | `IRQ_STATUS` | RW1C | Bit 0: job done; bit 1: job error |
| `0x00C` | `IRQ_ENABLE` | RW | Enables corresponding `IRQ_STATUS` bits |
| `0x010` | `IMAGE_WIDTH` | RW | Image width in pixels |
| `0x014` | `IMAGE_HEIGHT` | RW | Image height in pixels |
| `0x018` | `MODE_FLAGS` | RW | Bit 0: final residual subtraction enable |
| `0x01C` | `ERROR_CODE` | RO | Packet-router or compute error code |
| `0x020` | `STREAM_STATE` | RO | Bits 2:0 packet type; bits 5:3 ready layers |
| `0x024` | `PACKET_WORDS` | RO | Payload words accepted in current packet |
| `0x028` | `MODEL_COMMAND` | WO | Begin/finish load, validate, activate, or retire |
| `0x02C` | `MODEL_STATUS` | RO | Staging state, bank selectors, active-valid, and lifecycle error |
| `0x030` | `STAGING_MODEL_ID` | RO | Model ID read from the staging header |
| `0x034` | `STAGING_GENERATION` | RO | Generation ID read from the staging header |
| `0x038` | `ACTIVE_MODEL_ID` | RO | Atomically selected active model ID, or zero |
| `0x03C` | `ACTIVE_GENERATION` | RO | Atomically selected active generation, or zero |
| `0x040` | `METADATA_ADDRESS` | RW | Metadata kind, record index, and word index selector |
| `0x044` | `METADATA_DATA` | RW | Selected 32-bit staging metadata word |
| `0x048` | `METADATA_COMMIT` | WO | Bit 0 commits the selected record |
| `0x04C` | `MODEL_ERROR` | RW1C | Lifecycle error; write bit 0 to clear |
| `0x050` | `STAGING_COUNTS0` | RO | Tensor count in bits 31:16; layer count in bits 15:0 |
| `0x054` | `STAGING_COUNTS1` | RO | Quantization count in bits 15:0 |
| `0x080` | `PERF_JOB_CYCLES` | RO | Total active job cycles |
| `0x084` | `PERF_PACKET_CYCLES` | RO | Packet-router active cycles |
| `0x088` | `PERF_COMPUTE_CYCLES` | RO | Scheduler compute-active cycles |
| `0x08C` | `PERF_PREFETCH_CYCLES` | RO | Parameter prefetch overlap cycles |
| `0x090` | `PERF_LAYER0_CYCLES` | RO | Layer 0 selected compute cycles |
| `0x094` | `PERF_LAYER1_CYCLES` | RO | Layer 1 selected compute cycles |
| `0x098` | `PERF_LAYER2_CYCLES` | RO | Layer 2 selected compute cycles |
| `0x09C` | `PERF_INPUT_WORDS` | RO | Accepted input AXI-Stream words |
| `0x0A0` | `PERF_INPUT_STALLS` | RO | Input valid without ready cycles |
| `0x0A4` | `PERF_OUTPUT_WORDS` | RO | Accepted output AXI-Stream words |
| `0x0A8` | `PERF_OUTPUT_STALLS` | RO | Output valid without ready cycles |
| `0x0FC` | `VERSION` | RO | Register-map version, currently `0x00050001` |
| `0x100`-`0x17C` | `CAPABILITY_*` | RO | Versioned 128-byte capability record |
| `0x180`-`0x1BC` | `ERROR_RECORD_*` | RO | Sticky 64-byte structured-error record |

## Status Bits

| Bits | Meaning |
|---:|---|
| `0` | Busy |
| `1` | Done |
| `2` | Error |
| `3` | Performance counters active |
| `7:4` | Scheduler phase |
| `9:8` | Active layer |
| `12:10` | Layer parameter-ready mask |
| `13` | Parameter prefetch active |
| `14` | Parameter prefetch observed during this job |

## Command Sequence

Software should configure the image before issuing start:

```text
write IMAGE_WIDTH
write IMAGE_HEIGHT
write MODE_FLAGS
write IRQ_STATUS = 0x3
write IRQ_ENABLE
write CONTROL = 0x1
stream the seven input packets
wait for IRQ or poll STATUS
read ERROR_CODE and performance registers
```

`CONTROL.clear` resets the active packet/compute job and clears pending interrupt
status. It also clears the structured-error snapshot. Completion and error
interrupts are edge-captured and remain pending until cleared through
`IRQ_STATUS` or `CONTROL.clear`.

## Model Lifecycle Commands

`MODEL_COMMAND` accepts one command bit per write:

| Bit | Command | Required state / effect |
|---:|---|---|
| 0 | `BEGIN_LOAD` | Select the bank opposite the active bank and enter loading |
| 1 | `FINISH_LOAD` | End metadata writes and enter loaded-unvalidated |
| 2 | `VALIDATE` | Check committed records, header, counts, versions, sizes, and IDs |
| 3 | `ACTIVATE` | Atomically select validated staging metadata; rejected while busy |
| 4 | `RETIRE` | Clear active-valid; rejected while busy |

`MODEL_STATUS` is encoded as follows:

| Bits | Meaning |
|---:|---|
| `2:0` | staging state: 0 unloaded, 1 loading, 2 loaded-unvalidated, 3 validated |
| `3` | active model valid |
| `4` | staging bank selector |
| `5` | active bank selector |
| `15:8` | lifecycle error code |

`METADATA_ADDRESS[1:0]` selects header, layer, tensor, or quantization;
bits `7:2` select a record and bits `13:8` select its 32-bit word. Software
must fully write each record before writing bit 0 to `METADATA_COMMIT`.
Descriptor records are committed in ascending contiguous ID order. Metadata
readback uses synchronous block RAM; setting `METADATA_ADDRESS` before reading
`METADATA_DATA` provides the required clock of address-to-data latency.

The safe replacement sequence is:

```text
validate complete package in software
write MODEL_COMMAND.BEGIN_LOAD
write and commit header, layer, tensor, and quantization records
write MODEL_COMMAND.FINISH_LOAD
write MODEL_COMMAND.VALIDATE
confirm MODEL_STATUS staging state = validated and MODEL_ERROR = 0
write MODEL_COMMAND.ACTIVATE while STATUS.busy = 0
confirm ACTIVE_MODEL_ID and ACTIVE_GENERATION
```

The active model remains unchanged after any failed staging or validation
operation. See [runtime_model_lifecycle.md](runtime_model_lifecycle.md) for the
memory organization and validation boundary.

Software should read and validate the capability record once during driver
initialization. The exact record layouts, feature flags, error enums, and
current fixed-hardware interpretation are specified in
[capability_and_errors.md](capability_and_errors.md).

The current wrapper shares one clock/reset domain between AXI-Lite, AXI-Stream,
and the accelerator. A future block design must insert clock converters if those
interfaces use different clocks.
