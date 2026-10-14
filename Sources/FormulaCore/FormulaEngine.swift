import Foundation

/// 선택된 텍스트를 수식 후보 목록으로 바꾼다. 해석할 수 없으면 빈 배열.
public final class FormulaEngine: @unchecked Sendable {
    public static let maxInputLength = 200
    /// 이 토큰 수 이하의 짧은 식에서만 붙여 쓴 근호·절댓값을 괄호로 묶은 후보도 낸다.
    static let greedyTokenLimit = 8

    private let lexicon: Lexicon
    private let lexer: Lexer

    /// - Parameter userEntries: 사용자 사전 `{발음: [유니코드, LaTeX]}`. 기본 사전보다 우선한다.
    public init(userEntries: [String: [String]] = [:]) {
        lexicon = Lexicon(userEntries: userEntries)
        lexer = Lexer(lexicon: lexicon)
    }

    public func candidates(
        for input: String,
        format: OutputFormat = .unicode,
        options: EngineOptions = EngineOptions()
    ) -> [Candidate] {
        guard let text = Self.normalize(input) else { return [] }
        // 영어 단어 하나만 선택한 경우는 사전에 있는 단어일 때만 수식으로 본다.
        if text.allSatisfy({ $0.isASCII && $0.isLetter }), lexicon.table[text.lowercased()] == nil { return [] }
        guard let tokens = lexer.lex(text) else { return [] }
        let hasEvidence = Self.hasMathEvidence(tokens, spokenLetters: Self.containsHangul(text))

        var trees: [Node] = []
        if hasEvidence { trees += Self.parseTrees(tokens) }
        // `x1` → x₁: 붙여 쓴 글자+숫자를 하첨자로 본 해석을 뒤 순위 후보로 더한다.
        // 한 자리 2~9면 거듭제곱(`x2` → x²)으로 본 해석도 그 뒤에 더한다.
        // `x1` 하나만 있을 때는 소문자일 때만 (`A4`, `F1` 같은 일반 단어 제외).
        if hasEvidence || Self.isLowercaseLetterDigits(text) {
            if let subscripted = Self.attachingDigits(tokens, as: .underscore) {
                trees += Self.parseTrees(subscripted)
            }
            if let powered = Self.attachingDigits(tokens, as: .caret) {
                trees += Self.parseTrees(powered)
            }
        }
        guard !trees.isEmpty else { return [] }

        let limit = min(max(options.maxCandidates, 1), 5)
        var out: [Candidate] = []
        var seen = Set<String>()
        outer: for variant in Variant.ordered {
            for tree in trees {
                let unicodeRenderer = UnicodeRenderer(spacing: options.normalizeSpacing, variant: variant)
                let unicode = unicodeRenderer.render(tree)
                let latex = LatexRenderer(spacing: options.normalizeSpacing, variant: variant).render(tree)
                let candidate = Candidate(
                    unicode: unicode,
                    latex: latex,
                    rank: out.count + 1,
                    needsLatex: unicodeRenderer.failed,
                    note: unicodeRenderer.failed ? "LaTeX" : nil
                )
                guard seen.insert(candidate.text(for: format)).inserted else { continue }
                out.append(candidate)
                if out.count == limit { break outer }
            }
        }

        // 바뀌는 것이 없는 후보뿐이면 팝업을 띄울 이유가 없다 (`and/or`, `km/h`).
        let bare = text.filter { $0 != " " }
        let unchanged = out.allSatisfy { candidate in
            !candidate.needsLatex
                && candidate.unicode.filter { $0 != " " } == bare
                && (format == .unicode || candidate.latex.filter { $0 != " " } == bare)
        }
        return unchanged ? [] : out
    }

    private static func parseTrees(_ tokens: [Token]) -> [Node] {
        var trees: [Node] = []
        if let narrow = try? Parser(tokens, wide: false).parse() { trees.append(narrow) }
        let wideParser = Parser(tokens, wide: true)
        if let wide = try? wideParser.parse(), wideParser.usedWide { trees.append(wide) }
        if tokens.count <= greedyTokenLimit {
            let greedyParser = Parser(tokens, wide: false, greedy: true)
            if let greedy = try? greedyParser.parse(), greedyParser.usedGreedy { trees.append(greedy) }
        }
        return trees
    }

    /// 변수 한 글자 바로 뒤에 붙여 쓴 정수를 하첨자(`_`) 또는 지수(`^`)로 바꾼 토큰열. 바꿀 곳이 없으면 nil.
    /// 지수는 한 자리 2~9만. 앞 글자와 붙어 있는 경우(`mp3`, `ab1`)는 단어로 보고 건드리지 않는다.
    private static func attachingDigits(_ tokens: [Token], as marker: Tok) -> [Token]? {
        let isPower: Bool
        if case .caret = marker { isPower = true } else { isPower = false }
        var out: [Token] = []
        var changed = false
        for (i, token) in tokens.enumerated() {
            out.append(token)
            guard case .ident = token.tok, i + 1 < tokens.count,
                  case .num(let digits) = tokens[i + 1].tok, !tokens[i + 1].spaceBefore,
                  digits.allSatisfy(\.isNumber) else { continue }
            if i > 0, !token.spaceBefore, case .ident = tokens[i - 1].tok { continue }
            if isPower {
                guard digits.count == 1, digits >= "2" else { continue }
                // 뒤에 이미 거듭제곱이 붙어 있으면 (`x2제곱`) 지수로 보지 않는다.
                if i + 2 < tokens.count {
                    switch tokens[i + 2].tok {
                    case .caret, .powWord, .nthPower, .toThePower: continue
                    default: break
                    }
                }
            }
            out.append(Token(tok: marker, spaceBefore: false))
            changed = true
        }
        return changed ? out : nil
    }

    private static func isLowercaseLetterDigits(_ text: String) -> Bool {
        guard let first = text.first, first.isASCII, first.isLowercase, text.count >= 2 else { return false }
        return text.dropFirst().allSatisfy { $0.isASCII && $0.isNumber }
    }

    private static func normalize(_ input: String) -> String? {
        let trimmed = input.precomposedStringWithCanonicalMapping.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= maxInputLength else { return nil }
        // 여러 줄 수식은 범위 밖.
        guard !trimmed.contains(where: \.isNewline) else { return nil }
        return trimmed.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    /// 변수·숫자·괄호만으로 된 입력(일반 문장의 낱글자)은 수식으로 보지 않는다.
    /// 단, 한글로 쓴 알파벳(`에프(엑스)`, `2에이`)은 숫자나 괄호와 함께 쓰였으면 수식으로 본다.
    private static func hasMathEvidence(_ tokens: [Token], spokenLetters: Bool) -> Bool {
        var structural = false
        for token in tokens {
            switch token.tok {
            case .ident: continue
            case .num, .lparen, .rparen, .comma: structural = true
            default: return true
            }
        }
        return spokenLetters && structural
    }

    private static func containsHangul(_ text: String) -> Bool {
        text.unicodeScalars.contains { $0.value >= 0xAC00 && $0.value <= 0xD7A3 }
    }
}
