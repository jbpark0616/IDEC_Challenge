"""Check generated handoff archive, hashes, notebook syntax and source copies."""
from pathlib import Path
import ast
import hashlib
import json
import zipfile

here=Path(__file__).resolve().parent
root=here.parents[1]
folder=here/'colab'
manifest=json.loads((folder/'bundle_manifest.json').read_text())
bundle=folder/'winograd_uv8_bundle.zip'
assert hashlib.sha256(bundle.read_bytes()).hexdigest()==manifest['sha256']
with zipfile.ZipFile(bundle) as z:
    assert z.testzip() is None
    assert sorted(z.namelist())==sorted(manifest['files'])
    for name in z.namelist():
        assert z.read(name)==(root/name).read_bytes(), name
        if name.endswith('.py'):
            ast.parse(z.read(name).decode('utf-8-sig'), filename=name)
notebook=json.loads((folder/'Winograd_U8_V8_Validation.ipynb').read_text(encoding='utf-8'))
for cell in notebook['cells']:
    if cell['cell_type']=='code':
        ast.parse(''.join(cell['source']))
assert manifest['sha256'] in ''.join(notebook['cells'][1]['source'])
try:
    import nbformat
except ImportError:
    print('nbformat unavailable; JSON, cell syntax and archive verified')
else:
    nbformat.validate(nbformat.from_dict(notebook))
print('PASS handoff: ZIP integrity, source equality, SHA256, notebook code syntax; Colab not executed')
