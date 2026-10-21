import AppKit
import TrawlCore
import SwiftUI

/// SharePoint-style type icon: brand-colored letter tiles for Office and PDF files,
/// colored symbols for everything else.
struct TypeGlyph: View {
    let group: ResultGroup
    var size: CGFloat = 20

    var body: some View {
        switch group {
        case .category(.word): tile("W", Color(red: 0.09, green: 0.35, blue: 0.74))
        case .category(.excel): tile("X", Color(red: 0.06, green: 0.49, blue: 0.25))
        case .category(.powerpoint): tile("P", Color(red: 0.77, green: 0.24, blue: 0.11))
        case .category(.pdf): tile("PDF", Color(red: 0.82, green: 0.20, blue: 0.22))
        case .category(.markdown): tile("MD", Color(red: 0.16, green: 0.18, blue: 0.21))
        case .category(.html): tile("</>", Color(red: 0.89, green: 0.31, blue: 0.15))
        case .category(.text): symbol("doc.text.fill", Color(red: 0.36, green: 0.45, blue: 0.58))
        case .category(.log): symbol("list.bullet.rectangle.portrait.fill", Color(red: 0.45, green: 0.45, blue: 0.48))
        case .category(.image): symbol("photo.fill", Color(red: 0.0, green: 0.55, blue: 0.62))
        case .category(.video): symbol("film.fill", Color(red: 0.42, green: 0.27, blue: 0.70))
        case .category(.audio): symbol("music.note", Color(red: 0.85, green: 0.24, blue: 0.47))
        case .category(.archive): symbol("doc.zipper", Color(red: 0.55, green: 0.40, blue: 0.25))
        case .folder: symbol("folder.fill", Color(red: 0.97, green: 0.73, blue: 0.20))
        case .other: symbol("doc.fill", Color(red: 0.55, green: 0.57, blue: 0.60))
        }
    }

    private func tile(_ letter: String, _ color: Color) -> some View {
        RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
            .fill(color.gradient)
            .overlay(
                Text(letter)
                    .font(.system(size: size * (letter.count > 1 ? 0.36 : 0.62), weight: .bold))
                    .foregroundStyle(.white)
            )
            .frame(width: size, height: size)
    }

    private func symbol(_ name: String, _ color: Color) -> some View {
        Image(systemName: name)
            .resizable()
            .scaledToFit()
            .foregroundStyle(color)
            .frame(width: size * 0.9, height: size * 0.9)
            .frame(width: size, height: size)
    }
}

/// `TypeGlyph` rendered to an image, for places that need an NSImage such as menus.
@MainActor
enum TypeIcon {
    private static var cache: [ResultGroup: NSImage] = [:]

    static func image(for group: ResultGroup) -> NSImage {
        if let cached = cache[group] { return cached }
        let renderer = ImageRenderer(content: TypeGlyph(group: group, size: 16))
        renderer.scale = 2
        let image = renderer.nsImage ?? NSImage()
        cache[group] = image
        return image
    }
}

/// SharePoint-style quick filters above the results: round icon buttons, one per type
/// present. Clicking one shows only that type, clicking more combines them, and the
/// leading filter button shows everything again.
struct ResultFilterBar: View {
    @EnvironmentObject private var model: SearchModel

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                FilterChip(selected: false, help: "Show all types (\(model.allResults.count.formatted()))") {
                    Image(systemName: "line.3.horizontal.decrease")
                        .font(.system(size: 15, weight: .regular))
                        .foregroundStyle(model.resultFilter.isEmpty ? .secondary : .primary)
                } action: {
                    model.resultFilter = []
                }
                ForEach(visibleGroups) { group in
                    let count = model.groupCounts[group] ?? 0
                    FilterChip(selected: model.resultFilter.contains(group),
                               help: "\(group.title) (\(count.formatted()))") {
                        TypeGlyph(group: group, size: 20)
                    } action: {
                        model.toggleFilter(group)
                    }
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
        }
    }

    /// Groups that have results, plus any still selected.
    private var visibleGroups: [ResultGroup] {
        ResultGroup.allCases.filter { (model.groupCounts[$0] ?? 0) > 0 || model.resultFilter.contains($0) }
    }
}

private struct FilterChip<Icon: View>: View {
    let selected: Bool
    let help: String
    @ViewBuilder let icon: () -> Icon
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            icon()
                .frame(width: 38, height: 38)
                .background(
                    Circle().fill(selected ? Color(nsColor: .controlBackgroundColor)
                                           : Color.primary.opacity(hovering ? 0.11 : 0.06))
                )
                .overlay(Circle().strokeBorder(Color.accentColor, lineWidth: 2).opacity(selected ? 1 : 0))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(help)
        .accessibilityLabel(help)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// Toolbar menu choosing which file types a search looks at.
struct SearchTypesMenu: View {
    @EnvironmentObject private var model: SearchModel

    var body: some View {
        Menu {
            Toggle("All Files", isOn: Binding(
                get: { model.searchTypes.isEmpty }, set: { if $0 { model.searchTypes = [] } }))
            Toggle("Common Files", isOn: Binding(
                get: { model.searchTypes == FileCategory.common },
                set: { if $0 { model.searchTypes = FileCategory.common } }))
            Divider()
            ForEach(FileCategory.allCases) { category in
                Toggle(isOn: Binding(
                    get: { model.searchTypes.contains(category) },
                    set: { on in
                        if on { model.searchTypes.insert(category) } else { model.searchTypes.remove(category) }
                    })) {
                    Label {
                        Text(category.title)
                    } icon: {
                        Image(nsImage: TypeIcon.image(for: .category(category)))
                    }
                }
            }
        } label: {
            Label(summary, systemImage: "doc.on.doc")
                .labelStyle(.titleAndIcon)
        }
        .help("File types to search")
    }

    private var summary: String {
        switch model.searchTypes {
        case []: "All Files"
        case FileCategory.common: "Common Files"
        default:
            model.searchTypes.count == 1 ? model.searchTypes.first!.title : "\(model.searchTypes.count) Types"
        }
    }
}
