import AppKit

/// スニペットエディタの器（§10.4）。メニューバー常駐アプリのため SwiftUI の Window シーン
/// ではなく AppKit ウィンドウで管理する（AppKit からの表示制御を単純にするため）。
@MainActor
final class EditorWindowController {
    private var window: NSWindow?
    private let makeContent: () -> NSViewController

    init(makeContent: @escaping () -> NSViewController) {
        self.makeContent = makeContent
    }

    func show() {
        if window == nil {
            let newWindow = NSWindow(contentViewController: makeContent())
            newWindow.title = String(localized: "Snippets")
            newWindow.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            // 3 カラム（グループ / 一覧 / 編集）が収まる幅
            newWindow.setContentSize(NSSize(width: 940, height: 540))
            newWindow.setFrameAutosaveName("SnippetEditorWindow")
            newWindow.isReleasedWhenClosed = false
            newWindow.center()
            window = newWindow
        }
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }
}
