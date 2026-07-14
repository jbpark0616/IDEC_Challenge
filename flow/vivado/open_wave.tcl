# Open a waveform database in Vivado's waveform viewer
# Invoked by: vivado -source open_wave.tcl -tclargs <path/to/waves.wdb>
if {[llength $argv] < 1} {
    puts "ERROR: Usage: vivado -source open_wave.tcl -tclargs <wdb>"
    exit 1
}
open_wave_database [lindex $argv 0]
