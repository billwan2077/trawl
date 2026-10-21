import AppKit
import TrawlCore
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class SearchModel: ObservableObject {
    private static let defaults = UserDefaults.standard

    @Published var target = SearchTarget(rawValue: defaults.string(forKey: "target") ?? "") ?? .names {
        didSet { Self.defaults.set(target.rawValue, forKey: "target") }
    }
    @Published var caseSensitive = defaults.bool(forKey: "caseSensitive") {
        didSet { Self.defaults.set(caseSensitive, forKey: "caseSensitive") }
    }
    @Published var useRegex = defaults.bool(forKey: "useRegex") {
        didSet { Self.defaults.set(useRegex, forKey: "useRegex") }
    }
    @Published var includeHidden = defaults.bool(forKey: "includeHidden") {
        didSet { Self.defaults.set(includeHidden, forKey: "includeHidden") }
    }
    @Published var searchPackages = defaults.bool(forKey: "searchPackages") {
        didSet { Self.defaults.set(searchPackages, forKey: "searchPackages") }
    }
    @Published var includeFolders = defaults.object(forKey: "includeFolders") as? Bool ?? true {
        didSet { Self.defaults.set(includeFolders, forKey: "includeFolders") }
    }

    @Published var engineMode = EngineMode(rawValue: defaults.string(forKey: "engineMode") ?? "") ?? .both {
        didSet { Self.defaults.set(engineMode.rawValue, forKey: "engineMode") }
    }

    @Published var query = ""
    @Published var roots: [URL] {
        didSet {
            saveRoots()
            if let folderFilter, !roots.contains(folderFilter) { self.folderFilter = nil }
        }
    }
    /// Folder picked in the sidebar: only results inside it are shown, and the next search
    /// covers only it. Nil means all folders.
    @Published var folderFilter: URL? {
        didSet {
            recount()
            refilter()
        }
    }
    /// File types the search looks at; empty means all files.
    @Published var searchTypes: Set<FileCategory> = SearchModel.loadSearchTypes() {
        didSet { Self.defaults.set(searchTypes.map(\.rawValue).sorted(), forKey: "searchTypes") }
    }
    /// Every result of the last search.
    @Published private(set) var allResults: [SearchResult] = []
    /// The results shown in the table: `allResults` narrowed by `resultFilter`, sorted.
    @Published private(set) var results: [SearchResult] = []
    @Published private(set) var groupCounts: [ResultGroup: Int] = [:]
    /// Result types picked in the filter bar; empty shows everything.
    @Published var resultFilter: Set<ResultGroup> = [] { didSet { refilter() } }
    @Published var sortOrder: [KeyPathComparator<SearchResult>] = [] { didSet { results.sort(using: sortOrder) } }
    @Published private(set) var isSearching = false
    @Published private(set) var scanned = 0
    @Published private(set) var currentFolder = ""
    @Published private(set) var elapsed: TimeInterval?
    @Published private(set) var errorMessage: String?
    /// Which engines found each result.
    @Published private(set) var sourcesByURL: [URL: SearchSources] = [:]
    /// Results found per engine, counting duplicates.
    @Published private(set) var engineCounts: [SearchSources: Int] = [:]
    @Published private(set) var finishedEngines: SearchSources = []
    /// Engines used by the current or last search.
    @Published private(set) var activeEngines: SearchSources = []
    @Published private(set) var notice: String?
    /// Folders the last search was not allowed to read.
    @Published private(set) var unreadableFolders: [URL] = []

    private var task: Task<Void, Never>?

    init() {
        let saved = UserDefaults.standard.stringArray(forKey: "roots") ?? []
        let urls = saved.map { URL(fileURLWithPath: $0, isDirectory: true) }
        roots = urls.isEmpty ? [FileManager.default.homeDirectoryForCurrentUser] : urls
    }

    func start() {
        stop()
        errorMessage = nil
        guard !roots.isEmpty else { errorMessage = "Add a folder to search."; return }

        var options = SearchOptions(roots: folderFilter.map { [$0] } ?? roots)
        options.target = target
        options.match = MatchOptions(caseSensitive: caseSensitive, useRegex: useRegex)
        options.includeHidden = includeHidden
        options.searchPackages = searchPackages
        options.includeFolders = includeFolders
        options.fileTypes = searchTypes
        options.engines = engineMode.sources

        let stream: AsyncStream<SearchEvent>
        do {
            stream = try HybridSearcher.search(query: query, options: options)
        } catch {
            errorMessage = error.localizedDescription
            return
        }

        allResults = []
        sourcesByURL = [:]
        engineCounts = [:]
        finishedEngines = []
        activeEngines = options.engines
        notice = nil
        unreadableFolders = []
        results = []
        groupCounts = [:]
        resultFilter = []
        scanned = 0
        elapsed = nil
        isSearching = true
        let started = Date()
        task = Task {
            for await event in stream {
                switch event {
                case .results(let batch):
                    for result in batch {
                        sourcesByURL[result.url] = result.sources
                        engineCounts[result.sources, default: 0] += 1
                    }
                    append(batch)
                case let .sourcesAdded(urls, source):
                    for url in urls { sourcesByURL[url, default: []].formUnion(source) }
                    engineCounts[source, default: 0] += urls.count
                case .engineFinished(let engine, _):
                    finishedEngines.formUnion(engine)
                case .notice(let text):
                    notice = text
                case .unreadable(let urls):
                    // The folder scan and the Spotlight check can both report the same folder.
                    let known = Set(unreadableFolders.map(\.standardizedFileURL.path))
                    unreadableFolders += urls.filter { !known.contains($0.standardizedFileURL.path) }
                case let .progress(count, folder):
                    scanned = count
                    currentFolder = folder
                case .finished(let count):
                    scanned = count
                }
            }
            // A newer search replaced this one; leave its state alone.
            if Task.isCancelled { return }
            elapsed = Date().timeIntervalSince(started)
            currentFolder = ""
            isSearching = false
        }
    }

    func stop() {
        task?.cancel()
        task = nil
    }

    func chooseFolders() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = true
        panel.prompt = "Add"
        guard panel.runModal() == .OK else { return }
        addRoots(panel.urls)
    }

    func addRoots(_ urls: [URL]) {
        for url in urls where !roots.contains(url) { roots.append(url) }
    }

    func removeFromResults(_ urls: Set<URL>) {
        allResults.removeAll { urls.contains($0.url) }
        results.removeAll { urls.contains($0.url) }
        urls.forEach { sourcesByURL[$0] = nil }
        recount()
    }

    func toggleFilter(_ group: ResultGroup) {
        if resultFilter.contains(group) { resultFilter.remove(group) } else { resultFilter.insert(group) }
    }

    private func append(_ batch: [SearchResult]) {
        allResults.append(contentsOf: batch)
        let scoped = folderFilter == nil ? batch : batch.filter(isInFolder)
        for result in scoped { groupCounts[result.group, default: 0] += 1 }
        let shown = resultFilter.isEmpty ? scoped : scoped.filter { resultFilter.contains($0.group) }
        guard !shown.isEmpty else { return }
        results.append(contentsOf: shown)
        if !sortOrder.isEmpty { results.sort(using: sortOrder) }
    }

    private func refilter() {
        let shown = allResults.filter { isInFolder($0) && (resultFilter.isEmpty || resultFilter.contains($0.group)) }
        results = sortOrder.isEmpty ? shown : shown.sorted(using: sortOrder)
    }

    /// Type counts for the filter bar, limited to the selected folder.
    private func recount() {
        let scoped = folderFilter == nil ? allResults : allResults.filter(isInFolder)
        groupCounts = Dictionary(grouping: scoped, by: \.group).mapValues(\.count)
    }

    private func isInFolder(_ result: SearchResult) -> Bool {
        guard let folder = folderFilter?.standardizedFileURL.path else { return true }
        return folder == "/" || result.url.standardizedFileURL.path.hasPrefix(folder + "/")
    }

    private static func loadSearchTypes() -> Set<FileCategory> {
        Set((defaults.stringArray(forKey: "searchTypes") ?? []).compactMap(FileCategory.init(rawValue:)))
    }

    private func saveRoots() {
        UserDefaults.standard.set(roots.map(\.path), forKey: "roots")
    }
}

enum EngineMode: String, CaseIterable, Identifiable {
    case both = "Spotlight + Folder Scan"
    case walk = "Folder Scan Only"
    case spotlight = "Spotlight Only"

    var id: String { rawValue }

    var sources: SearchSources {
        switch self {
        case .both: [.spotlight, .walk]
        case .walk: .walk
        case .spotlight: .spotlight
        }
    }
}

/// How the filter bar groups results.
enum ResultGroup: Hashable, Identifiable {
    case category(FileCategory)
    case folder
    case other

    static let allCases: [ResultGroup] = FileCategory.allCases.map(ResultGroup.category) + [.folder, .other]

    var id: String {
        switch self {
        case .category(let c): c.rawValue
        case .folder: "folder"
        case .other: "other"
        }
    }

    var title: String {
        switch self {
        case .category(let c): c.title
        case .folder: "Folders"
        case .other: "Other"
        }
    }
}

extension SearchResult {
    var group: ResultGroup {
        if isDirectory { return .folder }
        return category.map(ResultGroup.category) ?? .other
    }
    var sortSize: Int64 { isDirectory ? -1 : size ?? -1 }
    var sortModified: Date { modified ?? .distantPast }
    var kind: String {
        if isDirectory { return "Folder" }
        return UTType(filenameExtension: url.pathExtension)?.localizedDescription ?? "Document"
    }
}
