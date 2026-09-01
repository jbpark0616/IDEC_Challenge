set clk_name  clk
set clk_port_name clk

# Report/submission runs target 1 GHz by default.  A tighter period can be
# supplied from the build flow (for example 400 ps for Fmax characterization)
# without editing this source-of-truth constraint file.
if {[info exists ::env(ASIC_CLK_PERIOD_PS)]} {
    set clk_period $::env(ASIC_CLK_PERIOD_PS)
} else {
    set clk_period 1000
}

if {[info exists ::env(ASIC_CLK_IO_PCT)]} {
    set clk_io_pct $::env(ASIC_CLK_IO_PCT)
} else {
    set clk_io_pct 0.2
}

set clk_port [get_ports $clk_port_name]

create_clock -name $clk_name -period $clk_period $clk_port

set non_clock_inputs [lsearch -inline -all -not -exact [all_inputs] $clk_port]

set_input_delay  [expr $clk_period * $clk_io_pct] -clock $clk_name $non_clock_inputs 
set_output_delay [expr $clk_period * $clk_io_pct] -clock $clk_name [all_outputs]
