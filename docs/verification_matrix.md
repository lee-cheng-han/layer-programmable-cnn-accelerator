# Verification Matrix

## Summary

| Level | Test / artifact | Status | Notes |
|---|---|---|---|
| Source hygiene | Python syntax compile | Passing | `python3 -m py_compile` over active scripts and models |
| Source hygiene | shell syntax check | Passing | `bash -n` over active shell scripts |
| model | `tests/test_image2image_int8.py` | Passing | bit-accurate Python integer model coverage |
| default parameters | Gaussian impulse-response test | Passing | all 16 hidden channels used; residual output matches the expected 3x3 low-pass kernel |
| golden generation | `make baremetal-headers` | Passing | writes deterministic tensors and C DMA packet header |
| software runtime corpus | `make runtime-corpus-test` | Passing | 24 seeded packages, 1-8 layers, 108 total layers, and 2,792 tiles cross-check compiler packages against the C ABI, tile, packet, and workspace runtime |
| package-to-RTL numeric flow | `make randomized-package-rtl-test` | Passing | seeded compiler package drives four mixed layers, 26 halo tiles, two-bank parameter recycling, randomized output backpressure, and 268 exact golden packet beats |
| UVM environment | `make uvm-u5` | 23/23 cases pass; functional target closed | Functional coverage is 96.72% against a 95% target; both AXI-Stream interface groups reach 100%. Fresh code scores are unavailable because XSim 2025.2 crashes after creating the merged code database but before emitting HTML; assertion coverage remains unmeasured |
| UVM channel scope | `verification/uvm_signoff.json` | Explicit | Fast randomized regression uses PC=2/PK=2 and 1-2 channels; dedicated parameterized RTL and implementation flows carry the separate 16-channel capacity obligation |
| compute RTL | `tb_parallel_mac_array` | Covered | PC x PK signed INT8 MAC datapath |
| post-processing RTL | `tb_parallel_requantizer` | Covered | per-channel multiply/shift, round-half-to-even ties, lane masks, and signed saturation |
| residual output RTL | `tb_tile_output_serializer_numeric` | Covered | post-quantization INT8 add/subtract, positive/negative saturation, and clipping-event accounting |
| compute RTL | `tb_tiled_conv1x1_engine` | Covered | array-backed and banked-scratchpad-backed 1x1 operand paths |
| compute RTL | `tb_tiled_conv3x3_engine` | Covered | array-backed and banked-scratchpad-backed 3x3 operand paths |
| tensor RTL | `tb_tensor_address_gen` | Covered | stride, padding, and valid/invalid address behavior |
| tensor RTL | `tb_banked_scratchpads` | Covered | one-cycle replicated-bank activation/weight scratchpad reads |
| runtime metadata RTL | `tb_model_metadata_store` | Covered | dual-bank loading, commit validation, atomic activation, failed replacement isolation, and busy rejection |
| runtime controller RTL | `tb_descriptor_driven_job_controller` | Covered | active metadata decode, mixed 1x1/3x3 execution, parameter stalls, residual output, eight-layer limit, and negative launch/geometry cases |
| runtime parameter RTL | `tb_runtime_parameter_banks` | Covered | two-bank loading, exact lengths, ABI CRC32, ownership, overlap, scratchpad reads, and failure isolation |
| programmable engine RTL | `tb_programmable_job_engine` | Covered | eight descriptor-driven layers execute while two physical parameter banks are recycled and prefetched |
| packed DMA parser RTL | `tb_packed_dma_packet_parser` | Covered | versioned headers, exact lengths, partial beats, backpressure, malformed framing, drain, and recovery |
| packed DMA runtime RTL | `tb_packed_dma_runtime_router` | Covered | activation routing, packed weight serialization, bias loading, CRC completion, semantic rejection, abort, and recovery |
| packed DMA output RTL | `tb_packed_dma_packet_writer` | Covered | output headers, four-byte packing, partial final beat, `TKEEP`, `TLAST`, and backpressure |
| scheduler RTL | `tb_single_layer_scheduler` | Covered | full-image array-backed and banked-scratchpad-backed scheduler paths |
| controller RTL | `tb_full_network_golden_flow` | Covered | full 3-layer denoising controller against Python golden tensors |
| stream RTL | `tb_stream_loaded_full_network_golden_flow` | Covered | packet-loaded full network with output backpressure |
| AXI stream RTL | `tb_axi_stream_full_network_golden_flow` | Covered | seven-packet AXI job, malformed packet cases, repeated starts, and output compare |
| implementation | programmable PL OOC | Passing | default and Explore routes close setup and hold at 125 MHz with the complete numeric path |
| implementation | `make full-zybo-z7-flow` | Prior baseline passing | regenerate the Zynq bitstream/XSA after Phase 9 before board use |
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
| bias, ReLU, quantization, saturation | High pre-board | active per-channel multiplier/shift/zero-point descriptors drive both tiled engines; standalone and integrated tests cover ties, tails, clipping, and counter readback |
| residual numeric domain | High pre-board | integrated final-layer residual add/subtract uses two post-requantization signed INT8 operands and saturates to INT8 |
| bandwidth feasibility | Analytical | worked 1024x1024 3x3 and 1x1 budgets in `docs/bandwidth_budget.md` |
| stream-loaded activations/weights/biases | High | stream-loaded full-network golden flow |
| seven-packet AXI tensor job | High | AXI stream full-network golden flow |
| output backpressure | High | stream-loaded and AXI stream golden flows |
| AXI-Lite control/status/performance registers | High pre-board | all 28 registers are modeled; address/data ordering, response stalls, byte strobes, predictor mirrors, resets, lifecycle, metadata, progress, parameter-bank, DDR-context, IRQ, error, and invalid-address behavior pass integrated tests |
| runtime metadata lifecycle | High pre-board | standalone lifecycle test plus complete AXI-Lite metadata load and activation |
| descriptor-driven execution | High pre-integration | active-bank four-layer golden flow, eight-layer boundary flow, and negative tests under Verilator CI |
| reusable runtime parameters | High pre-integration | bank-level negative tests plus integrated eight-layer scratchpad-backed execution |
| packed programmable DMA protocol | High pre-integration | parser/router/bank and output-writer tests with malformed packet recovery |
| DDR-backed spatial tiling | High pre-integration | directed plus randomized geometry, real halo scratchpad loader, multi-tile 1x1 and 3x3 stride-2 golden output, active DDR metadata, and AXI backpressure |
| multi-layer tiled execution | High pre-integration | two-layer packed tile flow through reusable parameters plus UVM closed loops that scatter actual layer-0 RTL output into DDR tensor memory and gather it for layer 1; the compiler-reference test checks a mixed 3x3-to-1x1 final tensor against Python, while progress and negative chain rejection are covered |
| integrated programmable runtime | High pre-board | atomic activation plus a compiler-derived four-layer mixed network with real parameter-bank recycling, 26 tiled inputs, and exact Python-to-RTL packed output comparison |
| programmable AXI-Lite system | High pre-board | AXI-Lite metadata/lifecycle/launch and progress readback, sticky structured first-fault capture/clear, malformed parameter rejection, active-model-preserving recovery, and deterministic randomized output backpressure |
| Zynq block design integration | Programmable wrapper selected; Phase 9 rebuild pending | source block design uses the packed programmable top; the current bitstream/XSA predates the completed numeric path |
| bare-metal DMA integration | High pre-board | package validation, atomic metadata activation, parameter-bank refill, clipped NHWC gather/scatter, packed packet validation, cache maintenance, and strict host compilation; target ELF rebuild pending XSA |
| real hardware behavior | Pending | board not yet available |

## Main Regression Commands

```bash
make model-test
make baremetal-runtime-test
make runtime-corpus-test
make randomized-package-rtl-test
make uvm-compile
make descriptor-test
make parameter-bank-test
make programmable-engine-test
make packed-dma-test
make packed-dma-runtime-test
make packed-dma-writer-test
make tile-test
make programmable-runtime-test
make programmable-system-test
make numeric-runtime-test
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
