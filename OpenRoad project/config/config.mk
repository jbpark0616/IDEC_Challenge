# Canonical designated-topic b1_g1 configuration (WSL).
export PROJECT_ROOT ?= /mnt/c/IDEC_challenge
include $(PROJECT_ROOT)/flow/openroad/designated_final.mk
export VERILOG_DEFINES = -DOPENROAD_CLKGATE
export DONT_USE_CELLS = *x1p*_ASAP7* *xp*_ASAP7* SDF*
