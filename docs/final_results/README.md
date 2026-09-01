# Midterm-report reference results

This directory preserves the final evidence used for the 2026 IDEC challenge
midterm report without committing the full generated `build/` tree.

## Reported configuration

- RTL regression: 1,000 MNIST images, 970 correct, 0 RTL/golden mismatches
- Accuracy: 97.0%
- Target operating frequency: 1 GHz
- Estimated Fmax: 1,180.21 MHz (`847.31 ps` minimum period)
- Post-synthesis cell area: 7,953.885720 um^2
- Activity-based power at 1 GHz: 16.59623 mW
- Average inference latency: approximately 1,220 cycles
- Dense-equivalent throughput: 0.366 TOPS
- Dense-equivalent energy efficiency: 22.05 TOPS/W

## Files

- `rtl_regression_1000.txt`: end-to-end RTL regression summary
- `chip_post_synthesis.rpt`: final post-synthesis timing and power report
- `chip_synth_stat.txt`: synthesized cell-area statistics
- `chip_activity_power.rpt`: switching-activity-annotated power report

The complete Vivado/OpenROAD outputs remain reproducible from the tracked flow
scripts and are intentionally excluded by `.gitignore`.
