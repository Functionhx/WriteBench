from pathlib import Path
from zipfile import ZipFile
from xml.etree import ElementTree as ET
import subprocess,re,json,hashlib,unicodedata
import argparse
parser=argparse.ArgumentParser(description='Extract user-provided CET-6 writing/translation papers with PDF/DOCX cross-checks.')
parser.add_argument('--source',type=Path,required=True)
args=parser.parse_args()
source=args.source
repo=Path(__file__).resolve().parents[1]
base=json.loads((repo/'Shared/QuestionBank/cet6-2022-2026.json').read_text())
ns={'w':'http://schemas.openxmlformats.org/wordprocessingml/2006/main'}
def normalize(text):
    text=re.sub(r'\s+',' ',text).strip()
    # Remove layout-only splits within Chinese words, preserving English word boundaries.
    text=re.sub(r'(?<=[\u3400-\u9fff])\s+(?=[\u3400-\u9fff])','',text)
    match=re.search(r'[\u3400-\u9fff]',text)
    if match:
        prefix,body=text[:match.start()].strip(),text[match.start():]
        body=re.sub(r'(?<![A-Za-z])\s+|\s+(?![A-Za-z])','',body)
        text=prefix+'\n\n'+body
    return text

def word_parts(path):
    with ZipFile(path) as z: root=ET.fromstring(z.read('word/document.xml'))
    lines=[''.join(n.text or '' for n in para.findall('.//w:t',ns)) for para in root.findall('.//w:p',ns)]
    start=next(i for i,line in enumerate(lines) if re.match(r'^Part\s+I\s+Writing',line))
    end=next(i for i,line in enumerate(lines) if re.match(r'^Part\s+II\s+Listening',line))
    translation=next(i for i,line in enumerate(lines) if re.match(r'^Part\s+IV\s+Translation',line))
    return normalize(' '.join(lines[start+1:end])),normalize(' '.join(lines[translation+1:]))

def pdf_parts(path):
    result=subprocess.run(['pdftotext','-layout',str(path),'-'],capture_output=True,text=True,check=True).stdout
    lines=[line for line in result.splitlines() if '懒笔记 · https://' not in line]
    result='\n'.join(lines)
    w=re.search(r'Part\s+I\s+Writing[^\n]*\n(.*?)Part\s+II\s+Listening',result,re.S)
    t=re.search(r'Part\s+IV\s+Translation[^\n]*\n(.*)$',result,re.S)
    assert w and t,path
    return normalize(w.group(1)),normalize(t.group(1))

audit=[]
for year,month,setno in sorted({(r['year'],r['month'],r['set']) for r in base['questions']}):
    stem=f'英语六级{year}年{month}月第{setno}套真题（整卷）'
    pdf=source/str(year)/(stem+'.pdf');docx=source/str(year)/(stem+'.docx')
    w,t=word_parts(docx);pw,pt=pdf_parts(pdf)
    match=(w==pw and t==pt)
    if not match:
        print('MISMATCH',year,month,setno,'writing',w==pw,'translation',t==pt)
        for label,a,b in [('writing',w,pw),('translation',t,pt)]:
            if a!=b: print(label,repr(a),repr(b))
    assert match,(year,month,setno)
    assert w.startswith('Directions:') and '150' in w and '200' in w and len(w)>100
    assert t.startswith('Directions:') and 'Chinese into English' in t and len(re.findall(r'[\u3400-\u9fff]',t))>100
    assert all(x not in w+t for x in ['懒笔记','参考译文','参考范文','答案解析','Part II','Questions 1'])
    for task,prompt in [('cet6Writing',w),('cet6Translation',t)]:
        row=next(r for r in base['questions'] if (r['year'],r['month'],r['set'],r['task'])==(year,month,setno,task))
        row['prompt']=prompt
        for fix in row.get('layoutCorrections',[]):
            if fix['original'] in row['prompt']: row['prompt']=row['prompt'].replace(fix['original'],fix['corrected'])
        row['verification']='providedDocument'
        row['sourceFile']=str(pdf.relative_to(source));row['sourceSha256']=hashlib.sha256(pdf.read_bytes()).hexdigest()
    audit.append(dict(year=year,month=month,set=setno,pdf=str(pdf.relative_to(source)),pdfSha256=hashlib.sha256(pdf.read_bytes()).hexdigest(),docxSha256=hashlib.sha256(docx.read_bytes()).hexdigest(),crossCheck='PDF and DOCX match after whitespace normalization',writingLength=len(w),translationLength=len(t)))
base['questions'].sort(key=lambda r:(-r['year'],-r['month'],r['set'],r['task']))
(repo/'Shared/QuestionBank/cet6-2022-2026.json').write_text(json.dumps(base,ensure_ascii=False,indent=2)+'\n')
(repo/'Shared/QuestionBank/cet6-import-audit.json').write_text(json.dumps(dict(source='User-provided local PDF and DOCX files',paperCount=len(audit),questionCount=len(base['questions']),papers=audit),ensure_ascii=False,indent=2)+'\n')
print(f'Extracted {len(base["questions"])} questions from {len(audit)} user-provided papers; all PDF/DOCX cross-checks passed.')
