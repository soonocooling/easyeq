import Foundation

struct ParseFailure: Error {}

/// 우선순위 클라이밍 파서.
/// 낮음 → 높음: 관계 < 가감 < 승제 < 분수(`/`) < 분의 < 붙여 쓴 곱 < 단항 < 함수 < 첨자·프라임.
final class Parser {
    private let toks: [Token]
    /// 띄어 쓴 근호·절댓값의 범위를 넓게(가감 수준까지) 잡는 해석.
    private let wide: Bool
    private var pos = 0
    private var absDepth = 0
    private var steps = 0
    private(set) var usedWide = false

    private static let stepLimit = 5000

    init(_ toks: [Token], wide: Bool) {
        self.toks = toks
        self.wide = wide
    }

    func parse() throws -> Node {
        let node = try parseRelation(top: true)
        guard pos == toks.count else { throw ParseFailure() }
        return node
    }

    private var peek: Tok? { pos < toks.count ? toks[pos].tok : nil }
    private var peekToken: Token? { pos < toks.count ? toks[pos] : nil }
    private var atEnd: Bool { pos >= toks.count }

    private func tick() throws {
        steps += 1
        if steps > Self.stepLimit { throw ParseFailure() }
    }

    private func skipOf() -> Bool {
        if case .of = peek {
            pos += 1
            return true
        }
        return false
    }

    // MARK: 이항 수준

    private func parseRelation(top: Bool) throws -> Node {
        let first = try parseAdditive()
        var parts: [RelPart] = []
        while case .rel(let op, _) = peek {
            pos += 1
            if atEnd {
                // 끝의 `=`는 그대로 두고 계산하지 않는다.
                guard top, op.isEquals else { throw ParseFailure() }
                parts.append(RelPart(op: op, rhs: nil))
                break
            }
            parts.append(RelPart(op: op, rhs: try parseAdditive()))
        }
        return parts.isEmpty ? first : .relation(first, parts)
    }

    private func parseAdditive() throws -> Node {
        var left = try parseMultiplicative()
        while case .bin(let op) = peek, op.level == .additive {
            pos += 1
            left = .binary(op, left, try parseMultiplicative())
        }
        return left
    }

    private func parseMultiplicative() throws -> Node {
        var left = try parseSlash()
        while case .bin(let op) = peek, op.level == .multiplicative {
            pos += 1
            left = .binary(op, left, try parseSlash())
        }
        return left
    }

    private func parseSlash() throws -> Node {
        var left = try parseBunui()
        while case .slash(let spoken) = peek {
            pos += 1
            left = .frac(left, try parseBunui(), spoken)
        }
        return left
    }

    /// `2분의 1` → 1/2 (분모가 먼저).
    private func parseBunui() throws -> Node {
        var left = try parseJuxtaposition()
        while case .bunui = peek {
            pos += 1
            left = .frac(try parseJuxtaposition(), left, true)
        }
        return left
    }

    private func parseJuxtaposition(stopAtNamedFn: Bool = false) throws -> Node {
        var items = [try parseUnary()]
        while let t = peek {
            if case .num = t {
                // `∫ 2x dx`처럼 큰 연산자 바로 뒤의 수만 곱으로 잇는다.
                guard items[items.count - 1].isBigOpHead else { break }
            } else if !startsOperand(t, stopAtNamedFn: stopAtNamedFn) {
                break
            }
            items.append(try parsePostfixed())
        }
        return items.count == 1 ? items[0] : .product(items)
    }

    private func startsOperand(_ t: Tok, stopAtNamedFn: Bool) -> Bool {
        switch t {
        case .ident, .sym, .lparen: return true
        case .fn(.named): return !stopAtNamedFn
        case .fn: return true
        case .bar: return absDepth == 0
        default: return false
        }
    }

    private func parseUnary() throws -> Node {
        if case .bin(let op) = peek, op.canBeUnary {
            try tick()
            pos += 1
            return .unary(op, try parseUnary())
        }
        return try parsePostfixed()
    }

    // MARK: 후위

    private func parsePostfixed(attachedOnly: Bool = false) throws -> Node {
        var node = try parsePrimary()
        loop: while let t = peekToken {
            if attachedOnly, t.spaceBefore { break }
            switch t.tok {
            case .caret:
                pos += 1
                node = Self.addSup(node, try parseScriptArg())
            case .underscore:
                pos += 1
                node = Self.addSub(node, try parseScriptArg())
            case .prime:
                pos += 1
                if case .prime(let base, let count) = node {
                    node = .prime(base, count + 1)
                } else {
                    node = .prime(node, 1)
                }
            case .bang:
                pos += 1
                node = .factorial(node)
            case .powWord(let n):
                pos += 1
                node = Self.addSup(node, .number(String(n)))
            case .toThePower:
                pos += 1
                node = Self.addSup(node, try parseScriptArg())
            case .ui:
                pos += 1
                node = try parsePossessive(node)
            default:
                break loop
            }
        }
        return node
    }

    /// `x의 제곱`, `x의 n제곱`, `x의 세제곱근`, `x의 절댓값`.
    private func parsePossessive(_ base: Node) throws -> Node {
        switch peek {
        case .powWord(let n)?:
            pos += 1
            return Self.addSup(base, .number(String(n)))
        case .fn(.root(let n))?:
            pos += 1
            return .root(n == 2 ? nil : .number(String(n)), base)
        case .fn(.abs)?:
            pos += 1
            return .abs(base.stripped)
        case .num?, .ident?, .sym?:
            let k = try parsePrimary()
            switch peek {
            case .powWord(2)?, .nthPower?:
                pos += 1
                return Self.addSup(base, k)
            case .fn(.root(2))?:
                pos += 1
                return .root(k, base)
            default:
                throw ParseFailure()
            }
        default:
            throw ParseFailure()
        }
    }

    private static func addSup(_ node: Node, _ exp: Node) -> Node {
        if case .script(let base, let sub, nil) = node { return .script(base, sub, exp) }
        return .script(node, nil, exp)
    }

    private static func addSub(_ node: Node, _ sub: Node) -> Node {
        if case .script(let base, nil, let sup) = node { return .script(base, sub, sup) }
        return .script(node, sub, nil)
    }

    private func parseScriptArg() throws -> Node {
        if case .bin(let op) = peek, op.canBeUnary {
            pos += 1
            return .unary(op, try parseScriptAtom())
        }
        return try parseScriptAtom()
    }

    private func parseScriptAtom() throws -> Node {
        switch peek {
        case .num(let s)?:
            pos += 1
            return .number(s)
        case .ident(let s)?:
            pos += 1
            return .variable(s)
        case .sym(let s)?:
            pos += 1
            return .symbol(s)
        case .lparen?:
            return try parsePrimary()
        case .lbrace?:
            pos += 1
            let savedAbs = absDepth
            absDepth = 0
            let inner = try parseRelation(top: false)
            guard case .rbrace = peek else { throw ParseFailure() }
            pos += 1
            absDepth = savedAbs
            return .group(inner)
        default:
            throw ParseFailure()
        }
    }

    // MARK: 기본 항

    private func parsePrimary() throws -> Node {
        try tick()
        guard let t = peek else { throw ParseFailure() }
        pos += 1
        switch t {
        case .num(let s):
            return .number(s)
        case .ident(let s):
            return .variable(s)
        case .sym(let s):
            switch s.kind {
            case .bigop:
                return try parseBigOp(s)
            case .lim:
                return try parseLimit(s)
            default:
                // `시그마 i=1부터 n까지`처럼 범위가 따라오면 합 기호로 본다.
                if s.unicode == "σ", sumBoundsFollow() { return try parseBigOp(Ops.sum) }
                return .symbol(s)
            }
        case .lparen:
            let savedAbs = absDepth
            absDepth = 0
            var items = [try parseRelation(top: false)]
            while case .comma = peek {
                pos += 1
                items.append(try parseRelation(top: false))
            }
            guard case .rparen = peek else { throw ParseFailure() }
            pos += 1
            absDepth = savedAbs
            return .group(items.count == 1 ? items[0] : .list(items))
        case .bar:
            absDepth += 1
            let inner = try parseAdditive()
            guard case .bar = peek else { throw ParseFailure() }
            pos += 1
            absDepth -= 1
            return .abs(inner)
        case .fn(let kind):
            return try parseFunction(kind)
        default:
            throw ParseFailure()
        }
    }

    private func parseFunction(_ kind: FuncKind) throws -> Node {
        let sawOf = skipOf()
        switch kind {
        case .named(let sym):
            var head: Node = .symbol(sym)
            if case .caret = peek {
                pos += 1
                head = .script(head, nil, try parseScriptArg())
            }
            let arg: Node
            if case .lparen = peek {
                arg = try parsePrimary()
            } else {
                arg = try parseJuxtaposition(stopAtNamedFn: true)
            }
            return .apply(head, arg)
        case .root, .abs:
            guard let next = peekToken else { throw ParseFailure() }
            let arg: Node
            if case .lparen = next.tok {
                arg = try parsePrimary()
            } else if wide, next.spaceBefore || sawOf {
                usedWide = true
                arg = try parseAdditive()
            } else {
                arg = try parseNarrowArgument()
            }
            if case .root(let n) = kind {
                return .root(n == 2 ? nil : .number(String(n)), arg)
            }
            return .abs(arg.stripped)
        }
    }

    /// 근호·절댓값의 좁은 범위: 항 하나와 거기 붙여 쓴 첨자까지.
    private func parseNarrowArgument() throws -> Node {
        if case .fn(let kind) = peek {
            try tick()
            pos += 1
            return try parseFunction(kind)
        }
        return try parsePostfixed(attachedOnly: true)
    }

    // MARK: 적분·합·극한

    private func sumBoundsFollow() -> Bool {
        if case .eFrom = peek { return true }
        return koreanBoundsAhead()
    }

    /// 뒤쪽 가까이에 `부터/에서`가 있는지. 중첩된 큰 연산자를 만나면 포기해 재시도 폭증을 막는다.
    private func koreanBoundsAhead() -> Bool {
        var depth = 0
        var j = pos
        while j < toks.count, j - pos <= 16 {
            switch toks[j].tok {
            case .lparen: depth += 1
            case .rparen: depth -= 1
            case .kFrom where depth == 0: return true
            case .kTo: return false
            case .sym(let s) where s.kind == .bigop || s.kind == .lim || s.unicode == "σ": return false
            default: break
            }
            j += 1
        }
        return false
    }

    private func parseBigOp(_ sym: Sym) throws -> Node {
        var lower: Node?
        var upper: Node?
        if case .eFrom = peek {
            // from A to B [of]
            pos += 1
            lower = try parseRelation(top: false)
            guard case .eTo = peek else { throw ParseFailure() }
            pos += 1
            upper = try parsePostfixed()
            _ = skipOf()
        } else if koreanBoundsAhead() {
            // A부터 B까지
            let savedPos = pos
            let savedAbs = absDepth
            do {
                let lo = try parseRelation(top: false)
                guard case .kFrom = peek else { throw ParseFailure() }
                pos += 1
                let hi = try parseAdditive()
                guard case .kTo = peek else { throw ParseFailure() }
                pos += 1
                lower = lo
                upper = hi
            } catch {
                pos = savedPos
                absDepth = savedAbs
            }
        } else {
            _ = skipOf()
        }
        let head: Node = .symbol(sym)
        return lower == nil && upper == nil ? head : .script(head, lower, upper)
    }

    private func parseLimit(_ sym: Sym) throws -> Node {
        var head: Node = .symbol(sym)
        if case .underscore = peek {
            pos += 1
            head = .script(head, try parseScriptArg(), nil)
        } else if case .asWord = peek {
            // limit as x approaches a [of]
            pos += 1
            let variable = try parsePrimary()
            guard case .rel(let op, _) = peek, op.unicode == Ops.arrow.unicode else { throw ParseFailure() }
            pos += 1
            let target = try parseUnary()
            _ = skipOf()
            head = .script(head, .relation(variable, [RelPart(op: Ops.arrow, rhs: target)]), nil)
        } else if pos + 1 < toks.count, case .rel(_, .particle) = toks[pos + 1].tok {
            // x가 a로 갈 때
            let savedPos = pos
            let savedAbs = absDepth
            do {
                let variable = try parsePrimary()
                pos += 1
                let target = try parseAdditive()
                guard case .goes = peek else { throw ParseFailure() }
                pos += 1
                head = .script(head, .relation(variable, [RelPart(op: Ops.arrow, rhs: target)]), nil)
            } catch {
                pos = savedPos
                absDepth = savedAbs
            }
        }
        guard let next = peek else { return head }
        switch next {
        case .num, .bin: break
        default: if !startsOperand(next, stopAtNamedFn: false) { return head }
        }
        return .apply(head, try parseMultiplicative())
    }
}
