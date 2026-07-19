import AppKit

/// メニューバー常駐の入口（F-1）と Clipy 型フルドロップダウンメニュー（P-3）。
/// 左右どちらのクリックでも同じネイティブメニューを表示する。
/// メニューは開くたびにフレッシュ構築（§10.2 — 差分監視より単純で確実）。
@MainActor
final class MenuBarController: NSObject, NSMenuDelegate {
    private let settings: SettingsStore
    private let history: HistoryService
    private let snippets: SnippetService
    private let paste: PasteService
    private let monitor: ClipboardMonitor
    private let openEditor: () -> Void
    private let openSettingsWindow: () -> Void
    private let checkForUpdates: () -> Void

    private var statusItem: NSStatusItem?
    private let menu = NSMenu()
    private lazy var clearMenuController = HistoryClearMenuController(history: history)
    /// 11 件目以降のチャンクサブメニューの遅延構築用。キーはサブメニューの identity、
    /// 値はそのチャンクに入る履歴項目。メインメニューを開くたびに rebuild() で作り直す
    private var pendingChunks: [ObjectIdentifier: [ClipHistoryItem]] = [:]

    /// 履歴項目のホバーで出す全文の格納庫。キーは NSMenuItem の identity、値は全文。
    /// NSMenuItem.toolTip を直接セットせず遅延セットするために、ここに保管しておく
    private var pendingToolTips: [ObjectIdentifier: String] = [:]
    /// 遅延セット中のタスク。ホバーが別項目に移ったらキャンセルする
    private var toolTipTask: Task<Void, Never>?

    private static let inlineHistoryCount = 10
    private static let chunkSize = 10
    /// NSMenuItem.toolTip の遅延（SwiftUI `.help()` と揃える。マウス移動と同時に出て
    /// パカパカする macOS 標準挙動を抑える）
    private static let toolTipDelay: Duration = .seconds(1)

    init(
        settings: SettingsStore,
        history: HistoryService,
        snippets: SnippetService,
        paste: PasteService,
        monitor: ClipboardMonitor,
        openEditor: @escaping () -> Void,
        openSettingsWindow: @escaping () -> Void,
        checkForUpdates: @escaping () -> Void
    ) {
        self.settings = settings
        self.history = history
        self.snippets = snippets
        self.paste = paste
        self.monitor = monitor
        self.openEditor = openEditor
        self.openSettingsWindow = openSettingsWindow
        self.checkForUpdates = checkForUpdates
        super.init()
        menu.delegate = self
    }

    func install() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        // モノトーンの template image（F-6）。ダークモード追従は AppKit 任せ（F-5）
        item.button?.image = NSImage(
            systemSymbolName: "doc.on.clipboard",
            accessibilityDescription: "Tattan"
        )
        item.menu = menu
        statusItem = item
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        if menu === self.menu {
            monitor.checkForChanges() // コピー直後に開いた時の取りこぼし防止（§5.1）
            rebuild()
            return
        }
        // 履歴チャンクのサブメニュー: ホバーで開かれた時に一度だけ中身を構築する
        // （上限 1000 件設定でもメニューを開く瞬間が重くならない。2026-07-02 レビュー指摘 #15）
        guard let chunk = pendingChunks.removeValue(forKey: ObjectIdentifier(menu)) else { return }
        for item in chunk {
            menu.addItem(makeHistoryMenuItem(item, index: nil))
        }
    }

    /// メニューアイテムのハイライト（ホバー / キーで移動）に追従して全文ツールチップを遅延セットする。
    /// macOS 標準の NSMenuItem.toolTip は連続ホバーで即座に切り替わってパカパカするので、
    /// SwiftUI `.help()` と揃えて 1 秒遅延で出す
    func menu(_ menu: NSMenu, willHighlight item: NSMenuItem?) {
        toolTipTask?.cancel()
        // 前回セットした toolTip を全部消しておく（別項目に移った瞬間に前の toolTip が
        // 残っていると視覚的にちらつく）
        clearAppliedToolTips(in: menu)

        guard let item, let text = pendingToolTips[ObjectIdentifier(item)] else { return }
        toolTipTask = Task { @MainActor [weak item] in
            try? await Task.sleep(for: Self.toolTipDelay)
            guard !Task.isCancelled, let item else { return }
            item.toolTip = text
        }
    }

    func menuDidClose(_ menu: NSMenu) {
        toolTipTask?.cancel()
        clearAppliedToolTips(in: menu)
    }

    /// メインメニュー・サブメニュー・別項目に付けた toolTip を再帰的に nil に戻す
    private func clearAppliedToolTips(in menu: NSMenu) {
        for menuItem in menu.items {
            if menuItem.toolTip != nil { menuItem.toolTip = nil }
            if let submenu = menuItem.submenu {
                clearAppliedToolTips(in: submenu)
            }
        }
    }

    // MARK: - メニュー構築

    private func rebuild() {
        menu.removeAllItems()
        toolTipTask?.cancel()
        pendingToolTips.removeAll()

        let items = history.fetchHistory()
        if items.isEmpty {
            let empty = NSMenuItem(title: String(localized: "No History"), action: nil, keyEquivalent: "")
            empty.isEnabled = false
            menu.addItem(empty)
        }

        // 先頭 10 件はインライン。1〜9 にはキーイコライバレント（F-3 と同じ操作感）
        for (index, item) in items.prefix(Self.inlineHistoryCount).enumerated() {
            menu.addItem(makeHistoryMenuItem(item, index: index))
            // スニペットはテキスト前提（D-3）なので、画像項目には Option 代替を出さない
            if item.kind != .image {
                menu.addItem(makeSaveAsSnippetAlternate(item, index: index))
            }
        }

        // 11 件目以降は 10 件ごとのサブメニュー（§10.2）。中身の NSMenuItem 構築は
        // menuNeedsUpdate（開かれた時）まで遅延する
        pendingChunks = [:]
        var start = Self.inlineHistoryCount
        while start < items.count {
            let end = min(start + Self.chunkSize, items.count)
            let parent = NSMenuItem(title: "\(start + 1) – \(end)", action: nil, keyEquivalent: "")
            let submenu = NSMenu()
            submenu.delegate = self
            pendingChunks[ObjectIdentifier(submenu)] = Array(items[start..<end])
            parent.submenu = submenu
            menu.addItem(parent)
            start = end
        }

        menu.addItem(.separator())
        addSnippetSection(to: menu)
        menu.addItem(.separator())
        addActionSection(to: menu)
    }

    private func addActionSection(to menu: NSMenu) {
        let editItem = NSMenuItem(
            title: String(localized: "Edit Snippets…"),
            action: #selector(openSnippetEditor), keyEquivalent: ""
        )
        editItem.target = self
        editItem.image = NSImage(systemSymbolName: "square.and.pencil", accessibilityDescription: nil)
        menu.addItem(editItem)

        let settingsItem = NSMenuItem(
            title: String(localized: "Settings…"),
            action: #selector(openSettings), keyEquivalent: ","
        )
        settingsItem.target = self
        menu.addItem(settingsItem)

        // architecture.md §10.2 のメニュー構成通り「アップデートを確認…」を Settings の直下に置く（G-4）
        let updateItem = NSMenuItem(
            title: String(localized: "Check for Updates…"),
            action: #selector(triggerCheckForUpdates), keyEquivalent: ""
        )
        updateItem.target = self
        updateItem.image = NSImage(systemSymbolName: "arrow.down.circle", accessibilityDescription: nil)
        menu.addItem(updateItem)

        menu.addItem(clearMenuController.makeMenuItem())

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(
            title: String(localized: "Quit Tattan"),
            action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"
        ))
    }

    private func makeHistoryMenuItem(_ item: ClipHistoryItem, index: Int?) -> NSMenuItem {
        let title = menuTitle(for: item)
        let menuItem = NSMenuItem(
            title: title,
            action: #selector(pasteHistoryItem(_:)),
            keyEquivalent: keyEquivalent(for: index)
        )
        menuItem.keyEquivalentModifierMask = []
        menuItem.target = self
        menuItem.representedObject = item
        // 履歴が 50 文字カット・改行スペース置換されて切れていたら、ネイティブメニューの
        // ホバーツールチップで全文を出す（ポップアップ版と同じ方針、2026-07-10 Ken 要望）。
        // 画像・機密は fullText が nil を返して自動で抑止される。
        // toolTip を直接セットするとメニュー内でホバーが動く度にパカパカ切り替わる（macOS 標準挙動）
        // ので、辞書に保管しておき willHighlight で 1 秒遅延セットする
        if let tooltip = TruncationHeuristic.tooltip(
            displayed: title,
            fullText: TruncationHeuristic.fullText(
                kind: item.kind,
                sensitivity: item.sensitivity,
                plainText: item.plainText,
                previewText: item.previewText
            ),
            visibleWidth: 0,
            idealWidth: 0
        ) {
            pendingToolTips[ObjectIdentifier(menuItem)] = tooltip
        }

        if let data = item.thumbnailData, let thumbnail = NSImage(data: data) {
            menuItem.image = resized(thumbnail, maxHeight: 24)
        } else if item.sensitivity == .creditCard {
            menuItem.image = NSImage(systemSymbolName: "creditcard", accessibilityDescription: nil)
        } else if item.sensitivity == .concealed {
            menuItem.image = NSImage(systemSymbolName: "key", accessibilityDescription: nil)
        } else if item.kind == .fileReference {
            menuItem.image = NSImage(systemSymbolName: "doc", accessibilityDescription: nil)
        } else if let hex = HexColorParser.firstColor(in: item.previewText) {
            // 履歴でもカラーコードはスウォッチ表示（D-6 の履歴版）
            menuItem.image = Self.swatchImage(for: hex)
        }
        return menuItem
    }

    private static func swatchImage(for color: HexColor) -> NSImage {
        let size = NSSize(width: 14, height: 14)
        return NSImage(size: size, flipped: false) { rect in
            let path = NSBezierPath(roundedRect: rect.insetBy(dx: 1, dy: 1), xRadius: 4, yRadius: 4)
            NSColor(
                red: color.red, green: color.green, blue: color.blue, alpha: color.alpha
            ).setFill()
            path.fill()
            NSColor.separatorColor.setStroke()
            path.lineWidth = 1
            path.stroke()
            return true
        }
    }

    /// Option 押しで「スニペットとして保存」に切り替わる代替項目（Q-1 の第 2 動線）
    private func makeSaveAsSnippetAlternate(_ item: ClipHistoryItem, index: Int) -> NSMenuItem {
        let alternate = NSMenuItem(
            title: String(localized: "Save as Snippet: \(menuTitle(for: item))"),
            action: #selector(saveAsSnippet(_:)),
            keyEquivalent: keyEquivalent(for: index)
        )
        alternate.keyEquivalentModifierMask = .option
        alternate.isAlternate = true
        alternate.target = self
        alternate.representedObject = item
        return alternate
    }

    /// タグのグループをメニュー直下に直接並べる（中間の「Snippets ▸」階層は挟まない。
    /// 2026-06-12 Ken の実機フィードバックによる変更）。タグなしスニペットは
    /// 「Snippets ▸」サブメニューにまとめる。
    private func addSnippetSection(to menu: NSMenu) {
        let allSnippets = snippets.fetchSnippets()
        guard !allSnippets.isEmpty else { return }

        for tag in snippets.fetchTags() {
            let tagged = allSnippets.filter { ($0.tags ?? []).contains { $0 === tag } }
            guard !tagged.isEmpty else { continue }
            let tagItem = NSMenuItem(title: tag.name, action: nil, keyEquivalent: "")
            let tagMenu = NSMenu()
            for snippet in tagged {
                tagMenu.addItem(makeSnippetMenuItem(snippet))
            }
            tagItem.submenu = tagMenu
            menu.addItem(tagItem)
        }

        // グループ無しのスニペットは包まず直置き（グループと同じ階層に並ぶ）
        let untagged = allSnippets.filter { ($0.tags ?? []).isEmpty }
        for snippet in untagged {
            menu.addItem(makeSnippetMenuItem(snippet))
        }
    }

    private func makeSnippetMenuItem(_ snippet: Snippet) -> NSMenuItem {
        let title = snippet.title.isEmpty ? String(localized: "Untitled") : snippet.title
        let item = NSMenuItem(title: title, action: #selector(pasteSnippet(_:)), keyEquivalent: "")
        item.target = self
        item.representedObject = snippet
        return item
    }

    // MARK: - アクション

    @objc private func pasteHistoryItem(_ sender: NSMenuItem) {
        guard let item = sender.representedObject as? ClipHistoryItem else { return }
        Task { await paste.paste(item) }
    }

    @objc private func pasteSnippet(_ sender: NSMenuItem) {
        guard let snippet = sender.representedObject as? Snippet else { return }
        Task { await paste.paste(snippet) }
    }

    @objc private func saveAsSnippet(_ sender: NSMenuItem) {
        guard let item = sender.representedObject as? ClipHistoryItem else { return }
        snippets.promote(item)
        openEditor()
    }

    @objc private func openSnippetEditor() {
        openEditor()
    }

    @objc private func openSettings() {
        openSettingsWindow()
    }

    @objc private func triggerCheckForUpdates() {
        checkForUpdates()
    }

    // MARK: - 表示ヘルパー

    private func menuTitle(for item: ClipHistoryItem) -> String {
        if item.kind == .image {
            return String(localized: "Image")
        }
        let preview = String(item.previewText.prefix(settings.previewLength))
            .replacingOccurrences(of: "\n", with: " ")
        return preview.isEmpty ? String(localized: "(Empty)") : preview
    }

    /// 1〜9 はそのまま、10 件目はキーボードで 9 の右隣にある「0」を割り当てる
    /// （インライン 10 件を全部キー操作できるように。2026-06-13 Ken 要望）
    private func keyEquivalent(for index: Int?) -> String {
        guard let index, index < 10 else { return "" }
        return index == 9 ? "0" : String(index + 1)
    }

    private func resized(_ image: NSImage, maxHeight: CGFloat) -> NSImage {
        let size = image.size
        guard size.height > maxHeight, size.height > 0 else { return image }
        let scale = maxHeight / size.height
        let copy = image.copy() as? NSImage ?? image
        copy.size = NSSize(width: size.width * scale, height: maxHeight)
        return copy
    }
}
