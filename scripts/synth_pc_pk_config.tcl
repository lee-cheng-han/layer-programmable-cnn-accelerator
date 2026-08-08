set_param general.maxThreads 8

set part_name xc7z020clg400-1
set top_name compute_slice_benchmark_top
set clock_period_ns 8.000

if {![info exists ::env(PC)] || ![info exists ::env(PK)]} {
 error "PC and PK environment variables are required"
}

set pc $::env(PC)
set pk $::env(PK)
if {[info exists ::env(OUT_DIR)]} {
 set out_dir $::env(OUT_DIR)
} else {
 set out_dir "build/synth_sweep/pc${pc}_pk${pk}"
}

file mkdir $out_dir

set sources [list \
 rtl/postprocess/parallel_bias_add.sv \
 rtl/postprocess/parallel_relu.sv \
 rtl/postprocess/parallel_quantizer.sv \
 rtl/postprocess/parallel_requantizer.sv \
 rtl/postprocess/parallel_saturate.sv \
 rtl/compute/reduction_tree.sv \
 rtl/compute/parallel_mac_array.sv \
 rtl/compute/psum_accumulator.sv \
 rtl/compute/compute_slice_benchmark_top.sv \
]

foreach source $sources {
 read_verilog -sv $source
}

read_xdc constraints/compute_slice_ooc.xdc

synth_design \
 -top $top_name \
 -part $part_name \
 -generic PC=$pc \
 -generic PK=$pk \
 -mode out_of_context \
 -flatten_hierarchy none

report_clocks -file "$out_dir/clocks.rpt"
report_utilization -file "$out_dir/utilization.rpt"
report_utilization -hierarchical -file "$out_dir/utilization_hier.rpt"
report_timing_summary -delay_type max -file "$out_dir/timing_summary.rpt"
report_drc -file "$out_dir/drc.rpt"
write_checkpoint -force "$out_dir/pc${pc}_pk${pk}_synth.dcp"

set timing_paths [get_timing_paths -delay_type max -max_paths 1]
set wns "NA"
if {[llength $timing_paths] > 0} {
 set wns [get_property SLACK [lindex $timing_paths 0]]
}

set metadata [open "$out_dir/metadata.txt" w]
puts $metadata "part=$part_name"
puts $metadata "top=$top_name"
puts $metadata "pc=$pc"
puts $metadata "pk=$pk"
puts $metadata "clock_period_ns=$clock_period_ns"
puts $metadata "wns_ns=$wns"
close $metadata

puts "============================================================"
puts " synthesis complete: PC=$pc PK=$pk"
puts "Part: $part_name"
puts "Clock target: $clock_period_ns ns"
puts "WNS: $wns ns"
puts "Reports: $out_dir"
puts "============================================================"

exit
