import AppKit
import TrawlCore
import SwiftUI

struct ResultsTable: View {
    @EnvironmentObject private var model: SearchModel
    @Binding var selection: Set<URL>
    @Binding var trashCandidates: Set<URL>

    private static let dateFormat = Date.FormatStyle(date: .abbreviated, time: .shortened)

    var body: some View {
        Table(model.results, selection: $selection, sortOrder: $model.sortOrder) {
            TableColumn("Name", value: \.name) { result in
                HStack(spacing: 6) {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: result.url.path))
                        .resizable().frame(width: 16, height: 16)
                    Text(result.name).lineLimit(1).truncationMode(.middle)
                }
                .onDrag { NSItemProvider(object: result.url as NSURL) }
                .help(result.matchedContent ? "Matched in contents" : "Matched in name")
            }
            .width(min: 160, ideal: 260)
            TableColumn("Folder", value: \.folder) { result in
                Text(result.folder).lineLimit(1).truncationMode(.head).foregroundStyle(.secondary)
            }
            .width(min: 120, ideal: 280)
            TableColumn("Size", value: \.sortSize) { result in
                Text(result.isDirectory ? "--" : ByteCountFormatter.string(fromByteCount: result.size ?? 0, countStyle: .file))
                    .monospacedDigit()
            }
            .width(min: 60, ideal: 80)
            TableColumn("Modified", value: \.sortModified) { result in
                Text(result.modified.map { $0.formatted(Self.dateFormat) } ?? "")
            }
            .width(min: 110, ideal: 150)
            TableColumn("Kind", value: \.kind) { result in
                Text(result.kind).lineLimit(1)
            }
            .width(min: 70, ideal: 120)
            TableColumn("Found By") { result in
                FoundBy(sources: model.sourcesByURL[result.url] ?? result.sources)
            }
            .width(min: 56, ideal: 64)
        }
        .contextMenu(forSelectionType: URL.self) { urls in
            if !urls.isEmpty {
                Button("Open") { open(urls) }
                Button("Reveal in Finder") { reveal(urls) }
                Button("Copy Path") { copyPaths(urls) }
                Divider()
                Button("Move to Trash…") { trashCandidates = urls }
            }
        } primaryAction: { urls in
            open(urls)
        }
        .overlay {
            if model.allResults.isEmpty, !model.isSearching, model.elapsed != nil {
                ContentUnavailableView.search
            }
        }
    }

    private func open(_ urls: Set<URL>) {
        urls.forEach { NSWorkspace.shared.open($0) }
    }

    private func reveal(_ urls: Set<URL>) {
        NSWorkspace.shared.activateFileViewerSelecting(Array(urls))
    }

    private func copyPaths(_ urls: Set<URL>) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(urls.map(\.path).sorted().joined(separator: "\n"), forType: .string)
    }
}

struct StatusBar: View {
    @EnvironmentObject private var model: SearchModel
    @State private var showingUnreadable = false

    var body: some View {
        HStack(spacing: 8) {
            if model.isSearching {
                ProgressView().controlSize(.small)
            }
            if let error = model.errorMessage {
                Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.red)
            } else {
                Text(summary).monospacedDigit()
            }
            if !model.unreadableFolders.isEmpty {
                let count = model.unreadableFolders.count
                Button { showingUnreadable = true } label: {
                    Label("\(count.formatted()) \(count == 1 ? "folder" : "folders") couldn't be read",
                          systemImage: "lock.fill")
                        .foregroundStyle(.orange)
                }
                .buttonStyle(.borderless)
                .help("Show folders macOS did not let Trawl read")
                .popover(isPresented: $showingUnreadable, arrowEdge: .top) {
                    UnreadableFolders(urls: model.unreadableFolders)
                }
            }
            Spacer()
            if let notice = model.notice, !model.isSearching {
                Label(notice, systemImage: "info.circle").foregroundStyle(.secondary).lineLimit(1)
            }
            if model.isSearching {
                Text(model.currentFolder).lineLimit(1).truncationMode(.head).foregroundStyle(.secondary)
            }
        }
        .font(.callout)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
    }

    private var summary: String {
        let total = model.allResults.count
        let shown = model.results.count
        var items = "\(total.formatted()) \(total == 1 ? "item" : "items")"
        if shown != total { items = "\(shown.formatted()) of \(items)" }
        guard model.isSearching || model.elapsed != nil else { return "Press Return to search" }
        var parts = [items]
        for (engine, title) in [(SearchSources.spotlight, "Spotlight"), (.walk, "Scan")]
        where model.activeEngines.contains(engine) {
            let running = model.isSearching && !model.finishedEngines.contains(engine) ? "…" : ""
            parts.append("\(title) \((model.engineCounts[engine] ?? 0).formatted())\(running)")
        }
        if model.activeEngines.contains(.walk) { parts.append("\(model.scanned.formatted()) scanned") }
        if let elapsed = model.elapsed {
            parts.append("\(elapsed.formatted(.number.precision(.fractionLength(1)))) s")
        }
        return parts.joined(separator: " · ")
    }
}

/// Icons showing which engines found a result.
private struct FoundBy: View {
    let sources: SearchSources

    var body: some View {
        HStack(spacing: 4) {
            if sources.contains(.spotlight) {
                Image(systemName: "magnifyingglass.circle.fill").foregroundStyle(.blue)
            }
            if sources.contains(.walk) {
                Image(systemName: "folder.fill").foregroundStyle(.secondary)
            }
        }
        .help(help)
    }

    private var help: String {
        switch sources {
        case [.spotlight, .walk]: "Found by Spotlight and the folder scan"
        case .spotlight: "Found by Spotlight only"
        default: "Found by the folder scan only"
        }
    }
}

/// Lists folders the search could not read and points to the privacy settings that unlock them.
private struct UnreadableFolders: View {
    let urls: [URL]
    private static let privacySettings =
        URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Folders Trawl couldn't read").font(.headline)
            Text("""
                macOS blocked access to these folders, so files in them are missing from both the \
                folder scan and Spotlight results. To include them, allow Trawl under Full Disk Access \
                (or Files and Folders) in Privacy & Security, then search again.
                """)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            List(urls.prefix(500), id: \.self) { url in
                Text(url.path).font(.system(.callout, design: .monospaced)).lineLimit(1).truncationMode(.middle)
                    .textSelection(.enabled)
            }
            .frame(height: min(CGFloat(urls.count) * 24 + 12, 240))
            HStack {
                if urls.count > 500 { Text("Showing 500 of \(urls.count.formatted())").foregroundStyle(.secondary) }
                Spacer()
                Button("Open Privacy & Security…") { NSWorkspace.shared.open(Self.privacySettings) }
            }
        }
        .padding(14)
        .frame(width: 460)
    }
}
