import AppKit
import ImageIO

/// 一覧表示専用のサムネイル生成（§3）。
/// 原本は externalStorage で遅延ロードし、一覧 UI はこのサムネイルだけを描画する（K-1/K-3）。
enum ThumbnailRenderer {
    /// 長辺の上限（px）。JPEG 圧縮と合わせて 1 件あたり目標 50KB 以下に収める
    static let maxDimension: CGFloat = 200

    private static let imageExtensions: Set<String> = [
        "png", "jpg", "jpeg", "gif", "heic", "heif", "tiff", "tif", "webp", "bmp"
    ]

    static func isImageFile(_ url: URL) -> Bool {
        imageExtensions.contains(url.pathExtension.lowercased())
    }

    /// 画像ファイルからのサムネイル生成。CGImageSource のダウンサンプリングを使い、
    /// ファイル全体をメモリに載せない（Finder でコピーした巨大画像でも安全 §3）
    static func thumbnailJPEG(forImageFileAt url: URL) -> Data? {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithURL(url as CFURL, sourceOptions) else { return nil }
        return thumbnailJPEG(source: source)
    }

    /// 生成失敗時は nil（UI 側は種別アイコンにフォールバックする）。
    /// NSImage.size（ポイント）基準だと Retina 画像のピクセル数を過小評価するため、
    /// ファイル版と同じ CGImageSource のピクセル基準ダウンサンプリングに統一
    /// （2026-07-02 レビュー指摘 #12）
    static func thumbnailJPEG(from imageData: Data) -> Data? {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(imageData as CFData, sourceOptions) else { return nil }
        return thumbnailJPEG(source: source)
    }

    private static func thumbnailJPEG(source: CGImageSource) -> Data? {
        let thumbnailOptions = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: Int(maxDimension)
        ] as CFDictionary
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions) else {
            return nil
        }
        return NSBitmapImageRep(cgImage: cgImage)
            .representation(using: .jpeg, properties: [.compressionFactor: 0.7])
    }
}
