if {[version -short] ne "2024.1"} {error "Vivado 2024.1 required"}
set root [file normalize [lindex $argv 0]]
set kind [lindex $argv 1]
set folder [expr {$kind eq "rtl" ? "03_rtl_project" : "05_gate_project"}]
open_project [file join $root $folder winograd_cnn_${kind}.xpr]
foreach f [get_files -all] {if {![file exists $f]} {error "Missing source: $f"}}
if {[lsearch -exact [get_property verilog_define [get_filesets sim_1]] SUBMISSION_GATE_20] >= 0} {error "20-image define still active"}
puts "PROJECT_CHECK_PASS kind=$kind top=[get_property top [get_filesets sim_1]] version=[version -short] images=1000"
launch_simulation -mode behavioral
run all
close_sim
close_project
puts "SIMULATION_COMPLETED kind=$kind version=[version -short]"
exit
