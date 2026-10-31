"""Check separation, protected RTL, archive inventory and initial VGG results."""
from pathlib import Path
import hashlib,json

ROOT=Path(__file__).resolve().parents[1]
EXP=ROOT/'experiments/row_sparse_fixed'
FREE=ROOT/'free_topic_vgg'
ARCHIVE=ROOT/'archive/designated_legacy_20261025'
def sha(path):
    with path.open('rb') as f: return hashlib.file_digest(f,'sha256').hexdigest()
def read(path): return json.loads(path.read_text(encoding='utf-8-sig'))
cleanup=read(ARCHIVE/'cleanup_result.json')
# Windows PowerShell 5 can serialize a wrapped ConvertFrom-Json array as a
# {value,Count} object. Normalize the ledger, retaining every recorded item.
if isinstance(cleanup['removed_files'],dict):
    cleanup['removed_files']=cleanup['removed_files']['value']
    (ARCHIVE/'cleanup_result.json').write_text(json.dumps(cleanup,indent=2),encoding='utf-8')
for item in cleanup['removed_files']: assert not Path(item['path']).exists(),item['path']
for record in cleanup['archives']:
    assert not Path(record['original']).exists()
    assert sha(Path(record['archive'])).upper()==record['zip_sha256'].upper()
for item in read(EXP/'original_sha256.json'):
    assert sha(ROOT/'verilog'/item['name']).upper()==item['sha256'].upper()
for name,digest in read(EXP/'iterations/matched_ablation/rtl_sha256.json').items():
    assert sha(EXP/'iterations/matched_ablation/rtl'/name)==digest
reference=read(FREE/'reference/designated_rtl/SOURCE.json')
for name,digest in reference['sha256'].items():
    assert sha(FREE/'reference/designated_rtl'/name)==digest
    assert sha(ROOT/reference['source']/name)==digest
accuracy=read(FREE/'artifacts/accuracy.json')
profile=read(FREE/'artifacts/sparsity.json')
indices=read(FREE/'artifacts/profile_indices.json')
assert accuracy['images']==10000 and accuracy['correct']==9416
assert len(set(indices['test_profile']))==1000 and len(set(indices['train_calibration']))==500
assert profile['profile_test_images']==1000
assert len(profile['layers'])==13
for entry in profile['layers'].values():
    for mode in ('fp32','int8_observer'):
        scopes=entry[mode]['scopes']
        for key in ('spatial_groups','row_count','zero_rows','dense_mac_beats_per_output_channel','row_compressed_mac_beats_per_output_channel'):
            assert scopes['all_tiles'][key]==sum(s[key] for name,s in scopes.items() if name!='all_tiles')
report={'designated_original_rtl_unchanged':True,'designated_matched_rtl_unchanged':True,
        'free_topic_reference_snapshot_matches':True,'legacy_archives_hash_verified':len(cleanup['archives']),
        'generated_files_deleted':len(cleanup['removed_files']),
        'generated_bytes_deleted':sum(x['bytes'] for x in cleanup['removed_files']),
        'archived_original_bytes':sum(f['bytes'] for a in cleanup['archives'] for f in a['files']),
        'archive_zip_bytes':sum(Path(a['archive']).stat().st_size for a in cleanup['archives']),
        'vgg_accuracy_percent':accuracy['top1_percent'],'profile_images':1000,
        'profile_boundary_counts_consistent':True,'free_topic_vgg_rtl_implemented':False}
(FREE/'artifacts/PROJECT_SETUP_AUDIT.json').write_text(json.dumps(report,indent=2))
print(json.dumps(report,indent=2))
