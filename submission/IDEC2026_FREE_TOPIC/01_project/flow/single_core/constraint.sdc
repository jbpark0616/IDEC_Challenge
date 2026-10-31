create_clock -name clk -period 1000 [get_ports clk]
set inputs [lsearch -inline -all -not -exact [all_inputs] clk]
set_input_delay 200 -clock clk $inputs
set_output_delay 200 -clock clk [all_outputs]
