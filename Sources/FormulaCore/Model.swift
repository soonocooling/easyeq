import Foundation

public enum OutputFormat: String, Sendable {
    case unicode
    case latex
}

public struct Candidate: Equatable, Sendable {
    public let unicode: String
    public let latex: String
    public let rank: Int
    /// 유니코드로 표현할 수 없는 구조가 있어 LaTeX 문자열로 대체해야 하는 후보.
    public let needsLatex: Bool
    public let note: String?

    public init(unicode: String, latex: String, rank: Int, needsLatex: Bool, note: String? = nil) {
        self.unicode = unicode
        self.latex = latex
        self.rank = rank
        self.needsLatex = needsLatex
        self.note = note
    }

    /// 실제로 삽입될 문자열.
    public func text(for format: OutputFormat) -> String {
        format == .latex || needsLatex ? latex : unicode
    }
}

public struct EngineOptions: Sendable {
    public var normalizeSpacing: Bool
    public var maxCandidates: Int

    public init(normalizeSpacing: Bool = true, maxCandidates: Int = 5) {
        self.normalizeSpacing = normalizeSpacing
        self.maxCandidates = maxCandidates
    }
}

// MARK: - 내부 모델

struct Sym {
    enum Kind { case plain, dOp, partial, bigop, lim, funcName }
    let unicode: String
    let latex: String
    var kind: Kind = .plain
}

struct BinOp {
    enum Level { case additive, multiplicative }
    let unicode: String
    let latex: String
    let level: Level
    /// `×` / `·` 후보가 갈리는 곱하기.
    var isTimes = false
    var canBeUnary = false
}

struct RelOp {
    let unicode: String
    let latex: String
    var isEquals = false
}

enum RelOrigin { case symbol, particle, word }

enum FuncKind {
    case root(Int)
    case abs
    case named(Sym)
}

enum Tok {
    case num(String)
    case ident(String)
    case sym(Sym)
    case bin(BinOp)
    case rel(RelOp, RelOrigin)
    /// `over`처럼 발음으로 쓴 경우 true.
    case slash(Bool)
    case bunui
    case caret, underscore, prime, bang
    case lparen, rparen, lbrace, rbrace, bar, comma
    case fn(FuncKind)
    case powWord(Int)
    case nthPower
    case toThePower
    case ui, of
    case kFrom, kTo, eFrom, eTo
    case goes, asWord
}

struct Token {
    var tok: Tok
    let spaceBefore: Bool
}

enum Ops {
    static let plus = BinOp(unicode: "+", latex: "+", level: .additive, canBeUnary: true)
    static let minus = BinOp(unicode: "−", latex: "-", level: .additive, canBeUnary: true)
    static let plusMinus = BinOp(unicode: "±", latex: "\\pm", level: .additive, canBeUnary: true)
    static let union = BinOp(unicode: "∪", latex: "\\cup", level: .additive)
    static let intersection = BinOp(unicode: "∩", latex: "\\cap", level: .additive)
    static let times = BinOp(unicode: "×", latex: "\\times", level: .multiplicative, isTimes: true)
    static let cross = BinOp(unicode: "×", latex: "\\times", level: .multiplicative)
    static let dot = BinOp(unicode: "·", latex: "\\cdot", level: .multiplicative)
    static let divide = BinOp(unicode: "÷", latex: "\\div", level: .multiplicative)

    static let equals = RelOp(unicode: "=", latex: "=", isEquals: true)
    static let notEquals = RelOp(unicode: "≠", latex: "\\neq")
    static let greaterEq = RelOp(unicode: "≥", latex: "\\geq")
    static let lessEq = RelOp(unicode: "≤", latex: "\\leq")
    static let greater = RelOp(unicode: ">", latex: ">")
    static let less = RelOp(unicode: "<", latex: "<")
    static let approx = RelOp(unicode: "≈", latex: "\\approx")
    static let element = RelOp(unicode: "∈", latex: "\\in")
    static let subset = RelOp(unicode: "⊂", latex: "\\subset")
    static let arrow = RelOp(unicode: "→", latex: "\\to")

    static let sum = Sym(unicode: "Σ", latex: "\\sum", kind: .bigop)
}

struct RelPart {
    let op: RelOp
    let rhs: Node?
}

indirect enum Node {
    case number(String)
    case variable(String)
    case symbol(Sym)
    /// 암묵적 곱 (붙여 쓴 항).
    case product([Node])
    case binary(BinOp, Node, Node)
    case relation(Node, [RelPart])
    /// 세 번째 값: 발음(`분의`, `over`)에서 온 분수라 분모의 곱을 괄호로 묶어야 하는지.
    case frac(Node, Node, Bool)
    case unary(BinOp, Node)
    case group(Node)
    case list([Node])
    case abs(Node)
    case root(Node?, Node)
    case apply(Node, Node)
    case script(Node, Node?, Node?)
    case prime(Node, Int)
    case factorial(Node)

    var stripped: Node {
        if case .group(let inner) = self { return inner }
        return self
    }

    var isGroup: Bool {
        if case .group = self { return true }
        return false
    }

    var isAtom: Bool {
        switch self {
        case .number, .variable, .symbol: return true
        default: return false
        }
    }

    var isApply: Bool {
        if case .apply = self { return true }
        return false
    }

    var isRoot: Bool {
        if case .root = self { return true }
        return false
    }

    func isSymbol(_ kinds: Sym.Kind...) -> Bool {
        if case .symbol(let s) = self { return kinds.contains(s.kind) }
        return false
    }

    var isBigOpHead: Bool {
        if isSymbol(.bigop) { return true }
        if case .script(let base, _, _) = self { return base.isSymbol(.bigop) }
        return false
    }

    var hasScript: Bool {
        if case .script = self { return true }
        return false
    }

    /// 첨자·계승을 붙일 때 괄호로 감싸야 하는 밑.
    var needsParensAsBase: Bool {
        switch self {
        case .binary, .relation, .frac, .unary, .root, .apply, .script, .list:
            return true
        case .product(let items):
            return items.count > 1
        default:
            return false
        }
    }

    /// `dy`, `∂f`처럼 미분 연산자로 시작하는 곱.
    var isDifferentialProduct: Bool {
        if case .product(let items) = self, let first = items.first {
            return first.isSymbol(.dOp, .partial)
        }
        return false
    }
}

struct Variant {
    var timesDot = false
    var partialSub = false
    var romanD = false

    /// 후보 순위: 사전 규칙의 기본 표기 → 곱하기 기호 → 편미분 표기 → 미분 d 글꼴.
    static let ordered: [Variant] = [
        Variant(),
        Variant(timesDot: true),
        Variant(partialSub: true),
        Variant(romanD: true),
        Variant(timesDot: true, partialSub: true),
        Variant(timesDot: true, romanD: true),
    ]
}

/// `dy/dx` 꼴: 분자·분모가 모두 `d`로 시작하는 곱.
func isDerivativeFrac(_ num: Node, _ den: Node) -> Bool {
    func startsWithD(_ n: Node) -> Bool {
        if case .product(let items) = n, items.count >= 2 { return items[0].isSymbol(.dOp) }
        return false
    }
    return startsWithD(num) && startsWithD(den)
}

/// `∂f/∂x` 꼴이면 (f, x)를 돌려준다.
func partialFracParts(_ num: Node, _ den: Node) -> (Node, String)? {
    guard case .product(let n) = num, n.count == 2, n[0].isSymbol(.partial),
          case .product(let d) = den, d.count == 2, d[0].isSymbol(.partial),
          case .variable(let v) = d[1] else { return nil }
    return (n[1], v)
}
