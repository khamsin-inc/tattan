import AppKit

/// Clear History ▸ サブメニュー（全消去 / 画像のみ / クレカ検知のみ。すべて確認付き）。
/// メニュー項目のターゲットとして生存し続ける必要があるため、MenuBarController が保持する。
@MainActor
final class HistoryClearMenuController: NSObject {
    private let history: HistoryService

    init(history: HistoryService) {
        self.history = history
    }

    func makeMenuItem() -> NSMenuItem {
        let parent = NSMenuItem(title: String(localized: "Clear History"), action: nil, keyEquivalent: "")
        parent.image = NSImage(systemSymbolName: "trash", accessibilityDescription: nil)
        let submenu = NSMenu()

        let allItem = NSMenuItem(title: String(localized: "Clear All…"),
                                 action: #selector(clearAll), keyEquivalent: "")
        allItem.target = self
        submenu.addItem(allItem)

        let imagesItem = NSMenuItem(title: String(localized: "Clear Images…"),
                                    action: #selector(clearImages), keyEquivalent: "")
        imagesItem.target = self
        imagesItem.image = NSImage(systemSymbolName: "photo", accessibilityDescription: nil)
        submenu.addItem(imagesItem)

        let cardsItem = NSMenuItem(title: String(localized: "Clear Credit Card Items…"),
                                   action: #selector(clearCreditCards), keyEquivalent: "")
        cardsItem.target = self
        cardsItem.image = NSImage(systemSymbolName: "creditcard", accessibilityDescription: nil)
        submenu.addItem(cardsItem)

        parent.submenu = submenu
        return parent
    }

    @objc private func clearAll() {
        // 誤爆防止に確認を挟む（P-2 で専用ショートカットを作らなかったのと同じ思想）
        confirmAndRun(
            message: String(localized: "Clear all history?"),
            informative: String(localized: "This removes every clipboard history item. Snippets are not affected."),
            confirmTitle: String(localized: "Clear History")
        ) { [weak self] in
            self?.history.deleteAll()
        }
    }

    @objc private func clearImages() {
        confirmAndRun(
            message: String(localized: "Clear all image items?"),
            informative: String(localized: "This removes every image from the clipboard history."),
            confirmTitle: String(localized: "Clear Images")
        ) { [weak self] in
            self?.history.deleteAllImages()
        }
    }

    @objc private func clearCreditCards() {
        confirmAndRun(
            message: String(localized: "Clear credit card items?"),
            informative: String(localized: "This removes every history item detected as a credit card number."),
            confirmTitle: String(localized: "Clear Credit Card Items")
        ) { [weak self] in
            self?.history.deleteAllCreditCardItems()
        }
    }

    private func confirmAndRun(
        message: String, informative: String, confirmTitle: String, action: () -> Void
    ) {
        let alert = NSAlert()
        alert.messageText = message
        alert.informativeText = informative
        alert.addButton(withTitle: confirmTitle)
        alert.addButton(withTitle: String(localized: "Cancel"))
        NSApp.activate()
        if alert.runModal() == .alertFirstButtonReturn {
            action()
        }
    }
}
