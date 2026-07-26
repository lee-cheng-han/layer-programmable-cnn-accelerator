#!/usr/bin/env bash
set -euo pipefail

if ! command -v verilator >/dev/null 2>&1; then
 echo "ERROR: verilator not found"
 exit 1
fi

build_dir="sim/verilator/packed_dma_runtime"
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
 --top-module tb_packed_dma_runtime_router \
 rtl/include/cnn_dma_packet_pkg.sv \
 rtl/tensor/weight_scratchpad.sv \
 rtl/tensor/ping_pong_weight_scratchpad.sv \
 rtl/stream/packed_dma_packet_parser.sv \
 rtl/stream/packed_dma_runtime_router.sv \
 rtl/runtime/cnn_runtime_parameter_banks.sv \
 tb/tb_packed_dma_runtime_router.sv \
 --Mdir "$build_dir"

"$build_dir/Vtb_packed_dma_runtime_router"
