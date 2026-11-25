# SwiftUI iOS 프로토타입 아카이브

- 2026-11-05~11-19. 순장이 iPhone에서 모임 기록, 녹음, 보고서 공유를 이어서 할 수 있도록 네이티브 UX를 개발했다. SwiftUI 탭과 탐색, 기존 API 인증과 Keychain 세션 복구, 모임 관리, AVFoundation 녹음과 구간 저장·재전송, STT 및 보고서 편집, DOCX 미리보기·공유를 구현했다.
- 2026-11-08. 당시 Mac Xcode 빌드 성공과 컴파일 오류 0개가 기록됐다. 이후 최종 소스의 재빌드, 시뮬레이터 실행, iPhone에서 운영 서버 로그인·세션 복구·장시간 녹음·중단 복구·STT·DOCX 공유 종단 간 검증은 확인되지 않았다.
- 2026-11-17. Oracle Cloud 웹 서버 구축 및 초대제 PWA 우선 방향을 기록했다.
- 2026-11-26. 순장 약 6명 규모에서 Apple 연회비와 별도 배포·유지보수 부담을 줄이기 위해 Web/PWA를 공식 플랫폼으로 확정했다. 브라우저 Groq 실시간 STT 검증과 Oracle 웹 서버 구축을 바탕으로 접속과 업데이트를 웹으로 통합한다.

마지막 iOS 커밋은 2026-11-19의 `9f0ccde4d84f77103a5c5097e10dcb3add5b6623`이다. 태그의 커밋과 복원한 `ios/` 파일을 확인한 뒤 현행 브랜치에서 제거했다.

```bash
git fetch origin tag ios-prototype-archive-20261126
git worktree add --detach ../MOIMLOG-ios-archive ios-prototype-archive-20261126
```

복원 경로는 `../MOIMLOG-ios-archive/ios/`이다. 실행 방법과 검증 기록은 태그의 [iOS README](https://github.com/itsjustcozyboy/MOIMLOG/blob/ios-prototype-archive-20261126/ios/README.md)와 [Phase 1 검증 문서](https://github.com/itsjustcozyboy/MOIMLOG/blob/ios-prototype-archive-20261126/ios/PHASE1_VALIDATION.md)에 있다.
