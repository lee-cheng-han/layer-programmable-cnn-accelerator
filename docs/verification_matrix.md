# Verification Matrix

## Summary

| Level | Test / artifact | Status | Notes |
|---|---|---|---|
| Source hygiene | Python syntax compile | Passing | `python3 -m py_compile` over active scripts and models |
| Source hygiene | shell syntax check | Passing | `bash -n` over active shell scripts |
| model | `tests/test_image2image_int8.py` | Passing | bit-accurate Python integer model coverage |
| default parameters | Gaussian impulse-response test | Passing | all 16 hidden channels used; residual output matches the expected 3x3 low-pass kernel |
| golden generation | `make baremetal-headers` | Passing | writes deterministic tensors and C DMA packet header |
| compute RTL | `tb_parallel_mac_array` | Covered | PC x PK signed INT8 MAC datapath |
| post-processing RTL | `tb_parallel_requantizer` | Covered | per-channel multiply/shift, round-half-to-even ties, lane masks, and signed saturation |
| compute RTL | `tb_tiled_conv1x1_engine` | Covered | array-backed and banked-scratchpad-backed 1x1 operand paths |
| compute RTL | `tb_tiled_conv3x3_engine` | Covered | array-backed and banked-scratchpad-backed 3x3 operand paths |
| tensor RTL | `tb_tensor_address_gen` | Covered | stride, padding, and valid/invalid address behavior |
| tensor RTL | `tb_banked_scratchpads` | Covered | one-cycle replicated-bank activation/weight scratchpad reads |
| runtime metadata RTL | `tb_model_metadata_store` | Covered | dual-bank loading, commit validation, atomic activation, failed replacement isolation, and busy rejection |
| runtime controller RTL | `tb_descriptor_driven_job_controller` | Covered | active metadata decode, mixed 1x1/3x3 execution, parameter stalls, residual output, eight-layer limit, and negative launch/geometry cases |
| runtime parameter RTL | `tb_runtime_parameter_banks` | Covered | two-bank loading, exact lengths, ABI CRC32, ownership, overlap, scratchpad reads, and failure isolation |
| programmable engine RTL | `tb_programmable_job_engine` | Covered | eight descriptor-driven layers execute while two physical parameter banks are recycled and prefetched |
| scheduler RTL | `tb_single_layer_scheduler` | Covered | full-image array-backed and banked-scratchpad-backed scheduler paths |
| controller RTL | `tb_full_network_golden_flow` | Covered | full 3-layer denoising controller against Python golden tensors |
| stream RTL | `tb_stream_loaded_full_network_golden_flow` | Covered | packet-loaded full network with output backpressure |
| AXI stream RTL | `tb_axi_stream_full_network_golden_flow` | Covered | seven-packet AXI job, malformed packet cases, repeated starts, and output compare |
| implementation | `make full-zybo-z7-flow` | Passing | Zynq block design, bitstream, and XSA generated at 125 MHz |
| software | `make vitis-app` | Passing | golden tensor AXI DMA app and FSBL build from XSA |
| boot package | `make boot-image` | Passing | packages `build/BOOT.BIN` |
| Board | Zybo Z7-20 UART PASS | Pending | requires physical board |

## Feature Coverage

| Feature | Current confidence | Evidence |
|---|---|---|
| INT8 arithmetic | High | Python model tests and RTL MAC/engine tests |
| 1x1 convolution | High | tiled engine tests and scheduler tests |
| 3x3 convolution | High | address generator, tiled engine, scheduler, and full-network golden tests |
| runtime channel tails | High | directed PC/PK tail cases; V1 intentionally uses no special RGB channel packing |
| bias, ReLU, quantization, saturation | High | Python model and parallel requantizer RTL tests cover per-channel scales, ties, and clipping |
| residual numeric domain | High | post-requantization signed INT8 add/subtract with signed INT8 saturation |
| bandwidth feasibility | Analytical | worked 1024x1024 3x3 and 1x1 budgets in `docs/bandwidth_budget.md` |
| stream-loaded activations/weights/biases | High | stream-loaded full-network golden flow |
| seven-packet AXI tensor job | High | AXI stream full-network golden flow |
| output backpressure | High | stream-loaded and AXI stream golden flows |
| AXI-Lite control/status/performance registers | High pre-board | integrated system wrapper and Vitis app build against exported XSA |
| runtime metadata lifecycle | High pre-board | standalone lifecycle test plus complete AXI-Lite metadata load and activation |
| descriptor-driven execution | High pre-integration | active-bank four-layer golden flow, eight-layer boundary flow, and negative tests under Verilator CI |
| reusable runtime parameters | High pre-integration | bank-level negative tests plus integrated eight-layer scratchpad-backed execution |
| Zynq block design integration | High pre-board | bitstream and XSA generated at 125 MHz |
| bare-metal DMA integration | High pre-board | Vitis app and BOOT.BIN build from XSA |
| real hardware behavior | Pending | board not yet available |

## Main Regression Commands

```bash
make model-test
make descriptor-test
make parameter-bank-test
make programmable-engine-test
make golden-test
make unit
make regression
make full-zybo-z7-flow
make vitis-app
make boot-image
```

## Remaining Evidence For 10/10 Hardware Validation

- Capture UART output showing `[PASS] image-to-image DMA golden test passed`.
- Record measured DMA/ transfer cycles and usec from the same UART run.
- Save a board setup photo or screenshot under `docs/assets/`.
- Update `docs/performance_results.md` with measured board latency/throughput.
