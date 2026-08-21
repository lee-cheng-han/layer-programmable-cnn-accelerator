#!/usr/bin/env bash
set -euo pipefail

if ! command -v verilator >/dev/null 2>&1; then
 echo "ERROR: verilator not found"
 exit 1
fi

build_dir="sim/verilator/descriptor_controller"
rm -rf "$build_dir"
mkdir -p "$build_dir"

verilator --binary --timing \
 -Irtl/include \
 -Wall \
 -Wno-fatal \
 -Wno-BLKLOOPINIT \
 -Wno-BLKSEQ \
 -Wno-DECLFILENAME \
 -Wno-PINCONNECTEMPTY \
 -Wno-UNUSEDSIGNAL \
 -Wno-UNUSEDPARAM \
 --top-module tb_descriptor_driven_job_controller \
 rtl/include/cnn_accel_abi_pkg.sv \
 rtl/scheduler/tail_mask_generator.sv \
 rtl/postprocess/parallel_bias_add.sv \
 rtl/postprocess/parallel_relu.sv \
 rtl/postprocess/parallel_quantizer.sv \
 rtl/postprocess/parallel_requantizer.sv \
 rtl/postprocess/parallel_saturate.sv \
 rtl/compute/reduction_tree.sv \
 rtl/compute/parallel_mac_array.sv \
 rtl/compute/psum_accumulator.sv \
 rtl/compute/tiled_conv1x1_engine.sv \
 rtl/compute/tiled_conv3x3_engine.sv \
 rtl/scheduler/single_layer_scheduler.sv \
 rtl/runtime/cnn_metadata_word_ram.sv \
 rtl/runtime/cnn_model_metadata_store.sv \
 rtl/scheduler/descriptor_driven_job_controller.sv \
 tb/tb_descriptor_driven_job_controller.sv \
 --Mdir "$build_dir"

"$build_dir/Vtb_descriptor_driven_job_controller"
