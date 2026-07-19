import AppKit
import os

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private(set) var dependencies: AppDependencies?
    private let logger = Logger(subsystem: "jp.khamsin.tattan", category: "launch")

    func applicationDidFinishLaunching(_ notification: Notification) {
        // ユニットテスト実行時はテストホストとして起動されるだけなので、常駐セットアップを行わない
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else { return }

        // K-2（起動 1 秒以内）の検証用に、体感起動 = ステータスアイテム表示までの所要を残す
        let start = ContinuousClock.now
        do {
            let dependencies = try AppDependencies()
            self.dependencies = dependencies
            dependencies.menuBarController.install()
            // notice レベル: info だとプロセス終了時にログが揮発し、後から log show で拾えない
            logger.notice("menu bar ready in \(start.duration(to: .now).description, privacy: .public)")
            dependencies.bootstrap()
        } catch {
            presentFatalError(error)
        }
    }

    /// ストア構築失敗など起動継続不能な異常。メニューバー常駐アプリは通常ウィンドウを
    /// 持たないため、黙って死なずに明示的なアラートを出してから終了する。
    private func presentFatalError(_ error: Error) {
        let alert = NSAlert()
        alert.alertStyle = .critical
        alert.messageText = "Tattan could not start"
        alert.informativeText = error.localizedDescription
        alert.runModal()
        NSApp.terminate(nil)
    }
}
