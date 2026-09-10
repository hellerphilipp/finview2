import Foundation

/// A runtime value produced while evaluating a CEL-subset expression.
///
/// The subset mirrors what the `statement-importer` YAML specs actually use:
/// string/number literals, `row[i]` indexing, the helper functions `double`
/// and `split`, string concatenation with `+`, arithmetic, comparisons and the
/// ternary operator. It is deliberately *not* a full CEL implementation.
public enum CELValue: Equatable, Sendable {
    case string(String)
    case double(Double)
    case bool(Bool)
    case list([CELValue])

    var asDouble: Double? {
        if case let .double(d) = self { return d }
        return nil
    }
    var asString: String? {
        if case let .string(s) = self { return s }
        return nil
    }
    var asBool: Bool? {
        if case let .bool(b) = self { return b }
        return nil
    }
    var asList: [CELValue]? {
        if case let .list(l) = self { return l }
        return nil
    }
}

public struct CELError: Error, CustomStringConvertible, Equatable {
    public let message: String
    public var description: String { message }
    init(_ message: String) { self.message = message }
}

// MARK: - Lexer

enum CELToken: Equatable {
    case number(Double)
    case string(String)
    case ident(String)
    case plus, minus, star, slash
    case eq, neq, lt, lte, gt, gte
    case and, or, not
    case question, colon, comma
    case lparen, rparen, lbracket, rbracket
    case eof
}

struct CELLexer {
    private let chars: [Character]
    private var pos = 0

    init(_ source: String) { chars = Array(source) }

    private func peek(_ offset: Int = 0) -> Character? {
        let i = pos + offset
        return i < chars.count ? chars[i] : nil
    }

    mutating func tokenize() throws -> [CELToken] {
        var tokens: [CELToken] = []
        while let c = peek() {
            if c.isWhitespace { pos += 1; continue }
            switch c {
            case "+": tokens.append(.plus); pos += 1
            case "-": tokens.append(.minus); pos += 1
            case "*": tokens.append(.star); pos += 1
            case "/": tokens.append(.slash); pos += 1
            case "?": tokens.append(.question); pos += 1
            case ":": tokens.append(.colon); pos += 1
            case ",": tokens.append(.comma); pos += 1
            case "(": tokens.append(.lparen); pos += 1
            case ")": tokens.append(.rparen); pos += 1
            case "[": tokens.append(.lbracket); pos += 1
            case "]": tokens.append(.rbracket); pos += 1
            case "'", "\"": tokens.append(.string(try readString(quote: c)))
            case "=":
                pos += 1
                guard peek() == "=" else { throw CELError("Unexpected '='") }
                pos += 1; tokens.append(.eq)
            case "!":
                pos += 1
                if peek() == "=" { pos += 1; tokens.append(.neq) } else { tokens.append(.not) }
            case "<":
                pos += 1
                if peek() == "=" { pos += 1; tokens.append(.lte) } else { tokens.append(.lt) }
            case ">":
                pos += 1
                if peek() == "=" { pos += 1; tokens.append(.gte) } else { tokens.append(.gt) }
            case "&":
                pos += 1
                guard peek() == "&" else { throw CELError("Expected '&&'") }
                pos += 1; tokens.append(.and)
            case "|":
                pos += 1
                guard peek() == "|" else { throw CELError("Expected '||'") }
                pos += 1; tokens.append(.or)
            default:
                if c.isNumber || (c == "." && (peek(1)?.isNumber ?? false)) {
                    tokens.append(.number(try readNumber()))
                } else if c.isLetter || c == "_" {
                    tokens.append(.ident(readIdent()))
                } else {
                    throw CELError("Unexpected character '\(c)'")
                }
            }
        }
        tokens.append(.eof)
        return tokens
    }

    private mutating func readString(quote: Character) throws -> String {
        pos += 1 // opening quote
        var out = ""
        while let c = peek() {
            if c == quote { pos += 1; return out }
            if c == "\\" {
                pos += 1
                guard let e = peek() else { break }
                switch e {
                case "n": out.append("\n")
                case "t": out.append("\t")
                case "\\": out.append("\\")
                case "'": out.append("'")
                case "\"": out.append("\"")
                default: out.append(e)
                }
                pos += 1
            } else {
                out.append(c); pos += 1
            }
        }
        throw CELError("Unterminated string literal")
    }

    private mutating func readNumber() throws -> Double {
        var s = ""
        while let c = peek(), c.isNumber || c == "." { s.append(c); pos += 1 }
        guard let d = Double(s) else { throw CELError("Invalid number '\(s)'") }
        return d
    }

    private mutating func readIdent() -> String {
        var s = ""
        while let c = peek(), c.isLetter || c.isNumber || c == "_" { s.append(c); pos += 1 }
        return s
    }
}

// MARK: - AST

indirect enum CELExpr {
    case number(Double)
    case string(String)
    case ident(String)
    case unary(CELToken, CELExpr)
    case binary(CELToken, CELExpr, CELExpr)
    case ternary(CELExpr, CELExpr, CELExpr)
    case call(String, [CELExpr])
    case index(CELExpr, CELExpr)
}

// MARK: - Parser (recursive descent)

struct CELParser {
    private let tokens: [CELToken]
    private var pos = 0

    init(_ tokens: [CELToken]) { self.tokens = tokens }

    static func parse(_ source: String) throws -> CELExpr {
        var lexer = CELLexer(source)
        var parser = CELParser(try lexer.tokenize())
        let expr = try parser.parseExpression()
        guard parser.current == .eof else { throw CELError("Unexpected trailing tokens") }
        return expr
    }

    private var current: CELToken { tokens[pos] }
    private mutating func advance() -> CELToken { defer { pos += 1 }; return tokens[pos] }
    private mutating func match(_ t: CELToken) -> Bool {
        if current == t { pos += 1; return true }
        return false
    }
    private mutating func expect(_ t: CELToken) throws {
        guard match(t) else { throw CELError("Expected \(t), got \(current)") }
    }

    mutating func parseExpression() throws -> CELExpr { try parseTernary() }

    private mutating func parseTernary() throws -> CELExpr {
        let cond = try parseOr()
        if match(.question) {
            let thenExpr = try parseExpression()
            try expect(.colon)
            let elseExpr = try parseTernary()
            return .ternary(cond, thenExpr, elseExpr)
        }
        return cond
    }

    private mutating func parseOr() throws -> CELExpr {
        var left = try parseAnd()
        while current == .or { let op = advance(); left = .binary(op, left, try parseAnd()) }
        return left
    }
    private mutating func parseAnd() throws -> CELExpr {
        var left = try parseEquality()
        while current == .and { let op = advance(); left = .binary(op, left, try parseEquality()) }
        return left
    }
    private mutating func parseEquality() throws -> CELExpr {
        var left = try parseRelational()
        while current == .eq || current == .neq { let op = advance(); left = .binary(op, left, try parseRelational()) }
        return left
    }
    private mutating func parseRelational() throws -> CELExpr {
        var left = try parseAdditive()
        while [.lt, .lte, .gt, .gte].contains(current) { let op = advance(); left = .binary(op, left, try parseAdditive()) }
        return left
    }
    private mutating func parseAdditive() throws -> CELExpr {
        var left = try parseMultiplicative()
        while current == .plus || current == .minus { let op = advance(); left = .binary(op, left, try parseMultiplicative()) }
        return left
    }
    private mutating func parseMultiplicative() throws -> CELExpr {
        var left = try parseUnary()
        while current == .star || current == .slash { let op = advance(); left = .binary(op, left, try parseUnary()) }
        return left
    }
    private mutating func parseUnary() throws -> CELExpr {
        if current == .minus || current == .not { let op = advance(); return .unary(op, try parseUnary()) }
        return try parsePostfix()
    }
    private mutating func parsePostfix() throws -> CELExpr {
        var expr = try parsePrimary()
        while match(.lbracket) {
            let idx = try parseExpression()
            try expect(.rbracket)
            expr = .index(expr, idx)
        }
        return expr
    }
    private mutating func parsePrimary() throws -> CELExpr {
        switch advance() {
        case let .number(n): return .number(n)
        case let .string(s): return .string(s)
        case let .ident(name):
            if match(.lparen) {
                var args: [CELExpr] = []
                if current != .rparen {
                    repeat { args.append(try parseExpression()) } while match(.comma)
                }
                try expect(.rparen)
                return .call(name, args)
            }
            return .ident(name)
        case .lparen:
            let e = try parseExpression()
            try expect(.rparen)
            return e
        default:
            throw CELError("Unexpected token \(tokens[pos - 1])")
        }
    }
}

// MARK: - Interpreter

struct CELInterpreter {
    let variables: [String: CELValue]

    /// Convert a value to a Double the way the Python `double()` helper does:
    /// blank → 0, comma decimal → dot, otherwise parse.
    static func toDouble(_ value: CELValue) throws -> Double {
        switch value {
        case let .double(d): return d
        case let .string(s):
            let t = s.trimmingCharacters(in: .whitespaces)
            if t.isEmpty { return 0.0 }
            guard let d = Double(t.replacingOccurrences(of: ",", with: ".")) else {
                throw CELError("double(): cannot parse '\(s)'")
            }
            return d
        default:
            throw CELError("double(): unsupported argument")
        }
    }

    func eval(_ expr: CELExpr) throws -> CELValue {
        switch expr {
        case let .number(n): return .double(n)
        case let .string(s): return .string(s)
        case let .ident(name):
            guard let v = variables[name] else { throw CELError("Unknown identifier '\(name)'") }
            return v

        case let .unary(op, operand):
            let v = try eval(operand)
            switch op {
            case .minus:
                guard let d = v.asDouble else { throw CELError("Unary '-' requires a number") }
                return .double(-d)
            case .not:
                guard let b = v.asBool else { throw CELError("Unary '!' requires a bool") }
                return .bool(!b)
            default: throw CELError("Bad unary operator")
            }

        case let .ternary(c, t, e):
            guard let cond = try eval(c).asBool else { throw CELError("Ternary condition must be a bool") }
            return try eval(cond ? t : e)

        case let .binary(op, l, r):
            return try evalBinary(op, l, r)

        case let .call(name, args):
            return try evalCall(name, args)

        case let .index(base, idx):
            let b = try eval(base)
            let i = try eval(idx)
            guard let list = b.asList else { throw CELError("Indexing requires a list") }
            guard let di = i.asDouble else { throw CELError("Index must be a number") }
            let n = Int(di)
            guard n >= 0, n < list.count else { throw CELError("Index \(n) out of bounds (len \(list.count))") }
            return list[n]
        }
    }

    private func evalBinary(_ op: CELToken, _ l: CELExpr, _ r: CELExpr) throws -> CELValue {
        // Logical operators short-circuit.
        if op == .and || op == .or {
            guard let lb = try eval(l).asBool else { throw CELError("Logical operator requires bools") }
            if op == .and && !lb { return .bool(false) }
            if op == .or && lb { return .bool(true) }
            guard let rb = try eval(r).asBool else { throw CELError("Logical operator requires bools") }
            return .bool(rb)
        }

        let a = try eval(l)
        let b = try eval(r)

        switch op {
        case .plus:
            if case let .string(sa) = a, case let .string(sb) = b { return .string(sa + sb) }
            if let da = a.asDouble, let db = b.asDouble { return .double(da + db) }
            throw CELError("'+' requires two strings or two numbers")
        case .minus, .star, .slash:
            guard let da = a.asDouble, let db = b.asDouble else { throw CELError("Arithmetic requires numbers") }
            switch op {
            case .minus: return .double(da - db)
            case .star: return .double(da * db)
            default:
                guard db != 0 else { throw CELError("Division by zero") }
                return .double(da / db)
            }
        case .eq: return .bool(a == b)
        case .neq: return .bool(a != b)
        case .lt, .lte, .gt, .gte:
            guard let da = a.asDouble, let db = b.asDouble else { throw CELError("Comparison requires numbers") }
            switch op {
            case .lt: return .bool(da < db)
            case .lte: return .bool(da <= db)
            case .gt: return .bool(da > db)
            default: return .bool(da >= db)
            }
        default:
            throw CELError("Unsupported binary operator")
        }
    }

    private func evalCall(_ name: String, _ args: [CELExpr]) throws -> CELValue {
        switch name {
        case "double":
            guard args.count == 1 else { throw CELError("double() takes 1 argument") }
            return .double(try Self.toDouble(try eval(args[0])))
        case "split":
            guard args.count == 2 else { throw CELError("split() takes 2 arguments") }
            guard let s = try eval(args[0]).asString, let d = try eval(args[1]).asString else {
                throw CELError("split() requires string arguments")
            }
            let parts = d.isEmpty ? s.map { String($0) } : s.components(separatedBy: d)
            return .list(parts.map { .string($0) })
        default:
            throw CELError("Unknown function '\(name)'")
        }
    }
}

/// Compile + evaluate a single CEL-subset expression against a set of variables.
public func evaluateCEL(_ source: String, variables: [String: CELValue]) throws -> CELValue {
    let ast = try CELParser.parse(source)
    return try CELInterpreter(variables: variables).eval(ast)
}
