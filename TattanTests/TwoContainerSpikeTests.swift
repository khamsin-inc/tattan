import Foundation
import SwiftData
import Testing
@testable import Tattan

/// Swift Testing 側にもテスト分類用の `Tag` 型があり、本アプリの `Tag` モデルと
/// 名前が衝突するため、テストコード内では別名で参照する
private typealias SnippetTag = Tattan.Tag

/// architecture.md §16 のリスク「同一 @Model 型を 2 つの ModelContainer に登録する構成」の検証スパイク。
///
/// CloudKit ミラーリング併用時の挙動は entitlements + iCloud アカウントが必要で
/// ユニットテストでは検証できないため、ここではローカル 2 ストアの分離・読み書き・
/// マージ取得を検証する。残り（ミラーリング実機確認）は Phase 2.6 で行う。
@MainActor
struct TwoContainerSpikeTests {

    /// テストごとに使い捨ての一時ディレクトリでコントローラを作る
    private func makeController() throws -> PersistenceController {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("TattanTests-\(UUID().uuidString)", isDirectory: true)
        return try PersistenceController(directory: directory, cloudKitEnabled: false)
    }

    @Test func twoStoresAreIsolated() throws {
        let controller = try makeController()
        let mainContext = controller.mainContainer.mainContext
        let localContext = controller.localContainer.mainContext

        let synced = ClipHistoryItem()
        synced.previewText = "synced"
        mainContext.insert(synced)
        try mainContext.save()

        let localOnly = ClipHistoryItem()
        localOnly.previewText = "local-only"
        localOnly.sensitivity = .creditCard
        localContext.insert(localOnly)
        try localContext.save()

        let mainItems = try mainContext.fetch(FetchDescriptor<ClipHistoryItem>())
        let localItems = try localContext.fetch(FetchDescriptor<ClipHistoryItem>())

        #expect(mainItems.count == 1)
        #expect(mainItems.first?.previewText == "synced")
        #expect(localItems.count == 1)
        #expect(localItems.first?.previewText == "local-only")
        #expect(localItems.first?.sensitivity == .creditCard)
    }

    @Test func mergedFetchOrdersByCopiedAtDescending() throws {
        let controller = try makeController()
        let mainContext = controller.mainContainer.mainContext
        let localContext = controller.localContainer.mainContext

        let base = Date(timeIntervalSince1970: 1_750_000_000)

        let oldest = ClipHistoryItem()
        oldest.previewText = "oldest"
        oldest.copiedAt = base
        mainContext.insert(oldest)

        let middle = ClipHistoryItem()
        middle.previewText = "middle"
        middle.copiedAt = base.addingTimeInterval(60)
        localContext.insert(middle)

        let newest = ClipHistoryItem()
        newest.previewText = "newest"
        newest.copiedAt = base.addingTimeInterval(120)
        mainContext.insert(newest)

        try mainContext.save()
        try localContext.save()

        // HistoryService（Phase 2.1）が行う「2 ストアのフェッチ + copiedAt 降順マージ」（§2.5）と同じ手順
        var descriptor = FetchDescriptor<ClipHistoryItem>(
            sortBy: [SortDescriptor(\.copiedAt, order: .reverse)]
        )
        descriptor.fetchLimit = 100
        let merged = try (mainContext.fetch(descriptor) + localContext.fetch(descriptor))
            .sorted { $0.copiedAt > $1.copiedAt }

        #expect(merged.map(\.previewText) == ["newest", "middle", "oldest"])
    }

    @Test func snippetTagManyToManyRelationship() throws {
        let controller = try makeController()
        let context = controller.mainContainer.mainContext

        let mailTag = SnippetTag()
        mailTag.name = "mail"
        let workTag = SnippetTag()
        workTag.name = "work"
        context.insert(mailTag)
        context.insert(workTag)

        let snippet = Snippet()
        snippet.title = "greeting"
        snippet.content = "お世話になっております。"
        context.insert(snippet)
        snippet.tags = [mailTag, workTag]
        try context.save()

        let fetchedSnippets = try context.fetch(FetchDescriptor<Snippet>())
        let fetchedTags = try context.fetch(
            FetchDescriptor<SnippetTag>(sortBy: [SortDescriptor(\.name)])
        )

        #expect(fetchedSnippets.first?.tags?.count == 2)
        #expect(fetchedTags.count == 2)
        #expect(fetchedTags.first?.snippets?.first?.title == "greeting")
    }

    /// CloudKit ミラーリングの前提（§2.1: 全プロパティにデフォルト値）が崩れていないことの番犬。
    /// 新フィールド追加時にデフォルト値を忘れると、ここではなく実機の同期初期化で初めて
    /// 落ちる事故になるため、引数なし init が通ることを常時確認する。
    @Test func modelsProvideCloudKitCompatibleDefaults() throws {
        let item = ClipHistoryItem()
        #expect(item.kind == .text)
        #expect(item.sensitivity == Sensitivity.none)
        #expect(item.previewText.isEmpty)
        #expect(item.byteSize == 0)

        let snippet = Snippet()
        #expect(snippet.tags?.isEmpty == true)

        let tag = SnippetTag()
        #expect(tag.snippets?.isEmpty == true)
    }
}
