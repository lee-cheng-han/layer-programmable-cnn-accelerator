if {$argc < 2} {
  puts "Usage: vivado -mode batch -source scripts/report_checkpoint.tcl -tclargs <checkpoint> <output-prefix>"
  exit 1
}

set checkpoint [lindex $argv 0]
set output_prefix [lindex $argv 1]

open_checkpoint $checkpoint
report_timing_summary -delay_type min_max -max_paths 10 \
  -file ${output_prefix}_timing_summary.rpt
report_timing -delay_type max -max_paths 20 -nworst 5 \
  -file ${output_prefix}_critical_paths.rpt
report_utilization -hierarchical -file ${output_prefix}_utilization.rpt
report_control_sets -verbose -file ${output_prefix}_control_sets.rpt

puts "Wrote checkpoint reports with prefix ${output_prefix}"
