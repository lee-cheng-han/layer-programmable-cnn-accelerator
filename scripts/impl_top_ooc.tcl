set_param general.maxThreads 8

set part_name xc7z020clg400-1
set top_name cnn_image2image_system_top
set clock_period_ns 8.000

# Keep the default top-level experiment small enough to finish quickly. Larger
# design points can be selected with PC, PK, and MAX_PIXELS environment overrides.
set pc 2
set pk 4
set max_pixels 16
set max_cin 16
set max_cout 16
set place_directive ""
set route_directive ""
set post_route_phys_directive "AggressiveExplore"

if {[info exists ::env(PC)]} {
 set pc $::env(PC)
}
if {[info exists ::env(PK)]} {
 set pk $::env(PK)
}
if {[info exists ::env(MAX_PIXELS)]} {
 set max_pixels $::env(MAX_PIXELS)
}
if {[info exists ::env(MAX_CIN)]} {
 set max_cin $::env(MAX_CIN)
}
if {[info exists ::env(MAX_COUT)]} {
 set max_cout $::env(MAX_COUT)
}
if {[info exists ::env(PLACE_DIRECTIVE)]} {
 set place_directive $::env(PLACE_DIRECTIVE)
}
if {[info exists ::env(ROUTE_DIRECTIVE)]} {
 set route_directive $::env(ROUTE_DIRECTIVE)
}
if {[info exists ::env(POST_ROUTE_PHYS_DIRECTIVE)]} {
 set post_route_phys_directive $::env(POST_ROUTE_PHYS_DIRECTIVE)
}
if {[info exists ::env(OUT_DIR)]} {
 set out_dir $::env(OUT_DIR)
} else {
 set out_dir "build/top_impl"
}

file mkdir $out_dir

proc get_slack_or_na {delay_type} {
 set paths [get_timing_paths -delay_type $delay_type -max_paths 1]
 if {[llength $paths] == 0} {
 return "NA"
 }
 return [get_property SLACK [lindex $paths 0]]
}

proc write_metadata {out_dir part_name top_name pc pk max_cin max_cout max_pixels clock_period_ns result_stage implementation_status implementation_error} {
 set metadata [open "$out_dir/metadata.txt" w]
 puts $metadata "part=$part_name"
 puts $metadata "top=$top_name"
 puts $metadata "pc=$pc"
 puts $metadata "pk=$pk"
 puts $metadata "max_cin=$max_cin"
 puts $metadata "max_cout=$max_cout"
 puts $metadata "max_pixels=$max_pixels"
 puts $metadata "clock_period_ns=$clock_period_ns"
 puts $metadata "wns_ns=[get_slack_or_na max]"
 puts $metadata "whs_ns=[get_slack_or_na min]"
 puts $metadata "flow=out_of_context_top_experiment"
 puts $metadata "result_stage=$result_stage"
 puts $metadata "implementation_status=$implementation_status"
 if {$implementation_error ne ""} {
 puts $metadata "implementation_error_file=$out_dir/implementation_error.txt"
 }
 close $metadata

 if {$implementation_error ne ""} {
 set error_file [open "$out_dir/implementation_error.txt" w]
 puts $error_file $implementation_error
 close $error_file
 }
}

proc utilization_over_limit_messages {path} {
 set file [open $path r]
 set contents [read $file]
 close $file

 set messages [list]
 foreach line [split $contents "\n"] {
 set columns [split [string trim $line "|"] "|"]
 if {[llength $columns] < 5} {
 continue
 }
 set label [string trim [lindex $columns 0]]
 regsub {\*} $label "" label
 set used_text [string map {"," ""} [string trim [lindex $columns 1]]]
 set available_text [string map {"," ""} [string trim [lindex $columns 4]]]
 if {![string is integer -strict $used_text] || ![string is integer -strict $available_text]} {
 continue
 }
 if {$label in {"Slice LUTs" "LUT as Logic" "F7 Muxes" "F8 Muxes"} && $used_text > $available_text} {
 lappend messages "$label uses $used_text of $available_text available"
 }
 }
 return $messages
}

set sources [list \
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
]

foreach source $sources {
 read_verilog -sv $source
}

read_xdc constraints/top_ooc.xdc

synth_design \
 -top $top_name \
 -part $part_name \
 -generic PC=$pc \
 -generic PK=$pk \
 -generic MAX_CIN=$max_cin \
 -generic MAX_COUT=$max_cout \
 -generic MAX_PIXELS=$max_pixels \
 -mode out_of_context \
 -flatten_hierarchy none

report_clocks -file "$out_dir/clocks_post_synth.rpt"
report_utilization -file "$out_dir/utilization_post_synth.rpt"
report_utilization -hierarchical -file "$out_dir/utilization_hier_post_synth.rpt"
report_timing_summary -delay_type max -file "$out_dir/timing_post_synth.rpt"
write_checkpoint -force "$out_dir/top_synth.dcp"

set overutil_messages [utilization_over_limit_messages "$out_dir/utilization_post_synth.rpt"]
if {[llength $overutil_messages] > 0} {
 set implementation_error "Post-synthesis utilization exceeds the target device:\n[join $overutil_messages "\n"]"
 write_metadata \
 $out_dir \
 $part_name \
 $top_name \
 $pc \
 $pk \
 $max_cin \
 $max_cout \
 $max_pixels \
 $clock_period_ns \
 "post_synth" \
 "failed" \
 $implementation_error

 puts "============================================================"
 puts " top implementation experiment complete"
 puts "Part: $part_name"
 puts "Top: $top_name"
 puts "Configuration: PC=$pc PK=$pk MAX_PIXELS=$max_pixels"
 puts "Clock target: $clock_period_ns ns"
 puts "Result stage: post_synth"
 puts "Implementation status: failed"
 puts $implementation_error
 puts "Reports: $out_dir"
 puts "============================================================"
 exit
}

set result_stage "post_route"
set implementation_status "passed"
set implementation_error ""

if {[catch {
 opt_design
 if {$place_directive eq ""} {
  place_design
 } else {
  place_design -directive $place_directive
 }
 phys_opt_design
 if {$route_directive eq ""} {
  route_design
 } else {
  route_design -directive $route_directive
 }
 phys_opt_design -directive $post_route_phys_directive

 report_clocks -file "$out_dir/clocks_post_route.rpt"
 report_utilization -file "$out_dir/utilization_post_route.rpt"
 report_utilization -hierarchical -file "$out_dir/utilization_hier_post_route.rpt"
 report_timing_summary -delay_type max -file "$out_dir/timing_post_route.rpt"
 report_timing_summary -delay_type min -file "$out_dir/timing_hold_post_route.rpt"
 report_drc -file "$out_dir/drc_post_route.rpt"
 write_checkpoint -force "$out_dir/top_routed.dcp"
} implementation_error]} {
 set result_stage "post_synth"
 set implementation_status "failed"
 catch {report_drc -file "$out_dir/drc_impl_failed.rpt"}
}

write_metadata \
 $out_dir \
 $part_name \
 $top_name \
 $pc \
 $pk \
 $max_cin \
 $max_cout \
 $max_pixels \
 $clock_period_ns \
 $result_stage \
 $implementation_status \
 $implementation_error

puts "============================================================"
puts " top implementation experiment complete"
puts "Part: $part_name"
puts "Top: $top_name"
puts "Configuration: PC=$pc PK=$pk MAX_PIXELS=$max_pixels"
puts "Clock target: $clock_period_ns ns"
puts "Result stage: $result_stage"
puts "Implementation status: $implementation_status"
puts "WNS: [get_slack_or_na max] ns"
puts "WHS: [get_slack_or_na min] ns"
puts "Reports: $out_dir"
puts "============================================================"

exit
