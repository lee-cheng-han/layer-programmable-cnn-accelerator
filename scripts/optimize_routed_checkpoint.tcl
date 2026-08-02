if {$argc < 2} {
  puts "Usage: vivado -mode batch -source scripts/optimize_routed_checkpoint.tcl -tclargs <routed-dcp> <output-dir> ?phys-opt-directive?"
  exit 1
}

set routed_checkpoint [lindex $argv 0]
set out_dir [lindex $argv 1]
set phys_opt_directive [expr {$argc >= 3 ? [lindex $argv 2] : "AggressiveExplore"}]
file mkdir $out_dir

open_checkpoint $routed_checkpoint
phys_opt_design -directive $phys_opt_directive
write_checkpoint -force "$out_dir/optimized_routed.dcp"

report_timing_summary -delay_type max -max_paths 20 \
  -file "$out_dir/optimized_setup_summary.rpt"
report_timing_summary -delay_type min -max_paths 20 \
  -file "$out_dir/optimized_hold_summary.rpt"
report_timing -delay_type max -max_paths 200 -nworst 10 \
  -unique_pins -file "$out_dir/optimized_setup_paths.rpt"
report_timing -delay_type min -max_paths 100 -nworst 10 \
  -unique_pins -file "$out_dir/optimized_hold_paths.rpt"
report_utilization -hierarchical -file "$out_dir/optimized_utilization.rpt"
report_control_sets -verbose -file "$out_dir/optimized_control_sets.rpt"
report_high_fanout_nets -timing -load_types -max_nets 100 \
  -file "$out_dir/optimized_high_fanout.rpt"
report_design_analysis -congestion -file "$out_dir/optimized_congestion.rpt"
report_clock_interaction -file "$out_dir/optimized_clock_interaction.rpt"
report_route_status -file "$out_dir/optimized_route_status.rpt"
report_methodology -file "$out_dir/optimized_methodology.rpt"
report_drc -file "$out_dir/optimized_drc.rpt"

puts "Wrote post-route optimized checkpoint and signoff reports to $out_dir"
