import re

def parse_transcript(text: str):
    segments=[]
    current=None
    # Explicit speaker labels only. Names are never automatically assigned to attendees.
    pattern=re.compile(r'^\s*(Speaker\s*\d+|화자\s*\d+|[^:\n\[\]]{1,40})\s*(?:\[([^\]]+)\])?\s*[:：]\s*(.*)$',re.I)
    stamp=re.compile(r'^\s*(Speaker\s*\d+|화자\s*\d+)\s*\[([^\]]+)\]\s*(.*)$',re.I)
    for line in text.splitlines():
        if not line.strip(): continue
        m=pattern.match(line) or stamp.match(line)
        if m:
            current={'speaker':None if m[1].strip() in ('미확인','화자 미확인') else m[1].strip(),'text':m[3].strip(),'timestamp':m[2] or ''}
            segments.append(current)
        elif current:
            current['text']+='\n'+line
        else:
            segments.append({'speaker':None,'text':line,'timestamp':''})
    return segments
