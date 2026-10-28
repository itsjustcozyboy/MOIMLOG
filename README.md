# 모임록 (MOIMLOG)

교회 순모임의 녹취를 검토하고 참석자별 보고서를 작성하는 모바일 우선 웹앱입니다. 참석자의 동의를 먼저 받고, 실제 개인정보는 접근이 통제된 환경에서만 사용하세요.

## 시작하기

Python 3.10 이상, Node.js 20 이상과 npm이 필요합니다. 음성 파일을 사용하려면 `ffprobe`(ffmpeg 패키지)도 설치하세요.

```bash
bash scripts/setup.sh
npm run dev
```

프런트엔드는 http://localhost:5173, API는 http://localhost:8000 에서 실행됩니다. Codespaces에서는 **포트** 탭에서 5173을 열어 접속하세요. 공개 포트에 민감한 자료를 올리지 말고 접근 권한과 HTTPS 설정을 확인하세요. 종료는 터미널에서 Ctrl+C를 누릅니다.

`.env`는 설치 스크립트가 `.env.example`에서 생성합니다. 설정을 바꾼 후 서버를 재시작하세요.

| 변수 | 용도 |
| --- | --- |
| `OPENAI_API_KEY` | 실제 AI 분석 키. 비어 있으면 로컬 검토 모드만 제공 |
| `OPENAI_MODEL` | 분석 모델 |
| `CLOVA_SPEECH_INVOKE_URL`, `CLOVA_SPEECH_SECRET` | CLOVA Speech 장문 인식 설정 |
| `DATA_DIR` | SQLite 및 사용자 파일 저장 위치 |
| `DATABASE_URL` | 선택적인 SQLite 연결 문자열 |
| `COOKIE_SECURE` | HTTPS 환경에서 `true`로 설정 |

키가 없으면 UTF-8 TXT를 업로드하고 화자를 연결한 뒤 **로컬 검토 초안**을 만들 수 있습니다. 이는 AI 분석이 아니며 원문을 임시 배치하므로 수동 분류가 필요합니다. 화자가 불명확한 내용은 미배정 상태로 남습니다. 실제 GPT 및 CLOVA 이용에는 별도 서비스 설정과 비용이 필요할 수 있습니다.

## 보고서 양식

교회에서 제공한 원본 `26_순보고서.docx`를 `backend/templates/26_순보고서.docx`에 배치하거나 로그인 후 설정에서 계정별로 업로드하세요. 원본이 없으면 다운로드할 수 없습니다. 표의 열 또는 반복 블록을 인식해 기존 구조를 복사하지만 모든 원본 양식에 대한 호환성은 보장되지 않습니다. 실제 원본으로 생성된 문서를 Word에서 확인하세요. 테스트용 합성 양식은 교회 원본이 아닙니다.

## 테스트 및 배포

```bash
npm test
npm run build
npm run test:e2e
```

E2E 테스트는 실행 중인 개발 서버와 Playwright Chromium이 필요합니다. 테스트는 합성 양식과 샘플 전사문을 사용합니다.

Docker 사용 시 `.env`를 준비하고 `docker compose up --build`를 실행한 뒤 8000 포트로 접속하세요. 데이터는 Docker 볼륨에, 공통 양식은 읽기 전용으로 마운트됩니다. 공개 서비스에서는 HTTPS, 안전한 쿠키, 비공개 데이터 저장소, 백업과 접근 제한을 별도로 구성하고 보안 검토를 거쳐야 합니다. 현재 내장 세션, 단일 프로세스 작업 큐와 SQLite는 소규모 MVP용입니다.

## 구성과 제약

- `frontend/`: React, TypeScript, Vite, React Router, TanStack Query 및 PWA
- `backend/app/`: FastAPI, Pydantic, SQLAlchemy, SQLite와 분석·음성·DOCX 서비스
- `backend/tests/`, `frontend/e2e/`: API 및 브라우저 테스트
- `samples/`: 개인정보가 아닌 테스트 전사문

참석 여부는 기본 미확인입니다. 녹음과 전사문은 각각 CLOVA와 OpenAI에 전송될 수 있으므로 화면의 동의를 확인하세요. 데이터 보관 기간은 마지막 수정 시각 기준이며 정리 작업은 서버 시작 시와 실행 중 주기적으로 수행됩니다. 작업 중 서버가 재시작되면 처리를 다시 시작해야 합니다. 실서비스 전 원본 양식 호환성, 실제 외부 API, 긴 녹음과 브라우저별 녹음 동작, 운영 보안 및 복구 절차를 검증해야 합니다.
