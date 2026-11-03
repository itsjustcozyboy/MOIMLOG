# MOIMLOG

순모임 녹음과 전사문을 검토하고 참석자별 나눔을 정리해 기존 `26_순보고서.docx`로 내려받는 웹앱입니다. 참석자 동의 후 Groq Whisper로 음성을 전사하고 Groq GPT-OSS로 보고서 초안을 만듭니다. 순장이 화자 연결과 결과를 확인하고 수정해야 합니다.

## 시작하기

Python 가상환경에 `backend/requirements.txt`를 설치하고 `npm --prefix frontend install`을 실행합니다. `.env.example`을 참고해 환경변수를 설정한 뒤 `npm run dev`를 실행합니다. 배포 시 HTTPS와 `COOKIE_SECURE=true`를 사용하세요. 보고서 생성에는 설정 화면에서 교회의 원본 DOCX를 등록해야 합니다. 저장소의 원본 양식은 변경하지 않습니다.

## Groq Free 기반 운영

Groq Console에서 API 키를 발급하고 GitHub 저장소의 Settings → Secrets and variables → Codespaces에 `GROQ_API_KEY`를 등록하세요. Codespace를 재시작하거나 환경에 키가 반영되었는지 확인합니다. 키 값을 소스나 로그에 기록하지 마세요. STT는 `whisper-large-v3-turbo`, 분석은 Groq Chat Completions의 `openai/gpt-oss-120b`를 사용합니다. OpenAI API 키, 다른 공급자, Batch와 Flex는 사용하지 않습니다.

`GROQ_FREE_ONLY=true`가 기본 설정이며 서버는 텍스트 모델을 GPT-OSS 120B로, 음성 모델을 Whisper Turbo로 고정합니다. 이 설정은 계정의 결제 플랜이나 청구를 확인하거나 강제할 수 없습니다. **사용자가 Groq Console에서 Free 플랜을 유지해야 하며, 실제 청구 여부는 Console에서 확인해야 합니다.** 이 앱은 플랜 변경이나 결제수단 등록을 하지 않습니다.

`.env.example`의 `GROQ_RPM`, `GROQ_RPD`, `GROQ_ASH`, `GROQ_ASD`는 음성 제한, `GROQ_TEXT_RPM`, `GROQ_TEXT_RPD`, `GROQ_TEXT_TPM`, `GROQ_TEXT_TPD`는 분석 제한입니다. 조직의 [Limits 화면](https://console.groq.com/settings/limits)에 맞춰 설정하세요. 기본값은 각각 음성 20 RPM / 2,000 RPD / 7,200 ASH / 28,800 ASD, 텍스트 30 RPM / 1,000 RPD / 8,000 TPM / 200,000 TPD입니다. RPM/RPD는 분/일 요청 수, TPM/TPD는 분/일 토큰, ASH/ASD는 시간/일 음성 초입니다. [공식 제한표](https://console.groq.com/docs/rate-limits)는 변경되며 조직별 예외가 있을 수 있습니다. 이 로컬 보수적 카운터는 다른 앱의 사용량을 알지 못하므로 실제 제한이나 무료 이용을 보장하지 않습니다. STT 무료 업로드 파일 한도는 [공식 문서](https://console.groq.com/docs/speech-to-text)에 따라 25 MB이며 서버가 큰 파일을 분할합니다.

직접 녹음은 약 15초 단위로 원본을 서버에 저장하고 영속 큐가 순서대로 전사합니다. 음성 한도에 도달하면 녹음을 계속 보관하며 큐에서 기다립니다. Groq 429는 Retry-After를 고려해 최대 3회 시도하고 이후 수동 재시도를 요구합니다. 업로드와 분석은 제한 시 보관된 원본이나 기존 보고서를 유지하고 수동 재시도를 안내합니다. 텍스트 분석은 작은 구간으로 나누고 SQLite에 요청 및 보수적인 토큰 예약을 기록합니다. 제한은 프로세스 재시작 후에도 유지되지만, 분석 자체의 부분 결과는 저장되지 않아 실패 후 전체 구간을 다시 분석합니다. 다른 제공자로 전환하지 않습니다.

텍스트의 미확인 화자 발언은 분석 모델에 참석자별 내용으로 전달하지 않고 별도 검토 항목으로 보관합니다. 확인된 매핑도 자동 화자 분리가 아니므로 순장이 직접 확인해야 합니다. AI 결과의 사실성이나 기도제목 출처는 보장할 수 없습니다. 민감한 개인 정보가 Groq로 전송되므로 녹음과 외부 전송 전에 모든 참석자의 동의를 받고 결과를 검토하세요. 직접 녹음한 원본은 보관 기간 동안 서버에 남습니다. 로컬 검토 모드는 AI 호출 없이 수동 분류할 수 있습니다.

6명이 같은 시간에 각각 2시간을 녹음하면 중첩 전송을 제외해도 시간당 21,600 음성 초가 필요합니다. 기본 7,200 ASH에서는 준실시간 처리가 밀립니다. 월 52시간의 총량만으로 실현 가능성을 보장할 수 없고, 모임의 일별·시간별 집중, 전송 중첩과 재시도, 각 조직의 실제 제한, 텍스트 토큰 사용량을 함께 고려해야 합니다. 외부 호스팅과 저장소 비용은 앱의 API 제한으로 통제되지 않으므로 월 5,000원 전체 예산도 별도 확인해야 합니다.

## 검증 및 남은 작업

자동 테스트는 `PYTHONPATH=. .venv/bin/pytest -q`, 프런트엔드 빌드는 `npm --prefix frontend run build`로 실행합니다. 테스트의 Groq 응답은 Mock이며 실제 Groq 호출이나 결제는 수행하지 않았습니다. 실제 한국어 STT, GPT-OSS의 스키마 수용과 분석 정확도, 장시간 실제 음성, 여러 순장 동시 사용 및 실제 무료 한도 내 운영은 별도 검증이 필요합니다. 특히 재시작 후 분석 부분 결과 복구, 텍스트 분석 요청의 영속 대기열과 월별 실제 토큰 표시, 자동 화자 분리는 아직 구현되지 않았습니다.
