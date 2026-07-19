import Foundation
import Testing
@testable import Tattan

/// SyncResetService の起動時ストア退避（performPendingStoreResetIfNeeded）の検証。
/// クラウドゾーン削除・再起動を伴うフルフローは entitlements + iCloud アカウントが
/// 必要なため実機確認とし、ここではファイル退避とフラグの挙動だけを検証する。
@MainActor
struct SyncResetServiceTests {

    /// テストごとに使い捨ての一時ディレクトリと UserDefaults suite を用意する
    private func makeSandbox() throws -> (directory: URL, defaults: UserDefaults, suiteName: String) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("TattanTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let suiteName = "TattanTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        return (directory, defaults, suiteName)
    }

    private func writeStoreFiles(in directory: URL) throws {
        for name in ["Main.store", "Main.store-shm", "Main.store-wal", "LocalOnly.store"] {
            try Data("dummy".utf8).write(to: directory.appendingPathComponent(name))
        }
        try FileManager.default.createDirectory(
            at: directory.appendingPathComponent("Main_ckAssets", isDirectory: true),
            withIntermediateDirectories: true
        )
    }

    @Test func movesMainStoreAsideWhenFlagIsSet() throws {
        let (directory, defaults, suiteName) = try makeSandbox()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        try writeStoreFiles(in: directory)
        defaults.set(true, forKey: "pendingSyncStoreReset")

        SyncResetService.performPendingStoreResetIfNeeded(directory: directory, defaults: defaults)

        let fileManager = FileManager.default
        // Main ストア一式は退避され、元の場所から消えている
        #expect(!fileManager.fileExists(atPath: directory.appendingPathComponent("Main.store").path))
        #expect(!fileManager.fileExists(atPath: directory.appendingPathComponent("Main.store-shm").path))
        #expect(!fileManager.fileExists(atPath: directory.appendingPathComponent("Main.store-wal").path))
        #expect(!fileManager.fileExists(atPath: directory.appendingPathComponent("Main_ckAssets").path))
        // LocalOnly（同期対象外の機微情報側）は残っている
        #expect(fileManager.fileExists(atPath: directory.appendingPathComponent("LocalOnly.store").path))
        // フラグは消えている（次回起動でループしない）
        #expect(!defaults.bool(forKey: "pendingSyncStoreReset"))
        // 退避先 Backups 配下に移動済みのストアが存在する
        let backups = directory.appendingPathComponent("Backups", isDirectory: true)
        let movedStores = try fileManager.contentsOfDirectory(atPath: backups.path)
        #expect(movedStores.count == 1)
        let movedDir = backups.appendingPathComponent(movedStores[0], isDirectory: true)
        #expect(fileManager.fileExists(atPath: movedDir.appendingPathComponent("Main.store").path))
    }

    @Test func prunesOldBackupsKeepingNewestGenerations() throws {
        let (directory, defaults, suiteName) = try makeSandbox()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let backups = directory.appendingPathComponent("Backups", isDirectory: true)
        // 退避ストアと旧形式 JSON ディレクトリが混在していても、名前順（= 時系列）で数える
        let names = [
            "2026-07-10_090000", "2026-07-11_090000-store", "2026-07-12_090000",
            "2026-07-13_090000-store", "2026-07-14_090000", "2026-07-15_090000-store",
            "2026-07-16_090000-store"
        ]
        for name in names {
            try FileManager.default.createDirectory(
                at: backups.appendingPathComponent(name, isDirectory: true),
                withIntermediateDirectories: true
            )
        }

        SyncResetService.pruneOldBackups(directory: directory, keeping: 5)

        let remaining = try FileManager.default.contentsOfDirectory(atPath: backups.path).sorted()
        #expect(remaining == Array(names.suffix(5)))
    }

    @Test func pruneDoesNothingWithoutBackupsDirectory() throws {
        let (directory, defaults, suiteName) = try makeSandbox()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        SyncResetService.pruneOldBackups(directory: directory, keeping: 5)

        // Backups ディレクトリを勝手に作らない
        let backups = directory.appendingPathComponent("Backups", isDirectory: true)
        #expect(!FileManager.default.fileExists(atPath: backups.path))
    }

    @Test func doesNothingWhenFlagIsAbsent() throws {
        let (directory, defaults, suiteName) = try makeSandbox()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        try writeStoreFiles(in: directory)

        SyncResetService.performPendingStoreResetIfNeeded(directory: directory, defaults: defaults)

        let fileManager = FileManager.default
        #expect(fileManager.fileExists(atPath: directory.appendingPathComponent("Main.store").path))
        #expect(!fileManager.fileExists(atPath: directory.appendingPathComponent("Backups").path))
    }
}
