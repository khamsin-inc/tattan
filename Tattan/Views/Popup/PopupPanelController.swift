import AppKit
import os
import SwiftUI

/// フォーカスを奪わずキー入力だけ受け取るパネル（§10.3）。
/// 対象アプリが active なまま数字キー・矢印で選べるのが 2 モード構成（P-3）の要。
final class NonActivatingPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// ポップアップの器（AppKit）。表示位置・キーモニタ・サイズ永続化（F-8）を担当し、
/// 中身は SwiftUI（PopupRootView）に委譲する。
@MainActor
final class PopupPanelController: NSObject, NSWindowDelegate {
    private let panel: NonActivatingPanel
    let viewModel: PopupViewModel
    private var keyMonitor: Any?
    private var generation = 0

    private let monitor: ClipboardMonitor
    private let history: HistoryService
    private let snippets: SnippetService
    private let settings: SettingsStore
    private let defaults = UserDefaults.standard
    private static let heightKey = "popupPanelHeight"
    private static let defaultHeight: CGFloat = 440

    init(
        monitor: ClipboardMonitor,
        history: HistoryService,
        snippets: SnippetService,
        settings: SettingsStore
    ) {
        self.monitor = monitor
        self.history = history
        self.snippets = snippets
        self.settings = settings
        viewModel = PopupViewModel()

        panel = NonActivatingPanel(
            contentRect: NSRect(origin: .zero, size: NSSize(width: 360, height: Self.defaultHeight)),
            styleMask: [.nonactivatingPanel, .borderless, .resizable],
            backing: .buffered,
            defer: true
        )
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]

        super.init()
        panel.delegate = self
        viewModel.onDismiss = { [weak self] in self?.hide() }
    }

    private static let logger = Logger(subsystem: "jp.khamsin.tattan", category: "popup")

    func show(mode: PopupMode) {
        let start = ContinuousClock.now
        monitor.checkForChanges() // コピー直後に開いた時の取りこぼし防止（§5.1）
        let historyItems = history.fetchHistory()
        viewModel.configure(
            mode: mode,
            historyItems: historyItems,
            snippetGroups: buildSnippetGroups(),
            previewLength: settings.previewLength,
            fontScale: settings.uiScale
        )
        // offscreen のパネル内の SwiftUI は rootView 差し替え（世代番号付き）でも
        // 古い描画のまま残った（2026-06-12 実機で段階的に確認）。表示のたびに
        // NSHostingView ごと作り直して、描画ツリーを確実に新規構築する
        generation += 1
        panel.contentView = NSHostingView(
            rootView: PopupRootView(model: viewModel, generation: generation)
        )
        positionNearCursor()
        panel.makeKeyAndOrderFront(nil)
        installKeyMonitor()
        // K-3（呼び出し→表示 100ms 以内）の検証用。実描画はこの直後のフレームで行われる。
        // notice レベル: info だとプロセス終了時に揮発して後から log show で拾えない
        Self.logger.notice("""
        popup shown in \(start.duration(to: .now).description, privacy: .public) \
        (history: \(historyItems.count))
        """)
    }

    func hide() {
        saveSize()
        removeKeyMonitor()
        panel.orderOut(nil)
    }

    var isVisible: Bool { panel.isVisible }

    /// メニューバーメニューと同じ構造（グループ submenu + グループ無し）を 2 カラム用に組む
    private func buildSnippetGroups() -> [PopupViewModel.SnippetGroup] {
        let allSnippets = snippets.fetchSnippets()
        var groups: [PopupViewModel.SnippetGroup] = []
        for tag in snippets.fetchTags() {
            let tagged = allSnippets.filter { ($0.tags ?? []).contains { $0 === tag } }
            if !tagged.isEmpty {
                groups.append(PopupViewModel.SnippetGroup(name: tag.name, iconName: tag.iconName, snippets: tagged))
            }
        }
        let untagged = allSnippets.filter { ($0.tags ?? []).isEmpty }
        if !untagged.isEmpty {
            groups.append(PopupViewModel.SnippetGroup(name: nil, iconName: nil, snippets: untagged))
        }
        return groups
    }

    /// パネル外クリック等でキーを失ったら閉じる
    func windowDidResignKey(_ notification: Notification) {
        hide()
    }

    // MARK: - 配置（F-2: カーソル近く + 画面内クランプ）

    private func positionNearCursor() {
        let size = savedSize()
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1280, height: 800)

        var origin = NSPoint(x: mouse.x + 8, y: mouse.y - size.height - 8)
        origin.x = min(max(origin.x, visible.minX), visible.maxX - size.width)
        origin.y = min(max(origin.y, visible.minY), visible.maxY - size.height)
        panel.setFrame(NSRect(origin: origin, size: size), display: true)
    }

    /// 幅は設定値（General タブのスライダー）、高さは前回の手動リサイズを引き継ぐ
    private func savedSize() -> NSSize {
        let height = defaults.object(forKey: Self.heightKey) as? Double ?? Self.defaultHeight
        return NSSize(width: CGFloat(settings.popupWidth), height: height)
    }

    /// 手動リサイズの結果を保存。幅は設定値へ書き戻して双方向に同期させる
    private func saveSize() {
        guard panel.isVisible else { return }
        settings.popupWidth = Int(panel.frame.width)
        defaults.set(Double(panel.frame.height), forKey: Self.heightKey)
    }

    // MARK: - キーボード（F-3）

    private func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let keyCode = event.keyCode
            let characters = event.charactersIgnoringModifiers
            let handled = MainActor.assumeIsolated { () -> Bool in
                guard let self, self.panel.isKeyWindow else { return false }
                return self.viewModel.handleKey(keyCode: keyCode, characters: characters)
            }
            return handled ? nil : event
        }
    }

    private func removeKeyMonitor() {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
        }
        keyMonitor = nil
    }
}
