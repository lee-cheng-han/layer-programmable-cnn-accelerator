#!/usr/bin/env bash
set -euo pipefail

if ! command -v verilator >/dev/null 2>&1; then
 echo "ERROR: verilator not found."
 echo "Install it with:"
 echo " sudo apt update"
 echo " sudo apt install verilator -y"
 exit 1
fi

verilator --lint-only \
 -Wall \
 -Wno-fatal \
 -Wno-BLKLOOPINIT \
 -Wno-BLKSEQ \
 -Wno-DECLFILENAME \
 -Wno-PINCONNECTEMPTY \
 -Wno-UNUSEDSIGNAL \
 -Wno-UNUSEDPARAM \
 --top-module cnn_image2image_system_top \
 rtl/include/cnn_accel_abi_pkg.sv \
 rtl/scheduler/tail_mask_generator.sv \
 rtl/postprocess/parallel_bias_add.sv \
 rtl/postprocess/parallel_relu.sv \
 rtl/postprocess/parallel_quantizer.sv \
 rtl/postprocess/parallel_requantizer.sv \
 rtl/postprocess/parallel_saturate.sv \
 rtl/postprocess/residual_add.sv \
 rtl/tensor/tensor_address_gen.sv \
 rtl/tensor/activation_scratchpad.sv \
 rtl/tensor/weight_scratchpad.sv \
 rtl/tensor/banked_activation_scratchpad.sv \
 rtl/tensor/banked_weight_scratchpad.sv \
 rtl/tensor/ping_pong_bank_controller.sv \
 rtl/tensor/ping_pong_activation_scratchpad.sv \
 rtl/tensor/ping_pong_weight_scratchpad.sv \
 rtl/tensor/activation_tensor_load_controller.sv \
 rtl/tensor/weight_tensor_load_controller.sv \
 rtl/tensor/output_tensor_store_controller.sv \
 rtl/stream/tensor_packet_router.sv \
 rtl/runtime/cnn_metadata_word_ram.sv \
 rtl/runtime/cnn_model_metadata_store.sv \
 rtl/runtime/cnn_runtime_parameter_banks.sv \
 rtl/runtime/cnn_programmable_job_engine.sv \
 rtl/scheduler/denoise_layer_descriptor_rom.sv \
 rtl/scheduler/performance_counters.sv \
 rtl/compute/reduction_tree.sv \
 rtl/compute/parallel_mac_array.sv \
 rtl/compute/psum_accumulator.sv \
 rtl/compute/tiled_conv1x1_engine.sv \
 rtl/compute/tiled_conv3x3_engine.sv \
 rtl/scheduler/single_layer_scheduler.sv \
 rtl/scheduler/descriptor_driven_job_controller.sv \
 rtl/scheduler/multi_layer_job_controller.sv \
 rtl/scheduler/stream_loaded_multi_layer_job_controller.sv \
 rtl/zynq/cnn_runtime_capabilities.sv \
 rtl/zynq/cnn_structured_error_snapshot.sv \
 rtl/zynq/cnn_axi_lite_slave.sv \
 rtl/zynq/cnn_image2image_axi_stream_top.sv \
 rtl/zynq/cnn_image2image_system_top.sv

verilator --lint-only \
 -Wall \
 -Wno-fatal \
 -Wno-BLKLOOPINIT \
 -Wno-BLKSEQ \
 -Wno-DECLFILENAME \
 -Wno-PINCONNECTEMPTY \
 -Wno-UNUSEDSIGNAL \
 -Wno-UNUSEDPARAM \
 --top-module descriptor_driven_job_controller \
 rtl/include/cnn_accel_abi_pkg.sv \
 rtl/scheduler/tail_mask_generator.sv \
 rtl/postprocess/parallel_bias_add.sv \
 rtl/postprocess/parallel_relu.sv \
 rtl/postprocess/parallel_quantizer.sv \
 rtl/postprocess/parallel_saturate.sv \
 rtl/compute/reduction_tree.sv \
 rtl/compute/parallel_mac_array.sv \
 rtl/compute/psum_accumulator.sv \
 rtl/compute/tiled_conv1x1_engine.sv \
 rtl/compute/tiled_conv3x3_engine.sv \
 rtl/scheduler/single_layer_scheduler.sv \
 rtl/scheduler/descriptor_driven_job_controller.sv

verilator --lint-only \
 -Wall \
 -Wno-fatal \
 -Wno-BLKLOOPINIT \
 -Wno-BLKSEQ \
 -Wno-DECLFILENAME \
 -Wno-PINCONNECTEMPTY \
 -Wno-UNUSEDSIGNAL \
 -Wno-UNUSEDPARAM \
 --top-module cnn_runtime_parameter_banks \
 rtl/tensor/weight_scratchpad.sv \
 rtl/tensor/ping_pong_weight_scratchpad.sv \
 rtl/runtime/cnn_runtime_parameter_banks.sv

echo "[PASS] Verilator lint completed"
