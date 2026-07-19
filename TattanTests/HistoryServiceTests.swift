import Foundation
import SwiftData
import Testing
@testable import Tattan

/// 取り込みパイプライン §5.3 [5]〜[9] の検証。
/// apply(_:)（同期パス）を直接呼んで決定的にテストする。
@MainActor
struct HistoryServiceTests {

    private struct Fixture {
        let settings: SettingsStore
        let persistence: PersistenceController
        let service: HistoryService
    }

    private func makeFixture() throws -> Fixture {
        let suiteName = "HistoryServiceTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        let settings = SettingsStore(defaults: defaults)

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("HistoryServiceTests-\(UUID().uuidString)", isDirectory: true)
        let persistence = try PersistenceController(directory: directory, cloudKitEnabled: false)
        let service = HistoryService(persistence: persistence, settings: settings)
        return Fixture(settings: settings, persistence: persistence, service: service)
    }

    private func textContent(_ text: String) -> ProcessedContent {
        ProcessedContent(content: CapturedContent(kind: .text, plainText: text))
    }

    private func concealedContent(_ text: String) -> ProcessedContent {
        ProcessedContent(content: CapturedContent(
            kind: .text, plainText: text, hasConcealedMarker: true
        ))
    }

    private func count(in container: ModelContainer) throws -> Int {
        try container.mainContext.fetchCount(FetchDescriptor<ClipHistoryItem>())
    }

    // MARK: - 振り分け（§2.2 / O-2 / E-1）

    @Test func normalTextGoesToMainStore() throws {
        let fixture = try makeFixture()
        fixture.service.apply(textContent("普通のテキスト"))

        #expect(try count(in: fixture.persistence.mainContainer) == 1)
        #expect(try count(in: fixture.persistence.localContainer) == 0)
    }

    @Test func creditCardTextGoesToLocalStoreWithMaskedPreview() throws {
        let fixture = try makeFixture()
        fixture.service.apply(textContent("カード: 4242 4242 4242 4242"))

        #expect(try count(in: fixture.persistence.mainContainer) == 0)
        #expect(try count(in: fixture.persistence.localContainer) == 1)

        let item = try #require(fixture.service.fetchHistory().first)
        #expect(item.sensitivity == .creditCard)
        // 表示用 previewText はマスク済み（§6.3）、実体 plainText は無加工（C-8）
        #expect(item.previewText == "カード: •••• •••• •••• 4242")
        #expect(item.plainText == "カード: 4242 4242 4242 4242")
    }

    @Test func oversizedContentGoesToLocalStore() throws {
        let fixture = try makeFixture()
        fixture.settings.syncSizeThresholdMB = 1

        let bigData = Data(count: 2 * 1024 * 1024)
        let content = CapturedContent(kind: .image, imageData: bigData)
        fixture.service.apply(ProcessedContent(content: content))

        #expect(try count(in: fixture.persistence.mainContainer) == 0)
        #expect(try count(in: fixture.persistence.localContainer) == 1)
    }

    // MARK: - 重複回避（時間問わず完全一致は 1 件に統合）

    @Test func consecutiveDuplicateUpdatesCopiedAtWithoutNewRecord() throws {
        let fixture = try makeFixture()
        fixture.service.apply(textContent("同じ内容"))
        let firstCopiedAt = try #require(fixture.service.fetchHistory().first).copiedAt

        fixture.service.apply(textContent("同じ内容"))

        let items = fixture.service.fetchHistory()
        #expect(items.count == 1)
        #expect(try #require(items.first).copiedAt >= firstCopiedAt)
    }

    /// A, B, A は時間問わず A 同士が統合される（2026-06-30 裁定: 完全一致は常に 1 件）
    @Test func nonConsecutiveDuplicateMergesIntoTwoRecords() throws {
        let fixture = try makeFixture()

        fixture.service.apply(textContent("A"))
        fixture.service.apply(textContent("B"))
        fixture.service.apply(textContent("A"))

        let items = fixture.service.fetchHistory()
        #expect(items.count == 2)
        // 先頭は A（再コピーで copiedAt が更新されて先頭に浮上）、その次に B
        #expect(items[0].plainText == "A")
        #expect(items[1].plainText == "B")
    }

    // MARK: - 上限執行（N-1）

    @Test func enforcesHistoryLimitAcrossBothStores() throws {
        let fixture = try makeFixture()
        fixture.settings.historyLimit = 5

        for index in 0..<8 {
            fixture.service.apply(textContent("item-\(index)"))
        }
        // クレカ項目（ローカルストア行き）も合算でカウントされる
        fixture.service.apply(textContent("カード: 4242 4242 4242 4242"))

        let total = try count(in: fixture.persistence.mainContainer)
            + (try count(in: fixture.persistence.localContainer))
        #expect(total == 5)

        // 最新（クレカ項目）が残り、最古から削られている
        let previews = fixture.service.fetchHistory().map(\.previewText)
        #expect(previews.first == "カード: •••• •••• •••• 4242")
        #expect(!previews.contains("item-0"))
    }

    // MARK: - 自動削除（C-7 / N-2）

    @Test func pruneExpiredDeletesOldItemsWhenEnabled() throws {
        let fixture = try makeFixture()
        fixture.settings.autoDeleteEnabled = true
        fixture.settings.autoDeleteDays = 30

        let context = fixture.persistence.mainContainer.mainContext
        let oldItem = ClipHistoryItem()
        oldItem.previewText = "old"
        oldItem.copiedAt = Date().addingTimeInterval(-40 * 86_400)
        context.insert(oldItem)
        let freshItem = ClipHistoryItem()
        freshItem.previewText = "fresh"
        context.insert(freshItem)
        try context.save()

        fixture.service.pruneExpired()

        let previews = fixture.service.fetchHistory().map(\.previewText)
        #expect(previews == ["fresh"])
    }

    @Test func pruneExpiredDoesNothingWhenDisabled() throws {
        let fixture = try makeFixture()
        fixture.settings.autoDeleteEnabled = false

        let context = fixture.persistence.mainContainer.mainContext
        let oldItem = ClipHistoryItem()
        oldItem.copiedAt = Date().addingTimeInterval(-365 * 86_400)
        context.insert(oldItem)
        try context.save()

        fixture.service.pruneExpired()
        #expect(fixture.service.fetchHistory().count == 1)
    }

    // MARK: - 削除操作（C-7: 個別 / 全消去）

    @Test func deleteRemovesSingleItem() throws {
        let fixture = try makeFixture()
        fixture.service.apply(textContent("残す"))
        fixture.service.apply(textContent("消す"))

        let target = try #require(fixture.service.fetchHistory().first { $0.previewText == "消す" })
        fixture.service.delete(target)

        let previews = fixture.service.fetchHistory().map(\.previewText)
        #expect(previews == ["残す"])
    }

    @Test func deleteAllClearsBothStores() throws {
        let fixture = try makeFixture()
        fixture.service.apply(textContent("normal"))
        fixture.service.apply(textContent("カード: 4242 4242 4242 4242"))

        fixture.service.deleteAll()

        #expect(fixture.service.fetchHistory().isEmpty)
        #expect(try count(in: fixture.persistence.mainContainer) == 0)
        #expect(try count(in: fixture.persistence.localContainer) == 0)
    }

    @Test func deleteAllImagesRemovesOnlyImages() throws {
        let fixture = try makeFixture()
        fixture.service.apply(textContent("keep me"))
        fixture.service.apply(ProcessedContent(
            content: CapturedContent(kind: .image, imageData: Data(count: 16))
        ))

        fixture.service.deleteAllImages()

        let remaining = fixture.service.fetchHistory()
        #expect(remaining.count == 1)
        #expect(remaining.first?.previewText == "keep me")
    }

    @Test func deleteAllCreditCardItemsRemovesOnlyCardItems() throws {
        let fixture = try makeFixture()
        fixture.service.apply(textContent("normal"))
        fixture.service.apply(textContent("カード: 4242 4242 4242 4242"))

        fixture.service.deleteAllCreditCardItems()

        let remaining = fixture.service.fetchHistory()
        #expect(remaining.count == 1)
        #expect(remaining.first?.previewText == "normal")
    }

    // MARK: - 機密情報トグル（O-3）

    /// ConcealedType マーカー付きはローカル専用ストアへ、previewText は固定マスク
    @Test func concealedContentGoesToLocalStoreWithFixedMask() throws {
        let fixture = try makeFixture()
        fixture.service.apply(concealedContent("hunter2-password"))

        #expect(try count(in: fixture.persistence.mainContainer) == 0)
        #expect(try count(in: fixture.persistence.localContainer) == 1)

        let item = try #require(fixture.service.fetchHistory().first)
        #expect(item.sensitivity == .concealed)
        // 表示用は固定マスク、実体は無加工（ペースト時に使う）
        #expect(item.previewText == "••••••••")
        #expect(item.plainText == "hunter2-password")
    }

    /// クレカ判定は ConcealedType より優先（1Password はクレカにも Concealed を付けるため）
    @Test func creditCardWinsOverConcealedMarker() throws {
        let fixture = try makeFixture()
        fixture.service.apply(concealedContent("4242 4242 4242 4242"))

        let item = try #require(fixture.service.fetchHistory().first)
        #expect(item.sensitivity == .creditCard)
        #expect(item.previewText == "•••• •••• •••• 4242")
    }

    @Test func deleteAllConcealedItemsRemovesOnlyConcealedItems() throws {
        let fixture = try makeFixture()
        fixture.service.apply(textContent("normal"))
        fixture.service.apply(concealedContent("password1"))
        fixture.service.apply(textContent("カード: 4242 4242 4242 4242"))

        fixture.service.deleteAllConcealedItems()

        let remaining = fixture.service.fetchHistory().map(\.sensitivity)
        #expect(remaining.contains(.none))
        #expect(remaining.contains(.creditCard))
        #expect(!remaining.contains(.concealed))
    }

    // MARK: - フェッチ（§2.5）

    @Test func fetchHistoryMergesStoresNewestFirst() throws {
        let fixture = try makeFixture()
        fixture.service.apply(textContent("first"))
        fixture.service.apply(textContent("カード: 4242 4242 4242 4242"))
        fixture.service.apply(textContent("last"))

        let previews = fixture.service.fetchHistory().map(\.previewText)
        #expect(previews == ["last", "カード: •••• •••• •••• 4242", "first"])
    }
}
