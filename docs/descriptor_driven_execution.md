# Descriptor-Driven Execution Control

## Scope

Phase 5 adds a generalized execution path that consumes the atomically active
metadata bank. It sequences one to eight V1 convolution descriptors without
rebuilding the bitstream and reuses the existing `single_layer_scheduler` for
both 1x1 and 3x3 layers.

This is a verified pre-integration path. The board-facing AXI-stream system
continues to use the preserved fixed three-layer controller until runtime
parameter banks and the packed DMA protocol are available.

## Execution Path

```text
active metadata bank
  -> decoded layer and tensor view
  -> descriptor_driven_job_controller
  -> active/prefetch parameter-bank request/ready interface
  -> single_layer_scheduler
  -> alternating intermediate feature banks
  -> final signed INT8 tensor
```

The metadata store resolves each layer's input and output tensor IDs against
the active tensor table and exposes their dimensions and channel counts. The
controller advances the layer index only after the current scheduler result is
stored. Intermediate results alternate between two logical feature banks.

## Accepted Runtime Behavior

- one to eight `CONV2D` layers
- 1x1 or 3x3 kernels
- stride 1 or 2
- symmetric per-edge padding 0 or 1
- dilation fixed at 1
- one to `MAX_CIN` input channels and one to `MAX_COUT` output channels
- optional bias and ReLU
- optional final post-quantization residual add or subtract
- temporary power-of-two shift quantization supplied with each parameter set

Before requesting parameters, the controller rejects inactive models,
unsupported operations, invalid geometry, broken tensor chains, incorrect
final-layer flags, and incompatible residual tensors. Residual arithmetic is
signed INT8 plus or minus signed INT8 with saturation to signed INT8.

## Parameter Boundary

`parameter_request` identifies the current layer through `active_layer`.
Phase 6 now resolves that request against two valid, layer-tagged parameter
banks. The selected bank holds weights, bias, and compatibility quantization
controls stable until `parameter_release`. Parameter wait cycles naturally
stall execution, allowing software or a future DMA prefetch engine to refill
the other bank. See [runtime_parameter_banks.md](runtime_parameter_banks.md).

Full per-output-channel multiplier/shift requantization remains the Phase 9
runtime postprocessing milestone.

## Verification

Run the simulator-independent test with:

```bash
make descriptor-test
```

`tb_descriptor_driven_job_controller` loads metadata through the real staging
lifecycle, validates and activates it, and then checks:

- a four-layer mixed 1x1/3x3 network with bias, shift quantization, residual
  add, and parameter backpressure
- an eight-layer identity network at the V1 layer-count limit
- launch rejection without an active model
- geometry rejection before any parameter request
