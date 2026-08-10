# Verification Plan

## Verification Scope

The design is verified at multiple levels:

1. Python bit-accurate model tests
2. RTL unit tests
3. Full-network golden tensor RTL tests
4. Packetized AXI-stream system tests
5. AXI-Lite register and performance-counter tests
6. UVM agents, register model, scoreboard, functional coverage, and recovery tests
7. Vivado synthesis and implementation checks
8. Vitis bare-metal app build validation
9. Planned board-level hardware test on Zybo Z7-20

## Verification Goals

| Area | Goal |
|---|---|
| Model correctness | Validate signed INT8/INT32 image-to-image arithmetic |
| RTL correctness | Validate compute, scratchpad, scheduler, and stream behavior |
| Packet protocol | Verify packet order, length, headers, TLAST, and error reporting |
| AXI-Lite protocol | Verify register reads/writes, command pulses, status, and counters |
| UVM system verification | Verify reusable transaction agents, RAL access, packet scoreboarding, constrained scenarios, recovery, and functional coverage |
| Zynq integration | Verify PS, AXI DMA, AXI-Lite, AXI-Stream, reset, and clock connectivity |
| Build reproducibility | Verify complete scripted flow from RTL to XSA/ELF/BOOT.BIN |
| Timing | Ensure implemented design meets 125 MHz |

## RTL Verification

Expected RTL coverage includes:

- reset and clear behavior
- tensor address generation
- tail masks for non-divisible channel tiles
- tiled 1x1 and 3x3 compute engines
- banked activation and weight scratchpad reads
- activation, bias, and weight load streams
- output stream ordering and `last`
- multi-layer scheduler sequencing
- parameter prefetch overlap
- residual and non-residual output modes
- per-output-channel multiplier/shift requantization
- positive and negative round-half-to-even ties
- positive and negative INT8 clipping with saturation-event masks
- INT8 residual add/subtract overflow saturation
- packet router malformed-input errors
- dual-bank metadata loading, record commits, validation, and atomic activation
- failed staging-model isolation and busy activation/retirement rejection
- active-bank descriptor decode and one-to-eight-layer execution sequencing
- descriptor geometry, tensor-chain, operation, and residual compatibility rejection
- temporary parameter-provider backpressure between runtime layers
- exact parameter length and CRC32 validation before bank visibility
- layer-tagged parameter acquire/release and active/prefetch overlap
- eight-layer execution while recycling two scratchpad-backed parameter banks
- output backpressure
- per-layer, DMA-stall, and saturation performance counter snapshots

## UVM Verification

The production system top has a UVM 1.2 environment with active AXI-Lite and
AXI-Stream ingress agents, a randomized-ready egress agent, packet monitors,
transaction scoreboard, functional coverage subscribers, virtual sequencer,
and register block/adapter. Implemented tests cover register access, complete
model lifecycle and execution, malformed packet recovery, and active-model
preservation. See [uvm_verification.md](uvm_verification.md).

```bash
make uvm-compile
make uvm-smoke
make uvm-regression
```

V1 uses ordinary PC/PK channel-tail masks. The first RGB layer is intentionally
not channel-packed; verification therefore covers the explicit 3-channel tail
at the configured input parallelism as well as full-width middle layers.

## Build Verification

Primary hardware/software build flow:

```bash
make full-preboard-proof
```

Equivalent important substeps:

```bash
make regression
make full-zybo-z7-flow
make boot-image
make flow-report
```

Passing criteria:

- Python model tests pass
- golden RTL tests pass
- unit RTL tests pass
- Vivado project is generated
- block design is valid
- bitstream is generated
- timing is met at 125 MHz
- XSA is exported
- Vitis bare-metal ELF is generated
- `build/BOOT.BIN` is packaged

## Current Status

| Verification Item | Status |
|---|---|
| Python model tests | Passing |
| golden RTL tests | Passing |
| unit RTL tests | Passing |
| descriptor-driven controller test | Passing |
| runtime parameter-bank tests | Passing |
| UVM source compile and complete DUT elaboration | Passing |
| UVM executable tests | Pending compatible simulator runtime |
| Zynq block design | Passing |
| implementation | Passing |
| Timing | Met at 125 MHz |
| XSA export | Passing |
| Vitis app build | Passing |
| BOOT.BIN | Passing |
| Board execution | Pending hardware |

## Board-Level Test Plan

The board-level test will run the generated ELF on the Zynq ARM processor after programming the FPGA bitstream.

Expected sequence:

1. Program FPGA with the `system_wrapper.bit`.
2. Run `cnn_baremetal.elf` on ARM Cortex-A9.
3. Open UART terminal.
4. Confirm startup banner.
5. Confirm register version.
6. Confirm residual and non-residual golden DMA jobs pass.
7. Archive printed performance counters.

Expected UART banner:

```text
Zynq Image-to-Image CNN DMA Test
```

Expected final line:

```text
[PASS] image-to-image DMA golden test passed
```
