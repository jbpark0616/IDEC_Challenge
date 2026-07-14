# IDEC CCDC 2026 — CNN Accelerator Build Flow
# Non-project mode: xvlog → xelab → xsim (behavioral sim)
#                   vivado -mode batch (synth, xpr export)
#
# Quick start:
#   make sim              — 1000-image accuracy check (PASS/FAIL)
#   make sim TOP=top_tb   — single-image smoke test
#   make sim WAVE=1       — dump waves.wdb for GUI inspection
#   make synth            — Vivado synth (Zynq FPGA, quick sanity check)
#   make synth-asic       — OpenROAD synth (ASAP7 7nm, competition metric via WSL)
#   make xpr              — export .xpr for competition submission
#   make wave             — open latest waves in Vivado GUI
#   make clean            — wipe build/
#   make help             — this menu

# Force Git Bash on Windows AND add its POSIX tools (rm, mkdir, cp, grep, tee)
# to PATH so GNU Make 3.81 can invoke them via CreateProcess for "simple"
# recipes that bypass SHELL. Short DOS 8.3 path sidesteps Program Files space.
ifeq ($(OS),Windows_NT)
    SHELL := C:/PROGRA~1/Git/usr/bin/bash.exe
    .SHELLFLAGS := -c
    export PATH := C:/PROGRA~1/Git/usr/bin:$(PATH)
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
ASIC_DIR   := $(BUILD)/asic
XPR_DIR    := $(BUILD)/xpr
FLOW       := flow/vivado

# OpenROAD (WSL Ubuntu) — invoked via wsl -d Ubuntu
WSL_DIST         := Ubuntu
ORFS_ROOT        := /home/junbeom/OpenROAD-flow-scripts
ORFS_DESIGN_CFG  := ./designs/asap7/chip/config.mk

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
.PHONY: help sim synth synth-asic xpr wave clean

help:
	@echo "IDEC CCDC 2026 — Available targets:"
	@echo "  make sim [TOP=top_tb|top_tb_1000] [WAVE=1]"
	@echo "                   — behavioral sim; auto PASS/FAIL vs baseline $(BASELINE)%"
	@echo "  make synth       — Vivado synth (FPGA target, quick sanity check)"
	@echo "  make synth-asic  — OpenROAD synth (ASAP7 7nm, competition metric)"
	@echo "                     Runs in WSL $(WSL_DIST) — real numbers for area/timing/power"
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
	@{ grep -A2 -E "WNS|TNS" $(SYNTH_DIR)/timing.rpt || true; } | head -20 || true

# ---------- OpenROAD synthesis (WSL Ubuntu, ASAP7 7nm) ----------
# Produces (under ~/OpenROAD-flow-scripts/flow/{results,reports}/asap7/chip/base/):
#   1_1_yosys.v            — Yosys canonicalized RTL
#   1_synth.v              — post-Yosys netlist (ASAP7 std cells)
#   1_synth.sdc            — post-synth SDC
#   synth_stat.txt         — cell counts + area (from Yosys stat)
#   1_synth_check.txt      — post-synth STA (WNS/TNS, power) — appears after synth-report
#
# Mirrored into build/asic/ on Windows side for convenience.

ORFS_RESULTS := $(ORFS_ROOT)/flow/results/asap7/chip/base
ORFS_REPORTS := $(ORFS_ROOT)/flow/reports/asap7/chip/base

synth-asic:
	@echo "===== OpenROAD synth in WSL ($(WSL_DIST)) ====="
	@mkdir -p $(ASIC_DIR)
	wsl -d $(WSL_DIST) -- bash -c "cd $(ORFS_ROOT) && source ./env.sh && cd flow && time make synth-report DESIGN_CONFIG=$(ORFS_DESIGN_CFG)"
	@echo ""
	@echo "===== Copying artifacts to $(ASIC_DIR) ====="
	wsl -d $(WSL_DIST) -- bash -c "cp -f $(ORFS_RESULTS)/1_*_yosys.v            /mnt/c/IDEC_challenge/$(ASIC_DIR)/netlist.v    2>/dev/null || true; \
	                                cp -f $(ORFS_RESULTS)/1_synth.sdc            /mnt/c/IDEC_challenge/$(ASIC_DIR)/          2>/dev/null || true; \
	                                cp -f $(ORFS_REPORTS)/synth_stat.txt         /mnt/c/IDEC_challenge/$(ASIC_DIR)/          2>/dev/null || true; \
	                                cp -f $(ORFS_REPORTS)/1_Post_synthesis.rpt   /mnt/c/IDEC_challenge/$(ASIC_DIR)/          2>/dev/null || true"
	@echo ""
	@echo "===== Baseline metrics ====="
	@grep -E "^   Chip area for|of which used for sequential" $(ASIC_DIR)/synth_stat.txt 2>/dev/null || echo "(area info missing)"
	@grep -E "^wns max|^tns max|clk period_min" $(ASIC_DIR)/1_Post_synthesis.rpt 2>/dev/null | head -5
	@grep -E "^Total " $(ASIC_DIR)/1_Post_synthesis.rpt 2>/dev/null | head -1

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
