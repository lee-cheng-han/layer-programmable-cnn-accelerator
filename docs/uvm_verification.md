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

Run source compilation and complete UVM elaboration:

```bash
make uvm-compile
```

Run an executable test on a working XSim UVM installation:

```bash
make uvm-smoke
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

Vivado/XSim 2025.2 on the current host successfully compiles every UVM source,
elaborates the complete programmable DUT, and builds the simulation snapshot.
The local XSim executable then raises an internal exception while loading even
a minimal independent UVM snapshot. This is a simulator/host runtime issue, not
a failure in the repository environment. `make uvm-compile` is therefore the
locally verified gate; executable UVM results must not be reported as passing
until the snapshot runs on a supported XSim host or another UVM simulator.

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
| U1 | Executable regression | Blocked by local XSim runtime | Register, smoke, and recovery tests produce zero-error UVM summaries with archived logs and reproducible seeds |
| U2 | Independent closed-loop checking | Planned | Actual RTL output is stored in behavioral DDR, reused by the next layer, and compared against the independent Python/DPI-C reference model |
| U3 | Protocol and RAL maturity | Planned | AXI timing variation, protocol validation, complete register model, predictor, mirrors, reset values, access policies, and byte strobes are covered |
| U4 | Constrained-random and fault campaign | Planned | Compiler-generated 1-8-layer sequences cover legal combinations plus reset, abort, corruption, reordering, timeout, replacement, interrupt, residual, and saturation faults |
| U5 | Coverage closure and signoff | Planned | Functional and assertion coverage are merged in CI, requirements map to tests and coverpoints, exclusions are reviewed, and all closure targets are met |

## Planned Work Packages

### Simulator And Regression

1. Run UVM on a supported XSim host or another UVM 1.2 simulator and archive
   zero-error logs for every implemented test.
2. Add simulator-specific compile adapters without changing the reusable UVM
   interfaces, packages, environment, or tests.
3. Record simulator, test name, random seed, source revision, command, and
   failure artifacts for every regression run.

### Independent End-To-End Checking

4. Add a behavioral DDR/DMA memory model that scatters actual RTL output packets
   and gathers the stored tensor for the next layer.
5. Connect the Python bit-accurate executor through generated transaction files
   or DPI-C and compare complete tensor memory, not only packet-local payloads.
6. Generate model lifecycle, metadata, parameter, and tile sequences directly
   from real compiler-produced packages instead of hardcoded descriptors.

### Agent And RAL Maturity

7. Expand the AXI-Lite agent to vary AW/W ordering, valid gaps, response
   readiness, byte strobes, and supported outstanding-channel behavior.
8. Make stream monitors independently validate magic, version, header size,
   packet type, flags, payload length, low-lane `TKEEP`, and final `TLAST` before
   publishing transactions.
9. Complete the register model for every software-visible register and add a
   predictor, mirror checks, reset-value tests, access-policy tests, and
   register/field coverage.
10. Move all multi-agent coordination into reusable virtual sequences and add
    dedicated reset and interrupt agents.
11. Split transactions, agents, RAL, environment, sequences, coverage, and tests
    into focused packages/files as the environment grows.

### Randomization, Assertions, And Faults

12. Add compiler-generated constrained-random 1-8-layer networks spanning both
    kernels, both strides, asymmetric padding, channel tails, activations,
    residual modes, quantization, clipping, and parameter-bank reuse.
13. Add reset-at-state, CRC corruption, stale tensor ID, packet reordering,
    truncation, abort, DMA timeout, model replacement, bank exhaustion, and
    recovery-without-reset sequence libraries.
14. Bind AXI, packet, lifecycle, bank-ownership, and internal progress SVA into
    the UVM top and collect assertion pass/fail and coverage separately.

### Coverage Closure

15. Define coverage targets, legal-bin exclusions, and crosses for kernel,
    stride, channels, activation, residual, padding, packet type, and fault.
16. Merge coverage databases across deterministic seeds in licensed CI and
    publish trend and closure reports.
17. Maintain requirement-to-test-to-assertion-to-coverpoint traceability and add
    targeted sequences for every uncovered legal bin.
18. Archive at least one real design or verification bug discovered by the UVM
    campaign, including seed, symptom, root cause, fix, and regression test.
