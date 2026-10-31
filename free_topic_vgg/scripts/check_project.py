"""Fast pre-commit integrity checks; no model inference or RTL simulation."""
from pathlib import Path
import ast
import json
import re

root=Path(__file__).resolve().parents[1]
design=json.loads((root/'design.json').read_text())
sources=(root/design['sources']).read_text().splitlines()
assert len(sources)==len(set(sources)) and sources
assert set(sources)=={p.relative_to(root).as_posix() for p in (root/'rtl').rglob('*.v')}
for name in sources:
    assert (root/name).is_file(), name
for folder in ('scripts','verification','model_tools'):
    for p in (root/folder).rglob('*.py'):
        ast.parse(p.read_text(encoding='utf-8-sig'),filename=str(p))
    for p in (root/folder).rglob('*.sh'):
        assert b'\r' not in p.read_bytes(),p
        for path in re.findall(r'-f\s+(rtl/[\w./]+)',p.read_text()):
            assert (root/path).is_file(),(p,path)
assert not (root/'experiments').exists()
for name in ('third_party/asap7_sram/LICENSE','reference/upstream/LICENSE.txt',
             'artifacts/profile_indices.json',
             'model_tools/quantization/artifacts/uv8/v_calibration.json'):
    assert (root/name).is_file(),name
print(f'PASS project integrity: {len(sources)} RTL sources, Python syntax, LF shell scripts, licenses and calibration.')
