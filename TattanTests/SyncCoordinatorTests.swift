import Foundation
import Testing
@testable import Tattan

/// SyncCoordinator の同期アクティビティ記録（recordSyncEvent）の状態遷移を検証。
/// NSPersistentCloudKitContainer の実イベント受信は CloudKit 環境が要るため実機確認とし、
/// ここではイベント値を直接流し込んで「最終同期時刻・連続失敗カウンタ」の挙動だけを見る。
@MainActor
struct SyncCoordinatorTests {

    private func makeCoordinator() throws -> (SyncCoordinator, UserDefaults, String) {
        let suiteName = "TattanTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        let settings = SettingsStore(defaults: defaults)
        settings.syncDecision = .enabled
        let coordinator = SyncCoordinator(settings: settings, isDegraded: false, defaults: defaults)
        return (coordinator, defaults, suiteName)
    }

    @Test func successfulDataTransferRecordsLastSyncedAt() throws {
        let (coordinator, defaults, suiteName) = try makeCoordinator()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let syncedAt = Date(timeIntervalSince1970: 1_752_800_000)

        coordinator.recordSyncEvent(endDate: syncedAt, isDataTransfer: true, errorDescription: nil)

        #expect(coordinator.lastSyncedAt == syncedAt)
        // 再起動を跨いで表示できるよう UserDefaults にも保存される
        #expect(defaults.object(forKey: "syncLastSyncedAt") as? Date == syncedAt)
    }

    @Test func setupEventDoesNotTouchLastSyncedAt() throws {
        let (coordinator, defaults, suiteName) = try makeCoordinator()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        coordinator.recordSyncEvent(endDate: .now, isDataTransfer: false, errorDescription: nil)

        #expect(coordinator.lastSyncedAt == nil)
    }

    @Test func consecutiveFailuresRaiseWarningAtThreshold() throws {
        let (coordinator, defaults, suiteName) = try makeCoordinator()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        for _ in 0..<2 {
            coordinator.recordSyncEvent(endDate: .now, isDataTransfer: true, errorDescription: "CKError 12")
        }
        #expect(!coordinator.isLikelyFailing)

        coordinator.recordSyncEvent(endDate: .now, isDataTransfer: true, errorDescription: "CKError 12")
        #expect(coordinator.isLikelyFailing)
        #expect(coordinator.lastErrorMessage == "CKError 12")
        // 失敗イベントでは最終同期時刻を進めない
        #expect(coordinator.lastSyncedAt == nil)
    }

    @Test func anySuccessResetsFailureStreak() throws {
        let (coordinator, defaults, suiteName) = try makeCoordinator()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        for _ in 0..<3 {
            coordinator.recordSyncEvent(endDate: .now, isDataTransfer: true, errorDescription: "boom")
        }
        #expect(coordinator.isLikelyFailing)

        // setup の成功でもカウンタは解除される（ミラーリングが息を吹き返した証拠なので）
        coordinator.recordSyncEvent(endDate: .now, isDataTransfer: false, errorDescription: nil)

        #expect(!coordinator.isLikelyFailing)
        #expect(coordinator.lastErrorMessage == nil)
    }

    @Test func lastSyncedAtIsRestoredFromDefaults() throws {
        let suiteName = "TattanTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let stored = Date(timeIntervalSince1970: 1_752_700_000)
        defaults.set(stored, forKey: "syncLastSyncedAt")
        let settings = SettingsStore(defaults: defaults)

        let coordinator = SyncCoordinator(settings: settings, isDegraded: false, defaults: defaults)

        #expect(coordinator.lastSyncedAt == stored)
    }
}
