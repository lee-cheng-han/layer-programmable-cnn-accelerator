# Continuous Integration

This repository uses two CI levels:

1. Hosted source checks on GitHub-hosted Ubuntu runners.
2. Vivado/XSim FPGA checks on a self-hosted runner with Xilinx tools installed.

The split is intentional. Open GitHub runners are good for source hygiene, but
Vivado, XSim, implementation, and Vitis builds require licensed FPGA tooling and
board-specific installation paths.

## Hosted CI

Workflow:

```text
.github/workflows/ci.yml
```

Checks:

- `ci / source · shell · python`
  - shell script syntax
  - `shellcheck`
  - Python syntax compilation for models, scripts, software, and tests
- `ci / model · golden tensors`
  - bit-accurate Python model tests through `make model-test`
  - deterministic golden DMA header regeneration through `make baremetal-headers`
  - generated header diff check
  - strict portable runtime and board-app compilation through `make baremetal-runtime-test`
  - seeded 1-8-layer package/tile/protocol corpus through `make runtime-corpus-test`
- `ci / rtl · verilator lint`
  - Verilator lint through `make lint`
  - compiler-derived four-layer package, parameter-bank refill, tiled numeric
    execution, packed-output comparison, and randomized backpressure through
    `make randomized-package-rtl-test`
- `ci / docs · evidence consistency`
  - README/result docs checked against the pre-board evidence log through `make docs-check`
  - checked-in warning-budget evidence must show zero unknown warnings, zero critical warnings, and zero errors

This workflow runs on pushes, pull requests, and manual dispatch.

## Vivado / XSim CI

Workflow:

```text
.github/workflows/vivado-xsim.yml
```

Runner requirements:

- Linux self-hosted GitHub Actions runner
- labels: `self-hosted`, `linux`, `vivado`
- Vivado 2025.2 available in `PATH`, or one of:
 - `VIVADO_SETTINGS=/path/to/Vivado/settings64.sh`
 - `$HOME/Xilinx/2025.2/Vivado/settings64.sh`
 - `/tools/Xilinx/2025.2/Vivado/settings64.sh`

Default check:

```bash
make regression
make uvm-compile
```

The UVM gate compiles the UVM 1.2 agents, RAL model, scoreboard, coverage,
tests, complete programmable DUT, and simulation snapshot. Executable UVM
regression is enabled only on a runner where the XSim UVM snapshot loads
successfully. The workflow uploads simulation logs as artifacts even on
failure.

## Full FPGA Flow

The Vivado workflow has a manual `run_bitstream` option. When enabled, it runs:

```bash
make clean
make full-preboard-proof
make check-warnings
make docs-check
```

This generates golden tensors and bare-metal headers, runs the model/golden/RTL
regression, creates the Zybo Z7 Vivado project, builds the bitstream, exports the
XSA, builds the Vitis bare-metal application, and packages `build/BOOT.BIN`.
It also enforces the Vivado warning budget and checks the docs against the
checked-in evidence summaries. The full-flow jobs upload build reports,
bitstreams, XSAs, ELFs, `BOOT.BIN`, and evidence logs as GitHub Actions
artifacts.

Use this full flow intentionally because it is much slower than RTL simulation.

The unlicensed push workflow also compiles and executes the portable package,
tile, and packet runtime and strictly compiles the board application against a
minimal BSP shim:

```bash
make baremetal-runtime-test
make runtime-corpus-test
make randomized-package-rtl-test
```
