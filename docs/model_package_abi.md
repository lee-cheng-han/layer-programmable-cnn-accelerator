# V1 Model Package ABI

## Status and Scope

This document is the normative binary contract for the layer-programmable V1
accelerator. The record sizes, byte offsets, enum values, numeric behavior, and
rejection rules are frozen at ABI version 1.

The checked-in board design still executes its fixed three-layer descriptor
path, but it now includes dual-bank runtime metadata storage and atomic model
activation. Descriptor-driven execution, packed DMA packets, DDR-backed tiling,
and autonomous parameter fetching remain later milestones and must consume this
contract without changing it.

The canonical executable definition is
[`models/cnn_abi.py`](../models/cnn_abi.py). Matching constants for bare-metal
software and RTL are in
[`cnn_accel_abi.h`](../software/zynq_baremetal/cnn_accel_abi.h) and
[`cnn_accel_abi_pkg.sv`](../rtl/include/cnn_accel_abi_pkg.sv).

## V1 Capability Envelope

| Property | V1 limit |
|---|---:|
| Layers | 1-8 |
| Tensors / quantization records | 32 / 32, with 1-16 channel parameters each |
| Input channels per layer | 1-16 |
| Output channels per layer | 1-16 |
| Kernel | square 1x1 or 3x3 |
| Stride | 1 or 2 independently per axis |
| Padding | 0 or 1 independently per edge |
| Dilation | fixed at 1 |
| Tensor width / height | 1-1024 independently |
| Tensor layout | NHWC |
| Activations and weights | signed INT8 |
| Bias and accumulation | signed INT32 |
| Output | saturated signed INT8 |
| Activation | none or ReLU |
| Residual | none, post-quant add, or post-quant subtract |
| Weight bytes per layer | at most 2,304 |
| Bias bytes per layer | at most 64 |
| Physical active/prefetch banks | two 4,096-byte weight banks and two 256-byte postprocessing banks |

Dimensions up to 1024x1024 are a functional maximum enabled by later spatial
tiling, not a real-time performance claim. The primary benchmark is 224x224,
512x512 is the substantial image-processing demonstration, and 1024x1024 is a
stress test.

## Encoding Rules

- All integers are little-endian.
- Records use fixed sizes and explicit byte offsets. Native C struct layout and
  C bitfields are not part of the ABI.
- Package tables and parameter data begin at 64-byte-aligned offsets.
- Every record includes `descriptor_version` and `descriptor_size` as its first
  two unsigned 16-bit fields.
- All reserved fields and bytes are zero. Readers reject nonzero reserved data.
- Writers emit only defined flag bits. Readers reject unknown flag bits.
- IDs and package-relative offsets are unsigned. `0xFFFF` means no residual
  tensor where that sentinel is permitted.
- Weight bytes use OIHW order. Tensor data uses NHWC order.
- Biases are signed little-endian INT32 values.

## Package Layout

```text
0                         128 bytes
+---------------------------+
| model package header      |
+---------------------------+ 64-byte aligned
| layer descriptors         | layer_count x 128
+---------------------------+ 64-byte aligned
| tensor descriptors        | tensor_count x 64
+---------------------------+ 64-byte aligned
| quantization descriptors  | quantization_count x 192
+---------------------------+ 64-byte aligned
| optional alignment        |
+---------------------------+ 64-byte aligned
| weights and biases        |
+---------------------------+ package_size
```

Offsets in the header and layer descriptors are relative to byte zero of this
package. They are not CPU virtual addresses, physical DDR addresses, or PL bus
addresses. Software may relocate the complete package without rewriting them.

## Model Header

The model header is 128 bytes.

| Offset | Size | Field | V1 rule |
|---:|---:|---|---|
| `0x00` | 4 | `magic` | bytes `CNN1`, integer `0x314E4E43` |
| `0x04` | 2 | `descriptor_version` | 1 |
| `0x06` | 2 | `descriptor_size` | 128 |
| `0x08` | 4 | `package_size` | complete package byte count |
| `0x0C` | 4 | `flags` | zero |
| `0x10` | 4 | `model_id` | software-assigned stable identity |
| `0x14` | 4 | `model_generation_id` | monotonically managed generation |
| `0x18` | 2 | `layer_count` | 1-8 |
| `0x1A` | 2 | `tensor_count` | 2-32 |
| `0x1C` | 2 | `quantization_count` | 1-32 |
| `0x1E` | 2 | reserved | zero |
| `0x20` | 4 | `layer_table_offset` | 64-byte aligned |
| `0x24` | 4 | `tensor_table_offset` | 64-byte aligned |
| `0x28` | 4 | `quantization_table_offset` | 64-byte aligned |
| `0x2C` | 4 | `parameter_data_offset` | 64-byte aligned |
| `0x30` | 4 | `parameter_data_size` | exact parameter-region bytes |
| `0x34` | 4 | `workspace_size` | required DDR tensor workspace bytes |
| `0x38` | 4 | `package_crc32` | package corruption check |
| `0x3C` | 2 | `input_tensor_id` | entry tensor |
| `0x3E` | 2 | `output_tensor_id` | result tensor |
| `0x40` | 32 | `package_sha256` | software/package identity digest |
| `0x60` | 32 | reserved | zero |

The SHA-256 digest is computed over the complete `package_size` bytes with
`package_crc32` at `0x38..0x3B` and `package_sha256` at `0x40..0x5F`
temporarily set to zero. After inserting that digest, CRC32 is computed over
the complete package with only `package_crc32` set to zero. CRC32 uses the standard reflected polynomial
`0xEDB88320`, initial value `0xFFFFFFFF`, and final XOR `0xFFFFFFFF` (the
behavior exposed by Python `zlib.crc32`).

## Layer Descriptor

Each layer descriptor is 128 bytes. Descriptor-table order is execution order,
and `layer_id` values are contiguous from zero.

| Offset | Size | Field | V1 rule |
|---:|---:|---|---|
| `0x00` | 2 | `descriptor_version` | 1 |
| `0x02` | 2 | `descriptor_size` | 128 |
| `0x04` | 2 | `layer_id` | execution index |
| `0x06` | 2 | `opcode` | 1 = CONV2D |
| `0x08` | 4 | `flags` | bit 0 bias, bit 1 final layer |
| `0x0C` | 2 | `input_tensor_id` | tensor-table reference |
| `0x0E` | 2 | `output_tensor_id` | tensor-table reference |
| `0x10` | 2 | `residual_tensor_id` | reference or `0xFFFF` |
| `0x12` | 2 | `quantization_id` | quantization-table reference |
| `0x14` | 4 | `weight_offset` | package-relative, 64-byte aligned |
| `0x18` | 4 | `weight_size` | exact OIHW INT8 byte count |
| `0x1C` | 4 | `bias_offset` | package-relative, 4-byte aligned |
| `0x20` | 4 | `bias_size` | exact INT32 byte count, or zero |
| `0x24` | 4 | `parameter_crc32` | weights followed by biases |
| `0x28` | 1 each | `kernel_height`, `kernel_width` | both 1 or both 3 |
| `0x2A` | 1 each | `stride_y`, `stride_x` | each 1 or 2 |
| `0x2C` | 1 each | top, bottom, left, right padding | each 0 or 1 |
| `0x30` | 1 each | `dilation_y`, `dilation_x` | both 1 |
| `0x32` | 1 | `activation` | 0 none, 1 ReLU |
| `0x33` | 1 | `residual_mode` | 0 none, 1 add, 2 subtract |
| `0x34` | 2 | `tile_height_hint` | zero lets hardware choose |
| `0x36` | 2 | `tile_width_hint` | zero lets hardware choose |
| `0x38` | 72 | reserved | zero |

The tensor table is authoritative for dimensions, channels, strides, element
type, and tensor quantization. Layer records do not duplicate those fields.

`parameter_crc32` covers exactly `weight_size` bytes followed immediately in
the CRC stream by exactly `bias_size` bytes. Alignment gaps and unused physical
bank capacity are excluded.

## Tensor Descriptor

Each tensor descriptor is 64 bytes.

| Offset | Size | Field | V1 rule |
|---:|---:|---|---|
| `0x00` | 2 | `descriptor_version` | 1 |
| `0x02` | 2 | `descriptor_size` | 64 |
| `0x04` | 2 | `tensor_id` | unique table identity |
| `0x06` | 2 | `flags` | input, output, constant |
| `0x08` | 8 | `ddr_offset` | relative to runtime tensor-workspace base |
| `0x10` | 4 | `allocation_size` | allocated bytes including stride padding |
| `0x14` | 2 | `width` | 1-1024 |
| `0x16` | 2 | `height` | 1-1024 |
| `0x18` | 2 | `channels` | 1-16 |
| `0x1A` | 1 | `element_type` | 1 = signed INT8 |
| `0x1B` | 1 | `layout` | 1 = NHWC |
| `0x1C` | 2 | `quantization_id` | quantization-table reference |
| `0x1E` | 2 | `lifetime_begin` | first layer index using allocation |
| `0x20` | 2 | `lifetime_end` | last layer index using allocation |
| `0x22` | 2 | reserved | zero |
| `0x24` | 4 | `row_stride` | bytes between adjacent rows |
| `0x28` | 4 | `pixel_stride` | bytes between adjacent pixels |
| `0x2C` | 4 | `channel_stride` | exactly 1 in V1 |
| `0x30` | 16 | reserved | zero |

The runtime address of element `(y, x, c)` is:

```text
tensor_workspace_base + ddr_offset
  + y * row_stride
  + x * pixel_stride
  + c * channel_stride
```

The model compiler owns lifetime analysis and may assign overlapping DDR
allocations only when tensor lifetimes do not overlap.

## Quantization Descriptor

Each quantization descriptor is 192 bytes and contains one fixed-point
requantization entry per output channel. Its size is a multiple of the 64-byte
record alignment.

| Offset | Size | Field | V1 rule |
|---:|---:|---|---|
| `0x00` | 2 | `descriptor_version` | 1 |
| `0x02` | 2 | `descriptor_size` | 192 |
| `0x04` | 2 | `quantization_id` | unique table identity |
| `0x06` | 2 | `flags` | zero |
| `0x08` | 2 | `channel_count` | 1-16 and equal to the tensor channel count |
| `0x0A` | 1 | `rounding_mode` | 1 = round half to even |
| `0x0B` | 1 | `output_zero_point` | exactly zero for symmetric V1 INT8 |
| `0x0C` | 52 | reserved | zero |
| `0x40` | 128 | channel entries | sixteen 8-byte entries |

Each channel entry contains a positive signed INT32 `quant_multiplier` at
offset zero, a `quant_shift` from 0 through 62 at offset four, and three zero
reserved bytes. Entries at or above `channel_count` are all zero.

Training-time input, weight, and output scales are converted by the compiler
into the integer multiplier and shift for each output channel. The accelerator
does not use floating-point arithmetic. For output channel `c`:

```text
biased = accumulator + bias[c]
activated = relu_enable ? max(biased, 0) : biased
product = activated * quant_multiplier[c]
rounded = round_half_to_even(product / 2^quant_shift[c])
predicted_int8 = clamp(rounded, -128, 127)
```

Round-half-to-even chooses the nearest integer and resolves an exact half-way
case to the even integer. The rule is symmetric for positive and negative
values and bit-identical in the Python executor and RTL requantizer.

During parameter loading, each bias and channel quantization entry becomes one
16-byte postprocessing-bank entry: INT32 bias, INT32 multiplier, UINT8 shift,
INT8 zero point, UINT8 rounding mode, UINT8 flags, and four reserved bytes.
Sixteen entries consume exactly 256 bytes.

Post-quant residual add/subtract sign-extends both the requantized convolution
INT8 value and residual INT8 value, performs the selected operation, and
saturates to INT8 again. The residual and output tensors must have identical
dimensions, element types, and `quantization_id`. Accumulator-domain residual
arithmetic is not part of V1.

## Physical Parameter Banks

V1 uses two independent 4,096-byte weight banks, not one bank divided into two
halves. Either bank can hold the maximum 2,304-byte `16x16x3x3` weight payload
while the other is filled. Two independent 256-byte postprocessing banks hold
all bias and requantization entries for one layer each.

## Validation and Activation

Software and hardware validate a complete staging model before activation.
Validation includes record versions/sizes, reserved bits, IDs and references,
table bounds/alignment, tensor geometry and strides, convolution output shape,
parameter lengths and bank capacities, quantization restrictions, residual
compatibility, and checksums.

The implemented metadata lifecycle is:

```text
UNLOADED
  -> LOAD_MODEL -> LOADED_UNVALIDATED
  -> VALIDATE_MODEL -> VALIDATED_STAGING
  -> ACTIVATE_MODEL -> ACTIVE
```

Staging and active metadata are distinct. Failed loading or validation does not
damage the active model. `RUN_IMAGE` accepts only an active, validated model,
and V1 rejects activation while a job is busy. The descriptor-driven runtime
consumes the active metadata view, while the preserved board wrapper still uses
the fixed scheduler. Exact register commands and the validation boundary are specified in
[runtime_model_lifecycle.md](runtime_model_lifecycle.md).

## Packed Wire Protocol

The model-package ABI and AXI-Stream framing remain separately versioned. The
implemented packed DMA protocol carries packet type, tensor ID, tile
coordinates, exact payload length, `TKEEP`, `TLAST`, and malformed-packet
recovery. Bits `7:0` carry the earliest tensor byte, followed by bits `15:8`,
`23:16`, and `31:24`. See
[packed_dma_protocol.md](packed_dma_protocol.md) for the normative wire format.

## Verification

Run the ABI and arithmetic model tests with:

```bash
make model-test
```

The ABI tests cover record sizes, little-endian encoding, round trips, reserved
bytes, unknown flags, CRC order, cross-language constants, valid-model checks,
and representative invalid models.
