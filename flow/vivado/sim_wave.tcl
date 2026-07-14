# Non-project mode simulation runner with waveform dump
# Invoked by: xsim <snapshot> -t sim_wave.tcl
# Produces: waves.wdb in the current xsim run directory
log_wave -recursive *
run all
quit
