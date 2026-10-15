import XCTest
@testable import FormulaCore

/// 입력 → 후보 표는 fixtures/formula-cases.json (FixtureTests). 여기는 Swift API 자체의 동작만 본다.
final class EngineTests: XCTestCase {
    private let engine = FormulaEngine()

    func testUnsupportedSuperscriptFallsBackToLatex() {
        let result = engine.candidates(for: "x^q", format: .unicode)
        XCTAssertEqual(result.count, 1)
        XCTAssertTrue(result[0].needsLatex)
        XCTAssertEqual(result[0].text(for: .unicode), "x^q")
        XCTAssertEqual(result[0].note, "LaTeX")
    }

    func testRanksAreSequential() {
        let all = engine.candidates(for: "루트 2 곱하기 x")
        XCTAssertEqual(all.map(\.rank), Array(1...all.count))
        let limited = engine.candidates(for: "루트 2 곱하기 x", options: EngineOptions(maxCandidates: 2))
        XCTAssertEqual(limited.map(\.rank), [1, 2])
    }

    func testCandidateLimitIsClamped() {
        XCTAssertEqual(engine.candidates(for: "루트 2 곱하기 x", options: EngineOptions(maxCandidates: 0)).count, 1)
        XCTAssertLessThanOrEqual(engine.candidates(for: "루트 2 곱하기 x", options: EngineOptions(maxCandidates: 9)).count, 5)
    }
}
