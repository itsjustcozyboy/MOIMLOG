from concurrent.futures import ThreadPoolExecutor
import time

import pytest
from fastapi.testclient import TestClient
from sqlalchemy import update

from backend.app.bootstrap_admin import bootstrap
from backend.app.db import AuthSession, SessionLocal
from backend.app.main import app
from conftest import invitation

H = {'X-Moimlog': '1'}
PASSWORD = 'test-password-123'


def credentials(email, token=''):
    return {'email': email, 'password': PASSWORD, 'name': '테스트', 'invitation': token}


def test_invitation_lifecycle(client):
    admin = 'administrator@test.example'
    bootstrap(admin, PASSWORD)
    with pytest.raises(ValueError):
        bootstrap('duplicate@test.example', PASSWORD)
    route = '/api/admin/invitations'
    assert client.get(route).status_code == 401
    assert client.post('/api/auth/register', json=credentials('public@test.example'), headers=H).status_code == 403
    assert client.post('/api/auth/login', json=credentials(admin), headers=H).status_code == 200
    assert client.get('/api/me').json()['isAdmin']
    assert client.post(route, headers={**H, 'Sec-Fetch-Site':'cross-site'}).status_code == 403
    assert client.post(route).status_code == 403
    revoked = client.post(route, headers=H).json()
    assert client.delete(f"{route}/{revoked['id']}", headers=H).status_code == 200
    ready = client.post(route, headers=H).json()
    assert all('token' not in row for row in client.get(route).json())

    guest = TestClient(app)
    for token in (revoked['token'], invitation(int(time.time())-1)):
        assert guest.post('/api/auth/register', json=credentials('guest@test.example', token), headers=H).status_code == 403
    assert guest.post('/api/auth/register', json=credentials('guest@test.example', ready['token']), headers=H).status_code == 200
    assert guest.get(route).status_code == 403
    assert guest.post('/api/auth/register', json=credentials('second@test.example', ready['token']), headers=H).status_code == 403


def test_concurrent_invitation_claim(client):
    token = invitation()
    def register(i):
        return TestClient(app).post('/api/auth/register', json=credentials(f'parallel-{i}@test.example', token), headers=H).status_code
    with ThreadPoolExecutor(max_workers=2) as pool:
        assert sorted(pool.map(register, range(2))) == [200, 403]


def test_cookie_expiry_and_logout(account, monkeypatch):
    email = account.get('/api/me').json()['email']
    with SessionLocal() as db:
        db.execute(update(AuthSession).values(expires=int(time.time())-1))
        db.commit()
    assert account.get('/api/me').status_code == 401
    monkeypatch.setenv('COOKIE_SECURE','true')
    browser = TestClient(app, base_url='https://testserver')
    login = browser.post('/api/auth/login', json=credentials(email), headers=H)
    assert login.status_code == 200
    cookie = login.headers['set-cookie'].lower()
    assert all(value in cookie for value in ('httponly','secure','samesite=lax'))
    assert browser.get('/api/me').status_code == 200
    assert browser.post('/api/auth/logout', headers=H).status_code == 200
    assert browser.get('/api/me').status_code == 401
