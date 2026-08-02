if {$argc < 2} {
  puts "Usage: vivado -mode batch -source scripts/implement_checkpoint.tcl -tclargs <synth-dcp> <output-dir> ?place-directive? ?route-directive?"
  exit 1
}

set synth_checkpoint [lindex $argv 0]
set out_dir [lindex $argv 1]
set place_directive ""
set route_directive ""
if {$argc >= 3} {
  set place_directive [lindex $argv 2]
}
if {$argc >= 4} {
  set route_directive [lindex $argv 3]
}
file mkdir $out_dir

proc write_physical_reports {out_dir stage} {
  set prefix "$out_dir/$stage"

  report_timing_summary -delay_type max -max_paths 20 \
    -file "${prefix}_setup_summary.rpt"
  report_timing_summary -delay_type min -max_paths 20 \
    -file "${prefix}_hold_summary.rpt"
  report_timing -delay_type max -max_paths 200 -nworst 10 \
    -unique_pins -file "${prefix}_setup_paths.rpt"
  report_timing -delay_type min -max_paths 100 -nworst 10 \
    -unique_pins -file "${prefix}_hold_paths.rpt"
  report_utilization -hierarchical -file "${prefix}_utilization.rpt"
  report_control_sets -verbose -file "${prefix}_control_sets.rpt"
  report_high_fanout_nets -timing -load_types -max_nets 100 \
    -file "${prefix}_high_fanout.rpt"
  report_design_analysis -congestion -file "${prefix}_congestion.rpt"
  report_clock_interaction -file "${prefix}_clock_interaction.rpt"
  report_methodology -file "${prefix}_methodology.rpt"
  report_drc -file "${prefix}_drc.rpt"
}

open_checkpoint $synth_checkpoint
opt_design
if {$place_directive eq ""} {
  place_design
} else {
  place_design -directive $place_directive
}
phys_opt_design
write_checkpoint -force "$out_dir/placed.dcp"
write_physical_reports $out_dir placed

if {$route_directive eq ""} {
  route_design
} else {
  route_design -directive $route_directive
}
write_checkpoint -force "$out_dir/routed.dcp"
report_route_status -file "$out_dir/routed_route_status.rpt"
write_physical_reports $out_dir routed

puts "Wrote placed and routed baseline checkpoints and reports to $out_dir"
