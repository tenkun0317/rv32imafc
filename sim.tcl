open_project rv32imafc.xpr
set_property top main [get_filesets sim_1]
launch_simulation -mode behavioral
log_wave -name wave -radix hex -r /main/u_alu/*
run 200ns
quit