import Foundation

/// Runs Spotlight and the folder walk side by side and merges their results by path.
///
/// Spotlight answers first from its index; the walk then fills in what the index misses
/// (hidden or unindexed folders, files changed since indexing). Each Spotlight hit is
/// checked against the search options before it is reported, and names are re-checked
/// with `Matcher`, so Spotlight never widens what a name search returns.
public enum HybridSearcher {
    public static func search(query: String, options: SearchOptions) throws -> AsyncStream<SearchEvent> {
        let matcher = try Matcher(query: query, options: options.match)

        var notice: String?
        var spotlight: AsyncStream<[String]>?
        if options.engines.contains(.spotlight) {
            switch SpotlightQueryBuilder.plan(for: query, options: options) {
            case .query(let string):
                spotlight = SpotlightSearcher.paths(query: string, scopes: FileSearcher.normalizedRoots(options.roots))
            case .skip(let reason):
                notice = reason
            }
        }
        let contentHitsAllowed = !((try? QueryParser.parse(query))?.containsNot ?? true)
        let walk = options.engines.contains(.walk) ? FileSearcher.search(options, matcher: matcher) : nil
        return merge(walk: walk, spotlight: spotlight, notice: notice) { path in
            verify(path, options: options, matcher: matcher, contentHitsAllowed: contentHitsAllowed)
        }
    }

    private enum Tagged: Sendable {
        case walk(SearchEvent)
        case spotlight([SearchResult])
        case spotlightDone
    }

    static func merge(walk: AsyncStream<SearchEvent>?, spotlight: AsyncStream<[String]>?, notice: String?,
                      verify: @escaping @Sendable (String) -> SearchResult?) -> AsyncStream<SearchEvent> {
        AsyncStream { continuation in
            let task = Task.detached(priority: .userInitiated) {
                if let notice { continuation.yield(.notice(notice)) }
                let (inner, innerContinuation) = AsyncStream<Tagged>.makeStream()
                await withTaskGroup(of: Void.self) { group in
                    if let walk {
                        group.addTask { for await event in walk { innerContinuation.yield(.walk(event)) } }
                    }
                    if let spotlight {
                        group.addTask {
                            for await paths in spotlight {
                                innerContinuation.yield(.spotlight(paths.compactMap(verify)))
                            }
                            innerContinuation.yield(.spotlightDone)
                        }
                    }
                    group.addTask {
                        var seen: [String: URL] = [:]
                        var counts: [SearchSources: Int] = [:]
                        var walkDone = walk == nil, spotlightDone = spotlight == nil
                        var scanned = 0

                        func report(_ batch: [SearchResult], from source: SearchSources) {
                            var fresh: [SearchResult] = []
                            var repeats: [URL] = []
                            for result in batch {
                                let key = result.url.standardizedFileURL.path
                                if let url = seen[key] { repeats.append(url) } else {
                                    seen[key] = result.url
                                    fresh.append(result)
                                }
                            }
                            counts[source, default: 0] += batch.count
                            if !fresh.isEmpty { continuation.yield(.results(fresh)) }
                            if !repeats.isEmpty { continuation.yield(.sourcesAdded(repeats, source)) }
                        }

                        // With no engine running, nothing will arrive: end the loop at once.
                        if walkDone, spotlightDone { innerContinuation.finish() }
                        for await tagged in inner {
                            switch tagged {
                            case .spotlight(let batch): report(batch, from: .spotlight)
                            case .spotlightDone:
                                spotlightDone = true
                                continuation.yield(.engineFinished(.spotlight, count: counts[.spotlight] ?? 0))
                            case .walk(.results(let batch)): report(batch, from: .walk)
                            case .walk(.finished(let count)):
                                scanned = count
                                walkDone = true
                                continuation.yield(.engineFinished(.walk, count: counts[.walk] ?? 0))
                            case .walk(let other): continuation.yield(other)
                            }
                            if walkDone, spotlightDone { break }
                        }
                        innerContinuation.finish()
                        continuation.yield(.finished(scanned: scanned))
                    }
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Turns a Spotlight path into a result if it still exists and passes the search options.
    static func verify(_ path: String, options: SearchOptions, matcher: Matcher,
                       contentHitsAllowed: Bool) -> SearchResult? {
        let url = URL(fileURLWithPath: path).standardizedFileURL
        guard let root = FileSearcher.normalizedRoots(options.roots).map(\.path).first(where: {
            $0 == "/" || url.path.hasPrefix($0 + "/")
        }) else { return nil }
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey]
        guard let values = try? url.resourceValues(forKeys: keys) else { return nil }
        let isDirectory = values.isDirectory ?? false

        if isDirectory, !options.includeFolders || !options.fileTypes.isEmpty { return nil }
        if !options.fileTypes.isEmpty {
            guard let category = FileCategory(url: url), options.fileTypes.contains(category) else { return nil }
        }
        // Hidden items and package contents between the root and the file, as the walk skips them.
        let relative = url.path.dropFirst(root == "/" ? 1 : root.count + 1).split(separator: "/")
        if !options.includeHidden, relative.contains(where: { $0.hasPrefix(".") }) { return nil }
        if !options.searchPackages {
            var ancestor = url.deletingLastPathComponent()
            while ancestor.path.count > root.count {
                if (try? ancestor.resourceValues(forKeys: [.isPackageKey]))?.isPackage == true { return nil }
                ancestor.deleteLastPathComponent()
            }
        }

        let nameMatch = options.target != .contents && matcher.matchesName(url.lastPathComponent)
        if !nameMatch, options.target == .names || !contentHitsAllowed { return nil }
        return SearchResult(url: url, isDirectory: isDirectory, size: values.fileSize.map(Int64.init),
                            modified: values.contentModificationDate, matchedContent: !nameMatch,
                            category: isDirectory ? nil : FileCategory(url: url), sources: .spotlight)
    }
}
