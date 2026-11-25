## iOS 중심 UX 개편 진행 상황
제품 방향은 순장이 대화에 집중하고, 모임 시작 → 녹음 → 전사 및 화자 확인 → 초안 검토 → DOCX 완성으로 이어지는 경험입니다.
홈·기록·내 정보의 세 탭으로 진입 구조를 단순화했습니다. 홈에는 녹음 시작, 미완료 기록 이어하기, 최근 3개 기록을 제공합니다.
화이트와 따뜻한 뉴트럴, 블루 강조색, 44px 이상 조작 영역, 큰 녹음 타이머, 시스템 다크모드 및 동작 줄이기 대응을 추가했습니다.
웹 아이콘은 기존 Lucide를 유지하며 네이티브는 SF Symbols를 사용합니다.

### 프로토타입 실행 및 검증
기존 백엔드 실행 방법을 따른 뒤 `cd frontend && npm install && npm run dev`로 실행합니다.
Codespaces에서 Vite 포트를 열어 iPhone 크기로 확인하세요. `npm run build`, `npm test`가 통과했습니다(기존 단위 테스트 3개).
백엔드·사용자 데이터·DOCX 양식 및 생성 로직은 변경하지 않았습니다. 기존 API와 녹음 저장 경로를 유지했습니다.
실제 브라우저 E2E, 320/375/390/430px 화면 검수, VoiceOver, 마이크 권한과 네트워크 단절 회귀 검증은 아직 수행하지 않았습니다.

### 네이티브 및 남은 작업
[iOS 실행 안내](https://github.com/itsjustcozyboy/MOIMLOG/blob/ios-prototype-archive-20261126/ios/README.md)를 참고하세요. SwiftUI TabView/NavigationStack 및 쿠키 저장소를 사용하는 API 클라이언트 소스를 추가했습니다.
**참고: 위 문단은 초기 프로토타입 시점 기록입니다.** 2026-11-08 기준 최신 [iOS 안내](https://github.com/itsjustcozyboy/MOIMLOG/blob/ios-prototype-archive-20261126/ios/README.md)에는 SwiftUI 인증·AVFoundation 녹음·DOCX 미리보기 및 공유 흐름이 구현되었고 Xcode 빌드가 성공(컴파일 오류 0개)했다고 기록되어 있습니다. 단, 실제 서버·iPhone에서 종단 간 동작은 여전히 미검증입니다.
웹 상세 작성은 기존 7단계 흐름이 남아 있습니다. 참석자 중심 편집, 자동 저장 UX 통합, 전사 구간 재생, 실제 iPhone 화면 검수와 접근성 검증이 다음 작업입니다.
따라서 이번 변경은 전체 리디자인 완료가 아닌 첫 구현 단계입니다.

### 이번 추가 작업 및 Mac 확인 사항

웹 작성 화면의 진행 안내는 모임과 녹음, 나눔 확인, 보고서 완성의 세 구간으로 정리했습니다. 저장된 기존 7개 단계와 서버 API는 호환을 위해 유지합니다. 선택 항목은 접었고, 참석자별 보고서 편집을 펼쳐 볼 수 있습니다.
`ios/project.yml`과 SwiftUI 로컬 녹음·음성 파일 공유 초안을 추가했습니다. **초기 작업 당시 기록:** 당시 네이티브 녹음과 서버 전사·보고서 연결 및 DOCX 공유는 미구현이었습니다. 최신 구현 상태는 아래 'iOS 구현 상태'와 [iOS 안내](https://github.com/itsjustcozyboy/MOIMLOG/blob/ios-prototype-archive-20261126/ios/README.md)를 우선 확인하세요.
Mac에서 XcodeGen으로 프로젝트를 생성하고 서명 설정, 실제 기기 녹음·중단·파일 보존·공유·접근성 검증을 수행하는 절차와 남은 구현은 [iOS 안내](https://github.com/itsjustcozyboy/MOIMLOG/blob/ios-prototype-archive-20261126/ios/README.md)에 있습니다. Xcode 빌드는 실행하지 않았습니다.

### iOS 구현 상태

SwiftUI 앱에 기존 서버 인증·모임 관리, 구간 녹음/STT, 보고서 편집 및 DOCX 공유 흐름을 구현했습니다. **2026-11-08 Mac Xcode 빌드 성공(컴파일 오류 0개)**이 [iOS README](https://github.com/itsjustcozyboy/MOIMLOG/blob/ios-prototype-archive-20261126/ios/README.md)에 기록되어 있습니다. 다만 시뮬레이터 실행과 실제 기기·운영 서버 연결, 로그인, 녹음/STT, DOCX 종단 간 검증은 완료하지 못했습니다. 이번 20261117 결정으로 배포 우선순위는 **초대제 PWA**이며 SwiftUI 소스는 보존합니다.
