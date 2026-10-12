import Foundation

/// 선택된 텍스트를 수식 후보 목록으로 바꾼다. 해석할 수 없으면 빈 배열.
public final class FormulaEngine: @unchecked Sendable {
    public static let maxInputLength = 200

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
        guard let tokens = lexer.lex(text), Self.hasMathEvidence(tokens) else { return [] }

        var trees: [Node] = []
        if let narrow = try? Parser(tokens, wide: false).parse() { trees.append(narrow) }
        let wideParser = Parser(tokens, wide: true)
        if let wide = try? wideParser.parse(), wideParser.usedWide { trees.append(wide) }
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

    private static func normalize(_ input: String) -> String? {
        let trimmed = input.precomposedStringWithCanonicalMapping.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= maxInputLength else { return nil }
        // 여러 줄 수식은 범위 밖.
        guard !trimmed.contains(where: \.isNewline) else { return nil }
        return trimmed.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    /// 변수·숫자·괄호만으로 된 입력(일반 문장의 낱글자)은 수식으로 보지 않는다.
    private static func hasMathEvidence(_ tokens: [Token]) -> Bool {
        tokens.contains { token in
            switch token.tok {
            case .num, .ident, .lparen, .rparen, .comma: return false
            default: return true
            }
        }
    }
}
