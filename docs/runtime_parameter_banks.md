# Runtime Parameter Banks

## Scope

Phase 6 replaces the descriptor controller's test-only parameter arrays with
two reusable, layer-tagged parameter banks. One bank may feed compute while the
other is loaded for a later layer. A completed layer releases its bank
atomically so that the loader can reuse it without overwriting parameters still
owned by compute.

The board-facing fixed-network path remains unchanged. The programmable path is
integrated in `cnn_programmable_job_engine` and verified before the packed DMA
protocol is connected in Phase 7.

## Physical Organization

Each logical bank contains:

- one independent weight scratchpad with a 4,096-byte architectural capacity
- one 256-byte postprocessing allocation
- signed INT32 bias values for up to 16 output channels
- temporary shift-quantization controls
- a valid bit and layer ID ownership tag

The maximum V1 payload remains 2,304 weight bytes and 64 bias bytes. The
remaining architectural capacity is reserved for natural alignment and the
full per-channel postprocessing entries added in Phase 9.

## Loading Contract

The Phase 6 loader is intentionally narrower than the future DMA protocol:

- weights arrive as signed INT8 bytes in OIHW order
- biases arrive as signed INT32 words
- bias words enter the checksum in little-endian byte order
- `weight_size` must equal `Cout * Cin * kernel_height * kernel_width`
- `bias_size` must equal `Cout * 4` when bias is enabled, otherwise zero
- sizes must fit their physical bank capacities
- CRC32 covers exactly the weight bytes followed by the bias bytes

CRC32 uses the reflected polynomial `0xEDB88320`, initial value
`0xFFFFFFFF`, and final XOR `0xFFFFFFFF`, matching Python `zlib.crc32` and the
V1 package ABI. A length or checksum failure leaves the selected bank invalid.

Phase 7 replaces these temporary byte/word loader signals with 32-bit packed
AXI-stream packets, `TKEEP`, `TLAST`, exact payload lengths, and recovery rules.

## Ownership

```text
FREE
  -> load_start
LOADING
  -> exact lengths and CRC pass
VALID(layer_id)
  -> matching parameter_request
COMPUTE_OWNED(layer_id)
  -> parameter_release
FREE
```

`parameter_ready` is asserted only when a valid bank's layer tag matches the
controller's requested layer and no bank is already compute-owned. Bias,
quantization controls, and scratchpad read selection remain stable until the
controller releases ownership.

## Verification

```bash
make parameter-bank-test
make programmable-engine-test
```

`tb_runtime_parameter_banks` covers two-bank loading, layer matching,
bias/quantization retention, scratchpad reads, compute ownership, overlapped
prefetch, CRC rejection, and exact-length rejection.

`tb_programmable_job_engine` executes an eight-layer descriptor-driven network
through only two physical banks. It recycles each released bank, observes
loading while the other bank computes, and checks the final tensor result.

