import asyncio, json
import httpx
import pytest
from backend.app.services import ai_analysis


def data(text='발언', speaker='S'):
    return {'meetingDate':'2026-01-01','leader':'순장','participants':[{'id':str(i),'name':'동명이인' if i<2 else str(i)} for i in range(6)],'mapping':{'S':'0'},'segments':[{'speaker':speaker,'text':text}]}

def report():
    return {'meetingDate':'2026-01-01','leader':'순장','meetingSummary':'요약','participants':[{'participantId':str(i),'name':'이름','sermonSharing':'말씀 적용','lifeSharing':'직장','prayerRequests':'','prayerSource':'none','needsReview':False,'warnings':[],'sunday':'unknown','youth':'unknown','meeting':'unknown','qt':'unknown'} for i in range(6)],'unassignedStatements':[],'warnings':[]}

class Client:
    calls=[]
    status=200
    content=None
    async def __aenter__(self): return self
    async def __aexit__(self,*args): pass
    async def post(self,url,**kwargs):
        self.calls.append(kwargs['json'])
        body={'choices':[{'message':{'content':self.content if self.content is not None else json.dumps(report(),ensure_ascii=False)}}]}
        return httpx.Response(self.status,json=body,request=httpx.Request('POST',url),headers={'Retry-After':'60'})

@pytest.fixture
def mock(monkeypatch):
    Client.calls=[]; Client.status=200; Client.content=None
    monkeypatch.setenv('GROQ_API_KEY','mock-key')
    monkeypatch.setattr(ai_analysis.httpx,'AsyncClient',lambda **kw:Client())
    monkeypatch.setattr(ai_analysis,'reserve_text',lambda tokens:None)
    return Client

def test_six_people_and_duplicate_names(mock):
    r=asyncio.run(ai_analysis.analyze(data(),'ai'))
    assert len(r.participants)==6 and r.participants[0].name==r.participants[1].name
    assert r.participants[0].prayerRequests=='' and r.participants[1].lifeSharing==''
    assert mock.calls[0]['response_format']['json_schema']['strict'] is True

def test_unidentified_never_sent(mock):
    r=asyncio.run(ai_analysis.analyze(data('김님 기도해 주세요',None),'ai'))
    assert r.unassignedStatements==['김님 기도해 주세요'] and not mock.calls
    assert all(not p.lifeSharing for p in r.participants)

def test_long_transcript_chunking(mock):
    text='말씀과 삶을 나누었습니다. '*800
    r=asyncio.run(ai_analysis.analyze(data(text),'ai'))
    assert len(mock.calls)>1 and len(r.participants)==6
    assert ''.join(json.loads(c['messages'][1]['content'])['segments'][0]['text'] for c in mock.calls)==text

@pytest.mark.parametrize('status,message',[(429,'사용량 제한'),(401,'키')])
def test_api_errors_preserve_input(mock,status,message):
    mock.status=status
    with pytest.raises(ValueError,match=message): asyncio.run(ai_analysis.analyze(data(),'ai'))
    assert len(mock.calls)==1

def test_invalid_json(mock):
    mock.content='{broken'
    with pytest.raises(ValueError,match='형식'): asyncio.run(ai_analysis.analyze(data(),'ai'))

def test_wrong_model_blocked(mock,monkeypatch):
    monkeypatch.setenv('GROQ_TEXT_MODEL','other')
    with pytest.raises(ValueError,match='모델'): asyncio.run(ai_analysis.analyze(data(),'ai'))
    assert not mock.calls
