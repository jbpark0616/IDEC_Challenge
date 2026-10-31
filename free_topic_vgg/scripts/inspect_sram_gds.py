"""Run with klayout -b -r scripts/inspect_sram_gds.py from project root."""
import json
from pathlib import Path
import pya

layout = pya.Layout()
layout.read("third_party/asap7_sram/gds/srambank_64b.gds")

def bitcells(cell):
    if cell.name == "sram_cell_6t_122":
        return 1
    return sum(inst.na * inst.nb * bitcells(inst.cell) if inst.is_regular_array()
               else bitcells(inst.cell) for inst in cell.each_inst())

tops = []
for cell in layout.top_cells():
    bbox = cell.dbbox()
    tops.append({"name": cell.name, "width_um": bbox.width(), "height_um": bbox.height(),
                 "bitcell_instance_count": bitcells(cell)})
report = {"dbu_um": layout.dbu, "tops": tops,
          "note": "Bitcell count is a geometry diagnostic, not functional capacity validation."}
Path("artifacts/sram_smoke/gds_inspection.json").write_text(json.dumps(report, indent=2) + "\n")
print(json.dumps(report, indent=2))
