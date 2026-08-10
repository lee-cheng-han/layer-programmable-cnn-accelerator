# Programmable Bare-Metal Runtime

The Zybo Z7-20 application is the software-managed DDR runtime for the
layer-programmable accelerator. It consumes the same relocatable `.cnn` model
package as the Python executor, validates it before touching hardware, stages
its descriptors through AXI-Lite, and atomically activates the new model.

The application is not tied to a fixed network shape or seven-packet stream.
Any package inside the V1 limits can describe one to eight 1x1/3x3 layers,
runtime channel counts, stride, padding, activation, residual behavior,
per-channel requantization, tensor strides, and DDR workspace placement.

## Execution Flow

1. Validate package size, table bounds, ABI record headers, package CRC32, and
   every layer parameter CRC32 using endian-safe parsing.
2. Write header, layer, tensor, and quantization records into staging metadata.
3. Issue `FINISH_LOAD`, `VALIDATE`, and `ACTIVATE`; confirm model identity and
   generation before execution.
4. Preload two reusable parameter banks, then refill a released bank when a
   later layer reaches the parameter-wait state.
5. Derive each output tile and clipped input receptive field from descriptors.
6. Gather NHWC source bytes from the package-defined DDR workspace and submit
   a versioned `INPUT_TILE` packet through AXI DMA.
7. Arm S2MM first, validate each returned `OUTPUT_TILE` header, then scatter
   its packed INT8 payload into the output tensor allocation.
8. Flush and invalidate cache ranges around DMA ownership transitions and
   terminate safely on DMA, model-lifecycle, packet, or runtime timeouts.

The checked-in bring-up asset is a 4x4 RGB identity package generated from
`examples/models/rgb_identity.json`. It exercises package activation, runtime
parameter loading, packed partial/full beats, tiled DMA, and exact golden
output comparison. Larger applications can supply another compiled package,
image buffer, and workspace without rebuilding the PL bitstream.

The reference app reserves a 256 MiB standalone DDR workspace at
`0x10000000`. Tensor descriptor offsets are relative to that base. Integrators
can move or resize the region to match their linker and memory map.

Expected UART result:

```text
[PASS] programmable package-driven CNN test passed
```

## Artifacts

- Board application: `software/zynq_baremetal/main.c`
- Portable package/tile/packet library: `cnn_programmable_runtime.c/.h`
- Shared ABI and register constants: `cnn_accel_abi.h`
- Generated demonstration: `generated/programmable_demo.h`
- Asset generator: `scripts/generate_programmable_baremetal_demo.py`
- Vitis project generator: `scripts/vitis/create_zynq_baremetal_app.py`

## Verification And Build

The portable library, real compiler-generated package, packet codec, tile
gather/scatter path, and board application syntax compile in open-source CI:

```bash
make baremetal-runtime-test
make runtime-corpus-test
```

`runtime-corpus-test` compiles and bit-accurately executes 24 deterministic
mixed networks in Python, then drives every generated package through the C
descriptor parser, parameter validation, tile planner, NHWC gather/scatter,
packed packet codec, corruption rejection, and exact output-tile coverage.

After the implemented Zybo XSA exists, build the target ELF with:

```bash
make vitis-app
```

Expected target artifact:

```text
build/vitis_ws/cnn_baremetal/build/cnn_baremetal.elf
```
