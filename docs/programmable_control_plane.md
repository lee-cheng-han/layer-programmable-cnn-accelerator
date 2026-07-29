# Programmable AXI-Lite Control Plane

## Scope

`cnn_programmable_system_top` combines the programmable AXI-Lite slave with
`cnn_programmable_runtime_top`. Software can stage metadata, validate and
activate a model, select the descriptor used to validate parameter packets,
launch a job, and inspect tensor/tile progress without RTL sideband controls.

The register interface version is `0x00050000`. All registers are 32-bit,
little-endian, and naturally aligned.

## Register Map

| Offset | Name | Access | Description |
|---:|---|---|---|
| `0x000` | `CONTROL` | W | bit 0 start, bit 1 clear |
| `0x004` | `STATUS` | R | busy, done, error, layer-done, active-model, active-layer, and parameter-bank state |
| `0x008` | `IRQ_STATUS` | RW1C | bit 0 done, bit 1 error |
| `0x00C` | `IRQ_ENABLE` | RW | done/error interrupt enables |
| `0x010` | `JOB_ID` | RW | expected packed-packet job ID |
| `0x014` | `PARAMETER_LAYER` | RW | active descriptor used for an idle parameter load |
| `0x018` | `MODEL_COMMAND` | W | begin, finish, validate, activate, retire, and clear-error pulses |
| `0x01C` | `MODEL_STATUS` | R | staging state, active-valid, and lifecycle error |
| `0x020` | `ACTIVE_MODEL_ID` | R | atomically active model identity |
| `0x024` | `ACTIVE_GENERATION` | R | active model generation |
| `0x028` | `ACTIVE_LAYER_COUNT` | R | active descriptor count |
| `0x02C` | `METADATA_ADDRESS` | RW | kind, record index, and word index |
| `0x030` | `METADATA_DATA` | RW | selected metadata word |
| `0x034` | `METADATA_COMMIT` | W | commit selected record |
| `0x038` | `MODEL_ERROR` | R/W | lifecycle error; writing bit 0 clears it |
| `0x03C` | `RUNTIME_ERROR` | R | failing layer and runtime error code |
| `0x040` | `ACTIVE_TENSORS` | R | output and input tensor IDs |
| `0x044` | `CURRENT_TILE` | R | tile Y and X coordinates |
| `0x048` | `COMPLETED_LAYERS` | R | completed layer count |
| `0x04C` | `COMPLETED_TILES` | R | completed tiles in the active layer |
| `0x050` | `PACKET_ERRORS` | R | packed parser error count |
| `0x054` | `PARAMETER_BANKS` | R | valid reusable parameter banks |
| `0x058`-`0x05C` | `INPUT_DDR` | R | active input tensor DDR offset |
| `0x060`-`0x064` | `OUTPUT_DDR` | R | active output tensor DDR offset |
| `0x0FC` | `VERSION` | R | `0x00050000` |

`METADATA_ADDRESS` uses bits `[1:0]` for record kind, `[7:2]` for record
index, and `[13:8]` for word index. This matches the existing metadata-store
aperture.

## AXI-Stream Boundary

The programmable block-design wrapper declares 32-bit ingress and egress AXI
streams with both `TKEEP` and `TLAST`. `TKEEP` is mandatory because packed INT8
payloads may end with one, two, or three valid bytes. The fixed-network wrapper
does not expose `TKEEP` and cannot carry this protocol without adaptation.

## Verification

`tb_programmable_system_top` performs every metadata write and model command
over AXI-Lite, loads a CRC-checked weight packet over AXI-Stream, starts the
job through `CONTROL`, sends two input tiles, checks packed output packets, and
reads model identity, tensor context, tile coordinates, DDR offsets, packet
errors, and completion counters back through AXI-Lite.

Run:

```bash
make programmable-system-test
```
