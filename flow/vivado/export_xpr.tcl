# Export a Vivado .xpr project from RTL sources — for competition submission
# Invoked by: vivado -mode batch -source export_xpr.tcl -tclargs <build_dir>
#
# Produces: $build_dir/exported.xpr

if {[llength $argv] < 1} {
    puts "ERROR: Usage: vivado -mode batch -source export_xpr.tcl -tclargs <build_dir>"
    exit 1
}
set build_dir [lindex $argv 0]
file mkdir $build_dir

set proj_root [file normalize [file join [file dirname [info script]] ../..]]

create_project -force exported $build_dir -part xck26-sfvc784-2LV-c

# RTL sources
foreach f [glob -directory $proj_root/verilog chip.v conv1.v conv2.v fc.v maxpool_relu.v comparator.v] {
    add_files -norecurse $f
}
set_property top chip [current_fileset]

# Testbench → sim fileset
add_files -fileset sim_1 -norecurse $proj_root/verilog/top_tb.v
set_property top top_tb_1000 [get_filesets sim_1]

# Constraints
add_files -fileset constrs_1 -norecurse $proj_root/flow/constraints/timing.xdc

update_compile_order -fileset sources_1
close_project

puts "===== DONE ====="
puts "Exported project: $build_dir/exported.xpr"
