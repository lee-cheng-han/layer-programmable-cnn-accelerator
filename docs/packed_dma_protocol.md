# Packed DMA Protocol V1

## Scope

The programmable runtime uses a versioned 32-bit AXI-Stream packet format for
activation tiles, layer parameters, and output tiles. The protocol RTL is
implemented and verified independently of the preserved fixed-network board
wrapper. Phase 8 will connect it to DDR-backed tiled execution in the Zybo
block design.

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

Run:

```bash
make packed-dma-test
make packed-dma-runtime-test
make packed-dma-writer-test
```

The tests cover partial final beats, lane order, input/output backpressure,
metadata, parameter CRC completion, semantic rejection, malformed-packet
abort, and successful recovery.
