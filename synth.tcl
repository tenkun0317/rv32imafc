create_project rv32imac_synth rv32imac_synth -part xc7a100tcsg324-1 -force

set src_dir [file normalize "rv32imac.src/sources_1"]
set files [list \
    top.sv ex.sv id.sv if.sv mem.sv wb.sv csr.sv reg.sv alu.sv div.sv mul.sv unified_bram.sv \
]

foreach f $files {
    add_files -norecurse [file join $src_dir $f]
}

read_xdc [file join "rv32imac.src" constrs_1 pins.xdc]

set_property top top [current_fileset]

launch_runs synth_1 -jobs 8
wait_on_run synth_1

open_run synth_1 -name synth_1

report_utilization -hierarchical -file synth_util.rpt
report_timing_summary -file synth_timing.rpt
puts "=== POST-SYNTHESIS UTILIZATION ==="
report_utilization
puts "=== POST-SYNTHESIS TIMING ==="
report_timing_summary -max_paths 5

puts "Running implementation..."

opt_design
place_design
phys_opt_design
route_design

report_utilization -hierarchical -file impl_util.rpt
report_timing_summary -file impl_timing.rpt

puts "=== POST-IMPLEMENTATION UTILIZATION ==="
report_utilization
puts "=== POST-IMPLEMENTATION TIMING ==="
report_timing_summary -max_paths 5
puts "Implementation complete."
exit