"""Persistent, deployment-wide conservative reservations, including failed requests."""
import os, sqlite3, json
from datetime import datetime, timezone
from ..db import DATA

def reserve(provider, amount, usage):
    if amount < 0: raise ValueError('잘못된 비용입니다.')
    with sqlite3.connect(DATA/'usage.sqlite') as db:
        db.execute('CREATE TABLE IF NOT EXISTS usage (month TEXT, provider TEXT, krw REAL, detail TEXT)')
        db.execute('BEGIN IMMEDIATE')
        month=datetime.now(timezone.utc).strftime('%Y-%m')
        total=db.execute('SELECT COALESCE(SUM(krw),0) FROM usage WHERE month=?',(month,)).fetchone()[0]
        if total+amount>float(os.getenv('AI_MONTHLY_BUDGET_KRW','5000')):
            raise ValueError('월 AI 예산 초과 위험으로 추가 처리를 차단했습니다.')
        db.execute('INSERT INTO usage VALUES (?,?,?,?)',(month,provider,amount,json.dumps(usage)))
