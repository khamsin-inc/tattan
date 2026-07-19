import AppKit
import CloudKit
import Foundation
import Observation
import os

/// iCloud 同期のリセット（同期が詰んだ時・クラウドを作り直したい時の復旧手段）。
///
/// 2 方向を提供する:
/// - `replaceCloud`: iCloud 側のゾーンを削除し、この Mac のデータで作り直す
/// - `replaceLocal`: この Mac の同期ストアを退避し、iCloud から取り直す
///
/// どちらも「JSON スナップショット保全 → （ゾーン削除）→ 再起動フラグ → 再起動」で、
/// 実際のストア退避は次回起動の最初期（PersistenceController 構築前）に行う。
/// 起動中の ModelContainer が掴んでいるストアファイルを動かすのは危険なため。
/// LocalOnly ストア（機微情報・巨大項目 = 同期対象外データ）には一切触れない。
@MainActor
@Observable
final class SyncResetService {

    enum Direction {
        /// iCloud のデータを消して、この Mac のデータで置き換える
        case replaceCloud
        /// この Mac の同期データを捨てて、iCloud から取り直す
        case replaceLocal
    }

    private enum Keys {
        static let pendingStoreReset = "pendingSyncStoreReset"
        static let pendingImportPath = "pendingSyncResetImportPath"
    }

    /// CoreData+CloudKit ミラーリングが使う固定ゾーン名（§4）
    private static let mirroringZoneName = "com.apple.coredata.cloudkit.zone"

    private(set) var isWorking = false

    @ObservationIgnored private let importExport: ImportExportService
    @ObservationIgnored private let logger = Logger(subsystem: "jp.khamsin.tattan", category: "syncReset")

    init(importExport: ImportExportService) {
        self.importExport = importExport
    }

    // MARK: - リセット実行（再起動前フェーズ）

    /// スナップショット保全 → （replaceCloud ならゾーン削除）→ 再起動。
    /// ゾーン削除に失敗した場合は throw して何も変えない（ローカルは無傷のまま）。
    func reset(_ direction: Direction) async throws {
        guard !isWorking else { return }
        isWorking = true
        defer { isWorking = false }

        // 1. どちらの方向でも、先に全データを JSON で保全する（事故時の最後の砦）。
        //    保存先は ~/Downloads — Application Support は一般ユーザーが辿り着けない（2026-07-18 Ken 指摘）
        let snapshotURL = Self.downloadsDirectory
            .appendingPathComponent("Tattan-backup-\(Self.timestamp()).json")
        try importExport.exportData(includeHistory: true).write(to: snapshotURL)
        logger.info("pre-reset snapshot saved: \(snapshotURL.path)")

        // 2. replaceCloud はクラウド側のゾーンを先に削除（失敗したらここで中断）
        if direction == .replaceCloud {
            try await deleteCloudZone()
            // 次回起動でスナップショットを再インポート → まっさらなゾーンへ再アップロード
            UserDefaults.standard.set(snapshotURL.path, forKey: Keys.pendingImportPath)
        }

        // 3. 再起動直前にバックアップの保存先を案内する（後から確実に見つけられるように）
        presentBackupNotice(fileName: snapshotURL.lastPathComponent)

        // 4. 次回起動の最初期に Main ストアを退避するフラグを立てて再起動
        UserDefaults.standard.set(true, forKey: Keys.pendingStoreReset)
        AppRelauncher.relaunch()
    }

    // MARK: - 起動時フック

    /// 起動の最初期（PersistenceController 構築前）に呼ぶ。
    /// リセットフラグが立っていれば Main ストア一式を Backups へ退避し、新規作成に備える。
    /// 失敗時の無限ループを避けるため、フラグは処理前に必ず消す。
    static func performPendingStoreResetIfNeeded(
        directory: URL = PersistenceController.defaultDirectory,
        defaults: UserDefaults = .standard
    ) {
        guard defaults.bool(forKey: Keys.pendingStoreReset) else { return }
        defaults.removeObject(forKey: Keys.pendingStoreReset)

        let fileManager = FileManager.default
        let destination = directory
            .appendingPathComponent("Backups", isDirectory: true)
            .appendingPathComponent("\(timestamp())-store", isDirectory: true)
        do {
            try fileManager.createDirectory(at: destination, withIntermediateDirectories: true)
        } catch {
            return // 退避先が作れないならストアに触らない（次回起動は通常通り）
        }
        // Main ストア関連のみ。LocalOnly（同期対象外データ）は絶対に動かさない
        let mainStoreItems = ["Main.store", "Main.store-shm", "Main.store-wal", ".Main_SUPPORT", "Main_ckAssets"]
        for name in mainStoreItems {
            let source = directory.appendingPathComponent(name)
            guard fileManager.fileExists(atPath: source.path) else { continue }
            try? fileManager.moveItem(at: source, to: destination.appendingPathComponent(name))
        }
    }

    /// 起動後（Service 稼働後）に呼ぶ。replaceCloud のスナップショット再インポートを行う。
    func performPendingImportIfNeeded() async {
        guard let path = UserDefaults.standard.string(forKey: Keys.pendingImportPath) else { return }
        UserDefaults.standard.removeObject(forKey: Keys.pendingImportPath)
        do {
            let data = try Data(contentsOf: URL(fileURLWithPath: path))
            try await importExport.importData(data)
            logger.info("post-reset import finished: \(path)")
        } catch {
            // インポートに失敗してもスナップショット自体は Backups に残っている
            logger.error("post-reset import failed: \(error)")
        }
    }

    // MARK: - バックアップ掃除

    /// Backups 配下（退避ストア・旧形式の JSON スナップショット）を新しい順に
    /// `keeping` 世代だけ残して削除する。起動時に呼ぶ。
    /// ~/Downloads に保存したバックアップ JSON はユーザーの持ち物なので絶対に触れない。
    static func pruneOldBackups(
        directory: URL = PersistenceController.defaultDirectory,
        keeping: Int = 5
    ) {
        let backups = directory.appendingPathComponent("Backups", isDirectory: true)
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: backups, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
        ) else { return } // Backups がまだ無ければ何もしない
        // エントリ名はタイムスタンプ（yyyy-MM-dd_HHmmss[-store]）なので名前の降順 = 新しい順
        let sorted = entries.sorted { $0.lastPathComponent > $1.lastPathComponent }
        for url in sorted.dropFirst(keeping) {
            try? FileManager.default.removeItem(at: url)
        }
    }

    // MARK: - 内部処理

    /// バックアップ JSON の保存先を伝えてから再起動する。
    /// リセット直後に「データはどこ?」と不安にさせないための一手間。
    private func presentBackupNotice(fileName: String) {
        let alert = NSAlert()
        alert.messageText = String(localized: "Backup saved to Downloads")
        alert.informativeText = String(localized: """
        A backup of all your data was saved as "\(fileName)" in your Downloads folder. \
        Tattan will now relaunch to apply the reset.
        """)
        alert.addButton(withTitle: String(localized: "OK"))
        NSApp.activate()
        alert.runModal()
    }

    /// ミラーリングゾーンを private DB から削除する。ゾーンが元々無い場合は成功扱い。
    private func deleteCloudZone() async throws {
        let zoneID = CKRecordZone.ID(zoneName: Self.mirroringZoneName, ownerName: CKCurrentUserDefaultName)
        let results = try await CKContainer.default().privateCloudDatabase
            .modifyRecordZones(saving: [], deleting: [zoneID])
        if case .failure(let error) = results.deleteResults[zoneID] {
            if let ckError = error as? CKError, ckError.code == .zoneNotFound {
                logger.info("cloud zone already absent; treating as success")
                return
            }
            throw error
        }
        logger.info("cloud zone deleted")
    }

    /// 非サンドボックスなので実ユーザーの ~/Downloads に直接書ける
    private static var downloadsDirectory: URL {
        FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Downloads", isDirectory: true)
    }

    private static func timestamp() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd_HHmmss"
        return formatter.string(from: Date())
    }
}
