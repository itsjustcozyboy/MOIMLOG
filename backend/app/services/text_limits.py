"""Conservative persistent per-deployment reservations; shared Groq usage is authoritative."""
import os, sqlite3, time
from ..db import DATA

def reserve_text(tokens):
    now=time.time()
    with sqlite3.connect(DATA/'text_usage.sqlite',timeout=30) as db:
        db.execute('CREATE TABLE IF NOT EXISTS calls (at REAL, tokens INTEGER)')
        db.execute('BEGIN IMMEDIATE')
        for window, column, limit in [(60,'COUNT(*)',int(os.getenv('GROQ_TEXT_RPM','30'))),(86400,'COUNT(*)',int(os.getenv('GROQ_TEXT_RPD','1000'))),(60,'COALESCE(SUM(tokens),0)',int(os.getenv('GROQ_TEXT_TPM','8000'))),(86400,'COALESCE(SUM(tokens),0)',int(os.getenv('GROQ_TEXT_TPD','200000')))]:
            used=db.execute(f'SELECT {column} FROM calls WHERE at>?',(now-window,)).fetchone()[0]
            if used+(1 if column=='COUNT(*)' else tokens)>limit:
                raise ValueError('Groq 텍스트 사용량 제한 대기 중입니다. 원문과 보고서는 보존되었습니다. 나중에 수동 재시도해 주세요.')
        db.execute('INSERT INTO calls VALUES (?,?)',(now,tokens))
