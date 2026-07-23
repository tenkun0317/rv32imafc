open_project rv32imac.xpr
set_property top main [get_filesets sim_1]
launch_simulation -mode behavioral -top main
run 200ns
quit