# DDR-Backed Tiled Execution

## Implemented Boundary

The programmable runtime now executes descriptor-driven multi-layer jobs as
sequences of packed DMA tiles without allocating a full image in PL memory.
`cnn_tiled_layer_runtime` connects:

```text
spatial_tile_planner
  -> packed INPUT_TILE validation
  -> zero-filled banked activation scratchpad
  -> existing 1x1/3x3 scheduler and reusable weight-bank interface
  -> channel serializer
  -> packed OUTPUT_TILE writer
```

`cnn_tiled_multi_layer_controller` walks one to eight active descriptors,
validates each layer and the inter-layer tensor chain, acquires the matching
reusable parameter bank, and starts the tiled layer runtime. It exposes the
active input/output tensor IDs, DDR layouts, tile coordinates, and progress so
software can gather each requested source rectangle and scatter each output
tile. The current integration remains software/DMA managed; autonomous DDR
fetching is a later optional milestone.

The atomically active metadata view exposes each layer's tile height/width
hints and both tensors' 64-bit DDR offset, allocation size, row stride, pixel
stride, and channel stride. These fields switch banks atomically with the rest
of the validated model. The multi-layer controller consumes that active-view
contract through explicit descriptor ports; direct top-level wiring to the
metadata store remains a board-integration task.

## Geometry

The default output tile is 16x16. A descriptor may request a smaller nonzero
tile up to that limit. Edge tiles are truncated to the remaining output
dimensions.

For an output tile beginning at `(tile_x, tile_y)`:

```text
input_origin_x = tile_x * stride_x - padding_left
input_origin_y = tile_y * stride_y - padding_top

local_input_width  = (tile_width  - 1) * stride_x + kernel_width
local_input_height = (tile_height - 1) * stride_y + kernel_height
```

The source rectangle is the intersection of this local receptive field and the
global input tensor. Negative origins and right/bottom overflow become zero
cells in the local scratchpad. A 16x16 output tile therefore needs at most:

| Operation | Maximum local input |
|---|---:|
| 1x1, stride 1 | 16x16 |
| 3x3, stride 1 | 18x18 |
| 1x1, stride 2 | 31x31 |
| 3x3, stride 2 | 33x33 |

The 33x33 local limit is independent of the V1 functional tensor limit of
1024x1024.

## Validation

The planner rejects unsupported dimensions, channels, kernels, strides, tile
hints, output shapes, and local footprints before issuing a tile. The loader
then validates job, tensor, layer, output-tile coordinates, channel range, and
exact byte length before modifying the local buffer.

The loader stalls payload ingress while clearing the local footprint. It
serializes contiguous low `TKEEP` lanes in lane order, writes NHWC elements to
the derived local coordinates, and includes a flush cycle for the registered
scratchpad write path before compute can start.

The runtime admits exactly one input packet header per latched tile context.
This prevents a back-to-back DMA source from presenting the next tile during
the cycle in which the loader completion pulse returns to the runtime.

## Verification

`tb_spatial_tile_planner` covers top-left and bottom-right halos, partial edge
tiles, stride 2, 1x1 convolution, asymmetric padding, payload lengths, and
invalid output shapes. It also checks every tile from 50 deterministic
randomized configurations spanning mixed kernels, strides, per-edge padding,
channel counts, dimensions, and tile hints against an independent geometry
calculation.

`tb_halo_tile_load_controller` checks zero-filled halo cells and every loaded
scratchpad byte using the real banked activation memory. It also checks early
backpressure and metadata rejection.

`tb_tiled_layer_runtime` executes a multi-tile 1x1 identity layer through real
activation and weight scratchpads, reconstructs packed output packets, and
checks exact values under periodic output backpressure.

`tb_tiled_layer_runtime_3x3_stride2` executes a 5x5 input through a 3x3
center-tap identity kernel at stride 2 and padding 1. It covers four output
tiles with top/left, right, bottom, and bottom-right clipped receptive fields,
then reconstructs the 3x3 global output through the packed output parser under
independent backpressure.

`tb_tiled_multi_layer_controller` runs a two-layer 1x1 identity network through
the real tiled runtime and reusable parameter scratchpad. It verifies packed
tile payloads and tensor IDs across a DDR tensor handoff, then proves that a
mismatched next-layer DDR offset is rejected before that layer starts.

Run:

```bash
make tile-test
```

## Remaining Integration Work

- Connect `cnn_model_metadata_store` directly to
  `cnn_tiled_multi_layer_controller` in the programmable system top.
- Add software scheduling that gathers clipped NHWC source rectangles from
  DDR and scatters output tiles back into DDR tensors.
- Add randomized multi-layer runtime payload/backpressure and malformed-packet
  recovery regressions.
- Integrate the programmable packet router/runtime into the Zybo block design
  and rerun implementation at 125 MHz.
