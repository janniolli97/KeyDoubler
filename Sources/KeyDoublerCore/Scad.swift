import Foundation

/// Minimal evaluator for the `name = expression;` assignments found in the .scad
/// profile and definition files (numbers, + - * / ( ), ternary, comparisons, arrays, variables).
public final class ScadEnv {
    public enum Value { case num(Double), arr([Value]), str(String), bool(Bool) }

    var exprs: [String: String] = [:]
    var cache: [String: Value] = [:]
    var resolving: Set<String> = []

    public init() {}

    /// Later assignments override earlier ones (OpenSCAD semantics).
    public func load(_ text: String) {
        let stripped = Scad.stripComments(text)
        // only top-level assignments: skip module bodies by tracking brace depth
        var depth = 0, cur = ""
        var statements: [String] = []
        for ch in stripped {
            if ch == "{" { depth += 1; cur = ""; continue }
            if ch == "}" { depth = max(0, depth - 1); cur = ""; continue }
            if depth > 0 { continue }
            if ch == ";" { statements.append(cur); cur = "" } else { cur.append(ch) }
        }
        for s in statements {
            let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let eq = t.firstIndex(of: "="), !t.hasPrefix("include"), !t.hasPrefix("module") else { continue }
            let name = t[..<eq].trimmingCharacters(in: .whitespaces)
            guard name.range(of: "^[A-Za-z_][A-Za-z0-9_]*$", options: .regularExpression) != nil else { continue }
            exprs[name] = String(t[t.index(after: eq)...]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        cache.removeAll()
    }

    public func set(_ name: String, _ expr: String) { exprs[name] = expr; cache.removeAll() }
    public func has(_ name: String) -> Bool { exprs[name] != nil }

    public func number(_ name: String) -> Double? {
        if case .num(let d)? = value(name) { return d }
        if case .bool(let b)? = value(name) { return b ? 1 : 0 }
        return nil
    }
    public func bool(_ name: String) -> Bool { (number(name) ?? 0) != 0 }

    public func value(_ name: String) -> Value? {
        if let c = cache[name] { return c }
        guard let e = exprs[name], !resolving.contains(name) else { return nil }
        resolving.insert(name); defer { resolving.remove(name) }
        guard let v = eval(e) else { return nil }
        cache[name] = v
        return v
    }

    public func eval(_ expr: String, extra: [String: Value] = [:]) -> Value? {
        var p = Parser(s: Array(expr), env: self, extra: extra)
        return p.ternary()
    }
    public func evalNumber(_ expr: String, extra: [String: Value] = [:]) -> Double? {
        if case .num(let d)? = eval(expr, extra: extra) { return d }
        return nil
    }

    struct Parser {
        let s: [Character]; var i = 0
        let env: ScadEnv; let extra: [String: Value]
        init(s: [Character], env: ScadEnv, extra: [String: Value]) { self.s = s; self.env = env; self.extra = extra }

        mutating func ws() { while i < s.count, s[i].isWhitespace { i += 1 } }
        mutating func eat(_ str: String) -> Bool {
            ws(); let a = Array(str)
            if i + a.count <= s.count, Array(s[i..<(i + a.count)]) == a { i += a.count; return true }
            return false
        }
        func num(_ v: Value?) -> Double? {
            switch v { case .num(let d)?: return d; case .bool(let b)?: return b ? 1 : 0; default: return nil }
        }
        mutating func ternary() -> Value? {
            guard let c = compare() else { return nil }
            if eat("?") {
                let a = ternary(); guard eat(":") else { return nil }; let b = ternary()
                return (num(c) ?? 0) != 0 ? a : b
            }
            return c
        }
        mutating func compare() -> Value? {
            guard var l = additive() else { return nil }
            while true {
                let ops = ["==", "!=", "<=", ">=", "<", ">"]
                guard let op = ops.first(where: { eat($0) }) else { break }
                guard let r = additive() else { return nil }
                if case .str(let a) = l, case .str(let b) = r {
                    l = .bool(op == "==" ? a == b : (op == "!=" ? a != b : false)); continue
                }
                guard let a = num(l), let b = num(r) else { return nil }
                switch op {
                case "==": l = .bool(a == b); case "!=": l = .bool(a != b)
                case "<=": l = .bool(a <= b); case ">=": l = .bool(a >= b)
                case "<": l = .bool(a < b); default: l = .bool(a > b)
                }
            }
            return l
        }
        mutating func additive() -> Value? {
            guard var l = term() else { return nil }
            while true {
                ws()
                if eat("+") { guard let a = num(l), let b = num(term()) else { return nil }; l = .num(a + b) }
                else if eat("-") { guard let a = num(l), let b = num(term()) else { return nil }; l = .num(a - b) }
                else { break }
            }
            return l
        }
        mutating func term() -> Value? {
            guard var l = unary() else { return nil }
            while true {
                ws()
                if eat("*") { guard let a = num(l), let b = num(unary()) else { return nil }; l = .num(a * b) }
                else if eat("/") { guard let a = num(l), let b = num(unary()) else { return nil }; l = .num(a / b) }
                else if eat("%") { guard let a = num(l), let b = num(unary()) else { return nil }; l = .num(a.truncatingRemainder(dividingBy: b)) }
                else { break }
            }
            return l
        }
        mutating func unary() -> Value? {
            if eat("-") { guard let v = num(unary()) else { return nil }; return .num(-v) }
            if eat("+") { return unary() }
            if eat("!") { guard let v = num(unary()) else { return nil }; return .bool(v == 0) }
            return postfix()
        }
        mutating func postfix() -> Value? {
            guard var v = primary() else { return nil }
            while eat("[") {
                guard let idx = num(ternary()), eat("]"), case .arr(let a) = v, Int(idx) >= 0, Int(idx) < a.count else { return nil }
                v = a[Int(idx)]
            }
            return v
        }
        mutating func primary() -> Value? {
            ws()
            guard i < s.count else { return nil }
            if eat("(") { let v = ternary(); return eat(")") ? v : nil }
            if s[i] == "[" {
                i += 1; var items: [Value] = []
                ws()
                if eat("]") { return .arr([]) }
                repeat { guard let v = ternary() else { return nil }; items.append(v) } while eat(",")
                return eat("]") ? .arr(items) : nil
            }
            if s[i] == "\"" {
                i += 1; var t = ""
                while i < s.count, s[i] != "\"" { t.append(s[i]); i += 1 }
                i += 1; return .str(t)
            }
            if s[i].isNumber || s[i] == "." {
                var t = ""
                while i < s.count, s[i].isNumber || s[i] == "." { t.append(s[i]); i += 1 }
                if i < s.count, s[i] == "e" || s[i] == "E" {
                    t.append(s[i]); i += 1
                    if i < s.count, s[i] == "-" || s[i] == "+" { t.append(s[i]); i += 1 }
                    while i < s.count, s[i].isNumber { t.append(s[i]); i += 1 }
                }
                return Double(t).map { .num($0) }
            }
            if s[i].isLetter || s[i] == "_" {
                var t = ""
                while i < s.count, s[i].isLetter || s[i].isNumber || s[i] == "_" { t.append(s[i]); i += 1 }
                if t == "true" { return .bool(true) }
                if t == "false" { return .bool(false) }
                if t == "len" || t == "sqrt" || t == "abs" || t == "sin" || t == "cos" {
                    guard eat("("), let v = ternary(), eat(")") else { return nil }
                    if t == "len", case .arr(let a) = v { return .num(Double(a.count)) }
                    guard let d = num(v) else { return nil }
                    switch t { case "sqrt": return .num(d.squareRoot()); case "abs": return .num(abs(d))
                    case "sin": return .num(sin(d * .pi / 180)); default: return .num(cos(d * .pi / 180)) }
                }
                if let e = extra[t] { return e }
                return env.value(t)
            }
            return nil
        }
    }
}

public enum Scad {
    static func stripComments(_ s: String) -> String {
        var out = "", i = s.startIndex
        while i < s.endIndex {
            let rest = s[i...]
            if rest.hasPrefix("//") { while i < s.endIndex, s[i] != "\n" { i = s.index(after: i) } }
            else if rest.hasPrefix("/*") {
                if let r = s.range(of: "*/", range: s.index(i, offsetBy: 2)..<s.endIndex) { i = r.upperBound } else { i = s.endIndex }
            } else { out.append(s[i]); i = s.index(after: i) }
        }
        return out
    }
}
