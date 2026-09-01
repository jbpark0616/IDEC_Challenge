# Activity-annotated post-synthesis power report.
# Required environment variables:
#   POWER_LIBERTY_DIR, POWER_ODB, POWER_SDC, POWER_VCD, POWER_REPORT,
#   POWER_ACTIVITY_REPORT

foreach variable {POWER_LIBERTY_DIR POWER_ODB POWER_SDC POWER_VCD POWER_REPORT POWER_ACTIVITY_REPORT} {
    if {![info exists ::env($variable)]} {
        error "Missing required environment variable: $variable"
    }
}

# OpenDB does not serialize Liberty timing/power models.  Reload the exact
# ASAP7 FF-corner libraries used by synthesis before opening the database.
set liberty_files [list \
    [file join $::env(POWER_LIBERTY_DIR) asap7sc7p5t_AO_RVT_FF_nldm_211120.lib.gz] \
    [file join $::env(POWER_LIBERTY_DIR) asap7sc7p5t_INVBUF_RVT_FF_nldm_220122.lib.gz] \
    [file join $::env(POWER_LIBERTY_DIR) asap7sc7p5t_OA_RVT_FF_nldm_211120.lib.gz] \
    [file join $::env(POWER_LIBERTY_DIR) asap7sc7p5t_SIMPLE_RVT_FF_nldm_211120.lib.gz] \
    [file join $::env(POWER_LIBERTY_DIR) asap7sc7p5t_SEQ_RVT_FF_nldm_220123.lib]]
foreach liberty_file $liberty_files {
    if {![file exists $liberty_file]} {
        error "Missing ASAP7 Liberty file: $liberty_file"
    }
    read_liberty $liberty_file
}

read_db $::env(POWER_ODB)
read_sdc $::env(POWER_SDC)

# XSim writes scopes as winograd_chip_1000_tb/dut/... .  Removing the
# testbench prefix maps the remaining hierarchy onto the linked chip design.
read_vcd -scope winograd_chip_1000_tb/dut $::env(POWER_VCD)

report_activity_annotation -report_annotated -report_unannotated \
    > $::env(POWER_ACTIVITY_REPORT)
report_checks -path_delay max -group_count 3 \
    > $::env(POWER_REPORT)
report_clock_min_period >> $::env(POWER_REPORT)
report_power -digits 6 >> $::env(POWER_REPORT)
