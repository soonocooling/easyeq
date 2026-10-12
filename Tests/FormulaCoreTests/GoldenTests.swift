import XCTest
@testable import FormulaCore

final class GoldenTests: XCTestCase {
    private let engine = FormulaEngine()

    private func unicode(_ input: String) -> [String] {
        engine.candidates(for: input, format: .unicode).map { $0.text(for: .unicode) }
    }

    private func latex(_ input: String) -> [String] {
        engine.candidates(for: input, format: .latex).map { $0.text(for: .latex) }
    }

    // MARK: 부록 B — 후보 전체와 순서

    func testAppendixB() {
        let rows: [(String, [String], [String])] = [
            ("루트2 곱하기 루트3", ["√2 × √3", "√2 · √3"], [#"\sqrt{2} \times \sqrt{3}"#, #"\sqrt{2} \cdot \sqrt{3}"#]),
            ("x제곱 + y^2 은 7", ["x² + y² = 7"], ["x^2 + y^2 = 7"]),
            ("dy/dx", ["dy/dx", "𝑑𝑦/𝑑𝑥"], [#"\frac{dy}{dx}"#, #"\frac{\mathrm{d}y}{\mathrm{d}x}"#]),
            ("y'", ["y′"], ["y'"]),
            ("라운드f/라운드x", ["∂f/∂x", "∂ₓf"], [#"\frac{\partial f}{\partial x}"#, #"\partial_x f"#]),
            ("절댓값(x^2+y^2)", ["|x² + y²|"], [#"\left| x^2 + y^2 \right|"#]),
        ]
        for (input, u, l) in rows {
            XCTAssertEqual(unicode(input), u, input)
            XCTAssertEqual(latex(input), l, input)
        }
    }

    // MARK: 기능 명세의 완료 조건

    func testSpecExamples() {
        XCTAssertEqual(unicode("루트 2 times x^2").first, "√2 × x²")
        XCTAssertEqual(unicode("루트2 곱하기 루트3 ="), ["√2 × √3 =", "√2 · √3 ="])
        XCTAssertEqual(unicode("루트 x 더하기 1"), ["√x + 1", "√(x + 1)"])
        XCTAssertEqual(unicode("square root of 2 times square root of 3").first, "√2 × √3")
        XCTAssertEqual(unicode("partial f over partial x"), ["∂f/∂x", "∂ₓf"])
        XCTAssertEqual(unicode("absolute value of x"), ["|x|"])
        XCTAssertEqual(unicode("루트2곱하기루트3"), ["√2 × √3", "√2 · √3"])
    }

    func testUnsupportedSuperscriptFallsBackToLatex() {
        let result = engine.candidates(for: "x^q", format: .unicode)
        XCTAssertEqual(result.count, 1)
        XCTAssertTrue(result[0].needsLatex)
        XCTAssertEqual(result[0].text(for: .unicode), "x^q")
        XCTAssertEqual(result[0].note, "LaTeX")
    }

    func testCandidateLimitAndRank() {
        let all = engine.candidates(for: "루트 2 곱하기 x")
        XCTAssertEqual(all.map(\.unicode), ["√2 × x", "√(2 × x)", "√2 · x", "√(2 · x)"])
        XCTAssertEqual(all.map(\.rank), [1, 2, 3, 4])
        let limited = engine.candidates(for: "루트 2 곱하기 x", options: EngineOptions(maxCandidates: 2))
        XCTAssertEqual(limited.map(\.unicode), ["√2 × x", "√(2 × x)"])
    }

    func testSpacingNormalizationCanBeDisabled() {
        let options = EngineOptions(normalizeSpacing: false)
        XCTAssertEqual(engine.candidates(for: "x제곱 + y^2 은 7", options: options).map(\.unicode), ["x²+y²=7"])
        XCTAssertEqual(
            engine.candidates(for: "루트2 곱하기 루트3", format: .latex, options: options).first?.latex,
            #"\sqrt{2} \times \sqrt{3}"#
        )
    }

    func testUserDictionaryOverridesDefaults() {
        let custom = FormulaEngine(userEntries: ["엘바": ["ƛ", "\\lambdabar"], "파이": ["Π", "\\Pi"]])
        XCTAssertEqual(custom.candidates(for: "엘바").map(\.unicode), ["ƛ"])
        XCTAssertEqual(custom.candidates(for: "엘바", format: .latex).map(\.latex), ["\\lambdabar"])
        XCTAssertEqual(custom.candidates(for: "2 파이").map(\.unicode), ["2Π"])
    }

    // MARK: 골든 테이블 — 첫 후보 (유니코드, LaTeX)

    private static let golden: [(String, String, String)] = [
        // 사칙·관계 (부록 A)
        ("3 더하기 4", "3 + 4", "3 + 4"),
        ("3 빼기 2", "3 − 2", "3 - 2"),
        ("x 마이너스 y", "x − y", "x - y"),
        ("a 곱하기 b", "a × b", #"a \times b"#),
        ("a times b", "a × b", #"a \times b"#),
        ("a * b", "a × b", #"a \times b"#),
        ("3 나누기 4", "3 ÷ 4", #"3 \div 4"#),
        ("a divided by b", "a ÷ b", #"a \div b"#),
        ("x 는 3", "x = 3", "x = 3"),
        ("x가 3", "x = 3", "x = 3"),
        ("x 같다 y", "x = y", "x = y"),
        ("x는 3이다", "x = 3", "x = 3"),
        ("x 같지 않다 y", "x ≠ y", #"x \neq y"#),
        ("x는 y와 같지 않다", "x ≠ y", #"x \neq y"#),
        ("x != y", "x ≠ y", #"x \neq y"#),
        ("x not equal to y", "x ≠ y", #"x \neq y"#),
        ("x 이상 3", "x ≥ 3", #"x \geq 3"#),
        ("x는 3 이상", "x ≥ 3", #"x \geq 3"#),
        ("x >= 3", "x ≥ 3", #"x \geq 3"#),
        ("x 이하 y", "x ≤ y", #"x \leq y"#),
        ("x <= y", "x ≤ y", #"x \leq y"#),
        ("x는 y보다 크다", "x > y", "x > y"),
        ("x 미만 3", "x < 3", "x < 3"),
        ("x는 약 3.14", "x ≈ 3.14", #"x \approx 3.14"#),
        ("2 파이 r 은 약 6.28", "2πr ≈ 6.28", #"2\pi r \approx 6.28"#),
        ("x ~= y", "x ≈ y", #"x \approx y"#),
        ("x -> 0", "x → 0", #"x \to 0"#),
        ("a-b", "a − b", "a - b"),
        ("-b +- 루트(b^2 - 4ac) / 2a", "−b ± √(b² − 4ac)/2a", #"-b \pm \frac{\sqrt{b^2 - 4ac}}{2a}"#),
        // 지수·근호
        ("x제곱", "x²", "x^2"),
        ("x 세제곱", "x³", "x^3"),
        ("x의 3제곱", "x³", "x^3"),
        ("x의 n제곱", "xⁿ", "x^n"),
        ("2의 10승", "2¹⁰", "2^{10}"),
        ("2^10", "2¹⁰", "2^{10}"),
        ("x^{10}", "x¹⁰", "x^{10}"),
        ("x^-1", "x⁻¹", "x^{-1}"),
        ("x^(a+b)", "xᵃ⁺ᵇ", "x^{a+b}"),
        ("e^x", "eˣ", "e^x"),
        ("x_i", "xᵢ", "x_i"),
        ("x_1^2", "x₁²", "x_1^2"),
        ("x squared plus y squared equals r squared", "x² + y² = r²", "x^2 + y^2 = r^2"),
        ("x to the power of n", "xⁿ", "x^n"),
        ("a^2 + b^2 = c^2", "a² + b² = c²", "a^2 + b^2 = c^2"),
        ("E = mc^2", "E = mc²", "E = mc^2"),
        ("m c 제곱", "mc²", "mc^2"),
        ("(x+1)제곱", "(x + 1)²", "(x + 1)^2"),
        ("루트2", "√2", #"\sqrt{2}"#),
        ("제곱근 2", "√2", #"\sqrt{2}"#),
        ("sqrt(2)", "√2", #"\sqrt{2}"#),
        ("sqrt 2", "√2", #"\sqrt{2}"#),
        ("루트(x+1) 더하기 2", "√(x + 1) + 2", #"\sqrt{x + 1} + 2"#),
        ("루트2 제곱", "(√2)²", #"(\sqrt{2})^2"#),
        ("루트 루트 2", "√(√2)", #"\sqrt{\sqrt{2}}"#),
        ("루트2x", "√2 x", #"\sqrt{2}x"#),
        ("2루트3", "2√3", #"2\sqrt{3}"#),
        ("8의 세제곱근", "∛8", #"\sqrt[3]{8}"#),
        ("세제곱근 8", "∛8", #"\sqrt[3]{8}"#),
        ("네제곱근 16", "∜16", #"\sqrt[4]{16}"#),
        ("x의 n제곱근", "ⁿ√x", #"\sqrt[n]{x}"#),
        ("x의 제곱근", "√x", #"\sqrt{x}"#),
        ("cube root of x", "∛x", #"\sqrt[3]{x}"#),
        // 분수·미적분
        ("2분의 1", "1/2", #"\frac{1}{2}"#),
        ("2x분의 1", "1/(2x)", #"\frac{1}{2x}"#),
        ("x 더하기 2분의 1", "x + 1/2", #"x + \frac{1}{2}"#),
        ("1 over 2", "1/2", #"\frac{1}{2}"#),
        ("a over bc", "a/(bc)", #"\frac{a}{bc}"#),
        ("(x+1) over 2", "(x + 1)/2", #"\frac{x + 1}{2}"#),
        ("디y/디x", "dy/dx", #"\frac{dy}{dx}"#),
        ("라운드 제곱 f / 라운드 x 제곱", "∂²f/∂x²", #"\frac{\partial^2f}{\partial x^2}"#),
        ("파셜 u / 파셜 t", "∂u/∂t", #"\frac{\partial u}{\partial t}"#),
        ("인테그랄 0부터 1까지 x제곱 dx", "∫₀¹ x² dx", #"\int_0^1 x^2 \, dx"#),
        ("적분 f(x) dx", "∫f(x) dx", #"\int f(x) \, dx"#),
        ("integral from 0 to 1 of x squared dx", "∫₀¹ x² dx", #"\int_0^1 x^2 \, dx"#),
        ("시그마 i=1부터 n까지 i제곱", "Σᵢ₌₁ⁿ i²", #"\sum_{i=1}^n i^2"#),
        ("sum from i=1 to n of i^2", "Σᵢ₌₁ⁿ i²", #"\sum_{i=1}^n i^2"#),
        ("대문자 시그마", "Σ", #"\sum"#),
        ("극한 f(x)", "lim f(x)", #"\lim f(x)"#),
        ("리미트 x가 0으로 갈 때 f(x)", #"\lim_{x \to 0} f(x)"#, #"\lim_{x \to 0} f(x)"#),
        ("limit as x approaches 0 of sin x / x", #"\lim_{x \to 0} \frac{\sin x}{x}"#, #"\lim_{x \to 0} \frac{\sin x}{x}"#),
        ("무한대", "∞", #"\infty"#),
        ("x -> 무한대", "x → ∞", #"x \to \infty"#),
        ("x 프라임", "x′", "x'"),
        ("y''", "y″", "y''"),
        ("f'(x)", "f′(x)", "f'(x)"),
        ("x 팩토리얼", "x!", "x!"),
        // 절댓값·괄호
        ("절댓값 x", "|x|", #"\left| x \right|"#),
        ("절대값(x)", "|x|", #"\left| x \right|"#),
        ("abs(x)", "|x|", #"\left| x \right|"#),
        ("x의 절댓값", "|x|", #"\left| x \right|"#),
        ("절댓값 x 빼기 1", "|x| − 1", #"\left| x \right| - 1"#),
        ("|x| 더하기 |y|", "|x| + |y|", #"\left| x \right| + \left| y \right|"#),
        ("괄호 열고 x 더하기 1 괄호 닫고 제곱", "(x + 1)²", "(x + 1)^2"),
        // 그리스 문자
        ("알파", "α", #"\alpha"#),
        ("알파 + 베타", "α + β", #"\alpha + \beta"#),
        ("감마", "γ", #"\gamma"#),
        ("델타 x", "δx", #"\delta x"#),
        ("엡실론", "ε", #"\epsilon"#),
        ("세타", "θ", #"\theta"#),
        ("람다 = 2", "λ = 2", #"\lambda = 2"#),
        ("뮤 곱하기 오메가", "μ × ω", #"\mu \times \omega"#),
        ("파이 r제곱", "πr²", #"\pi r^2"#),
        ("피", "φ", #"\phi"#),
        ("phi", "φ", #"\phi"#),
        ("시그마", "σ", #"\sigma"#),
        ("오메가", "ω", #"\omega"#),
        ("대문자 델타 x", "Δx", #"\Delta x"#),
        ("Delta x", "Δx", #"\Delta x"#),
        ("대문자 오메가", "Ω", #"\Omega"#),
        ("e^(i파이) + 1 = 0", #"e^{i\pi} + 1 = 0"#, #"e^{i\pi} + 1 = 0"#),
        // 벡터·물리
        ("나블라 f", "∇f", #"\nabla f"#),
        ("나블라 내적 F", "∇ · F", #"\nabla \cdot F"#),
        ("a 내적 b", "a · b", #"a \cdot b"#),
        ("a 외적 b", "a × b", #"a \times b"#),
        ("에이치바", "ħ", #"\hbar"#),
        // 집합·논리
        ("x는 A에 속한다", "x ∈ A", #"x \in A"#),
        ("A는 B의 부분집합", "A ⊂ B", #"A \subset B"#),
        ("A 합집합 B", "A ∪ B", #"A \cup B"#),
        ("A 교집합 B", "A ∩ B", #"A \cap B"#),
        ("모든 x", "∀x", #"\forall x"#),
        ("존재 x", "∃x", #"\exists x"#),
        ("for all x in A", "∀x ∈ A", #"\forall x \in A"#),
        // 함수
        ("사인 세타", "sin θ", #"\sin \theta"#),
        ("코사인 2x", "cos 2x", #"\cos 2x"#),
        ("로그 x", "log x", #"\log x"#),
        ("sin^2 x + cos^2 x = 1", "sin² x + cos² x = 1", #"\sin^2 x + \cos^2 x = 1"#),
    ]

    func testGoldenTable() {
        XCTAssertGreaterThanOrEqual(Self.golden.count + 6, 100)
        for (input, u, l) in Self.golden {
            XCTAssertEqual(unicode(input).first, u, "unicode: \(input)")
            XCTAssertEqual(latex(input).first, l, "latex: \(input)")
        }
    }
}
