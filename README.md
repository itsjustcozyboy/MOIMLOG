# MOIMLOG

MOIMLOG(모임록)는 교회 소그룹 순장 약 6명이 순모임을 기록하고 교회 양식의 보고서를 만드는 웹 서비스입니다. 2026-11-26에 React 기반 Web/PWA를 공식 배포 플랫폼으로 확정했습니다. 브라우저에서 검증한 Groq 실시간 STT와 구축된 Oracle Cloud 웹 서버를 활용해 접속과 업데이트를 웹으로 통합합니다. 월 운영비 목표는 5,000원 이하이며 유료 API와 Apple 개발자 계정은 사용하지 않습니다.

## 주요 기능

- 홈에서 모임을 시작하고 기록 탭에서 이어서 편집합니다. 로그인 세션은 서버 발급 쿠키로 유지합니다.
- 참석자 동의를 받은 뒤 **웹 화면을 활성화한 상태에서 녹음**하거나 **별도 녹음 파일을 업로드**합니다. 직접 녹음은 AudioWorklet으로 구간을 만들고 IndexedDB에 저장해 연결 복구 후 서버로 재전송합니다.
- Groq Whisper로 전사하고, 순장이 화자와 전사문을 확인한 뒤 GPT-OSS 초안을 편집합니다. 설정에서 등록한 교회 원본 `26_순보고서.docx` 양식으로 보고서를 생성하고 내려받습니다.

## 기술 아키텍처

React · TypeScript · Vite → FastAPI → SQLite 및 계정별 파일 / Groq Whisper 및 GPT-OSS. 개발 환경에서는 Vite가 `/api`를 FastAPI로 프록시합니다. 배포 이미지에서는 FastAPI가 빌드한 웹과 API를 같은 출처에서 제공합니다. 모바일 화면과 PWA manifest가 있으며 서비스 워커는 오프라인 탐색 안내를 제공합니다. 인증 API와 보고서는 서비스 워커에 캐시하지 않습니다.

## 웹 실행

Python, Node.js/npm, 음성 처리를 위한 FFmpeg를 준비합니다.

```bash
bash scripts/setup.sh
npm run dev
```

브라우저에서 `http://localhost:5173`을 엽니다. 설정 스크립트는 `.env`가 없을 때만 예제 파일을 복사합니다. 로컬 HTTP에서는 `COOKIE_SECURE=false`를 사용합니다. Groq 키 없이 로컬 검토 모드를 사용할 수 있습니다.

```bash
npm run build
npm --prefix frontend test
.venv/bin/python -m pytest backend/tests -q
docker compose config --quiet
```

## Oracle Cloud 배포 구조

브라우저 → HTTPS Caddy(Oracle VM 호스트) → `127.0.0.1:8000` → Docker Compose의 FastAPI. 2026-11-17 운영 기록에는 루프백 바인딩이 적용됐으며 당시 저장소에는 `8000:8000`이 남아 있었습니다. 현행 Compose 기본값은 `127.0.0.1:8000:8000`입니다.

운영 반영 전 기존 Compose 프로젝트 이름, `moimlog-data` 볼륨과 `/app/backend/data` 마운트, 실제 `DATA_DIR` 경로를 확인하고 백업·복원을 검증합니다. 기존 `.env`와 Caddy 설정을 유지하고 HTTPS에서 `COOKIE_SECURE=true`인지 확인합니다. 데이터 볼륨을 제거하는 `docker compose down -v`는 사용하지 않습니다. 별도 운영 반영 시 외부 8000 차단, HTTPS와 인증서 자동 갱신을 확인합니다.

## Groq 무료 운영

Groq Console에서 Free 플랜을 유지하고 키는 서버 환경변수로 관리합니다. `GROQ_FREE_ONLY=true`에서 앱은 Whisper Turbo와 GPT-OSS 120B를 사용합니다. 플랜과 청구 상태는 Console에서 확인합니다. `.env.example`의 음성·텍스트 제한은 조직별 Limits에 맞추며 다른 앱의 사용량은 별도로 고려합니다. 한도에 도달하면 동시 녹음의 전사가 서버 대기열에 쌓일 수 있습니다. 녹음과 Groq 전송 전 참석자 동의를 받습니다.

## 현재 개발 및 검증 현황

- 사용자가 브라우저의 Groq 실시간 STT와 2026-11-17 Oracle HTTPS 연결을 확인했습니다. iPhone Safari/PWA 설치·세션 유지·장시간 녹음은 별도 실기기 검증 대상입니다.
- iPhone 화면 잠금과 백그라운드는 녹음 지원 범위에서 제외합니다. Wake Lock과 페이지 비활성화·마이크 중단 안내는 후속 작업입니다.
- 서버 측 초대제, 첫 관리자 생성, 운영 수준 계정 격리 검증, 실제 교회 양식과 Groq 분석을 포함한 종단 간 검증, 백업 복원과 TLS 자동 갱신 확인이 남아 있습니다. 2026-11-17에는 Caddy에서 공개 가입 경로를 차단했습니다.

## 로드맵 및 개발 기록

- [Web/PWA 로드맵](docs/WEB_ROADMAP.md)
- [2026-11-17 Oracle Cloud 구축 기록](docs/history/20261117-oracle-cloud.md)
- [기존 웹·iOS 프로토타입 개발 기록](docs/history/20261119-prototype.md)
- [기존 Groq 운영 및 검증 기록](docs/history/20261119-groq-free.md)
- [2026-11-26 Web-first 결정과 iOS 아카이브 복원](docs/archive/ios-development.md)
