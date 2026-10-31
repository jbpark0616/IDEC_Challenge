# Same complete circuit; timing-oriented mapping variant.
include $(PROJECT_ROOT)/flow/full_cluster/config.mk
export ABC_AREA = 0
export SYNTH_ARGS = -noshare
