import Foundation

/// Translates a Trawl query into a Spotlight (MDQuery) query string.
///
/// Spotlight only receives the positive part of the query: NOT branches are dropped, which
/// can only widen the result set. `HybridSearcher` then re-checks names exactly with
/// `Matcher`, and keeps content-only hits only when the query has no NOT, because text
/// inside Office/PDF files cannot be re-checked here.
public enum SpotlightQueryBuilder {
    public enum Plan: Equatable, Sendable {
        case query(String)
        case skip(reason: String)
    }

    public static func plan(for query: String, options: SearchOptions) -> Plan {
        if options.match.useRegex { return .skip(reason: "Spotlight is not used for regular expressions.") }
        guard let expr = try? QueryParser.parse(query) else { return .skip(reason: "Query not understood.") }
        let hasNot = expr.containsNot
        let modifier = options.match.caseSensitive ? "" : "c"

        var parts: [String] = []
        if options.target != .contents {
            guard let names = relax(expr, { nameClause($0, $1, modifier) }) else {
                return .skip(reason: "Spotlight needs at least one word to look for.")
            }
            parts.append(names)
        }
        if options.target != .names, !hasNot {
            guard let contents = relax(expr, { contentClause($0, $1, modifier) }) else {
                return .skip(reason: "Spotlight needs at least one word to look for.")
            }
            parts.append(contents)
        }
        if parts.isEmpty { return .skip(reason: "Spotlight is not used for content searches with NOT.") }

        var result = parts.count == 1 ? parts[0] : "(\(parts[0]) || \(parts[1]))"
        if !options.fileTypes.isEmpty {
            let exts = options.fileTypes.flatMap(\.extensions).sorted()
            let typeClause = exts.map { "kMDItemFSName == \"*.\(escape($0))\"c" }.joined(separator: " || ")
            result = "(\(result) && (\(typeClause)))"
        }
        return .query(result)
    }

    /// The positive relaxation of `expr`; nil means "matches everything".
    private static func relax(_ expr: QueryExpr, _ clause: (String, Bool) -> String) -> String? {
        switch expr {
        case let .term(text, phrase): return clause(text, phrase)
        case .not: return nil
        case let .and(a, b):
            switch (relax(a, clause), relax(b, clause)) {
            case (nil, nil): return nil
            case let (x?, nil), let (nil, x?): return x
            case let (x?, y?): return "(\(x) && \(y))"
            }
        case let .or(a, b):
            guard let x = relax(a, clause), let y = relax(b, clause) else { return nil }
            return "(\(x) || \(y))"
        }
    }

    private static func isWildcard(_ text: String, _ phrase: Bool) -> Bool {
        !phrase && text.contains { $0 == "*" || $0 == "?" }
    }

    /// Names: plain terms match anywhere in the name, wildcard terms the whole name (as in `Matcher`).
    private static func nameClause(_ text: String, _ phrase: Bool, _ modifier: String) -> String {
        let value = isWildcard(text, phrase) ? escape(text, keepWildcards: true) : "*\(escape(text))*"
        return "kMDItemFSName == \"\(value)\"\(modifier)"
    }

    /// Contents: Spotlight matches words, so plain terms become word prefixes.
    private static func contentClause(_ text: String, _ phrase: Bool, _ modifier: String) -> String {
        let value: String
        if isWildcard(text, phrase) { value = escape(text, keepWildcards: true) }
        else if phrase { value = escape(text) }
        else { value = "\(escape(text))*" }
        return "kMDItemTextContent == \"\(value)\"\(modifier)"
    }

    static func escape(_ text: String, keepWildcards: Bool = false) -> String {
        var out = ""
        for c in text {
            if c == "\\" || c == "\"" || (!keepWildcards && (c == "*" || c == "?")) { out.append("\\") }
            out.append(c)
        }
        return out
    }
}

extension QueryExpr {
    var containsNot: Bool {
        switch self {
        case .term: false
        case .not: true
        case let .and(a, b), let .or(a, b): a.containsNot || b.containsNot
        }
    }
}

/// Runs a Spotlight query over some folders and streams the matching paths.
public enum SpotlightSearcher {
    public static func paths(query: String, scopes: [URL]) -> AsyncStream<[String]> {
        AsyncStream { continuation in
            let box = QueryBox()
            DispatchQueue.main.async {
                box.start(query: query, scopes: scopes,
                          onBatch: { continuation.yield($0) },
                          onFinish: { continuation.finish() })
            }
            continuation.onTermination = { _ in DispatchQueue.main.async { box.stop() } }
        }
    }

    /// Owns an NSMetadataQuery; used only on the main thread, where the query delivers its notifications.
    private final class QueryBox: @unchecked Sendable {
        private var query: NSMetadataQuery?
        private var observers: [NSObjectProtocol] = []
        private var delivered = 0
        private var onFinish: (() -> Void)?

        func start(query string: String, scopes: [URL],
                   onBatch: @escaping ([String]) -> Void, onFinish: @escaping () -> Void) {
            self.onFinish = onFinish
            guard let predicate = NSPredicate(fromMetadataQueryString: string) else { return stop() }
            let query = NSMetadataQuery()
            query.predicate = predicate
            query.searchScopes = scopes
            query.notificationBatchingInterval = 0.1
            self.query = query

            let center = NotificationCenter.default
            for name in [Notification.Name.NSMetadataQueryGatheringProgress, .NSMetadataQueryDidFinishGathering] {
                observers.append(center.addObserver(forName: name, object: query, queue: .main) { [weak self] note in
                    guard let self, let query = self.query else { return }
                    query.disableUpdates()
                    let count = query.resultCount
                    var batch: [String] = []
                    for i in self.delivered..<count {
                        if let item = query.result(at: i) as? NSMetadataItem,
                           let path = item.value(forAttribute: NSMetadataItemPathKey) as? String {
                            batch.append(path)
                        }
                    }
                    self.delivered = count
                    query.enableUpdates()
                    if !batch.isEmpty { onBatch(batch) }
                    if note.name == .NSMetadataQueryDidFinishGathering { self.stop() }
                })
            }
            if !query.start() { stop() }
        }

        func stop() {
            query?.stop()
            query = nil
            observers.forEach(NotificationCenter.default.removeObserver)
            observers = []
            onFinish?()
            onFinish = nil
        }
    }
}
