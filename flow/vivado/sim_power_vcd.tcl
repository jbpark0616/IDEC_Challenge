# Gate-level activity capture for one complete inference.
#
# Recording every combinational pin in the flattened 11 MB netlist makes XSim
# spend excessive time merely registering waveform objects.  Primary DUT
# signals and sequential-cell outputs are sufficient state boundaries: OpenSTA
# annotates these measured activities and propagates activity through the
# intervening combinational cells for power calculation.
open_vcd activity.vcd

# Generated before elaboration from the Yosys netlist and ASAP7 functional
# library.  It contains primary ports plus hierarchical output-pin paths for
# every standard-cell instance, which OpenSTA can map directly.
set object_file [open power_objects.txt r]
set power_signals [split [string trim [read $object_file]] "\n"]
close $object_file
puts "Power VCD objects: [llength $power_signals]"
log_vcd $power_signals
run all
close_vcd
quit
