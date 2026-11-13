# Layer activity PPA comparison

The final 16-core mapped netlist is the source of `ppa_core`. Only the
Verilog module name is changed for simulation. No RTL or mapped cell is
changed. This avoids a different mapping confounding the OFF/ON comparison.

The comparison is **Winograd + ICG, sparse OFF** versus **Winograd + ICG,
sparse ON**, using the existing runtime `sparse_enable` input. Area and static
Fmax are common to both modes; this experiment does not claim area savings,
Fmax gains, or quantify the incremental effect of ICG separately.

## Boundary and workload

- One compute core, including eight U/V SRAM macros. Four external activation
  SRAM banks, activation feed, multicast and other cores are excluded.
- Cases 10 and 11: saved actual U8/V8 VGG Conv9 and Conv13 activations and
  trained weights, local first four output channels, from one image.
- Every emitted output word is checked against the saved independent integer
  reference. These are layer slices, not full-network accuracy measurements.
- Resident U is preloaded before measurement. Both modes receive identical
  tile data and weights. The tile source offers data every cycle and the output
  sink is always ready. SRAM conflicts and command handling inside execution
  remain included. This is a controlled supply boundary, not full-system traffic.
- Measurement starts at command assertion and ends at observed completion,
  excluding reset, initial preload and post-completion idle.
- Clock is 1430 ps (699.300699 MHz), identical for both modes. Gate simulation
  has no SDF, routed capacitance or physical glitch-delay model.
- OpenROAD reads the gate VCD and exact synthesis Liberty models; power is a
  pre-layout activity-based estimate. SRAM power is limited by its Liberty model.
- Energy = average measured power × measured duration, per tested layer slice.
  Do not call this energy per image or total 16-core power.

## Run (repository root, Linux/WSL)

```sh
python3 free_topic_vgg/verification/layer_ppa/prepare.py
python3 free_topic_vgg/verification/layer_ppa/static.py
python3 -u free_topic_vgg/verification/layer_ppa/run.py --cases 10 11
```

The first script uses preserved gate netlist and local saved vectors. The
submission package will include the tested vectors, generated simulation models,
gate core, and self-contained scripts after the paired runs pass.
Results are written under `free_topic_vgg/evidence/layer_ppa/`.

## Tools

- Existing netlist producer: Yosys 0.64, revision 8449dd470 (netlist header).
- Current OpenROAD: 26Q2-2270-g4c26918f5a.
- Gate simulation: Icarus Verilog 12.0.
- No Vivado project is needed for this reproduction path.

Final physical verification and whole-network gate simulation are outside this
measurement. Inspect `activity.rpt` for annotation coverage before interpreting
power. Missing or failed cases must not be included as measured results.

The SRAM physical LEF has five `sdel` pins per macro which are absent from
its Liberty and behavioral model. The annotation audit expects those 40
LEF-only pins to be unannotated, and no other pin to be missed. This is not
a 100% physical-pin coverage claim. SRAM and standard-cell nominal PVT
conditions differ; the same supplied library combination is used in both modes.

The reused testbench's raw log retains legacy internal-counter fields
(`physical_bank_writes`, `transforms`, `V_writes`, `releases`, `weight_wait`,
`early`). Those monitors were removed for the flattened gate netlist, so their
printed zero placeholders are **not measurements**. The report uses only the
public interface output check, `active_cycles`, `mac_row_issues`, and VCD window.
