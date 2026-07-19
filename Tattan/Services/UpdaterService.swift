import AppKit
import Observation
import OSLog
import Sparkle

/// Sparkle 自動アップデート（要件 G-4）のラッパ。
///
/// - `startingUpdater: false` で初期化して、起動パスから外す（K-2 起動 1 秒予算）。
///   `start()` は `AppDependencies.bootstrap()` から非同期で呼ばれる
/// - `automaticallyChecksForUpdates` を SwiftUI で observe できるよう `@Observable`
/// - Sparkle の delegate は使わない。プライバシー要件（K-4）はシステムプロファイル送信を
///   OFF（Info.plist の `SUSendsSystemProfile=false`）で達成しており、追加のフックは不要
@MainActor
@Observable
final class UpdaterService {
    private let controller: SPUStandardUpdaterController
    @ObservationIgnored private let logger = Logger(subsystem: "jp.khamsin.tattan", category: "updater")

    /// 手動チェックを有効化してよいか（Sparkle がバックオフ中は false になる）。
    /// ボタン UI の enabled/disabled バインディング用
    var canCheckForUpdates: Bool = true

    init() {
        controller = SPUStandardUpdaterController(
            startingUpdater: false,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        // controller.updater は SPUUpdater。canCheckForUpdates は KVO 対応。
        // Sparkle 2.x では SPUStandardUpdaterController がそのまま observable のブリッジになる
        canCheckForUpdates = controller.updater.canCheckForUpdates
    }

    /// バックグラウンドチェックの開始。起動パスから外すため、AppDependencies.bootstrap の
    /// 非同期タスク側から呼ぶ。start() は Info.plist に必須キーが揃っていない場合に
    /// throw するが、アプリの他機能はそのまま使えるようログだけ残す
    func start() {
        do {
            try controller.updater.start()
        } catch {
            logger.error("Sparkle updater failed to start: \(error, privacy: .public)")
        }
        canCheckForUpdates = controller.updater.canCheckForUpdates
    }

    /// メニューバー「アップデートを確認…」/ About の「Check for Updates」ボタンから呼ぶ手動チェック
    func checkForUpdates() {
        controller.checkForUpdates(nil)
    }

    /// General 設定「自動でアップデートを確認」トグルの読み書き
    var automaticallyChecksForUpdates: Bool {
        get { controller.updater.automaticallyChecksForUpdates }
        set { controller.updater.automaticallyChecksForUpdates = newValue }
    }
}
