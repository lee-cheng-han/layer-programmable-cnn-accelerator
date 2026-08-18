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
| `cnn_uvm_compiler_reference_test` | A compiler-produced 1-8-layer package drives metadata, parameters, and source tiles; each observed RTL output is scattered into DDR and gathered with kernel/stride-aware source geometry for the next layer, then final memory is checked against the independent Python package executor |
| `cnn_uvm_parameter_crc_recovery_test` | Corrupts parameter payload data while preserving valid packet framing, checks descriptor CRC rejection and active-model preservation, clears the fault, and reloads valid parameters without reset |
| `cnn_uvm_reset_recovery_test` | Asserts reset while the runtime is waiting for tile data, verifies architectural reset state, reloads the model, and completes a clean job |
| `cnn_uvm_starvation_abort_test` | Withholds tile data for a bounded host timeout, verifies clean starvation, aborts with `clear`, checks bank-ownership release, and reruns without reset |
| `cnn_uvm_ordering_recovery_test` | Injects a stale tensor ID and bias-before-weight ordering error, checks structured status and error IRQ, then clears and reruns |
| `cnn_uvm_model_replacement_test` | Attempts an invalid staged replacement, proves that the active model survives, clears the staging error, and executes the retained model |
| `cnn_uvm_interrupt_test` | Enables completion interrupts, executes a job, verifies the IRQ pin and latched status, and checks write-one-to-clear behavior |
| `cnn_uvm_protocol_ral_test` | Address-first and data-first AXI-Lite writes, delayed responses, partial and zero-byte strobes, all 28 register definitions, predictor mirrors, reset values, frontdoor access, and invalid-address responses |

Run source compilation and complete UVM elaboration:

```bash
make uvm-compile
```

Run an executable test on a working XSim UVM installation:

```bash
make uvm-smoke
make uvm-closed-loop
make uvm-compiler-reference
make uvm-randomized
make uvm-faults
make uvm-u4
make uvm-protocol-ral
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

Vivado/XSim 2025.2 on the current host executes the complete 22-case U4/U5
campaign, including compiler-generated one- through eight-layer fixtures, with
zero UVM errors and zero UVM fatals. Vivado 2026.1 remains the primary build
toolchain, while 2025.2 is used for licensed coverage collection on this host.

The randomized campaign defaults to two deterministic models for every layer
count from 1 through 8. Reproduce or expand it with:

```bash
UVM_CAMPAIGN_SEED=20260812 UVM_CAMPAIGN_SEEDS=4 make uvm-randomized
```

## Coverage Model

Implemented coverpoints include:

- DMA packet type
- layer ID
- channel tails versus full vectors
- partial versus fully packed payloads
- AXI-Lite read versus write
- control, progress, and version register regions
- AXI response class
- AXI write-address versus write-data arrival order
- AXI response latency
- AXI write-strobe class
- packet-type by channel-class crosses
- register-operation by address-region crosses
- fault class and recovery outcome crosses

The UVM regression elaborates production RTL with `PC=2`, `PK=2`,
`MAX_CIN=2`, and `MAX_COUT=2` to keep randomized campaign turnaround bounded.
Its channel coverage therefore distinguishes scalar one-channel traffic from
full two-lane vectors. The target's 16-channel capacity is a separate
parameterized RTL/implementation configuration and must not be inferred from
this UVM coverage score alone. The exact UVM scope is recorded in
`verification/uvm_signoff.json`.

## Verification Maturity Plan

| Stage | Deliverable | Current status | Completion gate |
|---:|---|---|---|
| U0 | Reusable UVM foundation | Complete | Production DUT, agents, monitors, RAL foundation, scoreboard, coverage, virtual sequencer, and tests compile and elaborate |
| U1 | Executable regression | Complete locally | Register, smoke, recovery, closed-loop DDR, and compiler-reference tests produce zero-error UVM summaries; CI artifact and seed archival remain to be added |
| U2 | Independent closed-loop checking | Complete for directed mixed-network scope | A real compiler package drives a two-layer 3x3-to-1x1 job; actual layer-0 RTL output is stored in behavioral DDR and reused by layer 1, then complete final memory is compared with the independent Python executor |
| U3 | Protocol and RAL maturity | Complete for the single-outstanding interface | Deterministic AW/W/response timing variation, defensive packet validation, all 28 registers, byte-granular prediction, mirrors, reset values, access policies, byte strobes, and invalid-address responses are covered |
| U4 | Constrained-random and fault campaign | Complete for the deterministic 22-case baseline | Compiler-generated 1-8-layer sweeps and reset, starvation/abort, stale-ID, ordering, checksum, replacement, IRQ, residual add/subtract, and saturation scenarios execute with zero UVM errors and fatals |
| U5 | Coverage closure and signoff | Functional target closed; code/assertion targets open | Clean 23-case campaign reaches 96.72% functional coverage with zero UVM errors/fatals; merged code databases exist, but XSim 2025.2 crashes before emitting fresh code HTML, and assertion coverage remains unmeasured |

### U5 Signoff Flow

[`verification/uvm_signoff.json`](../verification/uvm_signoff.json) is the
machine-readable signoff source. It maps each requirement to UVM tests,
assertions, and coverpoints; records reviewed exclusions; and defines targets
of 95% functional, 90% statement, 85% branch, 85% condition, 80% toggle, and
100% assertion coverage. Every exclusion must include an identifier, scope,
reason, and owner. The first reviewed exclusion records XSim's automatic
omission of a 34,848-bit scratchpad array from toggle coverage because the
simulator caps one variable at 32,768 bits; its externally visible behavior
remains functionally covered.

```bash
make uvm-signoff   # validate symbols, mappings, exclusions, and targets
make uvm-coverage  # execute deterministic runs and merge with xcrg
make uvm-u5        # complete U5 coverage flow
```

`make uvm-coverage` completes collection even when targets have gaps so its
artifacts remain available for diagnosis. `make uvm-u5` is the strict signoff
gate and returns failure until all declared targets are measured and met.

The coverage campaign runs register/RAL, protocol, recovery, reset, abort,
ordering, replacement, IRQ, smoke, closed-loop DDR, residual, saturation, and
compiler-generated randomized 1-8-layer cases. XSim databases, a merged
database, text/HTML reports, logs, and the signoff manifest are retained under
`build/uvm_coverage/`. Passing `make uvm-signoff` proves traceability integrity;
it does not substitute for executing `make uvm-u5` and reviewing the measured
coverage against every declared target.

The initial measured campaign is retained under `build/uvm_coverage_2025/`.
The clean closure campaign under `build/uvm_coverage_final/` passes all 23
cases and raises functional coverage from 86.85% to 96.72%, closing the 95%
target. `all_targets_met` remains false because fresh code scores and assertion
coverage are not available. XSim 2025.2 creates the merged code database but
segfaults before writing its HTML report; this tool failure is kept distinct
from simulation and functional-coverage results.

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
5. Execute and archive the implemented compiler-generated 1-8-layer campaign
   and fault suite after correcting the local node-locked simulator license.

### Agent And RAL Maturity

6. Preserve the implemented single-outstanding AXI-Lite contract; add
   multi-outstanding behavior only if the RTL interface is intentionally
   extended to support it.
7. Move all multi-agent coordination into reusable virtual sequences and add
    dedicated reset and interrupt agents.
8. Split transactions, agents, RAL, environment, sequences, coverage, and tests
    into focused packages/files as the environment grows.

### Randomization, Assertions, And Faults

9. Use U5 coverage results to add targeted seeds beyond the implemented mixed
    kernels, strides, asymmetric padding, activations, channel tails, residual
    modes, clipping, and parameter-bank reuse.
10. Extend the implemented malformed-packet, checksum, reset, stale-ID,
    ordering, abort, replacement, and recovery tests only where U5 coverage
    identifies missing legal states; autonomous hardware DMA timeout remains
    outside the software-managed V1 architecture.
11. Extend the implemented interface-level AXI-Lite, AXI-Stream, reset, status,
    and interrupt SVA with lifecycle, bank-ownership, and internal-progress
    properties where U5 reports identify unobserved requirements.

### Coverage Closure

12. Execute the defined model, packet, AXI, fault, and SVA coverage against the
    checked-in targets; document every legal-bin exclusion with scope, reason,
    and owner.
13. Run the implemented deterministic database merge in licensed CI and publish
    trend and closure reports.
14. Maintain the machine-checked requirement-to-test-to-assertion-to-coverpoint
    manifest and add targeted sequences for every uncovered legal bin.
15. Archive at least one real design or verification bug discovered by the UVM
    campaign, including seed, symptom, root cause, fix, and regression test.
