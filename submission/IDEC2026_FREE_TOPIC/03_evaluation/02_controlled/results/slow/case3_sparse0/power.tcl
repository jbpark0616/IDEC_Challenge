read_liberty {/home/junbeom/OpenROAD-flow-scripts/flow/platforms/asap7/lib/NLDM/asap7sc7p5t_AO_RVT_FF_nldm_211120.lib.gz}
read_liberty {/home/junbeom/OpenROAD-flow-scripts/flow/platforms/asap7/lib/NLDM/asap7sc7p5t_INVBUF_RVT_FF_nldm_220122.lib.gz}
read_liberty {/home/junbeom/OpenROAD-flow-scripts/flow/platforms/asap7/lib/NLDM/asap7sc7p5t_OA_RVT_FF_nldm_211120.lib.gz}
read_liberty {/home/junbeom/OpenROAD-flow-scripts/flow/platforms/asap7/lib/NLDM/asap7sc7p5t_SIMPLE_RVT_FF_nldm_211120.lib.gz}
read_liberty {/home/junbeom/OpenROAD-flow-scripts/flow/platforms/asap7/lib/NLDM/asap7sc7p5t_SEQ_RVT_FF_nldm_220123.lib}
read_liberty {/mnt/c/IDEC_challenge/free_topic_vgg/third_party/asap7_sram/generated/LIB/srambank_256x4x64_6t122.lib}
read_lef {/home/junbeom/OpenROAD-flow-scripts/flow/platforms/asap7/lef/asap7_tech_1x_201209.lef}
read_lef {/home/junbeom/OpenROAD-flow-scripts/flow/platforms/asap7/lef/asap7sc7p5t_28_R_1x_220121a.lef}
read_lef {/mnt/c/IDEC_challenge/free_topic_vgg/third_party/asap7_sram/generated/LEF/srambank_256x4x64_6t122.lef}

read_verilog {/mnt/c/IDEC_challenge/free_topic_vgg/build/controlled_power/slow/core.v}
link_design ppa_core
create_clock -name clk -period 1430 [get_ports clk]
set inputs [lsearch -inline -all -not -exact [all_inputs] [get_ports clk]]
set_input_delay 200 -clock clk $inputs
set_output_delay 200 -clock clk [all_outputs]

read_vcd -scope tb_v8_packed/dut {/mnt/c/IDEC_challenge/free_topic_vgg/build/controlled_power/slow/case3_sparse0.vcd}
report_activity_annotation -report_unannotated > {/mnt/c/IDEC_challenge/free_topic_vgg/evidence/controlled_power/slow/case3_sparse0/activity.rpt}
report_power -digits 9 > {/mnt/c/IDEC_challenge/free_topic_vgg/evidence/controlled_power/slow/case3_sparse0/power.rpt}
report_clock_min_period > {/mnt/c/IDEC_challenge/free_topic_vgg/evidence/controlled_power/slow/case3_sparse0/timing.rpt}
report_design_area > {/mnt/c/IDEC_challenge/free_topic_vgg/evidence/controlled_power/slow/case3_sparse0/area.rpt}
report_checks -path_delay max -group_count 3 > {/mnt/c/IDEC_challenge/free_topic_vgg/evidence/controlled_power/slow/case3_sparse0/paths.rpt}
exit
