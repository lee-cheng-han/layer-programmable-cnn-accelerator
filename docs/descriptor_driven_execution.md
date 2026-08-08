# Descriptor-Driven Execution Control

## Scope

Phase 5 adds a generalized execution path that consumes the atomically active
metadata bank. It sequences one to eight V1 convolution descriptors without
rebuilding the bitstream and reuses the existing `single_layer_scheduler` for
both 1x1 and 3x3 layers.

The same active descriptor view now drives the integrated packed-DMA tiled
runtime selected by the production Zybo block design. The array-backed path is
retained as focused controller regression coverage.

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
- per-output-channel signed multiplier/shift requantization
- round-half-to-even, signed INT8 zero point, and signed INT8 saturation

Before requesting parameters, the controller rejects inactive models,
unsupported operations, invalid geometry, broken tensor chains, incorrect
final-layer flags, and incompatible residual tensors. Residual arithmetic is
signed INT8 plus or minus signed INT8 with saturation to signed INT8.

## Parameter Boundary

`parameter_request` identifies the current layer through `active_layer`.
Phase 6 resolves that request against two valid, layer-tagged parameter banks.
The selected bank holds weights and bias stable until `parameter_release`;
the active metadata store supplies the layer's per-channel quantization
descriptor. Parameter wait cycles naturally
stall execution, allowing software or a future DMA prefetch engine to refill
the other bank. See [runtime_parameter_banks.md](runtime_parameter_banks.md).

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
