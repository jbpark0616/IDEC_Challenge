from pathlib import Path
import sys
import pypdfium2 as pdfium
from PIL import Image,ImageOps,ImageDraw
from pypdf import PdfReader
p=Path(sys.argv[1]);out=p.parent/'pages';out.mkdir(exist_ok=True)
d=pdfium.PdfDocument(str(p));thumbs=[]
for i,page in enumerate(d):
    im=page.render(scale=1.5).to_pil().convert('RGB');im.save(out/f'page-{i+1}.png')
    im.thumbnail((300,430));thumb=Image.new('RGB',(320,460),'#dddddd');thumb.paste(im,((320-im.width)//2,20));ImageDraw.Draw(thumb).text((10,442),f'Page {i+1}',fill='black');thumbs.append(thumb)
for batch in range(0,len(thumbs),8):
    subset=thumbs[batch:batch+8];sheet=Image.new('RGB',(1280,460*((len(subset)+3)//4)),'white')
    for j,im in enumerate(subset):sheet.paste(im,((j%4)*320,(j//4)*460))
    sheet.save(out/f'contact-{batch//8+1}.png')
reader=PdfReader(str(p))
for i,page in enumerate(reader.pages):
    text=page.extract_text()
    print(i+1,text[:70].replace('\n',' '))
    if '4.3' in text or 'Fig. 7.' in text or '재매핑' in text:print('REVIEW',i+1)
print('PAGES',len(d))
