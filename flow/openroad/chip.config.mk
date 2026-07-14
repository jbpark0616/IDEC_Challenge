export PLATFORM               = asap7

export DESIGN_NAME            = chip
export DESIGN_NICKNAME        = chip

# Point directly at Windows-side verilog/ so we have a single source of truth
# for RTL across Vivado sim (Windows) and OpenROAD synth (WSL).
# Exclude top_tb.v (simulation-only, not synthesizable).
export VERILOG_FILES = $(filter-out %/top_tb.v, $(wildcard /mnt/c/IDEC_challenge/verilog/*.v))

# Constraint file stays with the platform-specific dir (competition provided)
export SDC_FILE      = $(DESIGN_HOME)/$(PLATFORM)/$(DESIGN_NICKNAME)/constraint.sdc

export ABC_AREA                 = 1

export CORE_UTILIZATION         = 40
export CORE_ASPECT_RATIO        = 1
export CORE_MARGIN              = 2
export PLACE_DENSITY            = 0.65
export TNS_END_PERCENT          = 100
export EQUIVALENCE_CHECK       ?=   1
export REMOVE_CELLS_FOR_EQY     = TAPCELL*
