# Winograd CNN timing constraints.
# Time unit: ps in the ASAP7 OpenROAD flow (1000 ps = 1 ns).
current_design chip
create_clock -name clk -period 1000.0000 [get_ports clk]

# All non-clock inputs share the same 200 ps external input delay.
# Wildcards select every bit of each named bus.
set_input_delay 200.0000 -clock [get_clocks clk] -add_delay [get_ports {
    rst_n
    data_in*
    conv1_u*
    conv2_u*
    conv1_bias*
    conv2_bias*
    conv1_requant_multiplier*
    conv2_requant_multiplier*
    fc_weight*
    fc_bias*
}]

# Classification outputs share the same 200 ps external output delay.
set_output_delay 200.0000 -clock [get_clocks clk] -add_delay [get_ports {
    decision*
    valid_out_6
}]
