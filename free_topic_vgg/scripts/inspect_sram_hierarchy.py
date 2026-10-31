"""Read-only KLayout hierarchy inspection; run from free_topic_vgg."""
import json
from pathlib import Path
import pya

layout = pya.Layout()
layout.read("third_party/asap7_sram/gds/srambank_64b.gds")
top = layout.top_cell()

def describe(cell, depth):
    result = []
    for inst in cell.each_inst():
        entry = {"cell": inst.cell.name, "count": inst.size(),
                 "bbox_in_parent_um": str(inst.dbbox()), "transform": str(inst.dcplx_trans)}
        if depth > 0:
            entry["children"] = describe(inst.cell, depth - 1)
        result.append(entry)
    return result

result = {"top": top.name, "bbox_um": str(top.dbbox()), "instances": describe(top, 2)}
Path("artifacts/sram_smoke/hierarchy.json").write_text(json.dumps(result, indent=2) + "\n")
for entry in result["instances"]:
    print(entry["cell"], entry["count"], entry["bbox_in_parent_um"], entry["transform"])
    for child in entry.get("children", []):
        print("  ", child["cell"], child["count"], child["bbox_in_parent_um"])
