import Foundation

/// 사전 최장 일치 방식 Lexer. 해석할 수 없는 글자가 하나라도 있으면 nil.
struct Lexer {
    let lexicon: Lexicon

    private static func isLatin(_ c: Character) -> Bool {
        guard let a = c.asciiValue else { return false }
        return (a >= 65 && a <= 90) || (a >= 97 && a <= 122)
    }

    private static func isDigit(_ c: Character) -> Bool {
        guard let a = c.asciiValue else { return false }
        return a >= 48 && a <= 57
    }

    func lex(_ text: String) -> [Token]? {
        let chars = Array(text)
        let n = chars.count
        var out: [Token] = []
        var space = false
        var i = 0

        func emit(_ tok: Tok) {
            out.append(Token(tok: tok, spaceBefore: space))
            space = false
        }

        while i < n {
            let c = chars[i]
            if c == " " {
                space = true
                i += 1
                continue
            }
            if Self.isDigit(c) {
                var j = i
                while j < n, Self.isDigit(chars[j]) { j += 1 }
                if j + 1 < n, chars[j] == ".", Self.isDigit(chars[j + 1]) {
                    j += 1
                    while j < n, Self.isDigit(chars[j]) { j += 1 }
                }
                emit(.num(String(chars[i..<j])))
                i = j
                continue
            }
            if let (tok, len) = matchPhrase(chars, at: i, isFirst: out.isEmpty) {
                // 영어 축약형(it's)의 아포스트로피는 프라임이 아니다.
                if case .prime = tok, c == "'" || c == "’", i + 1 < n, Self.isLatin(chars[i + 1]) {
                    return nil
                }
                emit(tok)
                i += len
                continue
            }
            if Self.isLatin(c) {
                let midRun = i > 0 && Self.isLatin(chars[i - 1])
                var j = i
                while j < n, Self.isLatin(chars[j]) { j += 1 }
                let run = Array(chars[i..<j])
                if !midRun, let (tok, len) = attachablePrefix(run) {
                    emit(tok)
                    i += len
                    continue
                }
                guard run.count <= 3 || Self.isDifferentialChain(run) else { return nil }
                var k = 0
                while k < run.count {
                    let isD = run[k] == "d" && k + 1 < run.count
                        && (k + 2 == run.count || run[k + 2] == "d")
                    if isD {
                        emit(.sym(Sym(unicode: "d", latex: "d", kind: .dOp)))
                        emit(.ident(String(run[k + 1])))
                        k += 2
                    } else {
                        emit(.ident(String(run[k])))
                        k += 1
                    }
                }
                i = j
                continue
            }
            return nil
        }
        return Self.rewriteKoreanRelations(out)
    }

    /// `dxdy`처럼 d+문자가 반복되는 꼴.
    private static func isDifferentialChain(_ run: [Character]) -> Bool {
        guard run.count == 4 else { return false }
        return run[0] == "d" && run[2] == "d"
    }

    private func attachablePrefix(_ run: [Character]) -> (Tok, Int)? {
        let lower = String(run).lowercased()
        for name in Lexicon.attachable where lower.hasPrefix(name) {
            let rest = run.count - name.count
            if rest >= 1, rest <= 2, let tok = lexicon.table[name] {
                return (tok, name.count)
            }
        }
        return nil
    }

    private func matchPhrase(_ chars: [Character], at i: Int, isFirst: Bool) -> (Tok, Int)? {
        let n = chars.count
        let startsLatin = Self.isLatin(chars[i])
        if startsLatin, i > 0, Self.isLatin(chars[i - 1]) { return nil }
        var len = min(lexicon.maxLength, n - i)
        while len >= 1 {
            defer { len -= 1 }
            let last = chars[i + len - 1]
            if last == " " { continue }
            // 라틴 한 글자는 항상 변수.
            if len == 1, startsLatin { continue }
            let raw = String(chars[i..<(i + len)])
            let key = raw.lowercased()
            // 대문자 그리스 문자(Σ, Δ)는 원형 그대로 먼저 찾는다.
            guard let tok = lexicon.table[raw] ?? lexicon.table[key] else { continue }
            let next: Character? = i + len < n ? chars[i + len] : nil
            if Self.isLatin(last), let next, Self.isLatin(next) { continue }
            if lexicon.particles.contains(key) {
                // 조사는 식 뒤에 붙고 뒤가 띄어져 있을 때만 `=`로 본다.
                if isFirst || (next != nil && next != " ") { continue }
            }
            if startsLatin, chars[i].isUppercase, let up = lexicon.upper[key] {
                return (.sym(up), len)
            }
            return (tok, len)
        }
        return nil
    }

    /// 한국어 어순 보정: `x는 3 이상` → `x ≥ 3`, `x는 약 3` → `x ≈ 3`, `x는 3이다` → `x = 3`.
    private static func rewriteKoreanRelations(_ input: [Token]) -> [Token] {
        var toks: [Token] = []
        for (idx, t) in input.enumerated() {
            if case .rel(_, .particle) = t.tok, idx + 1 < input.count, case .rel = input[idx + 1].tok {
                continue
            }
            toks.append(t)
        }
        guard let last = toks.last, case .rel(let op, .word) = last.tok, toks.count >= 2 else { return toks }

        var depth = 0
        var particleIndexes: [Int] = []
        var otherRelations = 0
        for (idx, t) in toks.dropLast().enumerated() {
            switch t.tok {
            case .lparen: depth += 1
            case .rparen: depth -= 1
            case .rel(_, .particle) where depth == 0: particleIndexes.append(idx)
            case .rel: otherRelations += 1
            default: break
            }
        }
        if particleIndexes.count == 1 {
            toks[particleIndexes[0]].tok = .rel(op, .word)
            toks.removeLast()
        } else if op.isEquals, !particleIndexes.isEmpty || otherRelations > 0 {
            toks.removeLast()
        }
        return toks
    }
}
