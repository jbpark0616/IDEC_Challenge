# Keep the actual parameterized compute module BEFORE coarse synthesis.
# Each repeated core is mapped once; all 16 instances remain in the netlist.
include $(PROJECT_ROOT)/flow/full_cluster/config.mk
export SYNTH_HIERARCHICAL = 0
export SYNTH_KEEP_MODULES = *vgg_sram_conv_layer
export SYNTH_ARGS = -noshare
export ABC_AREA = 0
