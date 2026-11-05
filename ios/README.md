# iOS 네이티브 기반

SwiftUI TabView와 화면, 기기 로컬 녹음과 오디오 파일 공유의 초기 구현입니다. 앱은 아직 서버 인증, 참석자 선택, 구간 전송/STT, 보고서 편집, DOCX 공유와 연결되지 않았습니다. 녹음은 기기에만 저장됩니다. `project.yml`은 XcodeGen 프로젝트 정의이며 저장소에는 생성된 `.xcodeproj`가 없습니다.

## Mac에서 프로젝트 생성과 실행

1. Xcode와 명령줄 도구, XcodeGen을 설치합니다. 저장소 루트에서 `cd ios && xcodegen generate`를 실행합니다.
2. `open MOIMLOG.xcodeproj`로 열고 Signing & Capabilities에서 자신의 Team과 고유한 Bundle Identifier를 설정합니다.
3. iOS 16 이상 iPhone을 선택해 빌드합니다. 마이크 권한 대화상자를 확인하고 참석자의 동의를 받은 뒤 녹음합니다.
4. 녹음 종료 후 공유 버튼으로 파일 앱 저장과 공유를 확인합니다. 현재 공유 대상은 DOCX가 아닌 로컬 음성 파일입니다.
5. 잠금 화면, 전화·오디오 중단, 마이크 권한 거부, 저장 공간 부족, 최대 길이 및 앱 종료 후 파일 보존을 실기기에서 검증합니다. Background Audio 설정만으로 백그라운드 녹음이 지속된다고 보장하지 않습니다.
6. Dynamic Type 최대 크기, VoiceOver, 다크모드와 Reduce Motion을 실제 기기에서 검증합니다.

## 서버 연결 전 작업

HTTPS API 주소를 구성하고 로그인·로그아웃·만료 시 `URLSession` 쿠키와 사용자별 데이터 격리를 실기기에서 검증해야 합니다. 서버는 `HttpOnly`, `SameSite=Lax` 쿠키를 사용하며 운영 환경에서 `COOKIE_SECURE=true`가 필요합니다. API 키는 서버에서만 관리합니다. AVAudioSession 중단 복구, 지속적 구간 저장·재전송, 기기 파일의 복구 UI, 서버 녹음 프로토콜, DOCX 다운로드·Quick Look·공유를 구현하고 테스트해야 합니다.

Xcode 빌드와 iOS 시뮬레이터 및 실기기 테스트는 Codespaces에서 수행하지 않았습니다. 현재 코드는 출시 준비가 된 녹음 기능이 아닙니다.