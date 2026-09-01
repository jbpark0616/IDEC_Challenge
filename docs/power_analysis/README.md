# 1 GHz activity-based power analysis

## Measurement setup

- Technology/library: ASAP7 RVT FF corner, the same five Liberty files used by synthesis
- Clock constraint: 1,000 ps (1 GHz)
- Netlist: OpenROAD post-synthesis standard-cell netlist
- Workload: one complete MNIST inference from reset through argmax
- Activity source: XSim gate-level VCD
- Directly annotated activity: all primary ports and standard-cell output pins
- Functional check during capture: RTL/Python mismatch 0

The VCD generator parses the synthesized netlist and the ASAP7 functional
libraries. It records the output pin of every standard-cell instance rather
than only top-level nets. OpenSTA then propagates the measured output activity
to the remaining cell input pins.

## STA at the operating point

| Metric | Result |
|---|---:|
| Target period | 1,000 ps |
| Worst slack | +152.69 ps (MET) |
| Estimated minimum period | 847.31 ps |
| Estimated Fmax | 1.18021 GHz |

The earlier `-447.31 ps` slack was measured against a 400 ps (2.5 GHz) stress
constraint. It did not represent failure at the intended 1 GHz operating
point. Fmax characterization remains available separately through
`make synth-asic-fmax`.

## Power result

| Group | Internal | Switching | Leakage | Total |
|---|---:|---:|---:|---:|
| Sequential | 12.6972 mW | 0.1181 mW | 0.0014 mW | 12.8167 mW |
| Combinational | 1.6269 mW | 2.1488 mW | 0.0039 mW | 3.7797 mW |
| **Total** | **14.3241 mW** | **2.2668 mW** | **0.0053 mW** | **16.5962 mW** |

- Direct VCD annotations: 74,225 pins
- Vectorless estimate at 1 GHz: 13.6 mW
- Activity-based estimate at 1 GHz: 16.60 mW

The result is more representative than the former 34.0 mW vectorless value,
which was evaluated with a 2.5 GHz clock. It is still a post-synthesis estimate:
the clock network is ideal and routed wire capacitance is absent. A final
sign-off-style number requires post-route parasitics and activity annotation on
the routed netlist. Multiple input images should also be used to remove
single-image workload bias before publication.

## Reproduction

```powershell
make synth-asic
make power-asic-activity
```

Generated evidence:

- `build/asic/chip/1_Post_synthesis.rpt`
- `build/asic/chip/activity_power.rpt`
- `build/asic/chip/activity_annotation.rpt`
- `build/sim/chip_winograd_gate_power/activity.vcd`
