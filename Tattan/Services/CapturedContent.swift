import AppKit

/// 1 回のコピーから抽出した内容。種別は §5.2 の優先順位（fileURL > image > RTF > text）で確定済み。
/// ペースト忠実度のため、従属 representation（richText のプレーンテキスト等）も一緒に保持する。
struct CapturedContent: Sendable {
    var kind: ContentKind
    var plainText: String?
    var rtfData: Data?
    var imageData: Data?
    var fileURLs: [URL] = []
    /// クリップボードに `org.nspasteboard.ConcealedType` マーカーが付いていたか（O-3）。
    /// ClipboardMonitor が検出して載せる。ProcessedContent.init が sensitivity 確定に使う
    var hasConcealedMarker: Bool = false

    /// E-1 同期サイズ閾値の判定に使う実体サイズ。
    /// fileReference はファイル中身をコピーしない（§3）ためパス文字列のサイズになる
    var byteSize: Int {
        switch kind {
        case .text, .fileReference:
            return plainText.map { $0.utf8.count } ?? 0
        case .richText:
            return (rtfData?.count ?? 0) + (plainText.map { $0.utf8.count } ?? 0)
        case .image:
            return imageData?.count ?? 0
        }
    }

    /// C-9 重複判定ハッシュの主ペイロード
    var primaryPayload: Data {
        switch kind {
        case .text, .fileReference:
            return Data((plainText ?? "").utf8)
        case .richText:
            return rtfData ?? Data((plainText ?? "").utf8)
        case .image:
            return imageData ?? Data()
        }
    }
}

extension CapturedContent {
    /// ペーストボードから §5.2 の優先順位で抽出する。取り出せるものが無ければ nil
    @MainActor
    static func read(from pasteboard: NSPasteboard) -> CapturedContent? {
        if let urls = pasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) as? [URL], !urls.isEmpty {
            let joinedPaths = urls.map(\.path).joined(separator: "\n")
            return CapturedContent(kind: .fileReference, plainText: joinedPaths, fileURLs: urls)
        }
        if let imageData = pasteboard.data(forType: .png) ?? pasteboard.data(forType: .tiff) {
            return CapturedContent(kind: .image, imageData: imageData)
        }
        if let rtfData = pasteboard.data(forType: .rtf) {
            return CapturedContent(kind: .richText, plainText: pasteboard.string(forType: .string), rtfData: rtfData)
        }
        if let string = pasteboard.string(forType: .string), !string.isEmpty {
            return CapturedContent(kind: .text, plainText: string)
        }
        return nil
    }
}

/// 背景キューで前処理済みの取り込みデータ（§1.5: ハッシュ・Luhn・サムネイルはメインを塞がない）。
struct ProcessedContent: Sendable {
    let content: CapturedContent
    let contentHash: String
    let sensitivity: Sensitivity
    let previewText: String
    let thumbnailData: Data?

    var byteSize: Int { content.byteSize }

    init(content: CapturedContent) {
        self.content = content
        contentHash = ContentHasher.hash(kind: content.kind, payload: content.primaryPayload)

        // §6.3 判定順序: クレカ判定が ConcealedType より優先（1Password はクレカにも
        // ConcealedType を付けるため。仕様 O-3）
        let isCreditCard = content.plainText
            .map { SensitiveContentClassifier.containsCreditCardNumber(in: $0) } ?? false
        if isCreditCard {
            sensitivity = .creditCard
        } else if content.hasConcealedMarker {
            sensitivity = .concealed
        } else {
            sensitivity = .none
        }

        // previewText は sensitivity に応じて表示時ではなく保存時にマスクする
        // （生のパスワード文字列が一覧/メニュー/どの描画パスにも出ない構造にする）
        let source = content.plainText ?? ""
        let previewSource: String
        switch sensitivity {
        case .creditCard:
            // マスク → 先頭 500 文字の順（逆だと途中で切れた番号がマスクをすり抜ける §6.3）
            previewSource = SensitiveContentClassifier.maskingCardNumbers(in: source)
        case .concealed:
            previewSource = "••••••••"
        case .none:
            previewSource = source
        }
        previewText = String(previewSource.prefix(500))

        var thumbnail = content.imageData.flatMap { ThumbnailRenderer.thumbnailJPEG(from: $0) }
        // 単一の画像ファイルのコピー（Finder ⌘C）は履歴でも画像として見せる
        // （2026-06-12 Ken フィードバック。実体は取り込まずサムネイルだけ生成）
        if thumbnail == nil, content.kind == .fileReference,
           content.fileURLs.count == 1, let url = content.fileURLs.first,
           ThumbnailRenderer.isImageFile(url) {
            thumbnail = ThumbnailRenderer.thumbnailJPEG(forImageFileAt: url)
        }
        thumbnailData = thumbnail
    }
}
