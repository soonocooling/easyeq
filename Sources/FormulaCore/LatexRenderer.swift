import Foundation

/// AST → LaTeX 문자열.
final class LatexRenderer {
    private let spacing: Bool
    private let variant: Variant
    private var romanD = false

    init(spacing: Bool, variant: Variant) {
        self.spacing = spacing
        self.variant = variant
    }

    private static func isLetter(_ c: Character) -> Bool {
        guard let a = c.asciiValue else { return false }
        return (a >= 65 && a <= 90) || (a >= 97 && a <= 122)
    }

    /// `\alpha`처럼 명령으로 끝나서 뒤에 글자가 바로 오면 안 되는 문자열.
    private static func endsWithCommand(_ s: String) -> Bool {
        var sawLetter = false
        for c in s.reversed() {
            if isLetter(c) {
                sawLetter = true
            } else {
                return sawLetter && c == "\\"
            }
        }
        return false
    }

    private static func join(_ left: String, _ right: String) -> String {
        if endsWithCommand(left), let first = right.first, isLetter(first) { return left + " " + right }
        return left + right
    }

    /// 이항·관계 연산자를 양옆 문자열 사이에 넣는다. 명령형 연산자는 항상 띄운다.
    private func infix(_ left: String, _ op: String, _ right: String?, compact: Bool) -> String {
        let sp = (spacing && !compact) || op.hasPrefix("\\") ? " " : ""
        guard let right else { return left + sp + op }
        return left + sp + op + sp + right
    }

    func render(_ node: Node, compact: Bool = false) -> String {
        switch node {
        case .number(let s), .variable(let s):
            return s
        case .symbol(let s):
            return s.kind == .dOp && romanD ? "\\mathrm{d}" : s.latex
        case .product(let items):
            return renderProduct(items, compact: compact)
        case .binary(let op, let l, let r):
            let symbol = op.isTimes && variant.timesDot ? "\\cdot" : op.latex
            return infix(render(l, compact: compact), symbol, render(r, compact: compact), compact: compact)
        case .relation(let first, let parts):
            var s = render(first, compact: compact)
            for part in parts {
                s = infix(s, part.op.latex, part.rhs.map { render($0, compact: compact) }, compact: compact)
            }
            return s
        case .frac(let num, let den, _):
            return renderFraction(num, den, compact: compact)
        case .unary(let op, let operand):
            return Self.join(op.latex, render(operand, compact: compact))
        case .group(let inner):
            return "(" + render(inner, compact: compact) + ")"
        case .list(let items):
            return items.map { render($0, compact: compact) }.joined(separator: compact ? "," : ", ")
        case .abs(let inner):
            return "\\left| " + render(inner, compact: compact) + " \\right|"
        case .root(let index, let arg):
            let body = "{" + render(arg.stripped, compact: compact) + "}"
            guard let index else { return "\\sqrt" + body }
            return "\\sqrt[" + render(index.stripped, compact: true) + "]" + body
        case .apply(let head, let arg):
            return render(head, compact: compact) + (arg.isGroup ? "" : " ") + render(arg, compact: compact)
        case .script(let base, let sub, let sup):
            var s = renderBase(base, compact: compact)
            if let sub { s += "_" + scriptArgument(sub) }
            if let sup { s += "^" + scriptArgument(sup) }
            return s
        case .prime(let base, let count):
            return renderBase(base, compact: compact) + String(repeating: "'", count: count)
        case .factorial(let base):
            return renderBase(base, compact: compact) + "!"
        }
    }

    private func renderBase(_ base: Node, compact: Bool) -> String {
        let s = render(base, compact: compact)
        return base.needsParensAsBase ? "(" + s + ")" : s
    }

    private func scriptArgument(_ content: Node) -> String {
        let s = render(content.stripped, compact: true)
        return s.count == 1 ? s : "{" + s + "}"
    }

    private func renderFraction(_ num: Node, _ den: Node, compact: Bool) -> String {
        if variant.partialSub, let (function, v) = partialFracParts(num, den) {
            return "\\partial_" + v + " " + render(function, compact: compact)
        }
        let wasRoman = romanD
        if variant.romanD, isDerivativeFrac(num, den) { romanD = true }
        defer { romanD = wasRoman }
        return "\\frac{" + render(num.stripped, compact: compact) + "}{" + render(den.stripped, compact: compact) + "}"
    }

    private func renderProduct(_ items: [Node], compact: Bool) -> String {
        var s = ""
        for (i, item) in items.enumerated() {
            let piece = render(item, compact: compact)
            guard i > 0 else {
                s = piece
                continue
            }
            let prev = items[i - 1]
            if item.isSymbol(.dOp), !prev.isSymbol(.dOp, .partial) {
                s += " \\, " + piece
            } else if prev.isApply || item.isApply || prev.isBigOpHead {
                s += " " + piece
            } else {
                s = Self.join(s, piece)
            }
        }
        return s
    }
}
