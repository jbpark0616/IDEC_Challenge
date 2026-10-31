"""Fetch only the pinned public ASAP7 SRAM assets used by our smoke test."""
import hashlib
import json
from pathlib import Path
from urllib.request import Request, urlopen

ROOT = Path(__file__).resolve().parents[1]
COMMIT = "9f5af0939e8dd3cc1a9693a50b23441691dd7d25"
BASE = "https://raw.githubusercontent.com/The-OpenROAD-Project/asap7_sram_0p0/"
MACRO = "srambank_256x4x64_6t122"
FILES = ["LICENSE", "README.md", "verilog/README.txt",
         f"generated/verilog/{MACRO}.v", f"generated/LIB/{MACRO}.lib",
         f"generated/LEF/{MACRO}.lef", "gds/srambank_64b.gds"]

def main():
    dest = ROOT / "third_party/asap7_sram"
    manifest = {"repository": "https://github.com/The-OpenROAD-Project/asap7_sram_0p0",
                "commit": COMMIT, "macro": MACRO, "files": []}
    for relative in FILES:
        url = BASE + COMMIT + "/" + relative
        data = urlopen(Request(url, headers={"User-Agent": "IDEC-SRAM-integration"}), timeout=60).read()
        target = dest / relative
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(data)
        manifest["files"].append({"path": relative, "url": url, "bytes": len(data),
                                  "sha256": hashlib.sha256(data).hexdigest()})
        print(relative, len(data))
    (dest / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")

if __name__ == "__main__":
    main()
