import Foundation

/// AST → 유니코드 텍스트. 표현할 수 없는 구조를 만나면 `failed`를 세우고 선형 표기로 대신한다.
final class UnicodeRenderer {
    private let spacing: Bool
    private let variant: Variant
    private(set) var failed = false

    init(spacing: Bool, variant: Variant) {
        self.spacing = spacing
        self.variant = variant
    }

    private static let superscripts: [Character: Character] = [
        "0": "⁰", "1": "¹", "2": "²", "3": "³", "4": "⁴", "5": "⁵", "6": "⁶", "7": "⁷", "8": "⁸", "9": "⁹",
        "+": "⁺", "−": "⁻", "-": "⁻", "=": "⁼", "(": "⁽", ")": "⁾",
        "a": "ᵃ", "b": "ᵇ", "c": "ᶜ", "d": "ᵈ", "e": "ᵉ", "f": "ᶠ", "g": "ᵍ", "h": "ʰ", "i": "ⁱ",
        "j": "ʲ", "k": "ᵏ", "l": "ˡ", "m": "ᵐ", "n": "ⁿ", "o": "ᵒ", "p": "ᵖ", "r": "ʳ", "s": "ˢ",
        "t": "ᵗ", "u": "ᵘ", "v": "ᵛ", "w": "ʷ", "x": "ˣ", "y": "ʸ", "z": "ᶻ",
    ]

    private static let subscripts: [Character: Character] = [
        "0": "₀", "1": "₁", "2": "₂", "3": "₃", "4": "₄", "5": "₅", "6": "₆", "7": "₇", "8": "₈", "9": "₉",
        "+": "₊", "−": "₋", "-": "₋", "=": "₌", "(": "₍", ")": "₎",
        "a": "ₐ", "e": "ₑ", "h": "ₕ", "i": "ᵢ", "j": "ⱼ", "k": "ₖ", "l": "ₗ", "m": "ₘ", "n": "ₙ",
        "o": "ₒ", "p": "ₚ", "r": "ᵣ", "s": "ₛ", "t": "ₜ", "u": "ᵤ", "v": "ᵥ", "x": "ₓ",
    ]

    private static func map(_ s: String, _ table: [Character: Character]) -> String? {
        var out = ""
        for c in s {
            guard let m = table[c] else { return nil }
            out.append(m)
        }
        return out
    }

    /// 라틴 문자를 수학 이탤릭 자형으로 바꾼다 (`dy/dx` → `𝑑𝑦/𝑑𝑥`).
    private static func mathItalic(_ s: String) -> String {
        var out = String.UnicodeScalarView()
        for u in s.unicodeScalars {
            switch u.value {
            case 0x68: out.append(Unicode.Scalar(0x210E)!)
            case 0x61...0x7A: out.append(Unicode.Scalar(0x1D44E + u.value - 0x61)!)
            case 0x41...0x5A: out.append(Unicode.Scalar(0x1D434 + u.value - 0x41)!)
            default: out.append(u)
            }
        }
        return String(out)
    }

    func render(_ node: Node, compact: Bool = false) -> String {
        let sp = spacing && !compact ? " " : ""
        switch node {
        case .number(let s), .variable(let s):
            return s
        case .symbol(let s):
            return s.unicode
        case .product(let items):
            return renderProduct(items, compact: compact)
        case .binary(let op, let l, let r):
            let symbol = op.isTimes && variant.timesDot ? "·" : op.unicode
            return render(l, compact: compact) + sp + symbol + sp + render(r, compact: compact)
        case .relation(let first, let parts):
            var s = render(first, compact: compact)
            for part in parts {
                s += sp + part.op.unicode
                if let rhs = part.rhs { s += sp + render(rhs, compact: compact) }
            }
            return s
        case .frac(let num, let den, let spoken):
            return renderFraction(num, den, spoken: spoken, compact: compact)
        case .unary(let op, let operand):
            return op.unicode + render(operand, compact: compact)
        case .group(let inner):
            return "(" + render(inner, compact: compact) + ")"
        case .list(let items):
            return items.map { render($0, compact: compact) }.joined(separator: compact ? "," : ", ")
        case .abs(let inner):
            return "|" + render(inner, compact: compact) + "|"
        case .root(let index, let arg):
            let inner = arg.stripped
            let body = render(inner, compact: compact)
            return rootSign(index) + (inner.isAtom ? body : "(" + body + ")")
        case .apply(let head, let arg):
            return render(head, compact: compact) + (arg.isGroup ? "" : " ") + render(arg, compact: compact)
        case .script(let base, let sub, let sup):
            var s = renderBase(base, compact: compact)
            if let sub { s += script(sub, Self.subscripts, marker: "_") }
            if let sup { s += script(sup, Self.superscripts, marker: "^") }
            return s
        case .prime(let base, let count):
            let marks = ["′", "″", "‴"]
            let mark = count <= 3 ? marks[count - 1] : String(repeating: "′", count: count)
            return renderBase(base, compact: compact) + mark
        case .factorial(let base):
            return renderBase(base, compact: compact) + "!"
        }
    }

    private func renderBase(_ base: Node, compact: Bool) -> String {
        let s = render(base, compact: compact)
        return base.needsParensAsBase ? "(" + s + ")" : s
    }

    private func rootSign(_ index: Node?) -> String {
        guard let index else { return "√" }
        if case .number("3") = index { return "∛" }
        if case .number("4") = index { return "∜" }
        let raw = render(index.stripped, compact: true)
        if let mapped = Self.map(raw, Self.superscripts) { return mapped + "√" }
        failed = true
        return "(" + raw + ")√"
    }

    private func script(_ content: Node, _ table: [Character: Character], marker: String) -> String {
        let raw = render(content.stripped, compact: true)
        if let mapped = Self.map(raw, table) { return mapped }
        failed = true
        return marker + (raw.count == 1 ? raw : "(" + raw + ")")
    }

    private func renderFraction(_ num: Node, _ den: Node, spoken: Bool, compact: Bool) -> String {
        if variant.partialSub, let (function, v) = partialFracParts(num, den) {
            return "∂" + script(.variable(v), Self.subscripts, marker: "_") + render(function, compact: compact)
        }
        var denominator = render(den, compact: compact)
        if spoken, case .product(let items) = den, items.count > 1, !den.isDifferentialProduct {
            // `2x분의 1`이 (1/2)x로 읽히지 않도록 분모의 곱은 묶는다.
            denominator = "(" + denominator + ")"
        }
        let s = render(num, compact: compact) + "/" + denominator
        return variant.romanD && isDerivativeFrac(num, den) ? Self.mathItalic(s) : s
    }

    private func renderProduct(_ items: [Node], compact: Bool) -> String {
        var s = ""
        for (i, item) in items.enumerated() {
            if i > 0, !compact, needsSpace(items[i - 1], item) { s += " " }
            s += render(item, compact: compact)
        }
        return s
    }

    private func needsSpace(_ prev: Node, _ cur: Node) -> Bool {
        if cur.isSymbol(.dOp), !prev.isSymbol(.dOp, .partial) { return true }
        if prev.isApply || prev.isRoot || cur.isApply { return true }
        if prev.isBigOpHead, prev.hasScript { return true }
        return false
    }
}
