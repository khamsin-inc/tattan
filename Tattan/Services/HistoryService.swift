import Foundation
import Observation
import os
import SwiftData

/// 履歴の取り込み・取得・削除を担う（§5.3 [5]〜[9] / C-7 / C-9 / O-2 / E-1）。
/// 2 ストア（同期可 main / 同期除外 local）への振り分けと横断操作はこのクラスに閉じ、
/// 他のコードは「履歴がどのストアにあるか」を意識しない。
@MainActor
@Observable
final class HistoryService {
    private let persistence: PersistenceController
    private let settings: SettingsStore
    private var maintenanceTimer: Timer?
    private var dedupBackstopTimer: Timer?
    private var remoteChangeObserver: NSObjectProtocol?
    private var dedupDebounceTask: Task<Void, Never>?
    private let logger = Logger(subsystem: "jp.khamsin.tattan", category: "history")

    /// CloudKit インポートが apply を経由せずに入る分の取りこぼし用バックストップ間隔（秒）。
    /// 本命は NSPersistentStoreRemoteChange 購読（observeRemoteChanges）で、これは安全網。
    /// 全件フェッチを伴うため常駐コストを抑えて 60 秒とし、同期 ON のときだけ回す
    /// （2026-07-02 レビュー指摘 #5。旧: 5 秒・無条件）
    private let dedupBackstopInterval: TimeInterval = 60

    init(persistence: PersistenceController, settings: SettingsStore) {
        self.persistence = persistence
        self.settings = settings
        observeRemoteChanges()
    }

    // MARK: - 取り込み

    /// ClipboardMonitor からの入口。重い前処理（ハッシュ・Luhn・サムネイル）は背景で行う（§1.5）
    func ingest(_ content: CapturedContent) async {
        let processed = await Task.detached(priority: .utility) {
            ProcessedContent(content: content)
        }.value
        apply(processed)
    }

    /// 取り込み本体（同期）。テストはここを直接呼ぶ。
    /// 重複排除は時間を問わず全期間で完全一致 contentHash を 1 件に統合する方針（2026-06-30 裁定）。
    /// Maccy/Clipy と同じ「履歴には同じ内容を常に 1 件だけ残す」UX
    func apply(_ processed: ProcessedContent) {
        if let twin = fetchAnyTwin(contentHash: processed.contentHash) {
            twin.copiedAt = Date()
            save(twin.modelContext)
            return
        }

        // [8] ストア振り分け（§2.2): クレカ・Concealed（O-2/O-3）またはサイズ閾値超（E-1）→ ローカル専用ストア
        let context = persistenceContext(for: processed)
        context.insert(makeItem(from: processed))
        save(context)

        // [9] 上限執行（N-1）
        enforceLimit()
    }

    /// 全期間の履歴から同一 contentHash を 1 件返す（両ストア合算で最新の copiedAt のもの）。
    /// ClipHistoryItem 側で contentHash にインデックスを張っており、上限 1000 件規模では実質ノーコスト
    private func fetchAnyTwin(contentHash: String) -> ClipHistoryItem? {
        guard !contentHash.isEmpty else { return nil }
        let predicate = #Predicate<ClipHistoryItem> { $0.contentHash == contentHash }
        var descriptor = FetchDescriptor<ClipHistoryItem>(
            predicate: predicate,
            sortBy: [SortDescriptor(\.copiedAt, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        let mainTwin = (try? persistence.mainContainer.mainContext.fetch(descriptor))?.first
        let localTwin = (try? persistence.localContainer.mainContext.fetch(descriptor))?.first
        return [mainTwin, localTwin]
            .compactMap { $0 }
            .max { $0.copiedAt < $1.copiedAt }
    }

    /// processed の機微判定・サイズに応じて保存先 ModelContext を選ぶ。
    /// 機微あり（クレカ/Concealed）または閾値超は localContainer、その他は mainContainer
    private func persistenceContext(for processed: ProcessedContent) -> ModelContext {
        let thresholdBytes = settings.syncSizeThresholdMB * 1024 * 1024
        let isLocalOnly = processed.sensitivity != .none || processed.byteSize > thresholdBytes
        return isLocalOnly
            ? persistence.localContainer.mainContext
            : persistence.mainContainer.mainContext
    }

    private func makeItem(from processed: ProcessedContent) -> ClipHistoryItem {
        let item = ClipHistoryItem()
        item.kind = processed.content.kind
        item.plainText = processed.content.plainText
        item.rtfData = processed.content.rtfData
        item.binaryData = processed.content.imageData
        item.filePathsJoined = processed.content.fileURLs.isEmpty
            ? nil
            : processed.content.fileURLs.map(\.path).joined(separator: "\n")
        item.previewText = processed.previewText
        item.thumbnailData = processed.thumbnailData
        item.contentHash = processed.contentHash
        item.byteSize = processed.byteSize
        item.sensitivity = processed.sensitivity
        return item
    }

    /// 履歴項目をペーストした時に呼ぶ。「最新のクリップボード = 先頭」へ浮上させる（§7 [4]）
    func markPasted(_ item: ClipHistoryItem) {
        item.copiedAt = Date()
        save(item.modelContext)
    }

    /// インポート用の直接挿入（§13.1）。重複チェックは行わず、元の日時を保持する。
    /// 上限執行はここでは行わない — 1 件ごとの全件フェッチで O(n²) になるため、
    /// 呼び出し側がバッチ完了後に enforceLimit() を 1 回呼ぶ（2026-07-02 レビュー指摘 #7）
    func importItem(_ processed: ProcessedContent, createdAt: Date, copiedAt: Date) {
        let context = persistenceContext(for: processed)
        let item = makeItem(from: processed)
        item.createdAt = createdAt
        item.copiedAt = copiedAt
        context.insert(item)
        save(context)
    }

    // MARK: - 取得

    /// 2 ストアを copiedAt 降順でマージ取得する（§2.5）。UI もこの結果だけを描画する
    func fetchHistory(limit: Int? = nil) -> [ClipHistoryItem] {
        let cap = limit ?? settings.historyLimit
        var descriptor = FetchDescriptor<ClipHistoryItem>(
            sortBy: [SortDescriptor(\.copiedAt, order: .reverse)]
        )
        descriptor.fetchLimit = cap
        let main = (try? persistence.mainContainer.mainContext.fetch(descriptor)) ?? []
        let local = (try? persistence.localContainer.mainContext.fetch(descriptor)) ?? []
        return Array((main + local).sorted { $0.copiedAt > $1.copiedAt }.prefix(cap))
    }

    // MARK: - 削除（C-7: 個別 / 全消去 / 自動削除）

    func delete(_ item: ClipHistoryItem) {
        let context = item.modelContext
        context?.delete(item)
        save(context)
    }

    func deleteAll() {
        do {
            try persistence.mainContainer.mainContext.delete(model: ClipHistoryItem.self)
            try persistence.localContainer.mainContext.delete(model: ClipHistoryItem.self)
        } catch {
            logger.error("deleteAll failed: \(error)")
        }
        save(persistence.mainContainer.mainContext)
        save(persistence.localContainer.mainContext)
    }

    /// 画像の履歴だけ削除（Clear History サブメニュー用）
    func deleteAllImages() {
        let raw = ContentKind.image.rawValue
        deleteMatching(#Predicate<ClipHistoryItem> { $0.kindRaw == raw })
    }

    /// クレカ検知項目だけ削除（Clear History サブメニュー用）
    func deleteAllCreditCardItems() {
        let raw = Sensitivity.creditCard.rawValue
        deleteMatching(#Predicate<ClipHistoryItem> { $0.sensitivityRaw == raw })
    }

    /// ConcealedType 由来項目だけ削除（O-3 / 将来の Clear History サブメニュー用）
    func deleteAllConcealedItems() {
        let raw = Sensitivity.concealed.rawValue
        deleteMatching(#Predicate<ClipHistoryItem> { $0.sensitivityRaw == raw })
    }

    private func deleteMatching(_ predicate: Predicate<ClipHistoryItem>) {
        do {
            try persistence.mainContainer.mainContext.delete(model: ClipHistoryItem.self, where: predicate)
            try persistence.localContainer.mainContext.delete(model: ClipHistoryItem.self, where: predicate)
        } catch {
            logger.error("deleteMatching failed: \(error)")
        }
        save(persistence.mainContainer.mainContext)
        save(persistence.localContainer.mainContext)
    }

    /// 自動削除（N-2: 既定 OFF / 有効時は保持日数超過分を削除）
    func pruneExpired(now: Date = Date()) {
        guard settings.autoDeleteEnabled else { return }
        let cutoff = now.addingTimeInterval(-TimeInterval(settings.autoDeleteDays) * 86_400)
        let predicate = #Predicate<ClipHistoryItem> { $0.copiedAt < cutoff }
        do {
            try persistence.mainContainer.mainContext.delete(model: ClipHistoryItem.self, where: predicate)
            try persistence.localContainer.mainContext.delete(model: ClipHistoryItem.self, where: predicate)
        } catch {
            logger.error("pruneExpired failed: \(error)")
        }
        save(persistence.mainContainer.mainContext)
        save(persistence.localContainer.mainContext)
    }

    /// 起動時に 1 回 + 6 時間ごとに自動削除を実行する（§13.5）
    func startMaintenance() {
        pruneExpired()
        // 起動時に既存履歴の重複を一掃する（旧バージョンで残った双子の片付け兼マイグレーション）
        dedupAllTwins()
        guard maintenanceTimer == nil else { return }
        let timer = Timer(timeInterval: 6 * 3_600, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.pruneExpired()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        maintenanceTimer = timer

        // CloudKit インポートが apply を経由せず直接ストアに入った場合の取りこぼし用バックストップ。
        // 通常はローカル apply 時点で fetchAnyTwin が拾うので、これはセーフティネット。
        // 端末跨ぎの重複は同期が無ければ発生しないため、同期 OFF のときは起動しない
        guard settings.syncDecision == .enabled, dedupBackstopTimer == nil else { return }
        let backstop = Timer(timeInterval: dedupBackstopInterval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.dedupAllTwins()
            }
        }
        RunLoop.main.add(backstop, forMode: .common)
        dedupBackstopTimer = backstop
    }

    // MARK: - 端末跨ぎ重複（CloudKit）対策

    /// `NSPersistentStoreRemoteChange` を購読。CloudKit から他端末のレコードが流入したら
    /// debounce してから重複掃除を走らせる（同期は連続でバースト発火しがちなので 1 秒の静粛待ち）
    private func observeRemoteChanges() {
        remoteChangeObserver = NotificationCenter.default.addObserver(
            forName: .NSPersistentStoreRemoteChange,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.scheduleDedup()
            }
        }
    }

    private func scheduleDedup() {
        dedupDebounceTask?.cancel()
        dedupDebounceTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            self?.dedupAllTwins()
        }
    }

    /// 履歴全体から同一 contentHash の重複を掃除し、最新の copiedAt のものだけ残す。
    /// 時間窓は設けない（2026-06-30 裁定: 完全一致は時間問わず必ず 1 件に統合する UX）
    private func dedupAllTwins() {
        let descriptor = FetchDescriptor<ClipHistoryItem>(
            sortBy: [SortDescriptor(\.copiedAt, order: .reverse)]
        )
        let main = (try? persistence.mainContainer.mainContext.fetch(descriptor)) ?? []
        let local = (try? persistence.localContainer.mainContext.fetch(descriptor)) ?? []
        let all = (main + local).sorted { $0.copiedAt > $1.copiedAt }

        var seen: Set<String> = []
        var deleted = 0
        for item in all {
            guard !item.contentHash.isEmpty else { continue }
            if seen.contains(item.contentHash) {
                item.modelContext?.delete(item)
                deleted += 1
            } else {
                seen.insert(item.contentHash)
            }
        }
        if deleted > 0 {
            logger.notice("dedup removed \(deleted, privacy: .public) duplicate(s)")
            save(persistence.mainContainer.mainContext)
            save(persistence.localContainer.mainContext)
        }
    }

    // MARK: - 内部処理

    /// 上限（N-1）を両ストア合算で執行し、古い順に削除する。
    /// 通常は apply が呼ぶ。バッチインポート完了後と設定で上限を下げたときは外から明示的に呼ぶ
    func enforceLimit() {
        let cap = max(1, settings.historyLimit)
        let all = fetchAllSorted()
        guard all.count > cap else { return }
        for item in all[cap...] {
            item.modelContext?.delete(item)
        }
        save(persistence.mainContainer.mainContext)
        save(persistence.localContainer.mainContext)
    }

    /// 全件を copiedAt 降順で取得（上限執行・全件カウント用。fetchLimit なし）
    private func fetchAllSorted() -> [ClipHistoryItem] {
        let descriptor = FetchDescriptor<ClipHistoryItem>(
            sortBy: [SortDescriptor(\.copiedAt, order: .reverse)]
        )
        let main = (try? persistence.mainContainer.mainContext.fetch(descriptor)) ?? []
        let local = (try? persistence.localContainer.mainContext.fetch(descriptor)) ?? []
        return (main + local).sorted { $0.copiedAt > $1.copiedAt }
    }

    private func save(_ context: ModelContext?) {
        guard let context, context.hasChanges else { return }
        do {
            try context.save()
        } catch {
            logger.error("save failed: \(error)")
        }
    }
}
