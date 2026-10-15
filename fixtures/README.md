# 공통 테스트 케이스

`formula-cases.json`은 수식 해석 엔진(FormulaCore)의 **기준 결과**다. macOS(Swift)판과 앞으로 만들 Windows(C#)판 등 모든 구현은 이 파일의 결과를 후보 순서까지 그대로 내야 한다. 한쪽 구현만 고쳐서 결과가 갈라지는 것을 막기 위한 파일이다.

- Swift: `Tests/FormulaCoreTests/FixtureTests.swift`가 이 파일을 읽어 검사한다 (`swift test`).
- 다른 구현: 같은 파일을 읽어 아래 규칙대로 검사하는 테스트를 만든다.

## 형식

```jsonc
{
  "version": 1,
  "groups": [
    {
      "name": "noSpacing",                  // 그룹 이름
      "description": "공백 정리 끔",          // 설명
      "options": {                           // 선택. 없으면 기본값
        "normalizeSpacing": false,           //   기본 true
        "maxCandidates": 2                   //   기본 5 (1~5)
      },
      "userEntries": {                       // 선택. 사용자 사전 {발음: [유니코드, LaTeX]}
        "엘바": ["ƛ", "\\lambdabar"]
      },
      "cases": [
        {
          "input": "루트2 곱하기 루트3",
          "unicode": ["√2 × √3", "√2 · √3"],                               // 유니코드 형식 후보 전체, 순서대로
          "latex": ["\\sqrt{2} \\times \\sqrt{3}", "\\sqrt{2} \\cdot \\sqrt{3}"], // LaTeX 형식 후보 전체, 순서대로
          "needsLatex": [true]               // 선택. 유니코드 후보별로 LaTeX 대체가 필요한지
        }
      ]
    }
  ]
}
```

## 검사 규칙

각 케이스마다 그룹의 `options`와 `userEntries`로 엔진을 만들고:

1. 유니코드 형식으로 후보를 구해, 각 후보가 **실제로 삽입될 문자열**의 목록이 `unicode`와 같아야 한다. 유니코드로 표현할 수 없는 후보는 LaTeX 문자열이 삽입되므로 그 값이 들어 있다 (`x^q`).
2. LaTeX 형식으로 후보를 구해, 삽입될 문자열의 목록이 `latex`와 같아야 한다.
3. `needsLatex`가 있으면 유니코드 후보 각각의 LaTeX 대체 여부가 같아야 한다.
4. 빈 배열은 "후보 없음 (팝업을 띄우지 않음)"을 뜻한다.

## 기준값 바꾸기

엔진 동작을 의도적으로 바꿨다면 이 파일도 같이 고친다. 고친 뒤에는 모든 구현이 다시 통과해야 한다. 새 규칙을 넣을 때는 해당 그룹에 케이스를 추가하거나, 새 그룹을 만든다.
