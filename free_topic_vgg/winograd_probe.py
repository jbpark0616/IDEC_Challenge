"""Exact F(2,3) input-transform statistics; no epsilon or approximate pruning."""
import torch
import torch.nn.functional as F

def transform_tiles(x):
    """NCHW -> (N, spatial tiles, channels, 4, 4), using Conv padding=1.

    Float32 activations are widened to float64 for mathematical cancellation
    analysis. Integer inputs use int64. This is NOT a quantized network run.
    """
    n,c,h,w=x.shape
    assert h%2==0 and w%2==0
    padded=F.pad(x,(1,1,1,1))
    d=padded.unfold(2,4,2).unfold(3,4,2).permute(0,2,3,1,4,5).reshape(n,(h//2)*(w//2),c,4,4)
    d=d.to(torch.float64 if x.is_floating_point() else torch.int64)
    t=torch.stack((d[...,0,:]-d[...,2,:],d[...,1,:]+d[...,2,:],
                   d[...,2,:]-d[...,1,:],d[...,1,:]-d[...,3,:]),dim=-2)
    v=torch.stack((t[...,0]-t[...,2],t[...,1]+t[...,2],
                   t[...,2]-t[...,1],t[...,1]-t[...,3]),dim=-1)
    return d,t,v

def tile_metrics(d,t,v):
    rows=(t==0).all(-1)
    assert torch.equal(rows,(v==0).all(-1)), 'T-row and V-row zero masks disagree'
    n,l,c,_,_=d.shape
    remaining=(~rows).sum(dim=2) # N,L,4: nonzero channel count per row
    compressed=remaining.max(-1).values
    full_zero=compressed==0
    return {
        'spatial_groups':n*l,'input_channel_tiles':n*l*c,'zero_input_channel_tiles':int((d==0).all((-1,-2)).sum()),
        'row_count':rows.numel(),'zero_rows':int(rows.sum()),
        'v_elements':v.numel(),'zero_v_elements':int((v==0).sum()),
        'whole_zero_groups':int(full_zero.sum()),
        'dense_mac_beats_per_output_channel':n*l*c,
        'tile_only_mac_beats_per_output_channel':int((~full_zero).sum())*c,
        'channel_tile_skip_mac_beats_per_output_channel':n*l*c-int((d==0).all((-1,-2)).sum()),
        'row_compressed_mac_beats_per_output_channel':int(compressed.sum()),
        'replay_descriptor_beats_per_output_channel':int(compressed.clamp_min(1).sum()),
        'active_row_products_per_output_channel':int((~rows).sum())*4,
        'issued_lane_slots_per_output_channel':int(compressed.sum())*16}

def inspect_activation(x):
    d,t,v=transform_tiles(x)
    overall=tile_metrics(d,t,v)
    h,w=x.shape[-2:]
    gy,gx=torch.meshgrid(torch.arange(h//2),torch.arange(w//2),indexing='ij')
    # Interior means the entire 4x4 tile is original data, without padding.
    interior=((gy*2-1>=0)&(gy*2+2<h)&(gx*2-1>=0)&(gx*2+2<w)).flatten()
    scopes={'all_tiles':overall}
    if bool(interior.any()): scopes['interior_tiles']=tile_metrics(d[:,interior],t[:,interior],v[:,interior])
    if bool((~interior).any()): scopes['boundary_tiles']=tile_metrics(d[:,~interior],t[:,~interior],v[:,~interior])
    return {'input_elements':x.numel(),'input_zeros':int((x==0).sum()),'scopes':scopes}
