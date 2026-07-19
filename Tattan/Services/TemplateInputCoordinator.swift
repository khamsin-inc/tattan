import AppKit
import SwiftUI

/// {{ask}} / {{choose}} の入力フォームを 1 枚のウィンドウで表示し、回答を集める（§9.3）。
/// フォーム表示は自アプリを activate するため、確定後は元のアプリへフォーカスを返してから
/// ペーストに進む（フォーカスジャグリングをここに閉じ込める）。
@MainActor
final class TemplateInputCoordinator: NSObject, NSWindowDelegate {

    struct Field: Identifiable {
        let id: Int            // TemplateNode の配列 index
        let label: String
        let defaultValue: String
        let options: [String]? // choose のときのみ
    }

    private var window: NSWindow?
    private var finishHandler: (([Int: String]?) -> Void)?
    /// 現在有効な入力セッションの識別子。古いセッションの finish が遅延発火しても
    /// 新しいセッションを巻き込まない（continuation の二重 resume 防止。
    /// 2026-07-02 レビュー指摘 #8）
    private var sessionID = UUID()

    /// interactive ノードが無ければ即 [:] を返す。ユーザーキャンセル時は nil（= ペースト中止）
    func collectAnswers(for nodes: [TemplateNode]) async -> [Int: String]? {
        let fields = nodes.enumerated().compactMap { index, node -> Field? in
            switch node {
            case .ask(let label, let defaultValue):
                return Field(id: index, label: label, defaultValue: defaultValue ?? "", options: nil)
            case .choose(let options):
                return Field(id: index, label: String(localized: "Choose"),
                             defaultValue: options.first ?? "", options: options)
            default:
                return nil
            }
        }
        guard !fields.isEmpty else { return [:] }

        // 既に別のフォームが開いていたらキャンセル扱いで畳む
        finishHandler?(nil)

        let previousApp = NSWorkspace.shared.frontmostApplication
        let session = UUID()
        sessionID = session

        return await withCheckedContinuation { continuation in
            let finish: ([Int: String]?) -> Void = { [weak self] answers in
                // sessionID の一致で「自分のセッションがまだ有効か」を確認する。
                // finishHandler の有無だけだと、別セッション稼働中に古い finish が
                // そのセッションを閉じて自分の continuation を二重 resume しうる
                guard let self, self.sessionID == session, self.finishHandler != nil else { return }
                self.finishHandler = nil
                let window = self.window
                self.window = nil
                window?.delegate = nil
                window?.close()
                // 対象アプリへフォーカスを返してからペーストへ（§9.3）
                previousApp?.activate()
                continuation.resume(returning: answers)
            }
            finishHandler = finish

            let form = TemplateInputFormView(
                fields: fields,
                onCommit: { finish($0) },
                onCancel: { finish(nil) }
            )
            let hosting = NSHostingController(rootView: form)
            let window = NSWindow(contentViewController: hosting)
            window.title = String(localized: "Snippet Input")
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.level = .floating
            window.delegate = self
            window.center()
            self.window = window
            NSApp.activate()
            window.makeKeyAndOrderFront(nil)
        }
    }

    /// 閉じるボタン（×）で閉じられた場合もキャンセルとして continuation を解決する
    func windowWillClose(_ notification: Notification) {
        finishHandler?(nil)
    }
}
