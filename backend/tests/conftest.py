import os, tempfile
# Tests use an isolated database and generated synthetic templates, never the church original.
os.environ['DATA_DIR']=tempfile.mkdtemp(prefix='moimlog-tests-')
os.environ['DATABASE_URL']='sqlite:///'+os.environ['DATA_DIR']+'/test.db'
os.environ.pop('OPENAI_API_KEY',None)
import pytest
from fastapi.testclient import TestClient
from backend.app.main import app, ATTEMPTS

@pytest.fixture
def client():
    ATTEMPTS.clear()
    with TestClient(app) as c:yield c

@pytest.fixture
def account(client):
    import uuid
    email=str(uuid.uuid4())+'@test.example'
    r=client.post('/api/auth/register',json={'email':email,'password':'test-password-123','name':'테스트 순장'},headers={'X-Moimlog':'1'})
    assert r.status_code==200,r.text
    return client

@pytest.fixture
def info():
    return {'meetingDate':'2026-10-18','leader':'김정환','title':'테스트 모임','participants':[{'id':'p1','name':'김정환'},{'id':'p2','name':'김정환'}]}

@pytest.fixture
def meeting(account,info):
    return account.post('/api/meetings',json=info,headers={'X-Moimlog':'1'}).json()
