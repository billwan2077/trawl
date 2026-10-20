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
            Spacer()
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
        let scanned = "\(model.scanned.formatted()) scanned"
        if let elapsed = model.elapsed {
            return "\(items) · \(scanned) · \(elapsed.formatted(.number.precision(.fractionLength(1)))) s"
        }
        return model.isSearching ? "\(items) · \(scanned)" : "Press Return to search"
    }
}
