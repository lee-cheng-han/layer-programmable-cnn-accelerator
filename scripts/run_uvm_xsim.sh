#!/usr/bin/env bash
set -euo pipefail

test_name="${UVM_TESTNAME:-cnn_uvm_smoke_test}"
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
build_dir="${TMPDIR:-/tmp}/cnn_uvm_xsim"
xilinx_root="${XILINX_VIVADO:-$HOME/Xilinx/2025.2/Vivado}"
xvlog_bin="${XVLOG:-$xilinx_root/bin/xvlog}"
xelab_bin="${XELAB:-$xilinx_root/bin/xelab}"
xsim_bin="${XSIM:-$xilinx_root/bin/xsim}"

for tool in "$xvlog_bin" "$xelab_bin" "$xsim_bin"; do
  if [[ ! -x "$tool" ]]; then
    echo "ERROR: required XSim tool not found: $tool" >&2
    exit 1
  fi
done

rm -rf "$build_dir"
mkdir -p "$build_dir"
cd "$build_dir"
cp "$xilinx_root/data/xsim/xsim.ini" ./xsim.ini

rtl_files=(
  rtl/include/cnn_accel_abi_pkg.sv
  rtl/include/cnn_dma_packet_pkg.sv
  rtl/scheduler/tail_mask_generator.sv
  rtl/postprocess/parallel_bias_add.sv
  rtl/postprocess/parallel_relu.sv
  rtl/postprocess/parallel_quantizer.sv
  rtl/postprocess/parallel_requantizer.sv
  rtl/postprocess/parallel_saturate.sv
  rtl/compute/reduction_tree.sv
  rtl/compute/parallel_mac_array.sv
  rtl/compute/psum_accumulator.sv
  rtl/compute/tiled_conv1x1_engine.sv
  rtl/compute/tiled_conv3x3_engine.sv
  rtl/scheduler/single_layer_scheduler.sv
  rtl/tensor/weight_scratchpad.sv
  rtl/tensor/banked_activation_scratchpad.sv
  rtl/tensor/banked_weight_scratchpad.sv
  rtl/tensor/ping_pong_bank_controller.sv
  rtl/tensor/ping_pong_weight_scratchpad.sv
  rtl/tensor/spatial_tile_planner.sv
  rtl/tensor/halo_tile_load_controller.sv
  rtl/stream/packed_dma_packet_parser.sv
  rtl/stream/packed_dma_runtime_router.sv
  rtl/stream/packed_dma_packet_writer.sv
  rtl/stream/tile_output_serializer.sv
  rtl/runtime/cnn_metadata_word_ram.sv
  rtl/runtime/cnn_model_metadata_store.sv
  rtl/runtime/cnn_runtime_parameter_banks.sv
  rtl/runtime/cnn_tiled_layer_runtime.sv
  rtl/runtime/cnn_tiled_multi_layer_controller.sv
  rtl/runtime/cnn_programmable_runtime_top.sv
  rtl/zynq/cnn_programmable_axi_lite_slave.sv
  rtl/zynq/cnn_programmable_system_top.sv
)

sources=(
  verification/uvm/interfaces/cnn_axi_lite_if.sv
  verification/uvm/interfaces/cnn_axis_if.sv
  verification/uvm/interfaces/cnn_status_if.sv
  verification/uvm/cnn_uvm_pkg.sv
  verification/uvm/cnn_uvm_tests_pkg.sv
  verification/uvm/tb_cnn_programmable_uvm.sv
)

for index in "${!rtl_files[@]}"; do
  rtl_files[index]="$repo_root/${rtl_files[index]}"
done
for index in "${!sources[@]}"; do
  if [[ "${sources[index]}" != /* ]]; then
    sources[index]="$repo_root/${sources[index]}"
  fi
done

"$xvlog_bin" --sv --uvm_version 1.2 -L uvm \
  --include "$repo_root/verification/uvm" \
  --include "$xilinx_root/data/xsim/system_verilog/uvm_include" \
  "${rtl_files[@]}" "${sources[@]}"
"$xelab_bin" --uvm_version 1.2 -L uvm --debug typical \
  --timescale 1ns/1ps \
  tb_cnn_programmable_uvm -s cnn_programmable_uvm_sim

if [[ "${UVM_COMPILE_ONLY:-0}" == "1" ]]; then
  echo "[PASS] UVM compile/elaboration"
  exit 0
fi

set +e
"$xsim_bin" cnn_programmable_uvm_sim --runall \
  --testplusarg "UVM_TESTNAME=$test_name" --onfinish quit |
  tee "${test_name}.log"
status=${PIPESTATUS[0]}
set -e

if [[ $status -ne 0 ]]; then
  exit "$status"
fi
if grep -Eq 'UVM_(FATAL|ERROR) *: *[1-9]' "${test_name}.log"; then
  echo "ERROR: UVM reported failures" >&2
  exit 1
fi
if ! grep -Eq 'UVM_ERROR *: *0|UVM_ERROR : *0' "${test_name}.log"; then
  echo "ERROR: no zero-error UVM summary found" >&2
  exit 1
fi

echo "[PASS] UVM test $test_name"
