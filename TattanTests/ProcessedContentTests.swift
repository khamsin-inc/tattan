import AppKit
import Foundation
import Testing
@testable import Tattan

/// 取り込み前処理（ProcessedContent）のテスト。
struct ProcessedContentTests {

    /// 4×4 の PNG を一時ファイルとして作る
    private func makeTempImageFile() throws -> URL {
        let rep = try #require(NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: 4, pixelsHigh: 4,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ))
        let png = try #require(rep.representation(using: .png, properties: [:]))
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ProcessedContentTests-\(UUID().uuidString).png")
        try png.write(to: url)
        return url
    }

    /// 単一の画像ファイルのコピー（Finder ⌘C）はサムネイル付きで履歴に入る（2026-06-12 仕様）
    @Test func singleImageFileGetsThumbnail() throws {
        let url = try makeTempImageFile()
        let content = CapturedContent(kind: .fileReference, plainText: url.path, fileURLs: [url])

        let processed = ProcessedContent(content: content)

        #expect(processed.thumbnailData != nil)
    }

    @Test func nonImageFileHasNoThumbnail() {
        let url = URL(fileURLWithPath: "/tmp/document.pdf")
        let content = CapturedContent(kind: .fileReference, plainText: url.path, fileURLs: [url])

        let processed = ProcessedContent(content: content)

        #expect(processed.thumbnailData == nil)
    }

    @Test func imageFileDetectionByExtension() {
        #expect(ThumbnailRenderer.isImageFile(URL(fileURLWithPath: "/tmp/a.PNG")))
        #expect(ThumbnailRenderer.isImageFile(URL(fileURLWithPath: "/tmp/a.heic")))
        #expect(!ThumbnailRenderer.isImageFile(URL(fileURLWithPath: "/tmp/a.pdf")))
        #expect(!ThumbnailRenderer.isImageFile(URL(fileURLWithPath: "/tmp/noext")))
    }
}
