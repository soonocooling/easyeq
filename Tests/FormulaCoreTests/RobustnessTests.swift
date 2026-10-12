import XCTest
@testable import FormulaCore

final class RobustnessTests: XCTestCase {
    private let engine = FormulaEngine()

    /// 일반 문장·단어를 드래그해도 팝업이 뜨면 안 된다 (F-05, F-11).
    func testOrdinaryTextProducesNoCandidates() {
        let inputs = [
            "오늘 점심 뭐 먹지", "hello world", "it's", "cost", "sink", "and/or", "km/h", "1/2", "a+b",
            "f(x, y)", "see you at 5", "I am at 5", "3개", "이상", "약", "은 3", "약 3", "x", "42",
            "", "   ", "the quick brown fox", "안녕하세요", "e-mail", "ok.", "x 더하기", "2 3",
            "첫째 줄\n둘째 줄",
        ]
        for input in inputs {
            XCTAssertEqual(engine.candidates(for: input), [], input)
        }
    }

    func testUnbalancedBracketsProduceNoCandidates() {
        for input in ["(x+1", "x+1)", "절댓값(x", "|x", "x^{2", "((x)"] {
            XCTAssertEqual(engine.candidates(for: input), [], input)
            XCTAssertEqual(engine.candidates(for: input, format: .latex), [], input)
        }
    }

    func testOverlongInputIsIgnored() {
        let long = Array(repeating: "x + ", count: 60).joined() + "1"
        XCTAssertGreaterThan(long.count, FormulaEngine.maxInputLength)
        XCTAssertEqual(engine.candidates(for: long), [])
    }

    func testDeterministicOrder() {
        for input in ["루트 2 곱하기 x", "라운드f/라운드x", "dy/dx", "절댓값 x 빼기 1 곱하기 y"] {
            let first = engine.candidates(for: input)
            XCTAssertFalse(first.isEmpty, input)
            for _ in 0..<100 {
                XCTAssertEqual(engine.candidates(for: input), first, input)
            }
        }
    }

    /// 무작위 문자열 1만 개: 크래시·무한 루프 없이 각 50ms 이내 (Phase 1 퍼징).
    func testFuzzingStaysFastAndSafe() {
        let pieces = [
            "루트", "제곱", "세제곱근", "절댓값", "곱하기", "더하기", "빼기", "분의", "의", "은", "는", "이", "가",
            "라운드", "디", "인테그랄", "시그마", "리미트", "부터", "까지", "으로 갈 때", "파이", "무한대", "약",
            "이상", "같지 않다", "대문자 ", "sqrt", "sin", "over", "times", "of", "from", "to", "as", "partial",
            "x", "y", "d", "dx", "f", "n", "0", "1", "23", "4.5", "+", "-", "*", "/", "^", "_", "'", "(", ")",
            "{", "}", "|", "=", "<=", "->", "!", ",", " ", " ", " ", "가나", "zzzz", "∫", "√", "²", "é", "😀",
        ]
        var generator = SplitMix64(seed: 0x5EED)
        var slowest = 0.0
        for _ in 0..<10_000 {
            let length = Int(generator.next() % 40) + 1
            var input = ""
            for _ in 0..<length {
                input += pieces[Int(generator.next() % UInt64(pieces.count))]
            }
            let start = CFAbsoluteTimeGetCurrent()
            _ = engine.candidates(for: input, format: .unicode)
            _ = engine.candidates(for: input, format: .latex)
            slowest = max(slowest, CFAbsoluteTimeGetCurrent() - start)
        }
        XCTAssertLessThan(slowest, 0.05, "가장 느린 입력: \(slowest * 1000)ms")
    }

    /// 깊은 중첩에서도 파싱이 폭증하지 않는다.
    func testPathologicalNestingIsBounded() {
        let inputs = [
            String(repeating: "(", count: 100) + "x" + String(repeating: ")", count: 100),
            String(repeating: "적분 ", count: 60) + "x 부터",
            String(repeating: "시그마 ", count: 60) + "부터 1 까지",
            String(repeating: "루트 ", count: 60) + "2",
            String(repeating: "- ", count: 90) + "x",
            String(repeating: "리미트 x가 ", count: 20),
        ]
        for input in inputs {
            let start = CFAbsoluteTimeGetCurrent()
            _ = engine.candidates(for: input)
            XCTAssertLessThan(CFAbsoluteTimeGetCurrent() - start, 0.05, String(input.prefix(20)))
        }
    }
}

private struct SplitMix64 {
    private var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
