import AppKit
import SwiftUI

/// 全 Service を生成・配線する手書き DI コンテナ（architecture.md §1.2）。
/// 組み立てとライフサイクル管理のみを担い、ビジネスロジックは持たない。
@MainActor
final class AppDependencies {
    let settings: SettingsStore
    let persistence: PersistenceController
    let historyService: HistoryService
    let snippetService: SnippetService
    let clipboardMonitor: ClipboardMonitor
    let permissions: PermissionService
    let pasteService: PasteService
    let hotkeyService: HotkeyService
    let launchAtLogin: LaunchAtLoginService
    let importExport: ImportExportService
    let syncCoordinator: SyncCoordinator
    let syncReset: SyncResetService
    let updater: UpdaterService
    let editorController: EditorWindowController
    let settingsWindowController: SettingsWindowController
    let popupController: PopupPanelController
    let menuBarController: MenuBarController

    // DI コンテナの init は「全 Service の生成 + プロパティ代入」の列挙が本体のため行数制限を抑制
    // swiftlint:disable:next function_body_length
    init() throws {
        let settings = SettingsStore()
        // 言語は TattanLauncher で AppleLanguages へ既に反映済み（プロセス最初期）
        // 同期リセット（設定 > Data）の再起動フラグが立っていれば、ストア構築前に
        // Main ストアを退避する。ModelContainer が開く前でないと安全に動かせない
        SyncResetService.performPendingStoreResetIfNeeded()
        // iCloud 同期の ON/OFF（E-5）。反映は再起動方式（2026-06-12 裁定）のため
        // 起動時のここで一度だけ決まる。CloudKit 付きストアの構築に失敗した場合は
        // ローカル動作にフォールバックして起動を続ける（起動不能にしない §16）
        let (persistence, syncDegraded): (PersistenceController, Bool) = try {
            let wantsCloudKit = settings.syncDecision == .enabled
            do {
                return (try PersistenceController(cloudKitEnabled: wantsCloudKit), false)
            } catch where wantsCloudKit {
                return (try PersistenceController(cloudKitEnabled: false), true)
            }
        }()
        let syncCoordinator = SyncCoordinator(settings: settings, isDegraded: syncDegraded)
        let historyService = HistoryService(persistence: persistence, settings: settings)
        let snippetService = SnippetService(persistence: persistence)
        let clipboardMonitor = ClipboardMonitor(settings: settings, history: historyService)
        let permissions = PermissionService()
        let pasteService = PasteService(
            monitor: clipboardMonitor,
            history: historyService,
            templateInput: TemplateInputCoordinator(),
            permissions: permissions
        )
        let hotkeyService = HotkeyService(snippets: snippetService, permissions: permissions)
        let launchAtLogin = LaunchAtLoginService()
        let importExport = ImportExportService(history: historyService, snippets: snippetService)
        let syncReset = SyncResetService(importExport: importExport)
        let updater = UpdaterService()

        let editorController = EditorWindowController {
            NSHostingController(
                rootView: SnippetEditorView()
                    .modelContainer(persistence.mainContainer)
                    .environment(snippetService)
                    .environment(hotkeyService)
                    .environment(settings)
            )
        }
        let settingsWindowController = SettingsWindowController {
            NSHostingController(
                rootView: SettingsView()
                    .environment(settings)
                    .environment(launchAtLogin)
                    .environment(hotkeyService)
                    .environment(permissions)
                    .environment(historyService)
                    .environment(importExport)
                    .environment(syncCoordinator)
                    .environment(syncReset)
                    .environment(updater)
            )
        }
        let popupController = PopupPanelController(
            monitor: clipboardMonitor,
            history: historyService,
            snippets: snippetService,
            settings: settings
        )
        let menuBarController = MenuBarController(
            settings: settings,
            history: historyService,
            snippets: snippetService,
            paste: pasteService,
            monitor: clipboardMonitor,
            openEditor: { editorController.show() },
            openSettingsWindow: { settingsWindowController.show() },
            checkForUpdates: { updater.checkForUpdates() }
        )

        Self.wire(
            popup: popupController,
            hotkeys: hotkeyService,
            paste: pasteService,
            history: historyService,
            snippets: snippetService,
            editor: editorController
        )

        self.settings = settings
        self.persistence = persistence
        self.historyService = historyService
        self.snippetService = snippetService
        self.clipboardMonitor = clipboardMonitor
        self.permissions = permissions
        self.pasteService = pasteService
        self.hotkeyService = hotkeyService
        self.launchAtLogin = launchAtLogin
        self.importExport = importExport
        self.syncCoordinator = syncCoordinator
        self.syncReset = syncReset
        self.updater = updater
        self.editorController = editorController
        self.settingsWindowController = settingsWindowController
        self.popupController = popupController
        self.menuBarController = menuBarController
    }

    /// イベント配線: ポップアップの操作 → ペースト / 昇格（Q-1）/ 削除（C-7）、
    /// ホットキー → ポップアップ（P-2 の 3 枠）/ スニペット即ペースト（D-5）。
    /// 配線対象の列挙が本体のためパラメータ数制限は抑制。
    private static func wire( // swiftlint:disable:this function_parameter_count
        popup: PopupPanelController,
        hotkeys: HotkeyService,
        paste: PasteService,
        history: HistoryService,
        snippets: SnippetService,
        editor: EditorWindowController
    ) {
        popup.viewModel.onPasteHistory = { item in
            popup.hide()
            Task { await paste.paste(item) }
        }
        popup.viewModel.onPasteSnippet = { snippet in
            popup.hide()
            Task { await paste.paste(snippet) }
        }
        popup.viewModel.onSaveAsSnippet = { item in
            popup.hide()
            snippets.promote(item)
            editor.show()
        }
        // 個別削除はポップアップを閉じない（ゴミ箱アイコンで連続削除できるように）
        popup.viewModel.onDeleteHistory = { item in
            history.delete(item)
        }
        hotkeys.onPopupTrigger = { mode in
            popup.show(mode: mode)
        }
        hotkeys.onSnippetTrigger = { uuid in
            guard let snippet = snippets.snippet(uuid: uuid) else { return }
            Task { await paste.paste(snippet) }
        }
    }

    /// 常駐機能の開始。ステータスアイテム表示（K-2 の体感起動）より後に呼ぶ（§1.2 の 2 段階起動）
    func bootstrap() {
        // 外観プリファレンス（F-5）を NSApp に反映。SwiftUI ルート・NSMenu・NSPanel を一括同期
        settings.appearance.applyToApp()
        snippetService.mergeDuplicateTags() // 同期マージ起因の同名タグを起動時リペア（§2.4）
        SyncResetService.pruneOldBackups() // 退避ストアの溜まりすぎ防止（5 世代残し。~/Downloads は対象外）
        historyService.startMaintenance()
        clipboardMonitor.start()
        hotkeyService.start()
        launchAtLogin.applyDefaultIfNeeded()
        syncCoordinator.startActivityMonitoring() // 最終同期時刻・連続エラーの記録（2026-07-18 事故対策）
        // Sparkle は起動パスから外す（K-2）ため、bootstrap の非同期タスク側で始動する
        updater.start()
        // 初回起動の案内は順番に: iCloud（E-5）→ Accessibility（§11）。
        // E-5 で「はい」を選ぶと再起動されるため、その場合の権限案内は次回起動で出る
        Task { [weak self] in
            // 同期リセット（replaceCloud）後の再インポート。まっさらなゾーンへ再アップロードされる
            await self?.syncReset.performPendingImportIfNeeded()
            await self?.syncCoordinator.presentFirstRunDialogIfNeeded()
            self?.promptAccessibilityOnFirstLaunch()
        }
    }

    /// ダブルタップ・自動ペーストの前提となる Accessibility 権限を、初回起動時に
    /// 一度だけシステムダイアログで案内する（本格的なオンボーディング §11 は Phase 2.6 で）
    private func promptAccessibilityOnFirstLaunch() {
        let key = "didPromptAccessibility"
        guard !permissions.isAccessibilityTrusted, !UserDefaults.standard.bool(forKey: key) else { return }
        UserDefaults.standard.set(true, forKey: key)
        permissions.promptForAccessibility()
    }
}
