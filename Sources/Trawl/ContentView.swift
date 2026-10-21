import AppKit
import TrawlCore
import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var model: SearchModel
    @State private var selection = Set<URL>()
    @State private var trashCandidates: Set<URL> = []
    @FocusState private var queryFocused: Bool

    var body: some View {
        NavigationSplitView {
            FolderList()
                .navigationSplitViewColumnWidth(min: 180, ideal: 220)
        } detail: {
            VStack(spacing: 0) {
                if !model.allResults.isEmpty {
                    ResultFilterBar()
                    Divider()
                }
                ResultsTable(selection: $selection, trashCandidates: $trashCandidates)
                Divider()
                StatusBar()
            }
        }
        .toolbar { toolbar }
        .onAppear { queryFocused = true }
        .confirmationDialog(trashTitle, isPresented: Binding(
            get: { !trashCandidates.isEmpty }, set: { if !$0 { trashCandidates = [] } }
        )) {
            Button("Move to Trash", role: .destructive) { moveToTrash(trashCandidates) }
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .principal) {
            TextField(model.useRegex ? "Regular expression" : "Search (AND, OR, NOT, \"phrase\", *, ?)",
                      text: $model.query)
                .textFieldStyle(.roundedBorder)
                .frame(minWidth: 260, idealWidth: 360)
                .focused($queryFocused)
                .onSubmit { model.start() }
        }
        ToolbarItem {
            Picker("Search In", selection: $model.target) {
                ForEach(SearchTarget.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
        }
        ToolbarItem {
            SearchTypesMenu()
        }
        ToolbarItem {
            if model.isSearching {
                Button { model.stop() } label: { Label("Stop", systemImage: "stop.circle") }
                    .keyboardShortcut(".", modifiers: .command)
            } else {
                Button { model.start() } label: { Label("Search", systemImage: "magnifyingglass") }
            }
        }
        ToolbarItem {
            Menu {
                Picker("Search Engine", selection: $model.engineMode) {
                    ForEach(EngineMode.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.inline)
                Divider()
                Toggle("Case Sensitive", isOn: $model.caseSensitive)
                Toggle("Regular Expression", isOn: $model.useRegex)
                Divider()
                Toggle("Include Hidden Files", isOn: $model.includeHidden)
                Toggle("Search Inside Packages", isOn: $model.searchPackages)
                Toggle("Include Folders in Results", isOn: $model.includeFolders)
            } label: {
                Label("Options", systemImage: "slider.horizontal.3")
            }
        }
    }

    private var trashTitle: String {
        trashCandidates.count == 1
            ? "Move “\(trashCandidates.first!.lastPathComponent)” to the Trash?"
            : "Move \(trashCandidates.count) items to the Trash?"
    }

    private func moveToTrash(_ urls: Set<URL>) {
        var trashed = Set<URL>()
        for url in urls where (try? FileManager.default.trashItem(at: url, resultingItemURL: nil)) != nil {
            trashed.insert(url)
        }
        model.removeFromResults(trashed)
        selection.subtract(trashed)
        trashCandidates = []
    }
}

private struct FolderList: View {
    @EnvironmentObject private var model: SearchModel

    private enum Item: Hashable {
        case all
        case folder(URL)
    }

    /// Selecting a folder filters results to it; "All Folders" clears the filter.
    private var selection: Binding<Item?> {
        Binding(
            get: { model.folderFilter.map(Item.folder) ?? .all },
            set: { item in
                if case .folder(let url) = item { model.folderFilter = url } else { model.folderFilter = nil }
            })
    }

    var body: some View {
        List(selection: selection) {
            Label("All Folders", systemImage: "square.stack.3d.up")
                .help("Show results from every folder and search them all")
                .tag(Item.all)
            Section("Search In") {
                ForEach(model.roots, id: \.self) { url in
                    Label {
                        Text(FileManager.default.displayName(atPath: url.path))
                    } icon: {
                        Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                            .resizable().frame(width: 16, height: 16)
                    }
                    .help("\(url.path)\nShow only results in this folder; the next search covers only it.")
                    .tag(Item.folder(url))
                }
                .onDelete { model.roots.remove(atOffsets: $0) }
            }
        }
        .onDeleteCommand(perform: removeSelected)
        .dropDestination(for: URL.self) { urls, _ in
            let folders = urls.filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
            model.addRoots(folders)
            return !folders.isEmpty
        }
        .safeAreaInset(edge: .bottom) {
            HStack(spacing: 4) {
                Button { model.chooseFolders() } label: { Image(systemName: "plus") }
                    .help("Add folders to search")
                Button(action: removeSelected) { Image(systemName: "minus") }
                    .disabled(model.folderFilter == nil)
                    .help("Remove the selected folder")
                Spacer()
            }
            .buttonStyle(.borderless)
            .padding(8)
        }
    }

    private func removeSelected() {
        guard let folder = model.folderFilter else { return }
        model.roots.removeAll { $0 == folder }
    }
}
