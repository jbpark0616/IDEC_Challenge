"""Audit macro preservation and GDS cell availability, not physical signoff."""
import hashlib
import json
import struct
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
VENDOR = ROOT / "third_party/asap7_sram"
OUT = ROOT / "artifacts/sram_smoke"
MACRO = "srambank_256x4x64_6t122"

def gds_structure_names(path):
    data = path.read_bytes()
    offset, names = 0, []
    while offset < len(data):
        length, record_type, _ = struct.unpack_from(">HBB", data, offset)
        if length < 4 or offset + length > len(data):
            raise ValueError("Malformed GDS record")
        if record_type == 6:  # STRNAME
            names.append(data[offset + 4:offset + length].rstrip(b"\0").decode("ascii"))
        offset += length
        if record_type == 4:  # ENDLIB; stream files may have zero block padding
            assert not any(data[offset:]), "Unexpected nonzero bytes after ENDLIB"
            break
    return names

def main():
    manifest = json.loads((VENDOR / "manifest.json").read_text())
    for item in manifest["files"]:
        assert hashlib.sha256((VENDOR / item["path"]).read_bytes()).hexdigest() == item["sha256"]
    netlist = json.loads((OUT / "netlist.json").read_text())
    cells = netlist["modules"]["vgg_sram_8k"]["cells"]
    assert len(cells) == 1 and next(iter(cells.values()))["type"] == MACRO
    assert "PASS SRAM" in (OUT / "simulation.log").read_text()
    assert "PASS OpenROAD" in (OUT / "openroad.log").read_text()
    names = gds_structure_names(VENDOR / "gds/srambank_64b.gds")
    warnings = [line for line in (OUT / "openroad.log").read_text().splitlines()
                if "WARNING" in line]
    result = {
        "commit": manifest["commit"], "macro": MACRO,
        "capacity_bytes": 8192, "simulation_pass": True,
        "synthesis_macro_count": len(cells), "synthesis_ff_count": 0,
        "openroad_link_floorplan_pass": True,
        "gds_structure_names": names, "matching_gds_top_present": MACRO in names,
        "openroad_warnings": warnings,
        "physical_macro_integration_complete": False,
        "physical_signoff_complete": False,
        "limits": ["LEF contains sdel[4:0], absent from Liberty and behavioral model",
                   "Downloaded GDS is not a matching 8KiB implementation",
                   "No routed timing/power result", "No VGG execution RTL yet",
                   "GDS presence alone does not verify geometry, LVS or DRC",
                   "Macro timing/corner and Liberty characterization require review"]
    }
    (OUT / "audit.json").write_text(json.dumps(result, indent=2) + "\n")
    print("PASS functional/synthesis/OpenROAD recognition smoke test; physical integration remains incomplete.")
    print("Matching GDS top present:", result["matching_gds_top_present"])

if __name__ == "__main__":
    main()
