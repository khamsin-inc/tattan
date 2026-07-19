import SwiftData
import SwiftUI

/// 3 カラムのスニペットエディタ（D-2）。設定画面（システム設定風サイドバー）とトーンを揃える。
/// 左 = グループ（タグ）サイドバー、中 = 選択グループのスニペット一覧、右 = 常時表示の編集エリア。
/// グループの追加・改名・削除は List 外のダイアログ／右クリックで行い（行を軽く保つ）、
/// グループ／スニペットともホバーで削除、ドラッグで並べ替えできる。
struct SnippetEditorView: View {
    @Environment(SnippetService.self) private var snippetService
    @Environment(SettingsStore.self) private var settings
    @Query(sort: [SortDescriptor(\Snippet.sortOrder), SortDescriptor(\Snippet.createdAt)])
    private var snippets: [Snippet]
    @Query(sort: [SortDescriptor(\Tag.sortOrder), SortDescriptor(\Tag.name)])
    private var tags: [Tag]

    @State private var groupSelection: GroupSelection? = .all
    @State private var snippetSelection = Set<Snippet>()
    @State private var renamingTag: Tag?
    @State private var renameDraft = ""
    @State private var pendingDeletion: PendingDeletion?
    @State private var iconPickingTag: Tag?

    /// 左サイドバーの選択。All（全件）か特定グループ（タグ UUID）。
    private enum GroupSelection: Hashable {
        case all
        case noGroup
        case tag(UUID)
    }

    /// 確認ダイアログ対象。グループ・スニペットで 1 つの alert に集約する
    private enum PendingDeletion: Identifiable {
        case group(Tag)
        case snippet(Snippet)
        case snippets([Snippet])

        var id: String {
            switch self {
            case .group(let tag): "group-\(tag.uuid)"
            case .snippet(let snippet): "snippet-\(snippet.uuid)"
            case .snippets(let snippets): "snippets-\(snippets.map(\.uuid.uuidString).joined())"
            }
        }
    }

    private var filteredSnippets: [Snippet] {
        switch groupSelection {
        case .tag(let uuid):
            snippets.filter { ($0.tags ?? []).contains { $0.uuid == uuid } }
        case .noGroup:
            snippets.filter { ($0.tags ?? []).isEmpty }
        case .all, .none:
            snippets
        }
    }

    /// グループ選択中に作る新規スニペットには、そのグループを自動で付ける
    private var newSnippetTags: [Tag] {
        if case .tag(let uuid) = groupSelection, let tag = tags.first(where: { $0.uuid == uuid }) {
            return [tag]
        }
        return []
    }

    var body: some View {
        NavigationSplitView(columnVisibility: .constant(.all)) {
            groupSidebar
        } content: {
            snippetList
        } detail: {
            detail
        }
        // サイドバーは常時表示（設定画面と同じ。折りたたみトグルは出さない）
        .toolbar(removing: .sidebarToggle)
        // 文字サイズ設定をこのウィンドウ配下の全 scaledFont に流す（F-7）
        .environment(\.uiScale, settings.uiScale)
        .alert(
            deletionTitle,
            isPresented: deletionPresented,
            presenting: pendingDeletion
        ) { deletion in
            Button(String(localized: "Delete"), role: .destructive) { confirmDeletion(deletion) }
            Button(String(localized: "Cancel"), role: .cancel) {}
        } message: { deletion in
            Text(deletionMessage(deletion))
        }
    }

    // MARK: - 左カラム（グループ）

    private var groupSidebar: some View {
        List(selection: $groupSelection) {
            Label(String(localized: "All"), systemImage: "tray.full")
                .scaledFont(13)
                .tag(GroupSelection.all)
                .dropDestination(for: String.self) { items, _ in
                    return handleDrop(items, to: nil)
                }
            // どのグループにも属さないスニペット（ポップアップの No Group と挙動を揃える）。
            // ここへドロップするとグループ無しになる
            Label(String(localized: "No Group"), systemImage: "tray")
                .scaledFont(13)
                .tag(GroupSelection.noGroup)
                .dropDestination(for: String.self) { items, _ in
                    return handleDrop(items, to: nil)
                }
            Section {
                ForEach(tags, id: \.uuid) { tag in
                    GroupRow(
                        tag: tag,
                        requestRename: { beginRename(tag) },
                        requestDelete: { pendingDeletion = .group(tag) },
                        acceptDrop: { handleDrop($0, to: tag) },
                        requestChangeIcon: { iconPickingTag = tag }
                    )
                    .tag(GroupSelection.tag(tag.uuid))
                }
                .onMove { offsets, dest in
                    snippetService.moveTags(fromOffsets: offsets, toOffset: dest)
                }
            }
        }
        .listStyle(.sidebar)
        .navigationSplitViewColumnWidth(min: 170, ideal: 195)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            footerButton(title: String(localized: "New Group"), systemImage: "folder.badge.plus") {
                let tag = snippetService.createGroup()
                groupSelection = .tag(tag.uuid)
                beginRename(tag) // 作成直後に改名ダイアログを開いて名前を入力させる
            }
        }
        // 改名・新規作成の入力は List 外のダイアログで（行内 TextField はフォーカスが
        // 不安定＆スクロールが重くなるため、確実なダイアログ方式にした）
        .alert(String(localized: "Group Name"), isPresented: renamePresented) {
            TextField(String(localized: "Group name"), text: $renameDraft)
            Button(String(localized: "Save")) { commitRename() }
            Button(String(localized: "Cancel"), role: .cancel) { renamingTag = nil }
        }
        .sheet(item: $iconPickingTag) { tag in
            IconPickerView(tag: tag)
        }
    }

    // MARK: - 中カラム（スニペット一覧）

    private var snippetList: some View {
        List(selection: $snippetSelection) {
            ForEach(filteredSnippets, id: \.self) { snippet in
                SnippetRow(snippet: snippet, requestDelete: { pendingDeletion = .snippet(snippet) })
                    .tag(snippet)
            }
            .onMove { offsets, dest in
                snippetService.moveSnippets(filteredSnippets, fromOffsets: offsets, toOffset: dest)
            }
        }
        // Delete キーで選択中（複数可）をまとめて削除。Cmd+A で表示中を全選択できる
        .onDeleteCommand { requestDeleteSelection() }
        .navigationSplitViewColumnWidth(min: 220, ideal: 260)
        .overlay {
            if filteredSnippets.isEmpty {
                ContentUnavailableView(
                    String(localized: "No Snippets"),
                    systemImage: "doc.on.clipboard",
                    description: Text(String(localized: "Create one with the button below."))
                )
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            footerButton(title: String(localized: "New Snippet"), systemImage: "plus") {
                snippetSelection = [snippetService.createSnippet(tags: newSnippetTags)]
            }
        }
    }

    // MARK: - 右カラム（編集）

    @ViewBuilder private var detail: some View {
        switch snippetSelection.count {
        case 1:
            if let snippet = snippetSelection.first {
                SnippetDetailView(snippet: snippet, onRequestDelete: { pendingDeletion = .snippet(snippet) })
                    .id(snippet.uuid) // 選択切替で編集ステートを確実にリセットする
            }
        case 0:
            ContentUnavailableView(
                String(localized: "No Snippet Selected"),
                systemImage: "doc.on.clipboard",
                description: Text(String(localized: "Select a snippet from the list, or create a new one."))
            )
        default:
            // 複数選択中は編集せず、件数と削除手段を案内する
            ContentUnavailableView(
                String(localized: "\(snippetSelection.count) Snippets Selected"),
                systemImage: "checklist",
                description: Text(String(localized: "Press Delete to remove them, or select a single snippet to edit."))
            )
        }
    }

    // MARK: - フッターボタン（各カラム下端）

    private func footerButton(
        title: String,
        systemImage: String,
        action: @escaping () -> Void
    ) -> some View {
        VStack(spacing: 0) {
            Divider()
            Button(action: action) {
                Label(title, systemImage: systemImage)
                    .scaledFont(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.plain)
        }
        // 左カラム(sidebar)と中カラムで List 下端の処理が異なり New Group / New Snippet の
        // 高さは厳密には揃わないが、運用上許容（2026-06-15 裁定）
        .background(.bar)
    }

    // MARK: - グループ改名（List 外ダイアログ）

    private var renamePresented: Binding<Bool> {
        Binding(get: { renamingTag != nil }, set: { if !$0 { renamingTag = nil } })
    }

    private func beginRename(_ tag: Tag) {
        renameDraft = tag.name
        renamingTag = tag
    }

    /// スニペットをグループへドロップしたときの付け替え。tag が nil なら「グループ無し」へ
    private func handleDrop(_ uuidStrings: [String], to tag: Tag?) -> Bool {
        let uuids = Set(uuidStrings.compactMap { UUID(uuidString: $0) })
        let dropped = snippets.filter { uuids.contains($0.uuid) }
        guard !dropped.isEmpty else { return false }
        for snippet in dropped {
            snippetService.setGroup(tag, for: snippet)
        }
        return true
    }

    private func commitRename() {
        if let tag = renamingTag {
            snippetService.renameTag(tag, to: renameDraft)
        }
        renamingTag = nil
    }

    // MARK: - 削除確認

    private var deletionPresented: Binding<Bool> {
        Binding(get: { pendingDeletion != nil }, set: { if !$0 { pendingDeletion = nil } })
    }

    private var deletionTitle: String {
        switch pendingDeletion {
        case .group: String(localized: "Delete Group?")
        case .snippet: String(localized: "Delete Snippet?")
        case .snippets(let snippets): String(localized: "Delete \(snippets.count) Snippets?")
        case .none: ""
        }
    }

    private func deletionMessage(_ deletion: PendingDeletion) -> String {
        switch deletion {
        case .group(let tag):
            let name = tag.name.isEmpty ? String(localized: "Untitled") : tag.name
            return String(localized: "“\(name)” will be removed. Its snippets will not be deleted.")
        case .snippet(let snippet):
            let title = snippet.title.isEmpty ? String(localized: "Untitled") : snippet.title
            return String(localized: "“\(title)” will be permanently deleted.")
        case .snippets(let snippets):
            return String(localized: "\(snippets.count) snippets will be permanently deleted.")
        }
    }

    /// 中カラムで選択中のスニペットを表示順で返す（確認メッセージ・削除順を安定させる）
    private var orderedSelection: [Snippet] {
        filteredSnippets.filter { snippetSelection.contains($0) }
    }

    /// Delete キーから。選択が 1 件なら単体、複数ならまとめて確認ダイアログを出す
    private func requestDeleteSelection() {
        let targets = orderedSelection
        guard !targets.isEmpty else { return }
        pendingDeletion = targets.count == 1 ? .snippet(targets[0]) : .snippets(targets)
    }

    private func confirmDeletion(_ deletion: PendingDeletion) {
        switch deletion {
        case .group(let tag):
            if groupSelection == .tag(tag.uuid) { groupSelection = .all }
            snippetService.deleteTag(tag)
        case .snippet(let snippet):
            snippetSelection.remove(snippet)
            snippetService.delete(snippet)
        case .snippets(let snippets):
            snippetSelection.subtract(snippets)
            snippetService.deleteSnippets(snippets)
        }
        pendingDeletion = nil
    }
}
