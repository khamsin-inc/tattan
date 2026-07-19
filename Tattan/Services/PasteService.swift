import AppKit
import os

/// 選択 → 自動ペーストの実行（F-4 / §7）。
/// ペーストボードへの書き戻し → 自己取り込み防止 → CGEvent で Cmd+V 送出、の一本道。
@MainActor
final class PasteService {
    private let pasteboard = NSPasteboard.general
    private let monitor: ClipboardMonitor
    private let history: HistoryService
    private let templateInput: TemplateInputCoordinator
    private let permissions: PermissionService
    private let logger = Logger(subsystem: "jp.khamsin.tattan", category: "paste")

    private let vKeyCode: CGKeyCode = 9          // kVK_ANSI_V
    private let leftArrowKeyCode: CGKeyCode = 123 // kVK_LeftArrow

    init(
        monitor: ClipboardMonitor,
        history: HistoryService,
        templateInput: TemplateInputCoordinator,
        permissions: PermissionService
    ) {
        self.monitor = monitor
        self.history = history
        self.templateInput = templateInput
        self.permissions = permissions
    }

    // MARK: - 履歴項目のペースト

    func paste(_ item: ClipHistoryItem) async {
        // ペーストボードを上書きする前に、直前のコピー（ポーリング 0.5 秒の窓）を必ず回収する。
        // ポップアップ/メニュー経由は表示時に回収済みだが、スニペット個別ホットキー等の
        // 直接経路では未回収のままここに来る（2026-07-02 レビュー指摘 #4）
        monitor.checkForChanges()
        pasteboard.clearContents()
        switch item.kind {
        case .text:
            pasteboard.setString(item.plainText ?? "", forType: .string)
        case .richText:
            // 保存済みの全 representation を書き戻して書式を保つ（§5.2 / §7）
            if let rtfData = item.rtfData {
                pasteboard.setData(rtfData, forType: .rtf)
            }
            pasteboard.setString(item.plainText ?? "", forType: .string)
        case .image:
            // 取り込み時の元形式（png/tiff）に依存しないよう NSImage 経由で複数 rep を提供する
            if let data = item.binaryData, let image = NSImage(data: data) {
                pasteboard.writeObjects([image])
            }
        case .fileReference:
            let urls = (item.filePathsJoined ?? "")
                .split(separator: "\n")
                .map { URL(fileURLWithPath: String($0)) }
            if urls.count == 1, let url = urls.first, ThumbnailRenderer.isImageFile(url),
               let pngData = Self.pngData(forImageFileAt: url) {
                // 単一の画像ファイルは「ファイル参照 + 画像データ」を 1 アイテムに両載せする。
                // Finder にはファイル複製、画像を受け付けるアプリには画像が入る（2026-06-12 Ken 要望）
                let pasteboardItem = NSPasteboardItem()
                pasteboardItem.setString(url.absoluteString, forType: .fileURL)
                pasteboardItem.setData(pngData, forType: .png)
                pasteboard.writeObjects([pasteboardItem])
            } else {
                pasteboard.writeObjects(urls as [NSURL])
            }
        }
        monitor.ignoredChangeCount = pasteboard.changeCount
        // 履歴からのペースト = その内容が最新のクリップボード。先頭に浮上させる（§7 [4]）
        history.markPasted(item)
        await sendPasteKeystroke(cursorOffsetFromEnd: nil)
    }

    // MARK: - スニペットのペースト（テンプレート展開込み §9.3）

    func paste(_ snippet: Snippet) async {
        // 上と同じ理由で、上書き前に直前のコピーを履歴へ回収しておく
        monitor.checkForChanges()
        let nodes = TemplateParser.parse(snippet.content)

        var answers: [Int: String] = [:]
        if nodes.contains(where: \.isInteractive) {
            guard let collected = await templateInput.collectAnswers(for: nodes) else {
                return // キャンセル = ペースト中止
            }
            answers = collected
            // フォームから対象アプリへのフォーカス復帰を待つ
            try? await Task.sleep(for: .milliseconds(120))
        }

        // {{clipboard}} は自分が上書きする「前」のペーストボードを読む（§9.3 の順序固定）
        let environment = TemplateEnvironment(clipboardText: pasteboard.string(forType: .string))
        let rendered = TemplateRenderer.render(nodes, answers: answers, environment: environment)

        pasteboard.clearContents()
        pasteboard.setString(rendered.text, forType: .string)
        monitor.ignoredChangeCount = pasteboard.changeCount
        await sendPasteKeystroke(cursorOffsetFromEnd: rendered.cursorOffsetFromEnd)
    }

    // MARK: - キーストローク送出

    private func sendPasteKeystroke(cursorOffsetFromEnd: Int?) async {
        // キャッシュ（isAccessibilityTrusted）はアクティブ化時にしか更新されないため、
        // ペースト直前は必ず OS から読み直す。Tattan を一度もアクティブにせず
        // 権限だけ付与されたケースでも自動ペーストが即座に有効になる
        permissions.refresh()
        guard permissions.isAccessibilityTrusted else {
            // フォールバック: クリップボードに積むだけ + 1 回だけ案内（§7.2）
            permissions.noteAccessibilityNeededForPaste()
            return
        }
        try? await Task.sleep(for: .milliseconds(80)) // フォーカス安定待ち（§7 [5]）
        postKey(vKeyCode, flags: .maskCommand)

        if let offset = cursorOffsetFromEnd, offset > 0 {
            // {{cursor}}: ペースト反映を待ってから ← を送る（§9.4 ベストエフォート）
            try? await Task.sleep(for: .milliseconds(150))
            for _ in 0..<offset {
                postKey(leftArrowKeyCode, flags: [])
            }
        }
    }

    /// ペースト時のみファイルから画像を読み出して PNG 化する（履歴 DB には実体を持たない §3）
    private static func pngData(forImageFileAt url: URL) -> Data? {
        guard let image = NSImage(contentsOf: url),
              let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .png, properties: [:])
    }

    private func postKey(_ keyCode: CGKeyCode, flags: CGEventFlags) {
        let source = CGEventSource(stateID: .combinedSessionState)
        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false) else {
            logger.error("CGEvent creation failed")
            return
        }
        keyDown.flags = flags
        keyUp.flags = flags
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
    }
}
