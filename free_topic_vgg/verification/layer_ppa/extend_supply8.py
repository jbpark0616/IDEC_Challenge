"""Run only the additional supply-8 conditions; leave old measurements intact."""
from pathlib import Path
p=Path(__file__).with_name('controlled_power.py')
s=p.read_text().split('\nrows=[]',1)[0]
s=s.replace("[('fast',1),('slow',4)]", "[('supply8',8)]")
s=s.replace('{done}/20 completed ({done*5}%)','{done}/30 completed ({done*100/30:.1f}%)')
exec(compile(s,str(p),'exec'),{'__file__':str(p),'__name__':'__main__'})
