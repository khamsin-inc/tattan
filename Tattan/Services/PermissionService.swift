import AppKit
import ApplicationServices
import Observation

/// Accessibility 権限の確認・誘導（§11）。
/// 権限が無くてもアプリは劣化モード（履歴記録 + 手動ペースト）で動き続ける。
@MainActor
@Observable
final class PermissionService {
    private var didShowPasteHint = false
    @ObservationIgnored private var activationObserver: NSObjectProtocol?

    /// AXIsProcessTrusted() のキャッシュ。computed のままだと @Observable の変更通知が
    /// 発火せず、システム設定で許可して戻ってきても設定画面の警告が消えなかった
    /// （2026-07-02 レビュー指摘 #6）。アプリがアクティブになるたびに refresh() で読み直す
    private(set) var isAccessibilityTrusted = false

    /// 現在の Pasteboard アクセス許可状態のキャッシュ（O-4 / macOS 26 Tahoe）。
    /// 既定 OFF の間は `.alwaysAllow` 相当が返る想定。Apple がデフォルト ON にした後は
    /// `.askEveryTime` / `.alwaysDeny` が起きうる
    private(set) var pasteboardAccessBehavior: NSPasteboard.AccessBehavior = .alwaysAllow

    init() {
        refresh()
        // 権限の付け外しはシステム設定側で起きるので、Tattan に戻ってきた
        // タイミング（didBecomeActive）で拾い直すのが最小コストで確実
        activationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refresh()
            }
        }
    }

    /// 権限状態を OS から読み直してキャッシュを更新する
    func refresh() {
        isAccessibilityTrusted = AXIsProcessTrusted()
        pasteboardAccessBehavior = NSPasteboard.general.accessBehavior
    }

    /// システム標準の許可ダイアログを表示する（一覧への追加も行われる）
    func promptForAccessibility() {
        // kAXTrustedCheckOptionPrompt は Swift 6 並行性検査に通らないグローバル変数のため、
        // その実体である固定文字列を直接使う
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }

    func openAccessibilitySettings() {
        let urlString = "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        guard let url = URL(string: urlString) else { return }
        NSWorkspace.shared.open(url)
    }

    // MARK: - Pasteboard Privacy (O-4 / macOS 26 Tahoe)

    /// `.alwaysAllow` のときだけ Tattan の挙動に影響なし
    var isPasteboardAccessAllowed: Bool {
        pasteboardAccessBehavior == .alwaysAllow
    }

    /// System Settings > Privacy & Security > "Paste from Other Apps" を開く
    func openPasteboardSettings() {
        let urlString = "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Pasteboard"
        guard let url = URL(string: urlString) else { return }
        NSWorkspace.shared.open(url)
    }

    /// 自動ペーストが権限不足でフォールバックした時の案内。
    /// 毎回出すと鬱陶しいのでセッション中 1 回だけ（§7.2）
    func noteAccessibilityNeededForPaste() {
        guard !didShowPasteHint else { return }
        didShowPasteHint = true

        let alert = NSAlert()
        alert.messageText = String(localized: "Enable auto-paste")
        alert.informativeText = String(localized: """
        The item was copied to the clipboard — press ⌘V to paste it. \
        To let Tattan paste automatically, allow Accessibility access in System Settings.
        """)
        alert.addButton(withTitle: String(localized: "Open System Settings"))
        alert.addButton(withTitle: String(localized: "Later"))
        NSApp.activate()
        if alert.runModal() == .alertFirstButtonReturn {
            promptForAccessibility()
            openAccessibilitySettings()
        }
    }
}
