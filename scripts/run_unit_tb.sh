#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 1 ]]; then
 echo "Usage: $0 <testbench_name>"
 exit 1
fi

TB_NAME="$1"
TB_FILE="tb/${TB_NAME}.sv"

if [[ ! -f "$TB_FILE" ]]; then
 echo "ERROR: Could not find testbench file: $TB_FILE"
 exit 1
fi

if ! command -v xvlog >/dev/null 2>&1; then
 echo "ERROR: xvlog not found. Source Vivado settings first."
 exit 1
fi

mkdir -p sim/xsim

cd sim/xsim

rm -rf \
 xsim.dir \
 "${TB_NAME}_xsim.dir" \
 "${TB_NAME}.jou" \
 "${TB_NAME}.log" \
 "${TB_NAME}_xsim_run.log" \
 xvlog.log \
 xelab.log \
 xsim.log \
 xsim.jou \
 xsim_*.backup.jou

echo "[XSim] Compiling RTL and ../../${TB_FILE}"

xvlog -sv -L work \
 --include ../../rtl/include \
 ../../rtl/include/cnn_accel_abi_pkg.sv \
 ../../rtl/include/cnn_dma_packet_pkg.sv \
 ../../rtl/scheduler/tail_mask_generator.sv \
 ../../rtl/postprocess/parallel_bias_add.sv \
 ../../rtl/postprocess/parallel_relu.sv \
 ../../rtl/postprocess/parallel_quantizer.sv \
 ../../rtl/postprocess/parallel_requantizer.sv \
 ../../rtl/postprocess/parallel_saturate.sv \
 ../../rtl/postprocess/residual_add.sv \
 ../../rtl/tensor/tensor_address_gen.sv \
 ../../rtl/tensor/activation_scratchpad.sv \
 ../../rtl/tensor/weight_scratchpad.sv \
 ../../rtl/tensor/banked_activation_scratchpad.sv \
 ../../rtl/tensor/banked_weight_scratchpad.sv \
 ../../rtl/tensor/ping_pong_bank_controller.sv \
 ../../rtl/tensor/ping_pong_activation_scratchpad.sv \
 ../../rtl/tensor/ping_pong_weight_scratchpad.sv \
 ../../rtl/tensor/activation_tensor_load_controller.sv \
 ../../rtl/tensor/weight_tensor_load_controller.sv \
 ../../rtl/tensor/output_tensor_store_controller.sv \
 ../../rtl/tensor/spatial_tile_planner.sv \
 ../../rtl/tensor/halo_tile_load_controller.sv \
 ../../rtl/stream/tensor_packet_router.sv \
 ../../rtl/stream/packed_dma_packet_parser.sv \
 ../../rtl/stream/packed_dma_runtime_router.sv \
 ../../rtl/stream/packed_dma_packet_writer.sv \
 ../../rtl/stream/tile_output_serializer.sv \
 ../../rtl/runtime/cnn_metadata_word_ram.sv \
 ../../rtl/runtime/cnn_model_metadata_store.sv \
 ../../rtl/runtime/cnn_runtime_parameter_banks.sv \
 ../../rtl/runtime/cnn_programmable_job_engine.sv \
 ../../rtl/runtime/cnn_tiled_layer_runtime.sv \
 ../../rtl/runtime/cnn_tiled_multi_layer_controller.sv \
 ../../rtl/runtime/cnn_programmable_runtime_top.sv \
 ../../rtl/runtime/cnn_programmable_performance_counters.sv \
 ../../rtl/zynq/cnn_programmable_axi_lite_slave.sv \
 ../../rtl/zynq/cnn_structured_error_snapshot.sv \
 ../../rtl/zynq/cnn_programmable_system_top.sv \
 ../../rtl/zynq/cnn_programmable_system_bd_wrapper.v \
 ../../rtl/scheduler/denoise_layer_descriptor_rom.sv \
 ../../rtl/scheduler/performance_counters.sv \
 ../../rtl/compute/reduction_tree.sv \
 ../../rtl/compute/parallel_mac_array.sv \
 ../../rtl/compute/psum_accumulator.sv \
 ../../rtl/compute/tiled_conv1x1_engine.sv \
 ../../rtl/compute/tiled_conv3x3_engine.sv \
 ../../rtl/scheduler/single_layer_scheduler.sv \
 ../../rtl/scheduler/descriptor_driven_job_controller.sv \
 ../../rtl/scheduler/multi_layer_job_controller.sv \
 ../../rtl/scheduler/stream_loaded_multi_layer_job_controller.sv \
 ../../rtl/zynq/cnn_runtime_capabilities.sv \
 ../../rtl/zynq/cnn_axi_lite_slave.sv \
 ../../rtl/zynq/cnn_image2image_axi_stream_top.sv \
 ../../rtl/zynq/cnn_image2image_system_top.sv \
 "../../${TB_FILE}"

echo "[XSim] Elaborating $TB_NAME"
xelab -debug typical "$TB_NAME" -s "${TB_NAME}_sim"

echo "[XSim] Running $TB_NAME"
set +e
xsim "${TB_NAME}_sim" -runall | tee "${TB_NAME}_xsim_run.log"
XSIM_STATUS=${PIPESTATUS[0]}
set -e

if [[ $XSIM_STATUS -ne 0 ]]; then
 echo "[FAIL] $TB_NAME: xsim exited with status $XSIM_STATUS"
 exit "$XSIM_STATUS"
fi

if grep -E "\[FAIL\]|FAILED|Fatal:|ERROR:" "${TB_NAME}_xsim_run.log" >/dev/null; then
 echo "[FAIL] $TB_NAME: failure pattern found in simulation log"
 exit 1
fi

if grep -E "\[PASS\]|PASS" "${TB_NAME}_xsim_run.log" >/dev/null; then
 echo "[PASS] $TB_NAME"
else
 echo "[FAIL] $TB_NAME: no PASS message found in simulation log"
 exit 1
fi
