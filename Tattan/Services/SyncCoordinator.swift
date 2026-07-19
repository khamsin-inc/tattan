import AppKit
import CloudKit
import CoreData
import Observation
import os

/// iCloud 同期のライフサイクル管理（E-2〜E-5 / §4）。
/// 同期処理そのものは SwiftData + CloudKit のミラーリングに全面委任し（§4.3, §4.4）、
/// ここは ① 初回ダイアログ（E-5）② アカウント状態の表示 ③ 再起動方式での ON/OFF 反映
/// （2026-06-12 裁定: ホットスワップはしない）④ 同期アクティビティの可視化
/// （最終同期時刻・連続エラー検知。2026-07-18「同期が 1 ヶ月詰まっても気付けない」事故対策）を担う。
@MainActor
@Observable
final class SyncCoordinator {

    enum DisplayStatus {
        case enabled
        case disabled
        /// 設定上は ON だが CloudKit ストア構築に失敗し、今回の起動はローカル動作
        case enabledButDegraded
        case noAccount
    }

    private enum Keys {
        static let lastSyncedAt = "syncLastSyncedAt"
    }

    /// この回数連続でミラーリングイベントが失敗したら「詰まっている」とみなして UI に警告を出す
    private static let failureAlertThreshold = 3

    @ObservationIgnored private let settings: SettingsStore
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let logger = Logger(subsystem: "jp.khamsin.tattan", category: "sync")
    @ObservationIgnored private var syncEventObserver: NSObjectProtocol?

    /// 起動時に CloudKit 付きストアの構築へ失敗してローカルへフォールバックしたか（§16 安全網）
    let isDegraded: Bool

    private(set) var accountStatus: CKAccountStatus?

    /// 最後に import/export イベントが成功した時刻。再起動を跨いで保持する
    /// （「最終同期が 3 日前のまま」という形で詰まりに気付けるようにする）
    private(set) var lastSyncedAt: Date?
    private(set) var lastErrorMessage: String?
    private(set) var consecutiveFailures = 0

    var isLikelyFailing: Bool { consecutiveFailures >= Self.failureAlertThreshold }

    init(settings: SettingsStore, isDegraded: Bool, defaults: UserDefaults = .standard) {
        self.settings = settings
        self.isDegraded = isDegraded
        self.defaults = defaults
        lastSyncedAt = defaults.object(forKey: Keys.lastSyncedAt) as? Date
    }

    var displayStatus: DisplayStatus {
        if settings.syncDecision == .enabled {
            return isDegraded ? .enabledButDegraded : .enabled
        }
        if let accountStatus, accountStatus != .available {
            return .noAccount
        }
        return .disabled
    }

    var isSyncEnabled: Bool { settings.syncDecision == .enabled }

    func refreshAccountStatus() async {
        accountStatus = try? await CKContainer.default().accountStatus()
    }

    // MARK: - 同期アクティビティの可視化（2026-07-18 事故対策）

    /// SwiftData の CloudKit ミラーリングが内部で使う NSPersistentCloudKitContainer の
    /// イベント通知（setup / import / export の完了と成否）を購読する。
    /// 同期 OFF・degraded 時はイベント自体が発生しないので購読しない。
    func startActivityMonitoring() {
        guard isSyncEnabled, !isDegraded, syncEventObserver == nil else { return }
        syncEventObserver = NotificationCenter.default.addObserver(
            forName: NSPersistentCloudKitContainer.eventChangedNotification,
            object: nil,
            queue: nil
        ) { [weak self] notification in
            // endDate なし = 開始通知なのでスキップ。Event は Sendable でないため
            // 必要な値だけ取り出してから MainActor へ渡す
            guard let event = notification.userInfo?[
                NSPersistentCloudKitContainer.eventNotificationUserInfoKey
            ] as? NSPersistentCloudKitContainer.Event,
                let endDate = event.endDate else { return }
            let isDataTransfer = event.type == .import || event.type == .export
            let errorDescription = event.error?.localizedDescription
            Task { @MainActor [weak self] in
                self?.recordSyncEvent(
                    endDate: endDate,
                    isDataTransfer: isDataTransfer,
                    errorDescription: errorDescription
                )
            }
        }
    }

    /// イベント 1 件ぶんの状態遷移。成功で失敗カウンタをリセットし、
    /// import/export の成功だけを「最終同期」として記録する（setup はデータ転送ではない）
    func recordSyncEvent(endDate: Date, isDataTransfer: Bool, errorDescription: String?) {
        if let errorDescription {
            consecutiveFailures += 1
            lastErrorMessage = errorDescription
            logger.error("sync event failed (\(self.consecutiveFailures) in a row): \(errorDescription)")
        } else {
            consecutiveFailures = 0
            lastErrorMessage = nil
            if isDataTransfer {
                lastSyncedAt = endDate
                defaults.set(endDate, forKey: Keys.lastSyncedAt)
            }
        }
    }

    /// E-5: 初回起動ダイアログ。「はい、使う」が既定ボタン（Enter で押せる）。
    /// iCloud 未ログインならログイン案内を出して disabled 扱い（設定からいつでも再試行可）
    func presentFirstRunDialogIfNeeded() async {
        guard settings.syncDecision == .undecided else { return }
        await refreshAccountStatus()

        guard accountStatus == .available else {
            presentNoAccountNotice()
            settings.syncDecision = .disabled
            return
        }

        let alert = NSAlert()
        alert.messageText = String(localized: "Sync with iCloud?")
        alert.informativeText = String(localized: """
        Snippets and clipboard history can sync across your Macs via iCloud. \
        You can change this anytime in Settings.
        """)
        alert.addButton(withTitle: String(localized: "Yes, Use iCloud"))
        alert.addButton(withTitle: String(localized: "Not Now"))
        NSApp.activate()
        if alert.runModal() == .alertFirstButtonReturn {
            settings.syncDecision = .enabled
            relaunch()
        } else {
            settings.syncDecision = .disabled
        }
    }

    /// 設定画面からの ON/OFF 切替（再起動して反映 §4.5）
    func setSyncEnabled(_ enabled: Bool) {
        settings.syncDecision = enabled ? .enabled : .disabled
        relaunch()
    }

    private func presentNoAccountNotice() {
        let alert = NSAlert()
        alert.messageText = String(localized: "iCloud is not available")
        alert.informativeText = String(localized: """
        Sign in to iCloud in System Settings, then turn on sync from Tattan's settings.
        """)
        alert.addButton(withTitle: String(localized: "OK"))
        NSApp.activate()
        alert.runModal()
    }

    /// 新しいインスタンスを起動してから自分を終了する（設定反映の再起動方式）
    private func relaunch() {
        AppRelauncher.relaunch()
    }
}

/// アプリ自身の再起動（設定反映の再起動方式で共用。2026-07-02 レビュー指摘 #9 で
/// SyncCoordinator / GeneralSettingsView の重複実装を統合）。
/// 新インスタンスの起動が成功したときだけ現プロセスを終了する —
/// 起動に失敗したのに terminate すると、アプリがただ消えて再起動もされない。
@MainActor
enum AppRelauncher {
    private static let logger = Logger(subsystem: "jp.khamsin.tattan", category: "relaunch")

    static func relaunch() {
        let bundleURL = Bundle.main.bundleURL
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: bundleURL, configuration: configuration) { _, error in
            Task { @MainActor in
                if let error {
                    Self.logger.error("relaunch failed: \(error)")
                } else {
                    NSApp.terminate(nil)
                }
            }
        }
    }
}
