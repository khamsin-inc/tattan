import AppKit

/// 設定ウィンドウの器。SwiftUI の Settings シーンを AppKit から開く公式 API が無く、
/// 非公式セレクタ（showSettingsWindow:）は macOS 26 で動作しないため、
/// エディタと同じ自前ウィンドウ方式で確実に開く。
@MainActor
final class SettingsWindowController {
    private var window: NSWindow?
    private let makeContent: () -> NSViewController

    init(makeContent: @escaping () -> NSViewController) {
        self.makeContent = makeContent
    }

    func show() {
        if window == nil {
            let newWindow = NSWindow(contentViewController: makeContent())
            newWindow.title = String(localized: "Tattan Settings")
            newWindow.styleMask = [.titled, .closable]
            // 中身が固定サイズ（SettingsView 540×460）なのでフレーム記憶は使わない
            // （過去に保存された潰れたフレームの復元事故も防ぐ）
            newWindow.isReleasedWhenClosed = false
            newWindow.center()
            window = newWindow
        }
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }
}
