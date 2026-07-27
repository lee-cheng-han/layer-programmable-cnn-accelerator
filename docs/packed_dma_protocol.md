# Packed DMA Protocol V1

## Scope

The programmable runtime uses a versioned 32-bit AXI-Stream packet format for
activation tiles, layer parameters, and output tiles. The protocol RTL is
implemented and verified through the programmable tiled-layer runtime. The
preserved fixed-network Zybo block design still uses its original packet path;
board integration of the programmable runtime remains a separate step.

Every packet consists of eight full header beats followed by an exact-length
payload:

```text
header[0..7], payload[0..payload_length-1]
```

Within each 32-bit payload beat, byte lane 0 is the earliest tensor element,
followed by lanes 1, 2, and 3. Multi-byte integer fields and signed INT32 bias
values are little-endian.

## Header

All header beats use `TKEEP=0b1111` and `TLAST=0`.

| Word | Bits | Field |
|---:|---|---|
| 0 | 31:0 | Magic `0x31504E43` (`CNP1` in little-endian memory order) |
| 1 | 7:0 | Protocol version, currently `1` |
| 1 | 15:8 | Header words, currently `8` |
| 1 | 23:16 | Packet type |
| 1 | 31:24 | Flags, zero in V1 |
| 2 | 31:0 | Job ID |
| 3 | 15:0 | Tensor ID |
| 3 | 31:16 | Layer ID |
| 4 | 15:0 | Tile X coordinate |
| 4 | 31:16 | Tile Y coordinate |
| 5 | 15:0 | Tile width |
| 5 | 31:16 | Tile height |
| 6 | 15:0 | Channel offset |
| 6 | 31:16 | Channel count |
| 7 | 31:0 | Exact payload length in bytes |

Packet types are:

| Value | Name | Payload |
|---:|---|---|
| 1 | `INPUT_TILE` | Packed signed INT8 activation bytes |
| 2 | `LAYER_WEIGHTS` | Packed signed INT8 weights in OIHW order |
| 3 | `LAYER_BIASES` | One signed INT32 bias per 32-bit beat |
| 4 | `OUTPUT_TILE` | Packed signed INT8 output bytes |

## Tile Coordinate Contract

For both `INPUT_TILE` and `OUTPUT_TILE`, `tile_x`, `tile_y`, `tile_width`, and
`tile_height` identify a rectangle in the layer's **output** tensor. This keeps
the packet coordinates unsigned even when a convolution receptive field begins
above or to the left of the input tensor.

An `INPUT_TILE` payload contains the clipped input receptive field needed for
that output rectangle. Its elements are NHWC ordered over:

```text
source_y .. source_y + source_height - 1
source_x .. source_x + source_width - 1
channel_offset .. channel_offset + channel_count - 1
```

The runtime derives `source_x`, `source_y`, and the source dimensions from the
active layer descriptor. Out-of-range halo positions are not transferred.
`halo_tile_load_controller` clears the complete local receptive-field buffer,
then places the clipped payload at its derived local X/Y offset. Untransferred
top, left, right, and bottom halo cells therefore read as signed INT8 zero.

V1 tiled execution currently requires one complete input-channel range per
tile: `channel_offset=0` and `channel_count=Cin`. Its exact input byte count is:

```text
source_width * source_height * Cin
```

An `OUTPUT_TILE` payload is ordinary NHWC output data for the header rectangle,
with exact length:

```text
tile_width * tile_height * Cout
```

## Payload Framing

`payload_length` is authoritative. Non-final payload beats use
`TKEEP=0b1111`. The final beat uses:

| Remaining bytes | `TKEEP` |
|---:|---:|
| 1 | `0001` |
| 2 | `0011` |
| 3 | `0111` |
| 4 | `1111` |

Only contiguous low byte lanes are legal. `TLAST` is asserted exactly on the
final payload beat. Zero-length packets are invalid.

Weights are serialized lane 0 first into the byte-wide runtime parameter-bank
loader. Bias packets remain naturally word-aligned. A layer with bias enabled
uses one `LAYER_WEIGHTS` packet immediately followed by its matching
`LAYER_BIASES` packet. Layer ID and exact payload length must match the active
parameter-load configuration before either payload is accepted.

## Flow Control

Every beat transfers only when `TVALID && TREADY` is true on a rising edge.
The source must hold `TDATA`, `TKEEP`, and `TLAST` stable while stalled.

The parser may accept the first seven header beats while a prior operation is
finishing. It backpressures the eighth beat until the destination accepts the
complete packet context. Payload backpressure then propagates from activation
storage or the parameter banks to AXI Stream.

The output writer accepts signed INT8 bytes, packs four bytes per beat, emits
the same eight-word header with packet type `OUTPUT_TILE`, and derives final
`TKEEP` and `TLAST` from the exact byte length.

## Errors And Recovery

The parser reports malformed header keep/last, magic, version, header size,
type, flags, payload length, payload keep, and payload last conditions. If the
malformed beat does not terminate the packet, the parser drains input until
`TLAST` and then accepts a new header without a global reset.

Semantic routing errors include unexpected packet order, mismatched layer ID,
mismatched parameter length, and unavailable parameter configuration. A parser
error during parameter loading aborts and invalidates the selected bank.
Previously validated banks remain isolated.

## RTL And Verification

| Module | Responsibility |
|---|---|
| `packed_dma_packet_parser` | Header validation, exact byte accounting, framing checks, and recovery |
| `packed_dma_runtime_router` | Activation routing, weight serialization, bias forwarding, and parameter abort |
| `packed_dma_packet_writer` | Output header generation and INT8 byte packing |
| `spatial_tile_planner` | Output-tile enumeration and clipped receptive-field/halo geometry |
| `halo_tile_load_controller` | Tile-context validation, zero fill, packed-byte placement, and scratchpad write flush |
| `cnn_tiled_layer_runtime` | Parameter acquisition, tile ingress, local compute, and packed tile egress |

Run:

```bash
make packed-dma-test
make packed-dma-runtime-test
make packed-dma-writer-test
make tile-test
```

The tests cover partial final beats, lane order, input/output backpressure,
metadata, parameter CRC completion, semantic rejection, malformed-packet
abort, halo and boundary geometry, malformed tile metadata, end-to-end
multi-tile golden output, output backpressure, and successful recovery.
