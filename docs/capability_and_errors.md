# Capability Discovery and Structured Errors

## Purpose

Software must discover what the loaded bitstream actually implements before it
loads or runs a model. Model ABI version and hardware capability are separate:
a bitstream may understand the V1 record vocabulary while not yet implementing
runtime package loading, DDR tiling, or autonomous fetching.

The control plane exposes two versioned, read-only records:

| AXI-Lite range | Record | Size |
|---:|---|---:|
| `0x100`-`0x17C` | Capability record | 128 bytes |
| `0x180`-`0x1BC` | Sticky structured-error record | 64 bytes |

Each 32-bit AXI-Lite register contains the corresponding four bytes of the
little-endian record. Reading all words in ascending address order reconstructs
the same byte sequence accepted by `CapabilityRecord.unpack()` or
`ErrorRecord.unpack()` in [`models/cnn_abi.py`](../models/cnn_abi.py).

## Capability Record

| Byte | AXI offset | Field |
|---:|---:|---|
| `0x00` | `0x100` | record version and size |
| `0x04` | `0x104` | hardware/register interface version |
| `0x08` | `0x108` | model ABI version and DMA beat bytes |
| `0x0C` | `0x10C` | feature flags |
| `0x10` | `0x110` | supported opcode mask |
| `0x14` | `0x114` | supported element-type mask |
| `0x18` | `0x118` | supported activation mask |
| `0x1C` | `0x11C` | supported rounding-mode mask |
| `0x20` | `0x120` | supported residual-mode mask |
| `0x24` | `0x124` | supported kernel-size mask |
| `0x28` | `0x128` | supported stride mask |
| `0x2C` | `0x12C` | maximum layers and tensors |
| `0x30` | `0x130` | maximum quant records and input channels |
| `0x34` | `0x134` | maximum output channels and tensor width |
| `0x38` | `0x138` | maximum tensor height and per-edge padding |
| `0x3C` | `0x13C` | maximum tile width and height |
| `0x40` | `0x140` | maximum spatial tensor elements |
| `0x44` | `0x144` | physical weight-bank bytes |
| `0x48` | `0x148` | physical post-processing-bank bytes (legacy field name: bias bank) |
| `0x4C` | `0x14C` | maximum semantic layer weight bytes |
| `0x50` | `0x150` | maximum semantic layer bias bytes |
| `0x54` | `0x154` | record and parameter alignment bytes |
| `0x58` | `0x158` | input/output channel parallelism (`PC`, `PK`) |
| `0x5C` | `0x15C` | accelerator clock in hertz |
| `0x60` | `0x160` | reserved; zero through `0x17C` |

Bitmask fields use `1 << enum_value`. Kernel and stride masks use
`1 << numeric_size`; for example, 1x1 and 3x3 support is bits 1 and 3.

### Feature Flags

| Bit | Name | Meaning |
|---:|---|---|
| 0 | `CAPABILITY_QUERY` | this record is implemented |
| 1 | `STRUCTURED_ERRORS` | the sticky error record is implemented |
| 2 | `MODEL_PACKAGES` | runtime can consume V1 model packages |
| 3 | `RUNTIME_METADATA` | descriptors reside in runtime-loaded memories |
| 4 | `PACKED_DMA` | packed-byte DMA protocol is implemented |
| 5 | `DDR_TILING` | DDR-backed spatial tiling is implemented |
| 6 | `AUTONOMOUS_FETCH` | hardware fetches layers/tiles without CPU service |
| 7 | `INTERRUPTS` | interrupt status and enable are implemented |
| 31 | `FIXED_NETWORK` | bitstream still uses a fixed synthesized network |

The checked-in board RTL currently reports:

```text
CAPABILITY_QUERY | STRUCTURED_ERRORS | RUNTIME_METADATA | INTERRUPTS | FIXED_NETWORK
```

It deliberately does **not** report `MODEL_PACKAGES`. Software can load,
validate, and atomically activate metadata, but the fixed scheduler does not
yet execute those descriptors. This prevents software from confusing retained
metadata with complete runtime package execution.

The fixed RTL also reports three layers, fixed 3x3/stride-1 operation,
`MAX_PIXELS` as both the maximum spatial element count and single-axis bound,
and the actual synthesized `PC`, `PK`, channel limits, and clock.
It advertises legacy arithmetic-shift quantization. The final programmable V1
target advertises per-output-channel round-half-to-even requantization; package
validation rejects a model whose rounding mode is absent from the capability
mask.

## Structured-Error Record

The record captures the first rising hardware error and remains stable until
`CONTROL.clear`. A later error cannot overwrite evidence from the original
failure.

| Byte | AXI offset | Field |
|---:|---:|---|
| `0x00` | `0x180` | record version and size |
| `0x04` | `0x184` | 32-bit error code |
| `0x08` | `0x188` | stage, record kind, and flags |
| `0x0C` | `0x18C` | record index and field ID |
| `0x10` | `0x190` | observed value, unsigned 64-bit |
| `0x18` | `0x198` | expected minimum, unsigned 64-bit |
| `0x20` | `0x1A0` | expected maximum, unsigned 64-bit |
| `0x28` | `0x1A8` | model ID |
| `0x2C` | `0x1AC` | model generation ID |
| `0x30` | `0x1B0` | implementation-specific detail |
| `0x34` | `0x1B4` | reserved; zero through `0x1BC` |

Error stages distinguish package load, package validation, model activation,
execution, and data-plane failures. Record kinds identify model, layer, tensor,
quantization, or packet records. Field IDs name concrete values such as width,
channel count, opcode, parameter size, packet type, or payload length.

For a limit error, software receives all of:

```text
error_code       = CAPABILITY_LIMIT_EXCEEDED
record_kind      = TENSOR
record_index     = failing tensor ID
field_id         = WIDTH
observed_value   = 2048
expected_min     = 1
expected_max     = 1024
model_id         = package model ID
generation_id    = package generation
```

The fixed packet router predates structured context. Its system wrapper
therefore records `DATA_PLANE_PROTOCOL`, packet kind/index, accepted packet
words as the observed value, and the legacy 8-bit router code in `detail`.

The programmable system now maps the same record at `0x180` and captures the
first lifecycle or runtime fault with active model generation, layer or tensor
context, tile coordinates, stage, subsystem kind, and observed low-level error
code. Firmware decodes and prints the record. Exact field/range propagation
from every internal validator remains the next diagnostic refinement.

## Software Validation

`validate_package_capabilities(package, capabilities)` checks a parsed package
against feature flags, counts, dimensions, spatial elements, channel limits,
parameter capacities, opcodes, kernels, strides, activation, residual mode,
rounding mode, padding, and element types. It raises `CapabilityError` with an attached
`ErrorRecord`, allowing host tools and hardware diagnostics to use the same
error vocabulary.

The final architectural envelope is returned by `target_v1_capabilities()`.
The honest checked-in hardware profile is returned by
`fixed_hardware_capabilities()`.
