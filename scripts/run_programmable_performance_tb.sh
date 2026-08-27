#!/usr/bin/env bash
set -euo pipefail

build_dir="${TMPDIR:-/tmp}/cnn_programmable_performance_tb"
rm -rf "$build_dir"

verilator --binary --timing -Wall -Wno-fatal \
  --top-module tb_programmable_performance_counters \
  rtl/runtime/cnn_programmable_performance_counters.sv \
  tb/tb_programmable_performance_counters.sv \
  -Mdir "$build_dir"

"$build_dir/Vtb_programmable_performance_counters"
