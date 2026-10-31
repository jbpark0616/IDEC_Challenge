# Reproduce the layer comparison

Use Linux/WSL with Python 3, Icarus Verilog 12 and OpenROAD/ASAP7 ORFS installed.
No Python ML package, dataset download or Vivado project is required for these saved slices.

```sh
cd 01_vgg_layers
export ORFS_ROOT=/path/to/OpenROAD-flow-scripts
# Optional if the OpenROAD executable is installed elsewhere:
# export OPENROAD=/path/to/openroad
python3 reproduce.py --cases 10 11
```

`reproduced_results/` is created separately from the supplied measured `results/`.
The script compiles the exact mapped core and uses the included vectors; it
does not rerun synthesis or modify the final RTL. `run.py` writes the exact
Liberty/LEF/SDC/VCD commands to each case's `power.tcl`.

Read README.md for the comparison boundary. Area and Fmax are common to both
runtime modes; this is not a claim of area or frequency improvement.
Activity VCDs are reproducible and compressed after measurement. They are
not included in the submission copy to avoid large waveform uploads.
The original source core is identifiable by manifest.json hashes.
