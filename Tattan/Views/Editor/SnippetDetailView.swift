import SwiftData
import SwiftUI

/// 右ペインの編集エリア（D-2）。タイトル / 本文 / タグ / 個別ホットキー（D-5）/
/// 「変数を挿入 ▼」（D-3 の発見性確保）。
struct SnippetDetailView: View {
    @Bindable var snippet: Snippet
    /// 削除は親（SnippetEditorView）が確認ダイアログを出すため、ここでは要求だけ伝える
    let onRequestDelete: () -> Void

    @Environment(SnippetService.self) private var snippetService
    @Environment(HotkeyService.self) private var hotkeyService
    @Query(sort: [SortDescriptor(\Tag.sortOrder), SortDescriptor(\Tag.name)])
    private var allTags: [Tag]
    @State private var showingNewGroup = false
    @State private var newGroupName = ""

    /// 「変数を挿入 ▼」の一覧（§9.5 の変数リファレンスと同じ並び）
    private static let variableTokens: [(label: String, token: String)] = [
        ("{{date}}", "{{date}}"),
        ("{{date:yyyy/MM/dd}}", "{{date:yyyy/MM/dd}}"),
        ("{{date+1}}", "{{date+1}}"),
        ("{{day}}", "{{day}}"),
        ("{{time}}", "{{time}}"),
        ("{{datetime}}", "{{datetime}}"),
        ("{{ask:Label}}", "{{ask:Label}}"),
        ("{{ask:Label|Default}}", "{{ask:Label|Default}}"),
        ("{{choose:A|B|C}}", "{{choose:A|B|C}}"),
        ("{{clipboard}}", "{{clipboard}}"),
        ("{{cursor}}", "{{cursor}}"),
        ("{{uuid}}", "{{uuid}}")
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                TextField(String(localized: "Title"), text: $snippet.title)
                    .textFieldStyle(.plain)
                    .scaledFont(13, weight: .semibold)
                    .padding(3)
                    .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.separator))
                if let hex = HexColorParser.firstColor(in: snippet.content) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color(red: hex.red, green: hex.green, blue: hex.blue, opacity: hex.alpha))
                        .frame(width: 24, height: 16)
                        .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(.separator))
                }
            }

            TextEditor(text: $snippet.content)
                .scaledFont(13)
                .padding(3)
                .frame(minHeight: 180)
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.separator))

            HStack {
                Menu {
                    ForEach(Self.variableTokens, id: \.token) { entry in
                        // カーソル位置への挿入は TextEditor の選択範囲 API が貧弱なため
                        // v1.0 では末尾追加とする（既知の妥協）
                        Button(entry.label) { snippet.content += entry.token }
                    }
                } label: {
                    Label(String(localized: "Insert Variable"), systemImage: "curlybraces")
                }
                .fixedSize()
                Spacer()
            }

            // グループ = タグ（D-1）の単一選択 UI。Ken の使い方（メアド/色/コマンド/その他）に
            // 合わせてフォルダ感覚で選べるようにする（データ上は複数タグ可のまま）
            HStack {
                Text(String(localized: "Group"))
                    .scaledFont(13)
                Menu {
                    Button(String(localized: "None")) { setGroup(nil) }
                    if !allTags.isEmpty {
                        Divider()
                        ForEach(allTags, id: \.uuid) { tag in
                            Button(tag.name) { setGroup(tag) }
                        }
                    }
                    Divider()
                    Button(String(localized: "New Group…")) {
                        newGroupName = ""
                        showingNewGroup = true
                    }
                } label: {
                    Text(currentGroupName ?? String(localized: "None"))
                }
                .fixedSize()
                Spacer()
            }
            .alert(String(localized: "New Group"), isPresented: $showingNewGroup) {
                TextField(String(localized: "Group name"), text: $newGroupName)
                Button(String(localized: "Create")) {
                    let name = newGroupName.trimmingCharacters(in: .whitespaces)
                    guard !name.isEmpty else { return }
                    setGroup(snippetService.tag(named: name))
                }
                Button(String(localized: "Cancel"), role: .cancel) {}
            }

            HotkeyRecorderField(
                title: String(localized: "Shortcut"),
                binding: HotkeyBinding.decode(snippet.hotkeyData),
                onChange: { hotkeyService.setSnippetBinding($0, for: snippet) },
                duplicateCheck: { hotkeyService.duplicateOwner(of: $0, excludingSnippet: snippet.uuid) }
            )

            Spacer()

            HStack {
                Spacer()
                Button(role: .destructive, action: onRequestDelete) {
                    Label(String(localized: "Delete Snippet"), systemImage: "trash")
                        .scaledFont(13)
                }
            }
        }
        .padding(16)
        .onDisappear {
            snippetService.touchUpdated(snippet)
        }
    }

    private var currentGroupName: String? {
        snippet.tags?.first?.name
    }

    private func setGroup(_ tag: Tag?) {
        snippet.tags = tag.map { [$0] } ?? []
        snippetService.touchUpdated(snippet)
    }
}
