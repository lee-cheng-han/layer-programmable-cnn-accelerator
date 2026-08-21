#!/usr/bin/env bash
set -euo pipefail

build_dir="${TMPDIR:-/tmp}/cnn_programmable_system_tb"
rm -rf "$build_dir"

verilator --binary --timing \
  -Irtl/include \
  -Wno-fatal -Wno-WIDTHTRUNC -Wno-WIDTHEXPAND \
  --top-module tb_programmable_system_top \
  rtl/include/cnn_accel_abi_pkg.sv \
  rtl/include/cnn_dma_packet_pkg.sv \
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
  rtl/tensor/weight_scratchpad.sv \
  rtl/tensor/banked_activation_scratchpad.sv \
  rtl/tensor/banked_weight_scratchpad.sv \
  rtl/tensor/ping_pong_bank_controller.sv \
  rtl/tensor/ping_pong_weight_scratchpad.sv \
  rtl/tensor/spatial_tile_planner.sv \
  rtl/tensor/halo_tile_load_controller.sv \
  rtl/stream/packed_dma_packet_parser.sv \
  rtl/stream/packed_dma_runtime_router.sv \
  rtl/stream/packed_dma_packet_writer.sv \
  rtl/stream/tile_output_serializer.sv \
  rtl/runtime/cnn_metadata_word_ram.sv \
  rtl/runtime/cnn_model_metadata_store.sv \
  rtl/runtime/cnn_runtime_parameter_banks.sv \
  rtl/runtime/cnn_tiled_layer_runtime.sv \
  rtl/runtime/cnn_tiled_multi_layer_controller.sv \
  rtl/runtime/cnn_programmable_runtime_top.sv \
  rtl/zynq/cnn_programmable_axi_lite_slave.sv \
  rtl/zynq/cnn_programmable_system_top.sv \
  tb/tb_programmable_system_top.sv \
  -Mdir "$build_dir"

"$build_dir/Vtb_programmable_system_top"
