#!/usr/bin/env bash
set -euo pipefail

TESTS=(
 tb_parallel_mac_array
 tb_psum_accumulator
 tb_tail_mask_postprocess
 tb_tiled_conv1x1_engine
 tb_tensor_address_gen
 tb_tiled_conv3x3_engine
 tb_scratchpads
 tb_banked_scratchpads
 tb_ping_pong_buffers
 tb_tensor_load_controllers
 tb_output_store_controller
 tb_layer_descriptors
 tb_model_metadata_store
 tb_descriptor_driven_job_controller
 tb_runtime_parameter_banks
 tb_programmable_job_engine
 tb_packed_dma_packet_parser
 tb_packed_dma_runtime_router
 tb_packed_dma_packet_writer
 tb_single_layer_scheduler
 tb_multi_layer_job_controller
 tb_stream_loaded_multi_layer_job_controller
 tb_performance_counters
 tb_axi_lite_slave
 tb_axi_stream_top
 tb_image2image_system_top
)

echo "============================================================"
echo "[UNIT] tb_parallel_requantizer (Verilator)"
echo "============================================================"
bash scripts/run_requantizer_tb.sh

for tb in "${TESTS[@]}"; do
 echo "============================================================"
 echo "[UNIT] $tb"
 echo "============================================================"
 bash scripts/run_unit_tb.sh "$tb"
done

echo "============================================================"
echo "[PASS] unit tests complete"
echo "============================================================"
