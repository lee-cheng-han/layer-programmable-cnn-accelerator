if {$argc < 2} {
  puts "Usage: vivado -mode batch -source scripts/route_checkpoint.tcl -tclargs <placed-dcp> <output-dir> ?route-directive? ?phys-opt-directive?"
  exit 1
}

set placed_checkpoint [lindex $argv 0]
set out_dir [lindex $argv 1]
set route_directive [expr {$argc >= 3 ? [lindex $argv 2] : ""}]
set phys_opt_directive [expr {$argc >= 4 ? [lindex $argv 3] : "AggressiveExplore"}]
file mkdir $out_dir

proc write_route_reports {out_dir} {
  report_timing_summary -delay_type max -max_paths 20 \
    -file "$out_dir/routed_setup_summary.rpt"
  report_timing_summary -delay_type min -max_paths 20 \
    -file "$out_dir/routed_hold_summary.rpt"
  report_timing -delay_type max -max_paths 200 -nworst 10 \
    -unique_pins -file "$out_dir/routed_setup_paths.rpt"
  report_timing -delay_type min -max_paths 100 -nworst 10 \
    -unique_pins -file "$out_dir/routed_hold_paths.rpt"
  report_utilization -hierarchical -file "$out_dir/routed_utilization.rpt"
  report_control_sets -verbose -file "$out_dir/routed_control_sets.rpt"
  report_high_fanout_nets -timing -load_types -max_nets 100 \
    -file "$out_dir/routed_high_fanout.rpt"
  report_design_analysis -congestion -file "$out_dir/routed_congestion.rpt"
  report_clock_interaction -file "$out_dir/routed_clock_interaction.rpt"
  report_route_status -file "$out_dir/routed_route_status.rpt"
  report_methodology -file "$out_dir/routed_methodology.rpt"
  report_drc -file "$out_dir/routed_drc.rpt"
}

open_checkpoint $placed_checkpoint
if {$route_directive eq ""} {
  route_design
} else {
  route_design -directive $route_directive
}
phys_opt_design -directive $phys_opt_directive
write_checkpoint -force "$out_dir/routed.dcp"
write_route_reports $out_dir

puts "Wrote routed checkpoint and signoff reports to $out_dir"
