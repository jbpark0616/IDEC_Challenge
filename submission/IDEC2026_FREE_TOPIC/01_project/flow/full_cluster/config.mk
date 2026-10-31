export PLATFORM = asap7
export DESIGN_NAME = vgg_sixteen_core_cluster
export DESIGN_NICKNAME = vgg_sixteen_core_cluster
export VERILOG_FILES = $(addprefix $(PROJECT_ROOT)/,$(shell cat $(PROJECT_ROOT)/rtl/sources.f))
export ADDITIONAL_LIBS = $(PROJECT_ROOT)/../02_libraries/asap7_sram/generated/LIB/srambank_256x4x64_6t122.lib
export ADDITIONAL_LEFS = $(PROJECT_ROOT)/../02_libraries/asap7_sram/generated/LEF/srambank_256x4x64_6t122.lef
export SDC_FILE = $(PROJECT_ROOT)/flow/single_core/constraint.sdc
export VERILOG_DEFINES = -DOPENROAD_CLKGATE
export DONT_USE_CELLS = *x1p*_ASAP7* *xp*_ASAP7* SDF*
export ABC_AREA = 1
export ABC_CLOCK_PERIOD_IN_PS = 1000
# Preserve repeated module structure during synthesis; all compute logic is
# mapped, not blackboxed. This reduces redundant mapping work for 16 cores.
export SYNTH_HIERARCHICAL = 1
export SYNTH_MINIMUM_KEEP_SIZE = 2000
export CORE_UTILIZATION = 40
export CORE_ASPECT_RATIO = 1
export CORE_MARGIN = 2
export PLACE_DENSITY = 0.65
export EQUIVALENCE_CHECK = 0
