## 20261117 작업 기록 — Oracle Cloud 서버 구축 및 초대제 PWA 방향 확정

> **기록 기준:** 2026-11-17 작업 기록(한국 시간으로 자정을 넘겨 이어진 설정 포함). 아래 '완료'는 사용자가 Oracle 콘솔·SSH 터미널 및 브라우저에서 확인해 전달한 결과를 뜻합니다. GitHub 소스코드 변경이나 자동화된 운영 통합 테스트 완료를 의미하지 않습니다.

### 목표 및 제품 결정

- **대상:** 교회 소그룹 순장 약 6명, 최대 2시간 모임 녹음. 월 운영비 목표 5,000원 이하.
- **주요 흐름:** 초대 링크 → 계정 생성·로그인 → 녹음 → Groq STT → 화자 확인 및 GPT-OSS 보고서 초안 → 순장 검토 → 기존 교회 DOCX 양식으로 완성.
- **배포 방향 결정:** **선택 A — 설치형 웹앱(PWA)** 우선. App Store / TestFlight 배포 없이 초대 링크로 접속하고 iPhone Safari에서 홈 화면에 추가해 사용. 기존 SwiftUI iOS 소스는 삭제하지 않고 보존.
- **서버 아키텍처:** 기존 FastAPI + React + Groq + SQLite를 Oracle Cloud Ubuntu VM에서 Docker Compose로 운영. GitHub Pages나 Vercel로 백엔드를 이전하지 않음.

### 오늘 완료한 인프라 작업 (사용자 확인)

| 영역 | 완료·확인 내용 |
| --- | --- |
| Oracle Cloud | Always Free-eligible `VM.Standard.A1.Flex` 선택, Ubuntu 24.04 ARM64, 1 OCPU / 6GB RAM, 기본 부트 볼륨으로 `moimlog-server` 생성. **무료 표시는 월 과금 0원을 보증하지 않으므로 계정 사용량 점검 필요** |
| 네트워크 | `moimlog-vcn`과 Public Subnet 생성, 공인 IPv4 할당, Mac → Ubuntu SSH 접속 확인 |
| Docker | Docker Engine 및 Compose 설치; 사용자가 `docker compose version v5.8.0` 결과 확인 |
| 배포 | GitHub MOIMLOG 코드 복제 및 `sudo docker compose up -d --build` 실행; `moimlog-moimlog-1` 컨테이너가 `Up` 상태로 확인됨 |
| 내부 API | 컨테이너 포트를 `127.0.0.1:8000:8000`으로 바꿔 외부 직접 접근을 제한; `curl http://127.0.0.1:8000/api/config` 정상 응답을 사용자 확인 |
| 환경변수 | Oracle VM의 별도 `.env`에 기존 Groq 키·`GROQ_FREE_ONLY=true`·`COOKIE_SECURE=true` 등을 설정. **실제 Groq 음성 전사/분석 호출은 미검증** |
| 네트워크 보안 | Oracle Ingress에서 외부 HTTPS TCP 443 허용; HTTP 80과 FastAPI 8000은 외부 개방하지 않음. SSH 22는 현재 모든 IP 허용으로 확인되어 범위 축소 필요 |
| HTTPS | Caddy **v2.11.9** 설치. IP 주소용 ACME 단기 인증서를 요청하는 Caddyfile 적용, `caddy validate`의 `Valid configuration` 확인. 사용자가 외부 HTTPS `/api/config` 접속 성공을 확인 |
| 임시 접근 제어 | Caddy에서 `/api/auth/register`, `/docs`, `/redoc`, `/openapi.json` 경로 차단 설정. **회원가입의 서버 자체 초대제 검증은 아직 미구현** |

**주의:** Docker Compose의 로컬 포트 변경, Caddy 설정, Oracle 방화벽, VM의 `.env`는 **Oracle 서버에 적용한 운영 설정**이며 현재 GitHub의 `docker-compose.yml`과 동일하다고 가정하면 안 됩니다. 운영 설정을 재현 가능한 형태로 코드화·문서화하되 API 키, SSH 개인키, 실제 비밀 정보는 커밋하지 않습니다. 서비스 공인 IP는 README에 직접 기재하지 않습니다.

### 20261117 기준 미완료·미검증

- 실제 사용자 계정 생성, 외부 iPhone/PWA 로그인 및 세션 유지, 여러 계정 간 기록 격리 테스트.
- 실기기 마이크 권한, 실제 Groq STT·GPT-OSS 분석, 교회 원본 `26_순보고서.docx` 업로드 및 보고서 DOCX 다운로드 전 과정.
- **공개 회원가입은 현재 Caddy에서 차단**돼 있으므로 초대 링크 계정 생성 기능 도입 전에는 일반 사용자 가입이 불가. 최초 운영자 계정 생성 절차도 별도로 완료·검증해야 함.
- 오디오 원본은 현재 라이브 녹음 큐의 SQLite BLOB과 기기 로컬 저장소에 남을 수 있으며, **STT 완료 후 자동 삭제가 아직 구현되지 않음**.
- IP 주소용 단기 TLS 인증서의 **자동 갱신 성공 여부**, 백업·복구, 장시간 실행 및 서버 재부팅 뒤 자동 복구 미검증.
- Oracle Always Free 용량/CPU·Groq Free 호출 한도/동시 녹음 처리량은 실제 모임 부하에 대한 검증 필요. 6명 동시 2시간 녹음은 기본 7,200 ASH 제한에서 준실시간 STT를 보장하지 못함.

### 다음 개발 계획 (우선순위)

1. **배포 보안과 재현성:** SSH 22 접속 허용 범위를 관리자의 IP로 축소(기존 SSH 접속 유지 확인 후), OS 보안 업데이트, Caddy 인증서 자동 갱신 검증, HTTPS/응답 헤더/인증/계정별 데이터 격리 점검. GitHub 설정과 Oracle 운영 파일 간 차이를 안전하게 관리.
2. **서버 측 초대제:** 외부 공개 회원가입을 백엔드에서도 차단하고, 관리자 전용 초대 링크 발급·만료·일회용 사용·취소 기능 및 최초 관리자 안전 생성 절차 구현. Caddy 차단만으로 인증을 보장하지 않음.
3. **PWA 설치 및 접속:** React 웹앱의 manifest, 서비스 워커, iPhone Safari '홈 화면에 추가' 흐름을 실제 기기에서 검증하고 초대 링크→회원가입→로그인 경험 완성. SwiftUI iOS 앱은 유지.
4. **2시간 녹음 안정화:** 기존 AudioWorklet 약 15초 구간 분할 녹음과 IndexedDB 로컬 저장/재전송 보존. Screen Wake Lock(지원 기기), 화면·마이크·AudioContext 중단 감지, 복귀 후 재개와 누락 구간 복구를 보완. **iOS PWA의 화면 잠금·백그라운드 녹음 지속은 플랫폼 제약으로 보장하지 않으며**, 이를 UI에 명확히 안내.
5. **음성 보관 최소화:** STT 및 전사문 저장이 완전히 확인된 후 짧은 복구 유예기간을 거쳐 음성 원본 삭제; 실패·재시도 구간은 보관. iPhone/브라우저 로컬 복사본 정리 및 SQLite 공간 회수 정책과 테스트 추가.
6. **실사용 검증:** iPhone Safari/PWA에서 30·60·120분 테스트, 화면 잠금/앱 전환/통화/네트워크 끊김/재진입, 6명 동시 부하, 녹음→전사→수정→분석→DOCX 생성 회귀 테스트 및 개인정보 동의 검증.
7. **운영 준비:** SQLite 볼륨 백업과 **복원 테스트**, 저장기간·삭제 정책, 무료 한도 모니터링, IP 변경 대응 및 장애 대응 안내 수립. 운영 사용자 온보딩 전 보안 검증 결과 기록.

**상태 요약:** Oracle VM의 **Docker + FastAPI + HTTPS 연결까지 사용자 확인 완료**. **초대제/PWA 설치 검증/실제 녹음/운영 보안 강화는 향후 작업**이며, 프로덕션 사용 가능이나 2시간 백그라운드 녹음 보장 상태가 아닙니다.

---
