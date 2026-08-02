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
| Result stage | Post-route physical optimization |
| Implementation status | Timing closed |

## Timing Signoff

Two clean physical searches were run from the same synthesized checkpoint.
Both satisfy setup and hold timing without failing endpoints.

| Run | Place / route directive | WNS | TNS | Setup failures | WHS | THS | Hold failures |
|---|---|---:|---:|---:|---:|---:|---:|
| Default | Default / default | 0.087 ns | 0.000 ns | 0 | 0.086 ns | 0.000 ns | 0 |
| Explore | Explore / Explore | 0.064 ns | 0.000 ns | 0 | 0.088 ns | 0.000 ns | 0 |

Post-synthesis setup slack is 0.512 ns. The default run's worst setup path is
a five-LUT BRAM-read-to-AXI-readback path. The Explore run's worst paths are
routing-only metadata writes into the distributed active-model cache. The
earlier deep arithmetic, DSP cascade, halo address, and tensor-selection paths
are no longer critical.

## Utilization

| Resource | Used | Available | Utilization |
|---|---:|---:|---:|
| Slice LUTs | 20,395 | 53,200 | 38.34% |
| Slice registers | 30,786 | 106,400 | 28.93% |
| F7 muxes | 4,098 | 26,600 | 15.41% |
| F8 muxes | 800 | 13,300 | 6.02% |
| Block RAM tiles | 38 | 140 | 27.14% |
| DSPs | 20 | 220 | 9.09% |

Both routed runs report no congestion windows above level 5. The OOC DRC and
methodology reports retain expected advisories for the absent PS7 wrapper,
unconstrained external I/O delays, asynchronous-reset DSP inference, and
optional DSP/BRAM pipeline registers. These are not timing violations.

## Artifacts

The Batch 25 evidence is under
`build/timing_closure/batch25_geometry_tensor_lookup_pipeline/`:

- `synth/top_synth.dcp` and post-synthesis timing/utilization reports
- `physical/optimized.dcp` and default setup, hold, congestion, fanout, DRC,
  methodology, and utilization reports
- `physical_explore/optimized.dcp` and equivalent Explore-run reports

The immediately preceding Batch 21 through Batch 24 directories preserve the
root-cause progression and make the closure work auditable.

## Regeneration

```bash
make programmable-top-synth

vivado -mode batch -source scripts/implement_checkpoint.tcl -tclargs \
  build/programmable_top_synth_candidate/top_synth.dcp \
  build/timing_closure/recheck_default

vivado -mode batch -source scripts/implement_checkpoint.tcl -tclargs \
  build/programmable_top_synth_candidate/top_synth.dcp \
  build/timing_closure/recheck_explore Explore Explore
```

Run `scripts/optimize_routed_checkpoint.tcl` on each resulting `routed.dcp` to
produce the final post-route setup and hold signoff reports.
