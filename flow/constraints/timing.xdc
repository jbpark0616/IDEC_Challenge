# Timing constraints for chip
# Baseline clock: 100 MHz (10 ns period)
# TB uses "always #5 clk = ~clk;" → 100 MHz — matches this.
create_clock -name clk -period 10.000 [get_ports clk]

# Async reset — false path from rst_n to all sync elements
set_false_path -from [get_ports rst_n]
