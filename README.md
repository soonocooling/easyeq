# easyeq

macOS 메뉴바에 상주하다가, 한글·영어로 쓴 수식 표현을 드래그하면 수식 후보를 띄워 그 자리를 바꿔 입력해주는 개인용 앱. 기획서는 [product-spec.md](product-spec.md).

## 현재 상태

| 단계 | 상태 |
|---|---|
| Phase 0 기술 검증 스파이크 | 스파이크 앱 작성 완료, 대상 앱에서 수동 검증 필요 |
| Phase 1 파서 코어 (`FormulaCore`) | 완료 — 골든 테스트·퍼징 통과 |
| Phase 2 통합 MVP | Phase 0 통과 후 착수 |

## 구조

- `Sources/FormulaCore` — Lexer → Parser(AST) → 모호성 확장 → 유니코드/LaTeX 렌더러. UI 의존 없음.
- `Sources/EasyEqSpike` — Phase 0 검증용 임시 앱 (버릴 코드).
- `Tests/FormulaCoreTests` — 골든 테스트, 오탐·퍼징·결정성 테스트.

## 사용

```sh
swift test                 # 파서 테스트
scripts/build-spike.sh     # 스파이크 빌드 + 서명 → build/EasyEqSpike.app
open build/EasyEqSpike.app # 접근성 권한 허용 후 여러 앱에서 텍스트를 드래그
```

스파이크는 드래그할 때마다 앱 이름, 읽기 방식(AX/클립보드), 좌표 획득 여부, 키 탭 성공 여부를 `~/Library/Logs/EasyEqSpike.log`에 남긴다. 선택한 텍스트 자체는 기록하지 않는다.
