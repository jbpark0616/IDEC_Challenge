"""Shared hex-vector encoding; independent of any RTL experiment."""
G=((2,0,0),(1,1,1),(1,-1,1),(0,0,2))

def dump(path, data, bits):
    path.parent.mkdir(parents=True,exist_ok=True)
    path.write_text(''.join(f'{int(v)&((1<<bits)-1):0{bits//4}x}\n' for v in data))

def pack(values):
    return [sum((int(v)&255)<<(8*j) for j,v in enumerate(values[i:i+8]))
            for i in range(0,len(values),8)]
