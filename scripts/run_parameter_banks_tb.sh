#!/usr/bin/env bash
set -euo pipefail

if ! command -v verilator >/dev/null 2>&1; then
 echo "ERROR: verilator not found"
 exit 1
fi

build_dir="sim/verilator/parameter_banks"
rm -rf "$build_dir"
mkdir -p "$build_dir"

verilator --binary --timing \
 -Wall \
 -Wno-fatal \
 -Wno-BLKLOOPINIT \
 -Wno-BLKSEQ \
 -Wno-DECLFILENAME \
 -Wno-PINCONNECTEMPTY \
 -Wno-UNUSEDSIGNAL \
 -Wno-UNUSEDPARAM \
 --top-module tb_runtime_parameter_banks \
 rtl/tensor/weight_scratchpad.sv \
 rtl/tensor/ping_pong_weight_scratchpad.sv \
 rtl/runtime/cnn_runtime_parameter_banks.sv \
 tb/tb_runtime_parameter_banks.sv \
 --Mdir "$build_dir"

"$build_dir/Vtb_runtime_parameter_banks"
