import Foundation
import SwiftData

/// 2 コンテナ戦略（architecture.md §2.2）の実装。
///
/// - `mainContainer`: 同期可ストア（Snippet / Tag / ClipHistoryItem）。
///   同期 ON のときだけ CloudKit ミラーリング（`.automatic` = entitlements のコンテナを使用）
/// - `localContainer`: 同期除外専用ストア（ClipHistoryItem のみ）。
///   クレカ検知（O-2）・サイズ閾値超（E-1）の履歴が入り、絶対に iCloud へ出ない
///
/// 同期 ON/OFF の切替は再起動方式（2026-06-12 裁定, §4.5）のため、
/// ホットスワップ用の再構築 API は持たない。起動時の `cloudKitEnabled` で確定する。
@MainActor
final class PersistenceController {
    let mainContainer: ModelContainer
    let localContainer: ModelContainer

    static var defaultDirectory: URL {
        URL.applicationSupportDirectory.appendingPathComponent("Tattan", isDirectory: true)
    }

    /// 旧アプリ名（Simple Copy Memo）時代のデータフォルダからの一回限りの移行
    /// （2026-06-12 の Tattan 改名でフォルダ名が変わったため。移行後は何もしない）
    private static func migrateLegacyDirectoryIfNeeded() {
        let fileManager = FileManager.default
        let legacy = URL.applicationSupportDirectory
            .appendingPathComponent("SimpleCopyMemo", isDirectory: true)
        guard fileManager.fileExists(atPath: legacy.path),
              !fileManager.fileExists(atPath: defaultDirectory.path) else { return }
        try? fileManager.moveItem(at: legacy, to: defaultDirectory)
    }

    init(directory: URL = PersistenceController.defaultDirectory,
         cloudKitEnabled: Bool = false) throws {
        // テストは一時ディレクトリを渡すため、実データの移行は既定パスのときだけ行う
        if directory == Self.defaultDirectory {
            Self.migrateLegacyDirectoryIfNeeded()
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let mainSchema = Schema([Snippet.self, Tag.self, ClipHistoryItem.self])
        let mainConfiguration = ModelConfiguration(
            "Main",
            schema: mainSchema,
            url: directory.appendingPathComponent("Main.store"),
            cloudKitDatabase: cloudKitEnabled ? .automatic : .none
        )
        mainContainer = try ModelContainer(for: mainSchema, configurations: [mainConfiguration])

        let localSchema = Schema([ClipHistoryItem.self])
        let localConfiguration = ModelConfiguration(
            "LocalOnly",
            schema: localSchema,
            url: directory.appendingPathComponent("LocalOnly.store"),
            cloudKitDatabase: .none
        )
        localContainer = try ModelContainer(for: localSchema, configurations: [localConfiguration])
    }
}
