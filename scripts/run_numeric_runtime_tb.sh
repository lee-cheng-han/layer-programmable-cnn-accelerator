#!/usr/bin/env bash
set -euo pipefail

if ! command -v verilator >/dev/null 2>&1; then
  echo "ERROR: verilator not found"
  exit 1
fi

build_dir="sim/verilator/numeric_runtime"
rm -rf "$build_dir"
mkdir -p "$build_dir"

verilator --binary --timing \
  -Wall \
  -Wno-fatal \
  -Wno-BLKSEQ \
  --top-module tb_tile_output_serializer_numeric \
  rtl/stream/tile_output_serializer.sv \
  tb/tb_tile_output_serializer_numeric.sv \
  --Mdir "$build_dir"

"$build_dir/Vtb_tile_output_serializer_numeric"
