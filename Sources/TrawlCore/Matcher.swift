import Foundation

public struct MatchOptions: Sendable, Equatable {
    public var caseSensitive: Bool
    public var useRegex: Bool

    public init(caseSensitive: Bool = false, useRegex: Bool = false) {
        self.caseSensitive = caseSensitive
        self.useRegex = useRegex
    }
}

/// Evaluates a query against file names and file contents.
public final class Matcher: @unchecked Sendable {
    /// A compiled predicate tree. Each term holds two predicates: one for names
    /// (wildcard terms anchored to the whole name) and one for contents (unanchored).
    private indirect enum Node {
        case term(name: (String) -> Bool, content: (String) -> Bool)
        case and(Node, Node)
        case or(Node, Node)
        case not(Node)
    }

    private let root: Node

    public convenience init(query: String, options: MatchOptions = MatchOptions()) throws {
        if options.useRegex {
            let regex = try Self.makeRegex(query, caseSensitive: options.caseSensitive)
            let predicate = Self.regexPredicate(regex)
            self.init(root: .term(name: predicate, content: predicate))
        } else {
            self.init(expr: try QueryParser.parse(query), caseSensitive: options.caseSensitive)
        }
    }

    public convenience init(expr: QueryExpr, caseSensitive: Bool) {
        self.init(root: Self.compile(expr, caseSensitive: caseSensitive))
    }

    private init(root: Node) { self.root = root }

    public func matchesName(_ name: String) -> Bool { evaluate(root, name, isName: true) }

    public func matchesContent(_ text: String) -> Bool { evaluate(root, text, isName: false) }

    private func evaluate(_ node: Node, _ text: String, isName: Bool) -> Bool {
        switch node {
        case let .term(name, content): return isName ? name(text) : content(text)
        case let .and(a, b): return evaluate(a, text, isName: isName) && evaluate(b, text, isName: isName)
        case let .or(a, b): return evaluate(a, text, isName: isName) || evaluate(b, text, isName: isName)
        case let .not(a): return !evaluate(a, text, isName: isName)
        }
    }

    private static func compile(_ expr: QueryExpr, caseSensitive: Bool) -> Node {
        switch expr {
        case let .and(a, b): return .and(compile(a, caseSensitive: caseSensitive), compile(b, caseSensitive: caseSensitive))
        case let .or(a, b): return .or(compile(a, caseSensitive: caseSensitive), compile(b, caseSensitive: caseSensitive))
        case let .not(a): return .not(compile(a, caseSensitive: caseSensitive))
        case let .term(text, phrase):
            if !phrase, text.contains(where: { $0 == "*" || $0 == "?" }) {
                let nameRegex = wildcardRegex(text, anchored: true, caseSensitive: caseSensitive)
                let contentRegex = wildcardRegex(text, anchored: false, caseSensitive: caseSensitive)
                return .term(name: regexPredicate(nameRegex), content: regexPredicate(contentRegex))
            }
            let options: String.CompareOptions = caseSensitive ? [] : [.caseInsensitive]
            let predicate: (String) -> Bool = { $0.range(of: text, options: options) != nil }
            return .term(name: predicate, content: predicate)
        }
    }

    /// `*` matches any run of characters (within a line), `?` exactly one character.
    static func wildcardRegex(_ pattern: String, anchored: Bool, caseSensitive: Bool) -> NSRegularExpression {
        var source = anchored ? "^" : ""
        for c in pattern {
            switch c {
            case "*": source += anchored ? ".*" : ".*?"
            case "?": source += "."
            default: source += NSRegularExpression.escapedPattern(for: String(c))
            }
        }
        if anchored { source += "$" }
        // Built only from escaped characters and `.*`/`.`, so it always compiles.
        return try! makeRegex(source, caseSensitive: caseSensitive)
    }

    static func makeRegex(_ pattern: String, caseSensitive: Bool) throws -> NSRegularExpression {
        do {
            return try NSRegularExpression(pattern: pattern, options: caseSensitive ? [] : [.caseInsensitive])
        } catch {
            throw QueryError("Invalid regular expression.")
        }
    }

    private static func regexPredicate(_ regex: NSRegularExpression) -> (String) -> Bool {
        { text in
            regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
        }
    }
}
