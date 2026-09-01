# IDEC CCDC 2026 — CNN Accelerator Build Flow
# Non-project mode: xvlog → xelab → xsim (behavioral sim)
#                   vivado -mode batch (synth, xpr export)
#
# Quick start:
#   make sim-chip-winograd-1000 — 1000-image accuracy regression
#   make synth            — Vivado synth (Zynq FPGA, quick sanity check)
#   make synth-asic       — OpenROAD synth (ASAP7 7nm, competition metric via WSL)
#   make xpr              — export .xpr for competition submission
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
ORFS_SDC         := $(ORFS_ROOT)/flow/designs/asap7/chip/constraint.sdc

MAC_RTL := verilog/winograd_mac_array.v
MAC_TB  := verification/winograd_mac_array_tb.v
TRANSFORM_RTL := verilog/winograd_input_transform.v
TRANSFORM_TB  := verification/winograd_input_transform_tb.v
OUTPUT_TRANSFORM_RTL := verilog/winograd_output_transform.v
OUTPUT_TRANSFORM_TB  := verification/winograd_output_transform_tb.v
POSTPROCESS_RTL := verilog/winograd_postprocess.v
POSTPROCESS_TB  := verification/winograd_postprocess_tb.v
FIFO_RTL := verilog/elastic_fifo.v
FIFO_TB  := verification/elastic_fifo_tb.v
V_REPLAY_RTL := verilog/winograd_v_replay_buffer.v
V_REPLAY_TB  := verification/winograd_v_replay_buffer_tb.v
WINOGRAD_CORE_RTL := verilog/elastic_fifo.v \
                     verilog/winograd_input_transform.v \
                     verilog/winograd_v_replay_buffer.v \
                     verilog/winograd_mac_array.v \
                     verilog/winograd_m_fifo.v \
                     verilog/winograd_output_transform.v \
                     verilog/winograd_postprocess.v \
                     verilog/winograd_conv_core.v
WINOGRAD_CORE_TB := verification/winograd_conv_core_tb.v
WINDOW_GENERATOR_RTL := verilog/winograd_sliding_window_generator.v
WINDOW_GENERATOR_TB  := verification/winograd_sliding_window_generator_tb.v
CNN_ACCELERATOR_RTL := verilog/winograd_sliding_window_generator.v \
                verilog/winograd_sequential_frame_buffer.v \
                $(WINOGRAD_CORE_RTL) \
                verilog/pipelined_argmax10.v \
                verilog/winograd_cnn_accelerator.v
CNN_ACCELERATOR_TB := verification/winograd_cnn_accelerator_tb.v
CNN_ACCELERATOR_REAL_TB := verification/winograd_cnn_accelerator_real_tb.v
WINOGRAD_CHIP_RTL := verilog/chip.v \
                $(CNN_ACCELERATOR_RTL)
WINOGRAD_CHIP_1000_TB := verification/winograd_chip_1000_tb.v
ASAP7_SIM_LIB_ARGS := "../../../OpenRoad project/std_cell/asap7sc7p5t_AO_RVT_TT_201020.v" \
                      "../../../OpenRoad project/std_cell/asap7sc7p5t_INVBUF_RVT_TT_201020.v" \
                      "../../../OpenRoad project/std_cell/asap7sc7p5t_OA_RVT_TT_201020.v" \
                      "../../../OpenRoad project/std_cell/asap7sc7p5t_SEQ_RVT_TT_220101.v" \
                      "../../../OpenRoad project/std_cell/asap7sc7p5t_SIMPLE_RVT_TT_201020.v" \
                      "../../../OpenRoad project/std_cell/empty.v"
ASAP7_FUNCTIONAL_LIB := verification/asap7_functional_cells.v
WINOGRAD_CHIP_NETLIST := build/asic/chip/netlist.v

# ---------- Config (override on CLI) ----------
SYNTH_TOP  ?= chip
SYNTH_RTL  ?= $(wildcard verilog/*.v)
ASIC_TOP   ?= chip
ASIC_RTL   ?=
ASIC_VARIANT ?= target_1ghz
ASIC_CLK_PERIOD_PS ?= 1000
ASIC_CLK_IO_PCT ?= 0.2
FIFO_DEPTH ?= 2
V_REPLAY_DEPTH ?= 2
M_FIFO_DEPTH ?= 1

SYNTH_OUT := $(SYNTH_DIR)/$(SYNTH_TOP)
ASIC_OUT  := $(ASIC_DIR)/$(ASIC_TOP)

ifneq ($(strip $(ASIC_RTL)),)
    ASIC_RTL_WSL := $(subst C:/,/mnt/c/,$(abspath $(ASIC_RTL)))
    ASIC_RTL_ARG := VERILOG_FILES='$(ASIC_RTL_WSL)'
endif

# ---------- Targets ----------
.PHONY: help sim-mac sim-transform sim-output-transform sim-postprocess sim-fifo sim-v-replay sim-core sim-window-generator sim-accelerator sim-accelerator-real sim-chip-winograd-1000 sim-chip-winograd-fifo-trace sim-chip-winograd-lifetime-trace sim-chip-winograd-gate-1000 sim-chip-winograd-gate-power sim-two-conv sim-two-conv-real synth synth-mac synth-asic synth-asic-fmax power-asic-activity xpr clean

help:
	@echo "IDEC CCDC 2026 — Available targets:"
	@echo "  make sim-mac     — unit test the 16-way Winograd/FC MAC array"
	@echo "  make sim-transform — unit test the Winograd activation transform"
	@echo "  make sim-output-transform — unit test the Winograd output transform"
	@echo "  make sim-postprocess — unit test fused bias/ReLU/max-pool/requant"
	@echo "  make sim-fifo       — unit test the generic elastic FIFO"
	@echo "  make sim-v-replay   — unit test the Winograd V replay circular buffer"
	@echo "  make sim-core       — end-to-end test the integrated Winograd conv core"
	@echo "  make sim-window-generator — unit test streaming 4x4 sliding window generator"
	@echo "  make sim-accelerator — test the complete Winograd CNN accelerator"
	@echo "  make sim-accelerator-real — compare real INT4 CNN against Python golden"
	@echo "  make sim-chip-winograd-1000 FIFO_DEPTH=2 V_REPLAY_DEPTH=2 M_FIFO_DEPTH=2"
	@echo "                   — competition-interface 1000-image regression/depth sweep"
	@echo "  make sim-chip-winograd-fifo-trace FIFO_DEPTH=2 — one-image FIFO trace CSV"
	@echo "  make sim-chip-winograd-lifetime-trace — one-image activation lifetime CSV"
	@echo "  make sim-chip-winograd-gate-1000 — ASAP7 post-synthesis 1000-image regression"
	@echo "  make sim-chip-winograd-gate-power — one-image gate VCD for power analysis"
	@echo "  make synth [SYNTH_TOP=chip] [SYNTH_RTL=\"file ...\"]"
	@echo "                   — generic Vivado synthesis sanity check"
	@echo "  make synth-mac   — shorthand for SYNTH_TOP=winograd_mac_array"
	@echo "  make synth-asic [ASIC_TOP=chip] [ASIC_CLK_PERIOD_PS=1000]"
	@echo "                   — generic OpenROAD ASAP7 synthesis"
	@echo "  make synth-asic-fmax — 400 ps stress constraint for Fmax characterization"
	@echo "  make power-asic-activity — annotate one-image gate VCD and report power"
	@echo "                     Runs in WSL $(WSL_DIST) — real numbers for area/timing/power"
	@echo "  make xpr         — export $(XPR_DIR)/exported.xpr for submission"
	@echo "  make clean       — remove $(BUILD)/"
	@echo ""
	@echo "  Vars: SYNTH_TOP=$(SYNTH_TOP)  ASIC_TOP=$(ASIC_TOP)"
	@echo "        VIVADO_BIN=$(VIVADO_BIN)"

# ---------- Simulation ----------
sim-mac: $(MAC_RTL) $(MAC_TB) $(FLOW)/sim.tcl
	@mkdir -p $(SIM_DIR)/mac
	@echo "===== [xvlog] MAC unit test compile ====="
	cd $(SIM_DIR)/mac && $(XVLOG) ../../../$(MAC_RTL) ../../../$(MAC_TB)
	@echo "===== [xelab] MAC unit test elaborate ====="
	cd $(SIM_DIR)/mac && $(XELAB) -top winograd_mac_array_tb -snapshot mac_tb_snap
	@echo "===== [xsim] MAC unit test run ====="
	cd $(SIM_DIR)/mac && $(XSIM) mac_tb_snap -t ../../../$(FLOW)/sim.tcl

sim-transform: $(TRANSFORM_RTL) $(TRANSFORM_TB) $(FLOW)/sim.tcl
	@mkdir -p $(SIM_DIR)/transform
	@echo "===== [xvlog] input-transform unit test compile ====="
	cd $(SIM_DIR)/transform && $(XVLOG) ../../../$(TRANSFORM_RTL) ../../../$(TRANSFORM_TB)
	@echo "===== [xelab] input-transform unit test elaborate ====="
	cd $(SIM_DIR)/transform && $(XELAB) -top winograd_input_transform_tb -snapshot transform_tb_snap
	@echo "===== [xsim] input-transform unit test run ====="
	cd $(SIM_DIR)/transform && $(XSIM) transform_tb_snap -t ../../../$(FLOW)/sim.tcl

sim-output-transform: $(OUTPUT_TRANSFORM_RTL) $(OUTPUT_TRANSFORM_TB) $(FLOW)/sim.tcl
	@mkdir -p $(SIM_DIR)/output_transform
	@echo "===== [xvlog] output-transform unit test compile ====="
	cd $(SIM_DIR)/output_transform && $(XVLOG) ../../../$(OUTPUT_TRANSFORM_RTL) ../../../$(OUTPUT_TRANSFORM_TB)
	@echo "===== [xelab] output-transform unit test elaborate ====="
	cd $(SIM_DIR)/output_transform && $(XELAB) -top winograd_output_transform_tb -snapshot output_transform_tb_snap
	@echo "===== [xsim] output-transform unit test run ====="
	cd $(SIM_DIR)/output_transform && $(XSIM) output_transform_tb_snap -t ../../../$(FLOW)/sim.tcl

sim-postprocess: $(POSTPROCESS_RTL) $(POSTPROCESS_TB) $(FLOW)/sim.tcl
	@mkdir -p $(SIM_DIR)/postprocess
	@echo "===== [xvlog] postprocess unit test compile ====="
	cd $(SIM_DIR)/postprocess && $(XVLOG) ../../../$(POSTPROCESS_RTL) ../../../$(POSTPROCESS_TB)
	@echo "===== [xelab] postprocess unit test elaborate ====="
	cd $(SIM_DIR)/postprocess && $(XELAB) -top winograd_postprocess_tb -snapshot postprocess_tb_snap
	@echo "===== [xsim] postprocess unit test run ====="
	cd $(SIM_DIR)/postprocess && $(XSIM) postprocess_tb_snap -t ../../../$(FLOW)/sim.tcl

sim-fifo: $(FIFO_RTL) $(FIFO_TB) $(FLOW)/sim.tcl
	@mkdir -p $(SIM_DIR)/fifo
	@echo "===== [xvlog] elastic FIFO unit test compile ====="
	cd $(SIM_DIR)/fifo && $(XVLOG) ../../../$(FIFO_RTL) ../../../$(FIFO_TB)
	@echo "===== [xelab] elastic FIFO unit test elaborate ====="
	cd $(SIM_DIR)/fifo && $(XELAB) -top elastic_fifo_tb -snapshot fifo_tb_snap
	@echo "===== [xsim] elastic FIFO unit test run ====="
	cd $(SIM_DIR)/fifo && $(XSIM) fifo_tb_snap -t ../../../$(FLOW)/sim.tcl

sim-v-replay: $(V_REPLAY_RTL) $(V_REPLAY_TB) $(FLOW)/sim.tcl
	@mkdir -p $(SIM_DIR)/v_replay
	@echo "===== [xvlog] V replay CB unit test compile ====="
	cd $(SIM_DIR)/v_replay && $(XVLOG) ../../../$(V_REPLAY_RTL) ../../../$(V_REPLAY_TB)
	@echo "===== [xelab] V replay CB unit test elaborate ====="
	cd $(SIM_DIR)/v_replay && $(XELAB) -top winograd_v_replay_buffer_tb -snapshot v_replay_tb_snap
	@echo "===== [xsim] V replay CB unit test run ====="
	cd $(SIM_DIR)/v_replay && $(XSIM) v_replay_tb_snap -t ../../../$(FLOW)/sim.tcl

sim-core: $(WINOGRAD_CORE_RTL) $(WINOGRAD_CORE_TB) $(FLOW)/sim.tcl
	@mkdir -p $(SIM_DIR)/winograd_core
	@echo "===== [xvlog] integrated Winograd core compile ====="
	cd $(SIM_DIR)/winograd_core && $(XVLOG) $(addprefix ../../../,$(WINOGRAD_CORE_RTL)) ../../../$(WINOGRAD_CORE_TB)
	@echo "===== [xelab] integrated Winograd core elaborate ====="
	cd $(SIM_DIR)/winograd_core && $(XELAB) -top winograd_conv_core_tb -snapshot winograd_core_tb_snap
	@echo "===== [xsim] integrated Winograd core run ====="
	cd $(SIM_DIR)/winograd_core && $(XSIM) winograd_core_tb_snap -t ../../../$(FLOW)/sim.tcl

sim-window-generator: $(WINDOW_GENERATOR_RTL) $(WINDOW_GENERATOR_TB) $(FLOW)/sim.tcl
	@echo "===== [xvlog] streaming window-generator unit test compile ====="
	mkdir -p $(SIM_DIR)/window_generator
	cd $(SIM_DIR)/window_generator && $(XVLOG) ../../../$(WINDOW_GENERATOR_RTL) ../../../$(WINDOW_GENERATOR_TB)
	@echo "===== [xelab] streaming window-generator unit test elaborate ====="
	cd $(SIM_DIR)/window_generator && $(XELAB) -top winograd_sliding_window_generator_tb -snapshot window_generator_tb_snap
	@echo "===== [xsim] streaming window-generator unit test run ====="
	cd $(SIM_DIR)/window_generator && $(XSIM) window_generator_tb_snap -t ../../../$(FLOW)/sim.tcl

sim-accelerator sim-two-conv: $(CNN_ACCELERATOR_RTL) $(CNN_ACCELERATOR_TB) $(FLOW)/sim.tcl
	@mkdir -p $(SIM_DIR)/accelerator
	@echo "===== [xvlog] CNN accelerator test compile ====="
	cd $(SIM_DIR)/accelerator && $(XVLOG) $(addprefix ../../../,$(CNN_ACCELERATOR_RTL)) ../../../$(CNN_ACCELERATOR_TB)
	@echo "===== [xelab] CNN accelerator test elaborate ====="
	cd $(SIM_DIR)/accelerator && $(XELAB) -top winograd_cnn_accelerator_tb -snapshot accelerator_tb_snap
	@echo "===== [xsim] CNN accelerator test run ====="
	cd $(SIM_DIR)/accelerator && $(XSIM) accelerator_tb_snap -t ../../../$(FLOW)/sim.tcl

sim-accelerator-real sim-two-conv-real: $(CNN_ACCELERATOR_RTL) $(CNN_ACCELERATOR_REAL_TB) $(FLOW)/sim.tcl
	@mkdir -p $(SIM_DIR)/accelerator_real
	@echo "===== [xvlog] real exported-model CNN accelerator test compile ====="
	cd $(SIM_DIR)/accelerator_real && $(XVLOG) $(addprefix ../../../,$(CNN_ACCELERATOR_RTL)) ../../../$(CNN_ACCELERATOR_REAL_TB)
	@echo "===== [xelab] real exported-model CNN accelerator test elaborate ====="
	cd $(SIM_DIR)/accelerator_real && $(XELAB) -top winograd_cnn_accelerator_real_tb -snapshot accelerator_real_tb_snap
	@echo "===== [xsim] real exported-model CNN accelerator test run ====="
	cd $(SIM_DIR)/accelerator_real && $(XSIM) accelerator_real_tb_snap -t ../../../$(FLOW)/sim.tcl

sim-chip-winograd-1000: $(WINOGRAD_CHIP_RTL) $(WINOGRAD_CHIP_1000_TB) $(FLOW)/sim.tcl
	@mkdir -p $(SIM_DIR)/chip_winograd_1000_td$(FIFO_DEPTH)_vd$(V_REPLAY_DEPTH)_md$(M_FIFO_DEPTH)
	@echo "===== [xvlog] Winograd chip 1000-image regression compile ====="
	cd $(SIM_DIR)/chip_winograd_1000_td$(FIFO_DEPTH)_vd$(V_REPLAY_DEPTH)_md$(M_FIFO_DEPTH) && $(XVLOG) -d TEST_CONV1_TILE_FIFO_DEPTH_$(FIFO_DEPTH) -d TEST_V_REPLAY_GROUP_DEPTH_$(V_REPLAY_DEPTH) -d TEST_M_FIFO_DEPTH_$(M_FIFO_DEPTH) $(addprefix ../../../,$(WINOGRAD_CHIP_RTL)) ../../../$(WINOGRAD_CHIP_1000_TB)
	@echo "===== [xelab] Winograd chip 1000-image regression elaborate ====="
	cd $(SIM_DIR)/chip_winograd_1000_td$(FIFO_DEPTH)_vd$(V_REPLAY_DEPTH)_md$(M_FIFO_DEPTH) && $(XELAB) -top winograd_chip_1000_tb -snapshot chip_winograd_1000_tb_snap
	@echo "===== [xsim] Winograd chip 1000-image regression run ====="
	cd $(SIM_DIR)/chip_winograd_1000_td$(FIFO_DEPTH)_vd$(V_REPLAY_DEPTH)_md$(M_FIFO_DEPTH) && $(XSIM) chip_winograd_1000_tb_snap -t ../../../$(FLOW)/sim.tcl

sim-chip-winograd-fifo-trace: $(WINOGRAD_CHIP_RTL) $(WINOGRAD_CHIP_1000_TB) $(FLOW)/sim.tcl
	@mkdir -p $(SIM_DIR)/chip_winograd_fifo_trace_d$(FIFO_DEPTH)
	@echo "===== [xvlog] FIFO depth trace compile ====="
	cd $(SIM_DIR)/chip_winograd_fifo_trace_d$(FIFO_DEPTH) && $(XVLOG) -d FIFO_TRACE -d TEST_CONV1_TILE_FIFO_DEPTH_$(FIFO_DEPTH) $(addprefix ../../../,$(WINOGRAD_CHIP_RTL)) ../../../$(WINOGRAD_CHIP_1000_TB)
	@echo "===== [xelab] FIFO depth trace elaborate ====="
	cd $(SIM_DIR)/chip_winograd_fifo_trace_d$(FIFO_DEPTH) && $(XELAB) -top winograd_chip_1000_tb -snapshot fifo_trace_tb_snap
	@echo "===== [xsim] FIFO depth trace run ====="
	cd $(SIM_DIR)/chip_winograd_fifo_trace_d$(FIFO_DEPTH) && $(XSIM) fifo_trace_tb_snap -t ../../../$(FLOW)/sim.tcl

sim-chip-winograd-lifetime-trace: $(WINOGRAD_CHIP_RTL) $(WINOGRAD_CHIP_1000_TB) $(FLOW)/sim.tcl
	@mkdir -p $(SIM_DIR)/chip_winograd_lifetime_trace
	@echo "===== [xvlog] activation lifetime trace compile ====="
	cd $(SIM_DIR)/chip_winograd_lifetime_trace && $(XVLOG) -d LIFETIME_TRACE -d TEST_CONV1_TILE_FIFO_DEPTH_2 -d TEST_V_REPLAY_GROUP_DEPTH_2 -d TEST_M_FIFO_DEPTH_1 $(addprefix ../../../,$(WINOGRAD_CHIP_RTL)) ../../../$(WINOGRAD_CHIP_1000_TB)
	@echo "===== [xelab] activation lifetime trace elaborate ====="
	cd $(SIM_DIR)/chip_winograd_lifetime_trace && $(XELAB) -top winograd_chip_1000_tb -snapshot lifetime_trace_tb_snap
	@echo "===== [xsim] activation lifetime trace run ====="
	cd $(SIM_DIR)/chip_winograd_lifetime_trace && $(XSIM) lifetime_trace_tb_snap -t ../../../$(FLOW)/sim.tcl

sim-chip-winograd-gate-1000: $(WINOGRAD_CHIP_NETLIST) $(ASAP7_FUNCTIONAL_LIB) $(WINOGRAD_CHIP_1000_TB) $(FLOW)/sim.tcl
	@mkdir -p $(SIM_DIR)/chip_winograd_gate_1000
	@echo "===== [xvlog] ASAP7 gate-level 1000-image regression compile ====="
	cd $(SIM_DIR)/chip_winograd_gate_1000 && $(XVLOG) -d GATE_LEVEL ../../../$(ASAP7_FUNCTIONAL_LIB) ../../../$(WINOGRAD_CHIP_NETLIST) ../../../$(WINOGRAD_CHIP_1000_TB)
	@echo "===== [xelab] ASAP7 gate-level 1000-image regression elaborate ====="
	cd $(SIM_DIR)/chip_winograd_gate_1000 && $(XELAB) -top winograd_chip_1000_tb -snapshot chip_winograd_gate_functional_tb_snap
	@echo "===== [xsim] ASAP7 gate-level 1000-image regression run ====="
	cd $(SIM_DIR)/chip_winograd_gate_1000 && $(XSIM) chip_winograd_gate_functional_tb_snap -t ../../../$(FLOW)/sim.tcl

sim-chip-winograd-gate-power: $(WINOGRAD_CHIP_NETLIST) $(WINOGRAD_CHIP_1000_TB) $(FLOW)/sim_power_vcd.tcl
	@mkdir -p $(SIM_DIR)/chip_winograd_gate_power
	node scripts/generate_gate_power_objects.js "$(WINOGRAD_CHIP_NETLIST)" "OpenRoad project/std_cell" "$(SIM_DIR)/chip_winograd_gate_power/power_objects.txt"
	@echo "===== [xvlog] ASAP7 one-image power trace compile ====="
	cd $(SIM_DIR)/chip_winograd_gate_power && $(XVLOG) -d GATE_LEVEL -d POWER_TRACE $(ASAP7_SIM_LIB_ARGS) ../../../$(WINOGRAD_CHIP_NETLIST) ../../../$(WINOGRAD_CHIP_1000_TB)
	@echo "===== [xelab] ASAP7 one-image power trace elaborate ====="
	cd $(SIM_DIR)/chip_winograd_gate_power && $(XELAB) -debug typical -top winograd_chip_1000_tb -snapshot chip_winograd_gate_power_snap
	@echo "===== [xsim] ASAP7 one-image VCD capture ====="
	cd $(SIM_DIR)/chip_winograd_gate_power && $(XSIM) chip_winograd_gate_power_snap -t ../../../$(FLOW)/sim_power_vcd.tcl

synth-mac:
	make synth SYNTH_TOP=winograd_mac_array SYNTH_RTL="$(MAC_RTL)"

# ---------- Synthesis ----------
synth: $(SYNTH_OUT)/timing.rpt

$(SYNTH_OUT)/timing.rpt: $(SYNTH_RTL) flow/constraints/timing.xdc $(FLOW)/synth.tcl
	@mkdir -p $(SYNTH_OUT)
	$(VIVADO) -mode batch \
	    -log $(SYNTH_OUT)/vivado.log -journal $(SYNTH_OUT)/vivado.jou \
	    -source $(FLOW)/synth.tcl \
	    -tclargs $(SYNTH_OUT) $(SYNTH_TOP) $(SYNTH_RTL)
	@echo ""
	@echo "===== Timing summary ====="
	@{ grep -A2 -E "WNS|TNS" $(SYNTH_OUT)/timing.rpt || true; } | head -20 || true

# ---------- OpenROAD synthesis (WSL Ubuntu, ASAP7 7nm) ----------
# Produces under ORFS {results,reports}/asap7/<ASIC_TOP>/<variant>/ and mirrors
# selected artifacts into build/asic/<ASIC_TOP>/.
#   1_1_yosys.v            — Yosys canonicalized RTL
#   1_synth.v              — post-Yosys netlist (ASAP7 std cells)
#   1_synth.sdc            — post-synth SDC
#   synth_stat.txt         — cell counts + area (from Yosys stat)
#   1_synth_check.txt      — post-synth STA (WNS/TNS, power) — appears after synth-report
#
# ASIC_RTL is optional. When omitted, config.mk reads all verilog/*.v and Yosys
# keeps only the hierarchy reachable from ASIC_TOP.

ORFS_RESULTS := $(ORFS_ROOT)/flow/results/asap7/$(ASIC_TOP)/$(ASIC_VARIANT)
ORFS_REPORTS := $(ORFS_ROOT)/flow/reports/asap7/$(ASIC_TOP)/$(ASIC_VARIANT)

synth-asic:
	@echo "===== OpenROAD synth: top=$(ASIC_TOP), platform=ASAP7 ====="
	@echo "===== STA target: $(ASIC_CLK_PERIOD_PS) ps ====="
	@mkdir -p $(ASIC_OUT)
	wsl -d $(WSL_DIST) -- bash -c "cp -f '/mnt/c/IDEC_challenge/OpenRoad project/config/constraint.sdc' $(ORFS_SDC) && cd $(ORFS_ROOT) && source ./env.sh && cd flow && time ASIC_CLK_PERIOD_PS='$(ASIC_CLK_PERIOD_PS)' ASIC_CLK_IO_PCT='$(ASIC_CLK_IO_PCT)' make synth-report DESIGN_CONFIG=$(ORFS_DESIGN_CFG) DESIGN_NAME='$(ASIC_TOP)' DESIGN_NICKNAME='$(ASIC_TOP)' SDC_FILE='$(ORFS_SDC)' FLOW_VARIANT='$(ASIC_VARIANT)' $(ASIC_RTL_ARG)"
	@echo ""
	@echo "===== Copying artifacts to $(ASIC_OUT) ====="
	wsl -d $(WSL_DIST) -- bash -c "cp -f $(ORFS_RESULTS)/1_*_yosys.v            /mnt/c/IDEC_challenge/$(ASIC_OUT)/netlist.v    2>/dev/null || true; \
	                                cp -f $(ORFS_RESULTS)/1_synth.sdc            /mnt/c/IDEC_challenge/$(ASIC_OUT)/          2>/dev/null || true; \
	                                cp -f $(ORFS_REPORTS)/synth_stat.txt         /mnt/c/IDEC_challenge/$(ASIC_OUT)/          2>/dev/null || true; \
	                                cp -f $(ORFS_REPORTS)/1_Post_synthesis.rpt   /mnt/c/IDEC_challenge/$(ASIC_OUT)/          2>/dev/null || true"
	@echo ""
	@echo "===== $(ASIC_TOP) metrics ====="
	@grep -E "^   Chip area for|of which used for sequential" $(ASIC_OUT)/synth_stat.txt 2>/dev/null || echo "(area info missing)"
	@grep -E "^wns max|^tns max|clk period_min" $(ASIC_OUT)/1_Post_synthesis.rpt 2>/dev/null | head -5
	@grep -E "^Total " $(ASIC_OUT)/1_Post_synthesis.rpt 2>/dev/null | head -1

synth-asic-fmax:
	$(MAKE) synth-asic ASIC_CLK_PERIOD_PS=400 ASIC_VARIANT=fmax_400ps

power-asic-activity: sim-chip-winograd-gate-power flow/openroad/report_activity_power.tcl
	@echo "===== OpenROAD activity-annotated power: top=$(ASIC_TOP) ====="
	wsl -d $(WSL_DIST) -- bash -c "cd $(ORFS_ROOT) && source ./env.sh && POWER_LIBERTY_DIR='$(ORFS_ROOT)/flow/platforms/asap7/lib/NLDM' POWER_ODB='$(ORFS_RESULTS)/1_synth.odb' POWER_SDC='$(ORFS_RESULTS)/1_synth.sdc' POWER_VCD='/mnt/c/IDEC_challenge/$(SIM_DIR)/chip_winograd_gate_power/activity.vcd' POWER_REPORT='/mnt/c/IDEC_challenge/$(ASIC_OUT)/activity_power.rpt' POWER_ACTIVITY_REPORT='/mnt/c/IDEC_challenge/$(ASIC_OUT)/activity_annotation.rpt' openroad -no_init -exit /mnt/c/IDEC_challenge/flow/openroad/report_activity_power.tcl"
	@echo "===== Activity annotation ====="
	@grep -E "(Annotated|Unannotated)" $(ASIC_OUT)/activity_annotation.rpt 2>/dev/null || true
	@echo "===== Activity-based power ====="
	@grep -E "^Total " $(ASIC_OUT)/activity_power.rpt 2>/dev/null | tail -1

# ---------- XPR export (for submission) ----------
xpr: $(XPR_DIR)/exported.xpr

$(XPR_DIR)/exported.xpr: $(WINOGRAD_CHIP_RTL) $(WINOGRAD_CHIP_1000_TB) flow/constraints/timing.xdc $(FLOW)/export_xpr.tcl
	@mkdir -p $(XPR_DIR)
	$(VIVADO) -mode batch -source $(FLOW)/export_xpr.tcl -tclargs $(XPR_DIR) \
	    -log $(XPR_DIR)/vivado.log -journal $(XPR_DIR)/vivado.jou

# ---------- Cleanup ----------
clean:
	rm -rf $(BUILD)
	@echo "Cleaned $(BUILD)/"
