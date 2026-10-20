import Foundation

/// Parsed Boolean query.
public indirect enum QueryExpr: Equatable, Sendable {
    case term(String, phrase: Bool)
    case and(QueryExpr, QueryExpr)
    case or(QueryExpr, QueryExpr)
    case not(QueryExpr)
}

public struct QueryError: Error, Equatable, LocalizedError, Sendable {
    public let message: String
    public init(_ message: String) { self.message = message }
    public var errorDescription: String? { message }
}

/// Parses Trawl-style Boolean queries.
///
/// Grammar (NOT binds tightest, then AND, then OR):
///
///     or      := and ("OR" and)*
///     and     := unary (["AND"] unary)*
///     unary   := "NOT" unary | primary
///     primary := WORD | "PHRASE" | "(" or ")"
public enum QueryParser {
    enum Token: Equatable {
        case word(String)
        case phrase(String)
        case and, or, not, lparen, rparen
    }

    public static func parse(_ input: String) throws -> QueryExpr {
        var tokens = try tokenize(input)[...]
        guard !tokens.isEmpty else { throw QueryError("Enter something to search for.") }
        let expr = try parseOr(&tokens)
        if let extra = tokens.first {
            throw QueryError(extra == .rparen ? "Unbalanced \")\" in query." : "Unexpected input in query.")
        }
        return expr
    }

    static func tokenize(_ input: String) throws -> [Token] {
        var tokens: [Token] = []
        var i = input.startIndex
        while i < input.endIndex {
            let c = input[i]
            if c.isWhitespace {
                i = input.index(after: i)
            } else if c == "(" {
                tokens.append(.lparen); i = input.index(after: i)
            } else if c == ")" {
                tokens.append(.rparen); i = input.index(after: i)
            } else if c == "\"" {
                let start = input.index(after: i)
                guard let end = input[start...].firstIndex(of: "\"") else {
                    throw QueryError("Missing closing quote in query.")
                }
                let text = String(input[start..<end])
                if !text.isEmpty { tokens.append(.phrase(text)) }
                i = input.index(after: end)
            } else if c == "-" || c == "!", case let next = input.index(after: i),
                      next < input.endIndex, !input[next].isWhitespace {
                // Prefix negation: -draft, !draft, -"a phrase", -(a b)
                tokens.append(.not); i = next
            } else {
                var end = i
                while end < input.endIndex, !input[end].isWhitespace, !"()\"".contains(input[end]) {
                    end = input.index(after: end)
                }
                let word = String(input[i..<end])
                switch word {
                case "AND", "&", "&&": tokens.append(.and)
                case "OR", "|", "||": tokens.append(.or)
                case "NOT", "!": tokens.append(.not)
                default: tokens.append(.word(word))
                }
                i = end
            }
        }
        return tokens
    }

    private static func parseOr(_ tokens: inout ArraySlice<Token>) throws -> QueryExpr {
        var lhs = try parseAnd(&tokens)
        while tokens.first == .or {
            tokens.removeFirst()
            lhs = .or(lhs, try parseAnd(&tokens))
        }
        return lhs
    }

    private static func parseAnd(_ tokens: inout ArraySlice<Token>) throws -> QueryExpr {
        var lhs = try parseUnary(&tokens)
        while let next = tokens.first {
            if next == .and {
                tokens.removeFirst()
            } else if next == .or || next == .rparen {
                break
            }
            lhs = .and(lhs, try parseUnary(&tokens))
        }
        return lhs
    }

    private static func parseUnary(_ tokens: inout ArraySlice<Token>) throws -> QueryExpr {
        if tokens.first == .not {
            tokens.removeFirst()
            return .not(try parseUnary(&tokens))
        }
        return try parsePrimary(&tokens)
    }

    private static func parsePrimary(_ tokens: inout ArraySlice<Token>) throws -> QueryExpr {
        guard let token = tokens.popFirst() else {
            throw QueryError("Query ends with an operator.")
        }
        switch token {
        case .word(let w): return .term(w, phrase: false)
        case .phrase(let p): return .term(p, phrase: true)
        case .lparen:
            let inner = try parseOr(&tokens)
            guard tokens.popFirst() == .rparen else { throw QueryError("Missing \")\" in query.") }
            return inner
        case .rparen: throw QueryError("Unbalanced \")\" in query.")
        case .and, .or: throw QueryError("Operator without a term before it.")
        case .not: throw QueryError("Unexpected NOT.")
        }
    }
}
