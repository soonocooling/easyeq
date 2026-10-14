# easyeq

macOS 메뉴바에 상주하다가, 한글·영어로 쓴 수식 표현을 드래그하거나 입력하면 수식 후보를 띄워 그 자리를 바꿔 입력해주는 개인용 앱. 기획서는 [product-spec.md](product-spec.md), 사용법은 앱 메뉴의 "사용 설명서"([docs/manual.html](docs/manual.html), [English](docs/manual.en.html)).

## 현재 상태

| 단계 | 상태 |
|---|---|
| Phase 0 기술 검증 스파이크 | 완료 — 결과는 기획서 Phase 0 절 (스파이크 코드는 git 기록에만 남김) |
| Phase 1 파서 코어 (`FormulaCore`) | 완료 — 골든 테스트·퍼징 통과 |
| Phase 2 통합 MVP (`EasyEq.app`) | 구현 완료, 수동 테스트 매트릭스 진행 중 |

## 구조

- `Sources/FormulaCore` — Lexer → Parser(AST) → 모호성 확장 → 유니코드/LaTeX 렌더러. UI 의존 없음.
- `Sources/EasyEq` — 메뉴바 앱.
  - `AppDelegate` 메뉴·상태 반영, `Settings` 설정 저장
  - `SelectionMonitor` 드래그 감지·수동 변환, `SelectionReader` 선택 읽기(AX → 클립보드 폴백)
  - `PopupController` 드래그 후보 팝업, `LiveController` 실시간 입력 후보
  - `KeyInterceptor` 키 이벤트 탭, `TextInserter` 클립보드 치환, `HotkeyManager` 전역 단축키
  - `OnboardingView`, `SettingsView`, `Windows`(설명서) 창
- `Tests/FormulaCoreTests` — 골든 테스트, 오탐·퍼징·결정성 테스트.
- `docs/manual*.html` — 앱 안 설명서 (빌드 스크립트가 번들에 넣는다).

## 사용

```sh
swift test                      # 파서 테스트
scripts/build-app.sh            # 빌드 + 서명 → build/EasyEq.app (Apple Silicon·Intel 겸용)
scripts/build-app.sh --install  # 빌드 후 /Applications에 설치하고 실행
```

처음 실행하면 접근성 권한 안내 창이 뜬다. 서명 인증서가 같으면 다시 빌드해도 권한이 유지된다.

로그는 `~/Library/Logs/EasyEq.log`에 이벤트 종류(앱 이름, 읽기 방식, 길이, 후보 수)만 남긴다. 선택하거나 입력한 텍스트 자체는 기록하지 않는다.
