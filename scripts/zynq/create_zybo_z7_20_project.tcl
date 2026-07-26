set part_name xc7z020clg400-1
set board_part digilentinc.com:zybo-z7-20:part0:1.2
set board_repo [file normalize board_files]
set proj_name zybo_z7_20_cnn
set proj_dir build/zybo_z7_20_cnn
set bd_name system

if {[info exists ::env(PROJ_NAME)]} {
 set proj_name $::env(PROJ_NAME)
}

if {[info exists ::env(PROJ_DIR)]} {
 set proj_dir $::env(PROJ_DIR)
}

file delete -force $proj_dir

set_param board.repoPaths [list $board_repo]
if {[llength [get_board_parts -quiet $board_part]] != 1} {
 puts "ERROR: Zybo Z7-20 board part $board_part was not loaded from $board_repo"
 exit 1
}

# Digilent's calibrated Zybo preset uses negative DQS-to-clock skews. Vivado
# labels these four expected board values critical, so keep them visible as
# budgeted warnings while preserving fatal handling for every other critical.
foreach msg_id {PSU-1 PSU-2 PSU-3 PSU-4} {
 set_msg_config -id $msg_id -new_severity WARNING
}

create_project $proj_name $proj_dir -part $part_name
set_property board_part $board_part [current_project]

set_property target_language Verilog [current_project]
set_property simulator_language Mixed [current_project]

set rtl_files [list \
 rtl/include/cnn_dma_packet_pkg.sv \
	rtl/include/cnn_accel_abi_pkg.sv \
	rtl/scheduler/tail_mask_generator.sv \
 rtl/postprocess/parallel_bias_add.sv \
 rtl/postprocess/parallel_relu.sv \
 rtl/postprocess/parallel_quantizer.sv \
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
 rtl/stream/packed_dma_packet_parser.sv \
 rtl/stream/packed_dma_runtime_router.sv \
 rtl/stream/packed_dma_packet_writer.sv \
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
 rtl/zynq/cnn_image2image_system_top.sv \
 rtl/zynq/cnn_image2image_system_bd_wrapper.v \
]

add_files -norecurse $rtl_files
update_compile_order -fileset sources_1

create_bd_design $bd_name
current_bd_design $bd_name

create_bd_cell -type ip -vlnv xilinx.com:ip:processing_system7 ps7

apply_bd_automation -rule xilinx.com:bd_rule:processing_system7 \
 -config {make_external "FIXED_IO, DDR" apply_board_preset "1" Master "Disable" Slave "Disable"} \
 [get_bd_cells ps7]

set_property -dict [list \
 CONFIG.PCW_USE_M_AXI_GP0 {1} \
 CONFIG.PCW_USE_S_AXI_HP0 {1} \
 CONFIG.PCW_EN_CLK0_PORT {1} \
 CONFIG.PCW_FPGA0_PERIPHERAL_FREQMHZ {125.0} \
] [get_bd_cells ps7]

create_bd_cell -type ip -vlnv xilinx.com:ip:proc_sys_reset rst_ps7_0

create_bd_cell -type ip -vlnv xilinx.com:ip:axi_interconnect axi_lite_interconnect
set_property -dict [list \
 CONFIG.NUM_MI {2} \
 CONFIG.NUM_SI {1} \
] [get_bd_cells axi_lite_interconnect]

create_bd_cell -type ip -vlnv xilinx.com:ip:axi_interconnect axi_mem_interconnect
set_property -dict [list \
 CONFIG.NUM_MI {1} \
 CONFIG.NUM_SI {2} \
] [get_bd_cells axi_mem_interconnect]

create_bd_cell -type ip -vlnv xilinx.com:ip:axi_dma axi_dma_0
set_property -dict [list \
 CONFIG.c_include_sg {0} \
 CONFIG.c_include_mm2s {1} \
 CONFIG.c_include_s2mm {1} \
 CONFIG.c_m_axi_mm2s_data_width {32} \
 CONFIG.c_m_axis_mm2s_tdata_width {32} \
 CONFIG.c_s_axis_s2mm_tdata_width {32} \
 CONFIG.c_sg_include_stscntrl_strm {0} \
] [get_bd_cells axi_dma_0]

create_bd_cell -type module -reference cnn_image2image_system_bd_wrapper cnn_0

connect_bd_net [get_bd_pins ps7/FCLK_CLK0] [get_bd_pins rst_ps7_0/slowest_sync_clk]
connect_bd_net [get_bd_pins ps7/FCLK_CLK0] [get_bd_pins ps7/M_AXI_GP0_ACLK]
connect_bd_net [get_bd_pins ps7/FCLK_CLK0] [get_bd_pins ps7/S_AXI_HP0_ACLK]

connect_bd_net [get_bd_pins ps7/FCLK_CLK0] [get_bd_pins axi_lite_interconnect/ACLK]
connect_bd_net [get_bd_pins ps7/FCLK_CLK0] [get_bd_pins axi_lite_interconnect/S00_ACLK]
connect_bd_net [get_bd_pins ps7/FCLK_CLK0] [get_bd_pins axi_lite_interconnect/M00_ACLK]
connect_bd_net [get_bd_pins ps7/FCLK_CLK0] [get_bd_pins axi_lite_interconnect/M01_ACLK]

connect_bd_net [get_bd_pins ps7/FCLK_CLK0] [get_bd_pins axi_mem_interconnect/ACLK]
connect_bd_net [get_bd_pins ps7/FCLK_CLK0] [get_bd_pins axi_mem_interconnect/S00_ACLK]
connect_bd_net [get_bd_pins ps7/FCLK_CLK0] [get_bd_pins axi_mem_interconnect/S01_ACLK]
connect_bd_net [get_bd_pins ps7/FCLK_CLK0] [get_bd_pins axi_mem_interconnect/M00_ACLK]

connect_bd_net [get_bd_pins ps7/FCLK_CLK0] [get_bd_pins axi_dma_0/s_axi_lite_aclk]
connect_bd_net [get_bd_pins ps7/FCLK_CLK0] [get_bd_pins axi_dma_0/m_axi_mm2s_aclk]
connect_bd_net [get_bd_pins ps7/FCLK_CLK0] [get_bd_pins axi_dma_0/m_axi_s2mm_aclk]
connect_bd_net [get_bd_pins ps7/FCLK_CLK0] [get_bd_pins cnn_0/s_axi_aclk]

connect_bd_net [get_bd_pins ps7/FCLK_RESET0_N] [get_bd_pins rst_ps7_0/ext_reset_in]

connect_bd_net [get_bd_pins rst_ps7_0/peripheral_aresetn] [get_bd_pins axi_lite_interconnect/ARESETN]
connect_bd_net [get_bd_pins rst_ps7_0/peripheral_aresetn] [get_bd_pins axi_lite_interconnect/S00_ARESETN]
connect_bd_net [get_bd_pins rst_ps7_0/peripheral_aresetn] [get_bd_pins axi_lite_interconnect/M00_ARESETN]
connect_bd_net [get_bd_pins rst_ps7_0/peripheral_aresetn] [get_bd_pins axi_lite_interconnect/M01_ARESETN]

connect_bd_net [get_bd_pins rst_ps7_0/peripheral_aresetn] [get_bd_pins axi_mem_interconnect/ARESETN]
connect_bd_net [get_bd_pins rst_ps7_0/peripheral_aresetn] [get_bd_pins axi_mem_interconnect/S00_ARESETN]
connect_bd_net [get_bd_pins rst_ps7_0/peripheral_aresetn] [get_bd_pins axi_mem_interconnect/S01_ARESETN]
connect_bd_net [get_bd_pins rst_ps7_0/peripheral_aresetn] [get_bd_pins axi_mem_interconnect/M00_ARESETN]

connect_bd_net [get_bd_pins rst_ps7_0/peripheral_aresetn] [get_bd_pins axi_dma_0/axi_resetn]
connect_bd_net [get_bd_pins rst_ps7_0/peripheral_aresetn] [get_bd_pins cnn_0/s_axi_aresetn]

connect_bd_intf_net [get_bd_intf_pins ps7/M_AXI_GP0] [get_bd_intf_pins axi_lite_interconnect/S00_AXI]
connect_bd_intf_net [get_bd_intf_pins axi_lite_interconnect/M00_AXI] [get_bd_intf_pins cnn_0/S_AXI]
connect_bd_intf_net [get_bd_intf_pins axi_lite_interconnect/M01_AXI] [get_bd_intf_pins axi_dma_0/S_AXI_LITE]

connect_bd_intf_net [get_bd_intf_pins axi_dma_0/M_AXI_MM2S] [get_bd_intf_pins axi_mem_interconnect/S00_AXI]
connect_bd_intf_net [get_bd_intf_pins axi_dma_0/M_AXI_S2MM] [get_bd_intf_pins axi_mem_interconnect/S01_AXI]
connect_bd_intf_net [get_bd_intf_pins axi_mem_interconnect/M00_AXI] [get_bd_intf_pins ps7/S_AXI_HP0]

connect_bd_intf_net [get_bd_intf_pins axi_dma_0/M_AXIS_MM2S] [get_bd_intf_pins cnn_0/S_AXIS]
connect_bd_intf_net [get_bd_intf_pins cnn_0/M_AXIS] [get_bd_intf_pins axi_dma_0/S_AXIS_S2MM]

set cnn_slave_seg [get_bd_addr_segs -quiet /cnn_0/s_axi/reg0]
if {[llength $cnn_slave_seg] < 1} {
 puts "ERROR: Could not find CNN slave segment /cnn_0/s_axi/reg0"
 puts [get_bd_addr_segs -hier]
 exit 1
}

assign_bd_address \
 -offset 0x43C00000 \
 -range 0x00001000 \
 -target_address_space [get_bd_addr_spaces ps7/Data] \
 $cnn_slave_seg \
 -force

set dma_lite_seg [get_bd_addr_segs -quiet /axi_dma_0/S_AXI_LITE/Reg]
if {[llength $dma_lite_seg] < 1} {
 puts "ERROR: Could not find AXI DMA control segment /axi_dma_0/S_AXI_LITE/Reg"
 puts [get_bd_addr_segs -hier]
 exit 1
}

assign_bd_address \
 -offset 0x40400000 \
 -range 0x00010000 \
 -target_address_space [get_bd_addr_spaces ps7/Data] \
 $dma_lite_seg \
 -force

assign_bd_address

validate_bd_design
save_bd_design

make_wrapper -files [get_files $proj_dir/$proj_name.srcs/sources_1/bd/$bd_name/$bd_name.bd] -top
add_files -norecurse $proj_dir/$proj_name.gen/sources_1/bd/$bd_name/hdl/${bd_name}_wrapper.v
set_property top ${bd_name}_wrapper [current_fileset]
update_compile_order -fileset sources_1

puts ""
puts "ZYBO Z7-20 IMAGE-TO-IMAGE BLOCK DESIGN CREATED"
puts "Project:"
puts " $proj_dir/$proj_name.xpr"
puts "CNN base address:"
puts " 0x43C00000"
puts "AXI DMA base address:"
puts " 0x40400000"
puts ""
