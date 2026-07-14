# IDEC CCDC 2026 — CNN Accelerator Build Flow
# Non-project mode: xvlog → xelab → xsim (behavioral sim)
#                   vivado -mode batch (synth, xpr export)
#
# Quick start:
#   make sim              — 1000-image accuracy check (PASS/FAIL)
#   make sim TB=top_tb    — single-image smoke test
#   make sim WAVE=1       — dump waves.wdb for GUI inspection
#   make synth            — synthesize chip, report timing/area/power
#   make xpr              — export .xpr for competition submission
#   make wave             — open latest waves in Vivado GUI
#   make clean            — wipe build/
#   make help             — this menu

# Force Git Bash on Windows — otherwise WSL bash or cmd.exe may be picked
# depending on the invoking shell, breaking mkdir -p / && / etc.
ifeq ($(OS),Windows_NT)
    SHELL := C:/Program Files/Git/usr/bin/bash.exe
else
    SHELL := /bin/bash
endif
.DELETE_ON_ERROR:

# ---------- Tool paths ----------
VIVADO_BIN ?= C:/AMDDesignTools/2025.2/Vivado/bin
XVLOG      := $(VIVADO_BIN)/xvlog
XELAB      := $(VIVADO_BIN)/xelab
XSIM       := $(VIVADO_BIN)/xsim
VIVADO     := $(VIVADO_BIN)/vivado

# ---------- Paths ----------
BUILD      := build
SIM_DIR    := $(BUILD)/sim
SYNTH_DIR  := $(BUILD)/synth
XPR_DIR    := $(BUILD)/xpr
FLOW       := flow/vivado

RTL := verilog/chip.v \
       verilog/conv1.v \
       verilog/conv2.v \
       verilog/fc.v \
       verilog/maxpool_relu.v \
       verilog/comparator.v
TB  := verilog/top_tb.v

# ---------- Config (override on CLI) ----------
# TB=top_tb_1000 (default, 1000-image accuracy) or TB=top_tb (single image smoke test)
TOP        ?= top_tb_1000
WAVE       ?= 0
BASELINE   ?= 96.0

# Log destination (unique per TOP so results don't clobber)
LOG := $(SIM_DIR)/$(TOP).log

# ---------- Targets ----------
.PHONY: help sim synth xpr wave clean

help:
	@echo "IDEC CCDC 2026 — Available targets:"
	@echo "  make sim [TOP=top_tb|top_tb_1000] [WAVE=1]"
	@echo "                   — behavioral sim; auto PASS/FAIL vs baseline $(BASELINE)%"
	@echo "  make synth       — synthesize chip → $(SYNTH_DIR)/{timing,utilization,power}.rpt"
	@echo "  make xpr         — export $(XPR_DIR)/exported.xpr for submission"
	@echo "  make wave        — open latest waves.wdb in Vivado GUI"
	@echo "  make clean       — remove $(BUILD)/"
	@echo ""
	@echo "  Vars: TOP=$(TOP)  WAVE=$(WAVE)  BASELINE=$(BASELINE)"
	@echo "        VIVADO_BIN=$(VIVADO_BIN)"

# ---------- Simulation ----------
# Non-project xsim flow: compile → elaborate → run → parse log
sim: $(LOG)
	@python scripts/check_accuracy.py $(LOG) --baseline $(BASELINE)

$(LOG): $(RTL) $(TB) $(FLOW)/sim.tcl $(FLOW)/sim_wave.tcl
	@mkdir -p $(SIM_DIR)
	@echo "===== [xvlog] compile ====="
	cd $(SIM_DIR) && $(XVLOG) $(addprefix ../../,$(RTL)) ../../$(TB)
	@echo "===== [xelab] elaborate (top=$(TOP), WAVE=$(WAVE)) ====="
	cd $(SIM_DIR) && $(XELAB) -top $(TOP) -snapshot $(TOP)_snap \
	    -timescale 1ps/1ps \
	    $(if $(filter 1,$(WAVE)),-debug typical,)
	@echo "===== [xsim] run ====="
	cd $(SIM_DIR) && $(XSIM) $(TOP)_snap \
	    -t ../../$(FLOW)/$(if $(filter 1,$(WAVE)),sim_wave,sim).tcl \
	    2>&1 | tee $(notdir $@)

wave:
	@if [ ! -f $(SIM_DIR)/$(TOP)_snap.wdb ]; then \
	    echo "No wave DB. Run: make sim WAVE=1"; exit 1; \
	fi
	$(VIVADO) -source $(FLOW)/open_wave.tcl -tclargs $(SIM_DIR)/$(TOP)_snap.wdb &

# ---------- Synthesis ----------
synth: $(SYNTH_DIR)/timing.rpt

$(SYNTH_DIR)/timing.rpt: $(RTL) flow/constraints/timing.xdc $(FLOW)/synth.tcl
	@mkdir -p $(SYNTH_DIR)
	$(VIVADO) -mode batch -source $(FLOW)/synth.tcl -tclargs $(SYNTH_DIR) \
	    -log $(SYNTH_DIR)/vivado.log -journal $(SYNTH_DIR)/vivado.jou
	@echo ""
	@echo "===== Timing summary ====="
	@grep -A2 -E "WNS|TNS" $(SYNTH_DIR)/timing.rpt | head -20 || true

# ---------- XPR export (for submission) ----------
xpr: $(XPR_DIR)/exported.xpr

$(XPR_DIR)/exported.xpr: $(RTL) $(TB) flow/constraints/timing.xdc $(FLOW)/export_xpr.tcl
	@mkdir -p $(XPR_DIR)
	$(VIVADO) -mode batch -source $(FLOW)/export_xpr.tcl -tclargs $(XPR_DIR) \
	    -log $(XPR_DIR)/vivado.log -journal $(XPR_DIR)/vivado.jou

# ---------- Cleanup ----------
clean:
	rm -rf $(BUILD)
	@echo "Cleaned $(BUILD)/"
