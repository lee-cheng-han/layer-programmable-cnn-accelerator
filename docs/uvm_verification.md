# UVM Verification Environment

## Purpose

The UVM environment is a second verification layer around the production
`cnn_programmable_system_top`. It complements rather than replaces the fast
Python, C, Verilator, directed SystemVerilog, and XSim regressions.

The environment targets design-verification workflows: reusable protocol
agents, transaction-level checking, register abstraction, constrained stimulus,
functional coverage, recovery testing, reproducible seeds, and coverage
closure.

## Architecture

```text
cnn_uvm_base_test
  |
  +-- cnn_uvm_env
      |
      +-- AXI-Lite active agent
      |   +-- sequencer
      |   +-- driver
      |   +-- monitor -> register coverage
      |
      +-- AXI-Stream ingress active agent
      |   +-- packet sequencer
      |   +-- packed-beat driver
      |   +-- packet monitor -> packet coverage
      |
      +-- AXI-Stream egress sink agent
      |   +-- randomized-ready driver
      |   +-- packet monitor -> scoreboard + packet coverage
      |
      +-- packet scoreboard
      +-- byte-addressed DDR tensor model
      +-- virtual sequencer
      +-- UVM register block and AXI adapter
```

The stream monitor reconstructs complete versioned DMA transactions from
`TDATA`, `TKEEP`, and `TLAST`. The scoreboard compares packet context and every
payload byte. Output readiness follows a deterministic LFSR pattern, so stalls
are repeatable.

## Implemented Tests

| Test | Intent |
|---|---|
| `cnn_uvm_register_access_test` | Read/write register access, version discovery, and invalid-address `SLVERR` |
| `cnn_uvm_smoke_test` | Model load, metadata commit, validation, atomic activation, parameter load, tiled execution, randomized output backpressure, and packet scoreboard |
| `cnn_uvm_protocol_recovery_test` | Malformed parameter length rejection, packet-error counting, active-model preservation, clear, and successful rerun |
| `cnn_uvm_closed_loop_ddr_test` | Two-layer execution where observed layer-0 RTL output is scattered into strided DDR tensor memory, gathered as layer-1 input, and checked as a complete final tensor |
| `cnn_uvm_compiler_reference_test` | A real compiler-produced two-layer 3x3-to-1x1 package drives metadata, parameters, and layer-0 tiles; observed RTL output is reused from DDR for layer 1 and the final tensor is checked against the independent Python package executor |

Run source compilation and complete UVM elaboration:

```bash
make uvm-compile
```

Run an executable test on a working XSim UVM installation:

```bash
make uvm-smoke
make uvm-closed-loop
make uvm-compiler-reference
UVM_TESTNAME=cnn_uvm_protocol_recovery_test bash scripts/run_uvm_xsim.sh
```

Run the current test set:

```bash
make uvm-regression
```

The runner uses Xilinx UVM 1.2 and the production RTL file set. A commercial
simulator can use the same interfaces, packages, test top, and test names with
an equivalent compile script.

## Current Local Tool Status

Vivado/XSim 2026.1 on the current host compiles every UVM source, elaborates the
complete programmable DUT, and executes the register-access, protocol-recovery,
end-to-end smoke, closed-loop DDR, and compiler-reference tests.
`make uvm-regression` completes with zero UVM errors and zero UVM fatals in all
five tests.

## Coverage Model

Implemented coverpoints include:

- DMA packet type
- layer ID
- channel tails versus full vectors
- partial versus fully packed payloads
- AXI-Lite read versus write
- control, progress, and version register regions
- AXI response class
- packet-type by channel-class crosses
- register-operation by address-region crosses

## Verification Maturity Plan

| Stage | Deliverable | Current status | Completion gate |
|---:|---|---|---|
| U0 | Reusable UVM foundation | Complete | Production DUT, agents, monitors, RAL foundation, scoreboard, coverage, virtual sequencer, and tests compile and elaborate |
| U1 | Executable regression | Complete locally | Register, smoke, recovery, closed-loop DDR, and compiler-reference tests produce zero-error UVM summaries; CI artifact and seed archival remain to be added |
| U2 | Independent closed-loop checking | Complete for directed mixed-network scope | A real compiler package drives a two-layer 3x3-to-1x1 job; actual layer-0 RTL output is stored in behavioral DDR and reused by layer 1, then complete final memory is compared with the independent Python executor |
| U3 | Protocol and RAL maturity | Planned | AXI timing variation, protocol validation, complete register model, predictor, mirrors, reset values, access policies, and byte strobes are covered |
| U4 | Constrained-random and fault campaign | Planned | Compiler-generated 1-8-layer sequences cover legal combinations plus reset, abort, corruption, reordering, timeout, replacement, interrupt, residual, and saturation faults |
| U5 | Coverage closure and signoff | Planned | Functional and assertion coverage are merged in CI, requirements map to tests and coverpoints, exclusions are reviewed, and all closure targets are met |

## Planned Work Packages

### Simulator And Regression

1. Archive zero-error logs, simulator version, test name, and random seed for
   every implemented test in CI.
2. Add simulator-specific compile adapters without changing the reusable UVM
   interfaces, packages, environment, or tests.
3. Record simulator, test name, random seed, source revision, command, and
   failure artifacts for every regression run.

### Independent End-To-End Checking

4. Extend the implemented behavioral DDR tensor model beyond the current
   multi-channel and padded-halo cases to cover overlapping legal lifetimes and
   broader stride combinations.
5. Expand the implemented generated-transaction reference flow from its
   directed two-layer network to constrained-random 1-8-layer packages.

### Agent And RAL Maturity

6. Expand the AXI-Lite agent to vary AW/W ordering, valid gaps, response
   readiness, byte strobes, and supported outstanding-channel behavior.
7. Make stream monitors independently validate magic, version, header size,
   packet type, flags, payload length, low-lane `TKEEP`, and final `TLAST` before
   publishing transactions.
8. Complete the register model for every software-visible register and add a
   predictor, mirror checks, reset-value tests, access-policy tests, and
   register/field coverage.
9. Move all multi-agent coordination into reusable virtual sequences and add
    dedicated reset and interrupt agents.
10. Split transactions, agents, RAL, environment, sequences, coverage, and tests
    into focused packages/files as the environment grows.

### Randomization, Assertions, And Faults

11. Add compiler-generated constrained-random 1-8-layer networks spanning both
    kernels, both strides, asymmetric padding, channel tails, activations,
    residual modes, quantization, clipping, and parameter-bank reuse.
12. Add reset-at-state, CRC corruption, stale tensor ID, packet reordering,
    truncation, abort, DMA timeout, model replacement, bank exhaustion, and
    recovery-without-reset sequence libraries.
13. Bind AXI, packet, lifecycle, bank-ownership, and internal progress SVA into
    the UVM top and collect assertion pass/fail and coverage separately.

### Coverage Closure

14. Define coverage targets, legal-bin exclusions, and crosses for kernel,
    stride, channels, activation, residual, padding, packet type, and fault.
15. Merge coverage databases across deterministic seeds in licensed CI and
    publish trend and closure reports.
16. Maintain requirement-to-test-to-assertion-to-coverpoint traceability and add
    targeted sequences for every uncovered legal bin.
17. Archive at least one real design or verification bug discovered by the UVM
    campaign, including seed, symptom, root cause, fix, and regression test.
