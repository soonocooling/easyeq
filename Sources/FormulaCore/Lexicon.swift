import Foundation

/// 발음·기호 → 토큰 기본 사전 (기획서 부록 A). 사용자 사전은 기본 사전보다 우선한다.
struct Lexicon {
    private(set) var table: [String: Tok] = [:]
    /// 첫 글자를 대문자로 쓴 영어 그리스 문자 이름 (`Delta` → Δ).
    private(set) var upper: [String: Sym] = [:]
    private(set) var particles: Set<String> = []
    private(set) var maxLength = 1

    /// 뒤에 변수를 붙여 쓸 수 있는 함수 이름 (`sinx`). 긴 이름부터.
    static let attachable = ["sqrt", "sin", "cos", "tan", "sec", "csc", "cot", "log", "exp", "lim", "abs", "ln"]

    init(userEntries: [String: [String]] = [:]) {
        buildOperators()
        buildRelations()
        buildStructure()
        buildFunctions()
        buildSymbols()
        buildGreek()
        for (spoken, pair) in userEntries where pair.count == 2 {
            let key = spoken.trimmingCharacters(in: .whitespaces).lowercased()
            guard !key.isEmpty else { continue }
            particles.remove(key)
            upper[key] = nil
            add([key], .sym(Sym(unicode: pair[0], latex: pair[1])))
        }
    }

    private mutating func add(_ spoken: [String], _ tok: Tok) {
        for s in spoken {
            var keys = [s]
            // 한글 구는 띄어쓰기 없이 써도 인식한다.
            if s.contains(" "), s.unicodeScalars.contains(where: { $0.value >= 0xAC00 && $0.value <= 0xD7A3 }) {
                keys.append(s.replacingOccurrences(of: " ", with: ""))
            }
            for key in keys {
                table[key] = tok
                maxLength = max(maxLength, key.count)
            }
        }
    }

    private mutating func buildOperators() {
        add(["+", "더하기", "플러스", "plus"], .bin(Ops.plus))
        add(["-", "−", "빼기", "마이너스", "minus"], .bin(Ops.minus))
        add(["±", "+-", "플러스마이너스", "plus or minus", "plus minus"], .bin(Ops.plusMinus))
        add(["*", "곱하기", "곱", "times", "multiplied by"], .bin(Ops.times))
        add(["×", "외적", "cross"], .bin(Ops.cross))
        add(["·", "내적", "dot"], .bin(Ops.dot))
        add(["÷", "나누기", "divided by"], .bin(Ops.divide))
        add(["∪", "합집합", "union"], .bin(Ops.union))
        add(["∩", "교집합", "intersection"], .bin(Ops.intersection))
        add(["/"], .slash(false))
        add(["over"], .slash(true))
        add(["분의"], .bunui)
    }

    private mutating func buildRelations() {
        add(["=", "==", "equals", "equal to", "is equal to"], .rel(Ops.equals, .symbol))
        add(["같다", "와 같다", "과 같다", "이다", "입니다"], .rel(Ops.equals, .word))
        let particleWords = ["은", "는", "이", "가"]
        add(particleWords, .rel(Ops.equals, .particle))
        particles.formUnion(particleWords)

        add(["≠", "!=", "not equal to", "is not equal to"], .rel(Ops.notEquals, .symbol))
        add(["같지 않다", "와 같지 않다", "과 같지 않다"], .rel(Ops.notEquals, .word))
        add(["≥", ">=", "greater than or equal to"], .rel(Ops.greaterEq, .symbol))
        add(["이상", "크거나 같다", "보다 크거나 같다"], .rel(Ops.greaterEq, .word))
        add(["≤", "<=", "less than or equal to"], .rel(Ops.lessEq, .symbol))
        add(["이하", "작거나 같다", "보다 작거나 같다"], .rel(Ops.lessEq, .word))
        add([">", "greater than"], .rel(Ops.greater, .symbol))
        add(["보다 크다", "초과"], .rel(Ops.greater, .word))
        add(["<", "less than"], .rel(Ops.less, .symbol))
        add(["보다 작다", "미만"], .rel(Ops.less, .word))
        add(["≈", "~=", "approximately", "approx", "약"], .rel(Ops.approx, .symbol))
        add(["∈", "in", "is in", "element of", "is an element of"], .rel(Ops.element, .symbol))
        add(["에 속한다", "속한다"], .rel(Ops.element, .word))
        add(["⊂", "subset of", "is a subset of"], .rel(Ops.subset, .symbol))
        add(["의 부분집합", "부분집합"], .rel(Ops.subset, .word))
        add(["→", "->", "approaches", "goes to", "tends to"], .rel(Ops.arrow, .symbol))
    }

    private mutating func buildStructure() {
        add(["^", "**"], .caret)
        add(["_"], .underscore)
        add(["'", "’", "′", "프라임", "prime"], .prime)
        add(["!", "팩토리얼", "factorial"], .bang)
        add(["(", "괄호 열고", "여는 괄호"], .lparen)
        add([")", "괄호 닫고", "닫는 괄호"], .rparen)
        add(["{"], .lbrace)
        add(["}"], .rbrace)
        add(["|"], .bar)
        add([","], .comma)
        add(["제곱", "squared", "²"], .powWord(2))
        add(["세제곱", "cubed", "³"], .powWord(3))
        add(["네제곱"], .powWord(4))
        add(["승"], .nthPower)
        add(["to the power of", "to the power", "to the"], .toThePower)
        add(["의"], .ui)
        add(["of"], .of)
        add(["부터", "에서"], .kFrom)
        add(["까지"], .kTo)
        add(["from"], .eFrom)
        add(["to"], .eTo)
        add(["으로 갈 때", "로 갈 때", "으로 갈때", "로 갈때"], .goes)
        add(["as"], .asWord)
    }

    private mutating func buildFunctions() {
        add(["루트", "제곱근", "sqrt", "square root", "root", "√"], .fn(.root(2)))
        add(["세제곱근", "cube root", "cbrt", "∛"], .fn(.root(3)))
        add(["네제곱근", "fourth root", "∜"], .fn(.root(4)))
        add(["절댓값", "절대값", "abs", "absolute value"], .fn(.abs))
        let named: [(String, [String])] = [
            ("sin", ["사인", "sin", "sine"]),
            ("cos", ["코사인", "cos", "cosine"]),
            ("tan", ["탄젠트", "tan", "tangent"]),
            ("log", ["로그", "log"]),
            ("ln", ["자연로그", "ln"]),
            ("exp", ["exp"]),
            ("sec", ["sec"]),
            ("csc", ["csc"]),
            ("cot", ["cot"]),
        ]
        for (name, spoken) in named {
            add(spoken, .fn(.named(Sym(unicode: name, latex: "\\" + name, kind: .funcName))))
        }
    }

    private mutating func buildSymbols() {
        add(["무한대", "무한", "infinity", "inf", "∞"], .sym(Sym(unicode: "∞", latex: "\\infty")))
        add(["에이치바", "hbar", "ħ"], .sym(Sym(unicode: "ħ", latex: "\\hbar")))
        add(["나블라", "nabla", "∇"], .sym(Sym(unicode: "∇", latex: "\\nabla")))
        add(["모든", "임의의", "for all", "forall", "∀"], .sym(Sym(unicode: "∀", latex: "\\forall")))
        add(["존재", "존재한다", "exists", "there exists", "∃"], .sym(Sym(unicode: "∃", latex: "\\exists")))
        add(["라운드", "파셜", "partial", "∂"], .sym(Sym(unicode: "∂", latex: "\\partial", kind: .partial)))
        add(["디"], .sym(Sym(unicode: "d", latex: "d", kind: .dOp)))
        add(["인테그랄", "인테그럴", "적분", "integral", "∫"], .sym(Sym(unicode: "∫", latex: "\\int", kind: .bigop)))
        add(["합", "sum", "summation", "∑", "대문자 시그마", "Σ"], .sym(Ops.sum))
        add(["극한", "리미트", "limit", "lim"], .sym(Sym(unicode: "lim", latex: "\\lim", kind: .lim)))
    }

    private mutating func buildGreek() {
        // (영어 이름, 한글 발음, 소문자, 대문자)
        let greek: [(String, [String], String, String?)] = [
            ("alpha", ["알파"], "α", nil),
            ("beta", ["베타"], "β", nil),
            ("gamma", ["감마"], "γ", "Γ"),
            ("delta", ["델타"], "δ", "Δ"),
            ("epsilon", ["엡실론", "입실론"], "ε", nil),
            ("zeta", ["제타"], "ζ", nil),
            ("eta", ["에타"], "η", nil),
            ("theta", ["세타", "쎄타"], "θ", "Θ"),
            ("kappa", ["카파"], "κ", nil),
            ("lambda", ["람다"], "λ", "Λ"),
            ("mu", ["뮤"], "μ", nil),
            ("nu", ["뉴"], "ν", nil),
            ("pi", ["파이"], "π", "Π"),
            ("rho", ["로"], "ρ", nil),
            ("sigma", ["시그마"], "σ", nil),
            ("tau", ["타우"], "τ", nil),
            ("phi", ["피"], "φ", "Φ"),
            ("chi", ["카이"], "χ", nil),
            ("psi", ["프사이"], "ψ", "Ψ"),
            ("omega", ["오메가"], "ω", "Ω"),
        ]
        for (name, korean, lower, upperChar) in greek {
            add([name, lower] + korean, .sym(Sym(unicode: lower, latex: "\\" + name)))
            guard let upperChar else { continue }
            let capitalized = name.prefix(1).uppercased() + name.dropFirst()
            let sym = Sym(unicode: upperChar, latex: "\\" + capitalized)
            upper[name] = sym
            add([upperChar] + korean.map { "대문자 " + $0 }, .sym(sym))
        }
        upper["sigma"] = Ops.sum
    }
}
