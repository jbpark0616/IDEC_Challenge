"""Export signed U8 row-bank payloads, with checked inverse packing.

Files contain no SRAM address gaps. A loader copies each output channel's
ceil(C/2) words to local_K * (channel_stride/2) in each of four U banks.
Only the current K block is resident; this is not whole-model SRAM allocation.
"""
from pathlib import Path
import hashlib
import json
import numpy as np
import torch
from probe import ROOT, make_u

HERE = Path(__file__).parent
DEST = HERE/'artifacts'/'u8_export'

def pack_rows(q):
    """[K,C,4,4] int8 -> [row,K,ceil(C/2),8] bytes, LE channel pair."""
    q = np.asarray(q, dtype=np.int8)
    k, c, rows, cols = q.shape
    assert rows == cols == 4
    padded = np.zeros((k, (c+1)//2*2, 4, 4), dtype=np.int8)
    padded[:, :c] = q
    return padded.transpose(2, 0, 1, 3).copy().reshape(4, k, (c+1)//2, 8).view(np.uint8)

def main():
    torch.set_num_threads(2)
    DEST.mkdir(parents=True, exist_ok=True)
    params = torch.load(ROOT/'artifacts/integer_vgg/integer_parameters.pt', weights_only=True)
    candidate_path = HERE/'artifacts/u8_candidates.pt'
    candidates = torch.load(candidate_path, weights_only=True)
    manifest = dict(format='signed U8; little-endian 64-bit words; four row banks',
                    candidate_sha256=hashlib.sha256(candidate_path.read_bytes()).hexdigest(),
                    local_address='local_K * (stride_channels/2) + input_channel//2',
                    half='input_channel % 2; low half is even channel',
                    shift='3-bit per K; reconstructed U16 = sign_extend(U8) << shift',
                    layers=[])
    for idx, (p, candidate) in enumerate(zip((p for p in params if p['conv']), candidates)):
        q, shift, stats = make_u(p['weight'], 8)
        assert torch.equal(q.to(torch.int8), candidate['u'])
        assert torch.equal(shift, candidate['shift'])
        assert int(shift.max()) <= 7
        k, c, _, _ = q.shape
        stride = 128 if c <= 128 else 256 if c <= 256 else 512
        packed = pack_rows(q.numpy())
        unpacked = packed.view(np.int8).reshape(4,k,-1,4).transpose(1,2,0,3)[:, :c]
        assert np.array_equal(unpacked, q.numpy())
        directory = DEST/f'conv{idx:02d}'
        directory.mkdir(exist_ok=True)
        hashes = {}
        for row in range(4):
            name = f'u_bank{row}.bin'
            payload = packed[row].tobytes()
            (directory/name).write_bytes(payload)
            hashes[name] = hashlib.sha256(payload).hexdigest()
        shift_bytes = shift.numpy().astype(np.uint8).tobytes()
        (directory/'u_shift.bin').write_bytes(shift_bytes)
        hashes['u_shift.bin'] = hashlib.sha256(shift_bytes).hexdigest()
        manifest['layers'].append(dict(layer=idx, k=k, c=c, stride_channels=stride,
            words_per_output_per_bank=(c+1)//2, output_stride_words=stride//2,
            max_resident_outputs=min(8,1024//(stride//2)),
            u8_payload_bytes=int(packed.size), u16_payload_bytes=k*c*16*2,
            shift_bytes=k, quantization=stats, sha256=hashes))
    assert len(manifest['layers']) == len(candidates) == 13
    (DEST/'manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
    print('Exported and round-trip checked all 13 convolution U banks; fresh quantization matches candidates')
    print('U16 bytes:',sum(x['u16_payload_bytes'] for x in manifest['layers']))
    print('U8 bytes:',sum(x['u8_payload_bytes'] for x in manifest['layers']))

if __name__ == '__main__':
    main()
