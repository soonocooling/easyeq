import XCTest
@testable import FormulaCore

/// fixtures/formula-cases.json의 공통 케이스를 검사한다. 다른 언어 구현도 같은 파일로 검사한다.
final class FixtureTests: XCTestCase {
    private struct Fixture: Decodable {
        let version: Int
        let groups: [Group]
    }

    private struct Group: Decodable {
        let name: String
        let options: Options?
        let userEntries: [String: [String]]?
        let cases: [Case]
    }

    private struct Options: Decodable {
        let normalizeSpacing: Bool?
        let maxCandidates: Int?
    }

    private struct Case: Decodable {
        let input: String
        let unicode: [String]
        let latex: [String]
        let needsLatex: [Bool]?
    }

    private static let url = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("fixtures/formula-cases.json")

    private func load() throws -> Fixture {
        try JSONDecoder().decode(Fixture.self, from: Data(contentsOf: Self.url))
    }

    func testFixtureIsLargeEnough() throws {
        let fixture = try load()
        XCTAssertEqual(fixture.version, 1)
        // 기획서 Phase 1 완료 조건: 100개 이상.
        XCTAssertGreaterThanOrEqual(fixture.groups.reduce(0) { $0 + $1.cases.count }, 100)
    }

    func testAllCases() throws {
        for group in try load().groups {
            let engine = FormulaEngine(userEntries: group.userEntries ?? [:])
            var options = EngineOptions()
            if let v = group.options?.normalizeSpacing { options.normalizeSpacing = v }
            if let v = group.options?.maxCandidates { options.maxCandidates = v }

            for c in group.cases {
                let label = "[\(group.name)] \(c.input.debugDescription)"
                let unicode = engine.candidates(for: c.input, format: .unicode, options: options)
                let latex = engine.candidates(for: c.input, format: .latex, options: options)
                XCTAssertEqual(unicode.map { $0.text(for: .unicode) }, c.unicode, "unicode \(label)")
                XCTAssertEqual(latex.map { $0.text(for: .latex) }, c.latex, "latex \(label)")
                if let needsLatex = c.needsLatex {
                    XCTAssertEqual(unicode.map(\.needsLatex), needsLatex, "needsLatex \(label)")
                }
            }
        }
    }
}
