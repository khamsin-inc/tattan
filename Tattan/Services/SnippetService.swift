import Foundation
import Observation
import os
import SwiftData

/// スニペット・タグの CRUD（D-1, D-2）と履歴からの昇格（Q-1）。
/// タグ名の一意性は CloudKit 制約で DB に張れないため、ここで担保する（§2.4）。
@MainActor
@Observable
final class SnippetService {
    private let persistence: PersistenceController
    private let logger = Logger(subsystem: "jp.khamsin.tattan", category: "snippet")

    /// スニペットのホットキー割り当てが変わった時の通知（HotkeyService が再登録に使う）
    var onSnippetsChanged: (() -> Void)?

    private var context: ModelContext { persistence.mainContainer.mainContext }

    init(persistence: PersistenceController) {
        self.persistence = persistence
    }

    // MARK: - スニペット

    @discardableResult
    func createSnippet(title: String = "", content: String = "", tags: [Tag] = []) -> Snippet {
        let snippet = Snippet()
        snippet.title = title
        snippet.content = content
        snippet.sortOrder = (fetchSnippets().map(\.sortOrder).max() ?? -1) + 1
        context.insert(snippet)
        snippet.tags = tags
        save()
        notifyChanged()
        return snippet
    }

    /// 編集確定時に呼ぶ。updatedAt は LWW（E-3）の観測用。
    /// 削除確定後に SnippetDetailView.onDisappear から遅れて飛んでくるケースを
    /// 無害化する（renameTag と同じガード。2026-07-02 レビュー指摘 #2）
    func touchUpdated(_ snippet: Snippet) {
        guard snippet.modelContext != nil else { return }
        snippet.updatedAt = Date()
        save()
        notifyChanged()
    }

    func delete(_ snippet: Snippet) {
        context.delete(snippet)
        save()
        notifyChanged()
    }

    /// 複数スニペットの一括削除（D-2 複数選択）。1 回の save にまとめてから通知する
    func deleteSnippets(_ targets: [Snippet]) {
        guard !targets.isEmpty else { return }
        for snippet in targets {
            context.delete(snippet)
        }
        save()
        notifyChanged()
    }

    /// スニペットの手動並べ替え（ドラッグ）。表示中（グループフィルタ後）の配列を受け取り、
    /// その配列が全体順序の中で占めるスロットだけ入れ替えて sortOrder を 0 から振り直す。
    /// 並び順は全体で 1 本（D-2）なので、グループ内で並べ替えても他グループのスニペットの
    /// 相対位置は保たれる。`displayed` が All（＝全件）のときは単純な全体並べ替えになる。
    func moveSnippets(_ displayed: [Snippet], fromOffsets: IndexSet, toOffset: Int) {
        var reordered = displayed
        reordered.move(fromOffsets: fromOffsets, toOffset: toOffset)

        let displayedUUIDs = Set(displayed.map(\.uuid))
        var reorderedIterator = reordered.makeIterator()
        let resequenced = fetchSnippets().map { snippet -> Snippet in
            // 表示中スニペットが占めていたスロットへ、並べ替え後の順で詰め直す
            if displayedUUIDs.contains(snippet.uuid), let next = reorderedIterator.next() {
                return next
            }
            return snippet
        }
        for (index, snippet) in resequenced.enumerated() {
            snippet.sortOrder = index
        }
        save()
        notifyChanged()
    }

    /// スニペットのグループ（タグ）を付け替える。tag が nil なら「グループ無し」。
    /// ドラッグ&ドロップでの移動に使う（運用は 1 スニペット 1 グループなので単一に揃える）
    func setGroup(_ tag: Tag?, for snippet: Snippet) {
        snippet.tags = tag.map { [$0] } ?? []
        snippet.updatedAt = Date()
        save()
        notifyChanged()
    }

    func fetchSnippets() -> [Snippet] {
        let descriptor = FetchDescriptor<Snippet>(
            sortBy: [SortDescriptor(\.sortOrder), SortDescriptor(\.createdAt)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    func snippet(uuid: UUID) -> Snippet? {
        fetchSnippets().first { $0.uuid == uuid }
    }

    // MARK: - タグ

    func fetchTags() -> [Tag] {
        let descriptor = FetchDescriptor<Tag>(
            sortBy: [SortDescriptor(\.sortOrder), SortDescriptor(\.name)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    /// find-or-create。名前は大文字小文字を区別しない一致で再利用する
    func tag(named name: String) -> Tag {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if let existing = fetchTags().first(where: {
            $0.name.compare(trimmed, options: .caseInsensitive) == .orderedSame
        }) {
            return existing
        }
        let tag = Tag()
        tag.name = trimmed
        tag.sortOrder = (fetchTags().map(\.sortOrder).max() ?? -1) + 1
        context.insert(tag)
        save()
        return tag
    }

    /// 新規グループをユニークな仮名で作成（左カラムの「New Group」用）。
    /// 直後にインライン改名される前提なので、仮名は既存と重複しない範囲で連番を振る
    @discardableResult
    func createGroup() -> Tag {
        let base = String(localized: "New Group")
        let existingNames = Set(fetchTags().map { $0.name.lowercased() })
        var name = base
        var suffix = 2
        while existingNames.contains(name.lowercased()) {
            name = "\(base) \(suffix)"
            suffix += 1
        }
        let tag = Tag()
        tag.name = name
        tag.sortOrder = (fetchTags().map(\.sortOrder).max() ?? -1) + 1
        context.insert(tag)
        save()
        notifyChanged()
        return tag
    }

    /// グループ削除。スニペット自体は消えず「グループ無し」になる
    func deleteTag(_ tag: Tag) {
        context.delete(tag)
        save()
        notifyChanged()
    }

    /// グループの手動並べ替え（ドラッグ）。sortOrder を 0 から振り直す
    func moveTags(fromOffsets: IndexSet, toOffset: Int) {
        var orderedTags = fetchTags()
        orderedTags.move(fromOffsets: fromOffsets, toOffset: toOffset)
        for (index, tag) in orderedTags.enumerated() {
            tag.sortOrder = index
        }
        save()
        notifyChanged()
    }

    /// グループ（タグ）のアイコン（SF Symbol 名）を設定する。nil で既定の folder に戻す
    func setIcon(_ iconName: String?, for tag: Tag) {
        tag.iconName = iconName
        save()
        notifyChanged()
    }

    /// グループ名の変更。既存グループと同名（大文字小文字無視）になった場合は統合する
    func renameTag(_ tag: Tag, to newName: String) {
        // 削除済みオブジェクトへの遅延コミット（シートの onDisappear 等）を無害化
        guard tag.modelContext != nil else { return }
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, tag.name != trimmed else { return }
        tag.name = trimmed
        mergeDuplicateTags() // 同名になった場合はここで統合される
        notifyChanged()
    }

    /// LWW 同期マージで生じうる同名タグの自動統合（起動時リペア §2.4）
    func mergeDuplicateTags() {
        var canonicalByName: [String: Tag] = [:]
        for tag in fetchTags() {
            let key = tag.name.lowercased()
            guard let canonical = canonicalByName[key] else {
                canonicalByName[key] = tag
                continue
            }
            for snippet in tag.snippets ?? [] where !(snippet.tags ?? []).contains(where: { $0 === canonical }) {
                // tags は CloudKit 互換で optional。nil のとき `?.append` だと付け替えが
                // 無言で消えるので、明示的に配列を再構築する（2026-07-02 レビュー指摘 #10）
                snippet.tags = (snippet.tags ?? []) + [canonical]
            }
            context.delete(tag)
            logger.info("merged duplicate tag: \(key)")
        }
        save()
    }

    // MARK: - 履歴からの昇格（Q-1）

    @discardableResult
    func promote(_ item: ClipHistoryItem) -> Snippet {
        let content = item.plainText ?? ""
        let firstLine = content.split(separator: "\n", maxSplits: 1).first.map(String.init) ?? ""
        return createSnippet(title: String(firstLine.prefix(30)), content: content)
    }

    // MARK: - 内部処理

    private func notifyChanged() {
        onSnippetsChanged?()
    }

    private func save() {
        guard context.hasChanges else { return }
        do {
            try context.save()
        } catch {
            logger.error("save failed: \(error)")
        }
    }
}
