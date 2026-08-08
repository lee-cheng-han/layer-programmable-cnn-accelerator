# Programmable Top-Level Implementation

This report records out-of-context implementation evidence for the
layer-programmable image-to-image RTL top. It proves that the complete PL RTL
fits and closes timing on the Zybo Z7-20 device. It is not a board bitstream;
the processing system, AXI DMA, board clocks, and external constraints are
validated by the separate board flow.

## Configuration

| Field | Value |
|---|---:|
| Part | `xc7z020clg400-1` |
| Top | `cnn_programmable_system_top` |
| PC / PK | 2 / 4 |
| Maximum input / output channels | 16 / 16 |
| Maximum tile width / height | 16 / 16 |
| Clock target | 125.000 MHz (8.000 ns) |
| Vivado | 2025.2 |
| Result stage | Routed |
| Implementation status | Timing closed |

## Timing Signoff

Two clean physical searches were run from the same synthesized checkpoint.
Both satisfy setup and hold timing without failing endpoints.

| Run | Place / route directive | WNS | TNS | Setup failures | WHS | THS | Hold failures |
|---|---|---:|---:|---:|---:|---:|---:|
| Default | Default / default | 0.023 ns | 0.000 ns | 0 | 0.096 ns | 0.000 ns | 0 |
| Explore | Explore / Explore | 0.013 ns | 0.000 ns | 0 | 0.096 ns | 0.000 ns | 0 |

Post-synthesis setup is `WNS=-0.279 ns`, `TNS=-2.232 ns`, with eight estimated
failing endpoints. Physical placement and routing close all endpoints in two
independent searches. The default run's worst setup path crosses the residual
tile serializer and packed output writer. The Explore run's worst path is a
descriptor geometry check feeding the sticky runtime error register. The
requantization multiplier, rounding, zero-point, parser byte accounting, and
residual arithmetic paths are no longer critical.

## Utilization

| Resource | Used | Available | Utilization |
|---|---:|---:|---:|
| Slice LUTs | 28,862 | 53,200 | 54.25% |
| Slice registers | 38,994 | 106,400 | 36.65% |
| F7 muxes | 4,855 | 26,600 | 18.25% |
| F8 muxes | 1,098 | 13,300 | 8.26% |
| Block RAM tiles | 43 | 140 | 30.71% |
| DSPs | 54 | 220 | 24.55% |

Both routed runs report no congestion windows above level 5. The OOC DRC and
methodology reports retain expected advisories for the absent PS7 wrapper,
unconstrained external I/O delays, asynchronous-reset DSP inference, and
optional DSP/BRAM pipeline registers. These are not timing violations.

## Artifacts

The current Phase 9 evidence is under:

- `build/programmable_top_synth_candidate/` for the synthesized checkpoint and
  post-synthesis timing/utilization reports
- `build/programmable_top_phase9_route_final/` for the default routed
  checkpoint and setup, hold, congestion, fanout, DRC, and utilization reports
- `build/programmable_top_phase9_route_explore/` for the independent
  Explore/Explore routed checkpoint and equivalent reports

These results include the integrated per-channel requantizer, residual
scratchpad/load path, residual arithmetic, and saturation-event counters.

## Regeneration

```bash
make programmable-top-synth

vivado -mode batch -source scripts/implement_checkpoint.tcl -tclargs \
  build/programmable_top_synth_candidate/top_synth.dcp \
  build/programmable_top_phase9_route_final

vivado -mode batch -source scripts/implement_checkpoint.tcl -tclargs \
  build/programmable_top_synth_candidate/top_synth.dcp \
  build/programmable_top_phase9_route_explore Explore Explore
```
