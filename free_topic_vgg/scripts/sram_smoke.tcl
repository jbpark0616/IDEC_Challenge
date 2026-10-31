# Run from free_topic_vgg. Isolated read/link/floorplan check, not routed PPA.
set root $::env(ORFS_ROOT)
set macro srambank_256x4x64_6t122
set vendor third_party/asap7_sram/generated
read_lef $root/flow/platforms/asap7/lef/asap7_tech_1x_201209.lef
read_lef $root/flow/platforms/asap7/lef/asap7sc7p5t_28_R_1x_220121a.lef
read_lef $vendor/LEF/$macro.lef
read_liberty $vendor/LIB/$macro.lib
read_verilog artifacts/sram_smoke/netlist.v
link_design vgg_sram_8k
initialize_floorplan -site asap7sc7p5t -die_area {0 0 60 110} -core_area {5 5 55 105}
set db [ord::get_db]
set block [[$db getChip] getBlock]
set instances [$block getInsts]
if {[llength $instances] != 1} { error "Expected exactly one SRAM instance" }
set inst [lindex $instances 0]
set master [$inst getMaster]
if {[$master getName] ne $macro || ![$master isBlock]} {
    error "SRAM was not preserved as a BLOCK macro"
}
$inst setOrient R0
set dbu [$block getDbUnitsPerMicron]
$inst setLocation [expr {10 * $dbu}] [expr {10 * $dbu}]
$inst setPlacementStatus FIRM
write_db artifacts/sram_smoke/macro.odb
write_def artifacts/sram_smoke/macro.def
puts "PASS OpenROAD: one BLOCK SRAM, master=[$master getName], DBU/um=[$block getDbUnitsPerMicron], width=[$master getWidth], height=[$master getHeight]"
