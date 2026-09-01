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

# RTL sources for the competition-interface Winograd chip.
set rtl_names {
    chip.v
    elastic_fifo.v
    winograd_sliding_window_generator.v
    winograd_sequential_frame_buffer.v
    winograd_input_transform.v
    winograd_v_replay_buffer.v
    winograd_mac_array.v
    winograd_m_fifo.v
    winograd_output_transform.v
    winograd_postprocess.v
    winograd_conv_core.v
    pipelined_argmax10.v
    winograd_cnn_accelerator.v
}
foreach name $rtl_names {
    add_files -norecurse [file join $proj_root verilog $name]
}
set_property top chip [current_fileset]

# Testbench → sim fileset
add_files -fileset sim_1 -norecurse \
    $proj_root/verification/winograd_chip_1000_tb.v
set_property top winograd_chip_1000_tb [get_filesets sim_1]

# Constraints
add_files -fileset constrs_1 -norecurse $proj_root/flow/constraints/timing.xdc

update_compile_order -fileset sources_1
close_project

puts "===== DONE ====="
puts "Exported project: $build_dir/exported.xpr"
