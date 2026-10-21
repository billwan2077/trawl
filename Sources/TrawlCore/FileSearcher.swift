import Foundation

public enum SearchTarget: String, CaseIterable, Sendable, Identifiable {
    case names = "Names"
    case contents = "Contents"
    case both = "Names & Contents"
    public var id: String { rawValue }
}

public struct SearchOptions: Sendable {
    public var roots: [URL]
    public var target: SearchTarget = .names
    public var match = MatchOptions()
    public var includeHidden = false
    public var searchPackages = false
    public var includeFolders = true
    public var maxContentSize = 50 * 1024 * 1024
    /// Only files of these types are searched; empty means all files. Folders are never
    /// returned while a type filter is set.
    public var fileTypes: Set<FileCategory> = []
    /// Which engines `HybridSearcher` runs.
    public var engines: SearchSources = [.spotlight, .walk]

    public init(roots: [URL]) { self.roots = roots }
}

public struct SearchResult: Identifiable, Hashable, Sendable {
    public var id: URL { url }
    public let url: URL
    public let isDirectory: Bool
    public let size: Int64?
    public let modified: Date?
    public let matchedContent: Bool
    public let category: FileCategory?
    /// The engine that reported this result first; see `SearchEvent.sourcesAdded` for later ones.
    public let sources: SearchSources

    public var name: String { url.lastPathComponent }
    public var folder: String { url.deletingLastPathComponent().path }
}

/// The engines that can find a result.
public struct SearchSources: OptionSet, Hashable, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }
    public static let spotlight = SearchSources(rawValue: 1)
    public static let walk = SearchSources(rawValue: 2)
}

public enum SearchEvent: Sendable {
    /// Results not reported before.
    case results([SearchResult])
    /// Results already reported that another engine also found.
    case sourcesAdded([URL], SearchSources)
    case progress(scanned: Int, folder: String)
    /// One engine is done; `count` is how many results it found.
    case engineFinished(SearchSources, count: Int)
    /// Something the user should know, e.g. why Spotlight was not used.
    case notice(String)
    case finished(scanned: Int)
}

public enum FileSearcher {
    private static let keys: [URLResourceKey] = [
        .isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey, .contentModificationDateKey,
    ]
    /// Volumes and pseudo-filesystems that duplicate or never hold user files.
    private static let skippedPaths: Set<String> = ["/System/Volumes", "/dev", "/private/var/vm", "/Volumes"]

    /// Walks `options.roots` and streams matches. Cancelling the consuming task stops the walk.
    public static func search(_ options: SearchOptions, matcher: Matcher) -> AsyncStream<SearchEvent> {
        AsyncStream { continuation in
            let task = Task.detached(priority: .userInitiated) {
                let scanned = await walk(options, matcher: matcher, continuation: continuation)
                continuation.yield(.finished(scanned: scanned))
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private static func walk(_ options: SearchOptions, matcher: Matcher,
                             continuation: AsyncStream<SearchEvent>.Continuation) async -> Int {
        let fm = FileManager.default
        var enumOptions: FileManager.DirectoryEnumerationOptions = []
        if !options.includeHidden { enumOptions.insert(.skipsHiddenFiles) }
        if !options.searchPackages { enumOptions.insert(.skipsPackageDescendants) }
        let wantsNames = options.target != .contents
        let wantsContents = options.target != .names
        let maxConcurrent = max(2, ProcessInfo.processInfo.activeProcessorCount)

        var scanned = 0
        var pending: [SearchResult] = []
        var lastFlush = Date()

        func flush(folder: String, force: Bool = false) {
            guard force || Date().timeIntervalSince(lastFlush) > 0.15 else { return }
            if !pending.isEmpty { continuation.yield(.results(pending)); pending.removeAll() }
            continuation.yield(.progress(scanned: scanned, folder: folder))
            lastFlush = Date()
        }

        await withTaskGroup(of: SearchResult?.self) { group in
            var running = 0
            for root in normalizedRoots(options.roots) {
                guard let enumerator = fm.enumerator(at: root, includingPropertiesForKeys: keys,
                                                     options: enumOptions, errorHandler: { _, _ in true })
                else { continue }
                while let url = enumerator.nextObject() as? URL {
                    if Task.isCancelled { group.cancelAll(); return }
                    if skippedPaths.contains(url.path) { enumerator.skipDescendants(); continue }
                    scanned += 1
                    let values = try? url.resourceValues(forKeys: Set(keys))
                    let isDirectory = values?.isDirectory ?? false
                    if !options.fileTypes.isEmpty {
                        guard !isDirectory, let category = FileCategory(url: url),
                              options.fileTypes.contains(category) else { continue }
                    }

                    if wantsNames, !isDirectory || options.includeFolders, matcher.matchesName(url.lastPathComponent) {
                        pending.append(makeResult(url, values, matchedContent: false))
                    } else if wantsContents, values?.isRegularFile == true, values?.isSymbolicLink != true,
                              (values?.fileSize ?? 0) <= options.maxContentSize {
                        if running >= maxConcurrent, let done = await group.next() {
                            running -= 1
                            if let done { pending.append(done) }
                        }
                        running += 1
                        group.addTask {
                            guard !Task.isCancelled, let text = readText(url, maxSize: options.maxContentSize),
                                  matcher.matchesContent(text) else { return nil }
                            return makeResult(url, values, matchedContent: true)
                        }
                    }
                    flush(folder: isDirectory ? url.path : url.deletingLastPathComponent().path)
                }
            }
            for await done in group {
                if let done { pending.append(done) }
            }
        }
        flush(folder: "", force: true)
        return scanned
    }

    private static func makeResult(_ url: URL, _ values: URLResourceValues?, matchedContent: Bool) -> SearchResult {
        SearchResult(url: url, isDirectory: values?.isDirectory ?? false,
                     size: values?.fileSize.map(Int64.init), modified: values?.contentModificationDate,
                     matchedContent: matchedContent, category: values?.isDirectory == true ? nil : FileCategory(url: url),
                     sources: .walk)
    }

    /// Drops duplicate roots and roots nested inside another root.
    static func normalizedRoots(_ roots: [URL]) -> [URL] {
        let paths = Set(roots.map { $0.standardizedFileURL.path })
        return paths.sorted().filter { path in
            !paths.contains { other in other != path && (other == "/" || path.hasPrefix(other + "/")) }
        }.map { URL(fileURLWithPath: $0, isDirectory: true) }
    }

    /// Returns the file's text, or nil if it is too large, unreadable, or looks binary.
    static func readText(_ url: URL, maxSize: Int) -> String? {
        guard let data = try? Data(contentsOf: url, options: .alwaysMapped), data.count <= maxSize else { return nil }
        if data.count >= 2, (data[0] == 0xFF && data[1] == 0xFE) || (data[0] == 0xFE && data[1] == 0xFF) {
            return String(data: data, encoding: .utf16)
        }
        if data.prefix(8192).contains(0) { return nil }
        return String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1)
    }
}
