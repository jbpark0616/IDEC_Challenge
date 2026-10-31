"""Read-only size inventory; skip directory reparse points/junctions."""
import os, stat, json, heapq, time
from pathlib import Path
roots=['C:/IDEC_challenge','C:/AMDDesignTools','C:/intelFPGA_lite','C:/Users/jbpar/AppData',
       'C:/Users/jbpar/Downloads','C:/Users/jbpar/miniconda3','C:/Users/jbpar/.cache',
       'C:/Users/jbpar/.codex','C:/Users/jbpar/.docker','C:/Temp','C:/My_Lab','C:/vm_share']
results=[]
for root in roots:
    groups={};largest=[];errors=0;skipped=0;total=0;stack=[root]
    while stack:
        directory=stack.pop()
        try:
            with os.scandir(directory) as entries:
                for e in entries:
                    try:
                        s=e.stat(follow_symlinks=False)
                        if s.st_file_attributes & stat.FILE_ATTRIBUTE_REPARSE_POINT:
                            skipped+=1;continue
                        if e.is_dir(follow_symlinks=False):stack.append(e.path);continue
                        n=s.st_size;total+=n
                        parts=Path(e.path).relative_to(root).parts
                        key='/'.join(parts[:min(2,len(parts)-1)]) or '.'
                        groups[key]=groups.get(key,0)+n
                        heapq.heappush(largest,(n,e.path))
                        if len(largest)>15:heapq.heappop(largest)
                    except OSError:errors+=1
        except OSError:errors+=1
    result=dict(root=root,total_gib=round(total/2**30,3),errors=errors,skipped_reparse=skipped,
        groups=sorted([{'path':k,'gib':round(v/2**30,3)} for k,v in groups.items()],key=lambda x:-x['gib'])[:20],
        largest=[{'path':p,'gib':round(n/2**30,3)} for n,p in sorted(largest,reverse=True)])
    results.append(result);print(json.dumps(result),flush=True)
Path('build/disk_audit.json').write_text(json.dumps(results,indent=2),encoding='utf-8')
