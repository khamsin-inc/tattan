import SwiftUI

// SnippetEditorView の行ビュー・シート群。本体と分離してファイル肥大を防ぐ
// （SwiftLint file_length。2026-07-02 分割）。

/// 左カラムのグループ行。改名・削除は右クリック（または改名は親のダイアログ、削除はホバー🗑️）。
/// 行内に編集 UI を持たないので軽い。
struct GroupRow: View {
    let tag: Tag
    let requestRename: () -> Void
    let requestDelete: () -> Void
    let acceptDrop: ([String]) -> Bool
    let requestChangeIcon: () -> Void
    @State private var isHovered = false
    @State private var isDropTargeted = false

    var body: some View {
        HStack(spacing: 6) {
            // 並べ替え可能のサイン（実際のドラッグは行全体で発生する）
            Image(systemName: "line.3.horizontal")
                .scaledFont(11)
                .foregroundStyle(.tertiary)
            Image(systemName: tag.iconName ?? "folder")
                .scaledFont(13)
                .foregroundStyle(.secondary)
            Text(tag.name.isEmpty ? String(localized: "Untitled") : tag.name)
                .scaledFont(13)
                .lineLimit(1)
            Spacer(minLength: 4)
            // ホバー時のみ削除を出す（常に置いて opacity だけ切り替え、行の高さを揺らさない）
            Button(action: requestDelete) {
                Image(systemName: "trash").scaledFont(13).foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
            .opacity(isHovered ? 1 : 0)
            .allowsHitTesting(isHovered)
            .help(String(localized: "Delete group"))
        }
        .contentShape(Rectangle())
        // スニペットをこのグループへドロップで移動。受理中はハイライト
        .background(
            isDropTargeted ? AnyShapeStyle(Color.accentColor.opacity(0.25)) : AnyShapeStyle(.clear),
            in: RoundedRectangle(cornerRadius: 6)
        )
        .onHover { isHovered = $0 }
        .dropDestination(for: String.self) { items, _ in
            acceptDrop(items)
        } isTargeted: { isDropTargeted = $0 }
        .contextMenu {
            Button(String(localized: "Rename")) { requestRename() }
            Button(String(localized: "Change Icon…")) { requestChangeIcon() }
            Button(String(localized: "Delete"), role: .destructive) { requestDelete() }
        }
    }
}

/// 中カラムのスニペット行。ホバーで削除ボタン。
struct SnippetRow: View {
    let snippet: Snippet
    let requestDelete: () -> Void
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 6) {
            // 並べ替え可能のサイン（実際のドラッグは行全体で発生する）
            Image(systemName: "line.3.horizontal")
                .scaledFont(11)
                .foregroundStyle(.tertiary)
            // カラーコードを含むスニペットはスウォッチ表示（D-6）
            if let hex = HexColorParser.firstColor(in: snippet.content) {
                Circle()
                    .fill(Color(red: hex.red, green: hex.green, blue: hex.blue, opacity: hex.alpha))
                    .frame(width: 10, height: 10)
                    .overlay(Circle().strokeBorder(.separator, lineWidth: 1))
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(snippet.title.isEmpty ? String(localized: "Untitled") : snippet.title)
                    .scaledFont(13)
                    .lineLimit(1)
                if !(snippet.tags ?? []).isEmpty {
                    Text((snippet.tags ?? []).map(\.name).sorted().joined(separator: ", "))
                        .scaledFont(10)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 4)
            Button(action: requestDelete) {
                Image(systemName: "trash").scaledFont(13).foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
            .opacity(isHovered ? 1 : 0)
            .allowsHitTesting(isHovered)
            .help(String(localized: "Delete this snippet"))
        }
        .contentShape(Rectangle())
        // グループへドラッグして移動（uuid を運ぶ）。並び替え onMove と同居させる試み
        .draggable(snippet.uuid.uuidString)
        .onHover { isHovered = $0 }
    }
}

/// グループのアイコン（SF Symbol）を選ぶシート。右クリック →「Change Icon…」から開く。
struct IconPickerView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(SnippetService.self) private var snippetService
    let tag: Tag

    /// グループ分けでよく使う汎用シンボル（メアド→封筒、住所→家 などをカバー）
    private static let icons = [
        "folder", "envelope", "house", "person", "person.2", "phone",
        "tag", "star", "heart", "flag", "bookmark", "paperclip",
        "link", "lock", "key", "creditcard", "cart", "gift",
        "briefcase", "building.2", "globe", "mappin.and.ellipse", "calendar", "clock",
        "doc.text", "terminal", "curlybraces", "paintpalette", "camera", "photo",
        "music.note", "bubble.left", "paperplane", "pencil", "number", "at"
    ]

    private let columns = [GridItem(.adaptive(minimum: 46), spacing: 8)]

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text(String(localized: "Change Icon"))
                    .font(.headline)
                Spacer()
                Button(String(localized: "Done")) { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            ScrollView {
                LazyVGrid(columns: columns, spacing: 8) {
                    ForEach(Self.icons, id: \.self) { icon in
                        Button {
                            snippetService.setIcon(icon, for: tag)
                            dismiss()
                        } label: {
                            Image(systemName: icon)
                                .font(.system(size: 18))
                                .frame(width: 42, height: 42)
                                .background(
                                    (tag.iconName ?? "folder") == icon
                                        ? AnyShapeStyle(Color.accentColor.opacity(0.25))
                                        : AnyShapeStyle(Color.secondary.opacity(0.12)),
                                    in: RoundedRectangle(cornerRadius: 8)
                                )
                        }
                        .buttonStyle(.plain)
                        .help(icon)
                    }
                }
                .padding(2)
            }
        }
        .padding(16)
        .frame(width: 340, height: 380)
    }
}
