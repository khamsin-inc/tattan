import Foundation
import Observation
import os

/// JSON でのインポート / エクスポート（M-1 / §13.1）。
/// 単一 JSON ファイル・画像は Base64 埋め込み（依存ライブラリを増やさない 2026-06-12 裁定 #5）。
/// クレカ検知項目は平文ファイルに書き出さないため常に除外（O-2 の精神）。
@MainActor
@Observable
final class ImportExportService {

    struct ExportFile: Codable {
        var format = "tattan-export"
        var version = 1
        var exportedAt: Date
        var tags: [TagDTO]
        var snippets: [SnippetDTO]
        var history: [HistoryDTO]?
    }

    struct TagDTO: Codable {
        var name: String
        var sortOrder: Int
    }

    struct SnippetDTO: Codable {
        var title: String
        var content: String
        var tags: [String]
        var sortOrder: Int
        var hotkey: Data?
    }

    struct HistoryDTO: Codable {
        var kind: String
        var createdAt: Date
        var copiedAt: Date
        var plainText: String?
        var rtfBase64: String?
        var imageBase64: String?
        var filePaths: [String]?
    }

    enum ImportError: LocalizedError {
        case invalidFormat
        var errorDescription: String? {
            String(localized: "This file is not a Tattan export.")
        }
    }

    @ObservationIgnored private let history: HistoryService
    @ObservationIgnored private let snippets: SnippetService

    init(history: HistoryService, snippets: SnippetService) {
        self.history = history
        self.snippets = snippets
    }

    // MARK: - エクスポート

    func exportData(includeHistory: Bool) throws -> Data {
        let tagDTOs = snippets.fetchTags().map { TagDTO(name: $0.name, sortOrder: $0.sortOrder) }
        let snippetDTOs = snippets.fetchSnippets().map { snippet in
            SnippetDTO(
                title: snippet.title,
                content: snippet.content,
                tags: (snippet.tags ?? []).map(\.name).sorted(),
                sortOrder: snippet.sortOrder,
                hotkey: snippet.hotkeyData
            )
        }
        var historyDTOs: [HistoryDTO]?
        if includeHistory {
            historyDTOs = history.fetchHistory()
                .filter { $0.sensitivity == .none } // O-2/O-3: 機微情報（クレカ/Concealed）は書き出さない
                .map { item in
                    HistoryDTO(
                        kind: item.kindRaw,
                        createdAt: item.createdAt,
                        copiedAt: item.copiedAt,
                        plainText: item.plainText,
                        rtfBase64: item.rtfData?.base64EncodedString(),
                        imageBase64: item.binaryData?.base64EncodedString(),
                        filePaths: item.filePathsJoined.map { $0.components(separatedBy: "\n") }
                    )
                }
        }

        let file = ExportFile(
            exportedAt: Date(),
            tags: tagDTOs,
            snippets: snippetDTOs,
            history: historyDTOs
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(file)
    }

    // MARK: - インポート（§13.1 のマージ規則）

    func importData(_ data: Data) async throws {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let file: ExportFile
        do {
            file = try decoder.decode(ExportFile.self, from: data)
        } catch {
            throw ImportError.invalidFormat
        }
        // 旧名（Simple Copy Memo）時代に書き出したファイルも受け入れる
        guard file.format == "tattan-export" || file.format == "simple-copy-memo-export" else {
            throw ImportError.invalidFormat
        }

        // タグ: 名前一致で再利用（find-or-create）
        for dto in file.tags {
            _ = snippets.tag(named: dto.name)
        }

        // スニペット: title + content 完全一致はスキップ（重複防止）
        let existing = snippets.fetchSnippets()
        for dto in file.snippets {
            guard !existing.contains(where: { $0.title == dto.title && $0.content == dto.content }) else {
                continue
            }
            let tagObjects = dto.tags.map { snippets.tag(named: $0) }
            let snippet = snippets.createSnippet(title: dto.title, content: dto.content, tags: tagObjects)
            if let hotkey = dto.hotkey {
                snippet.hotkeyData = hotkey
                snippets.touchUpdated(snippet)
            }
        }

        // 履歴: 元の日時を保持して追加。
        // 重い前処理（ハッシュ・Luhn・サムネイル）は ingest と同じく背景で行い（§1.5）、
        // 上限執行はループ後に 1 回だけ（2026-07-02 レビュー指摘 #7）
        let entries: [HistoryImportEntry] = (file.history ?? []).map { dto in
            let kind = ContentKind(rawValue: dto.kind) ?? .text
            let content = CapturedContent(
                kind: kind,
                plainText: dto.plainText,
                rtfData: dto.rtfBase64.flatMap { Data(base64Encoded: $0) },
                imageData: dto.imageBase64.flatMap { Data(base64Encoded: $0) },
                fileURLs: (dto.filePaths ?? []).map { URL(fileURLWithPath: $0) }
            )
            return HistoryImportEntry(content: content, createdAt: dto.createdAt, copiedAt: dto.copiedAt)
        }
        guard !entries.isEmpty else { return }

        let processed = await Task.detached(priority: .utility) {
            entries.map { (item: ProcessedContent(content: $0.content), entry: $0) }
        }.value
        for (item, entry) in processed {
            history.importItem(item, createdAt: entry.createdAt, copiedAt: entry.copiedAt)
        }
        history.enforceLimit()
    }
}

/// インポート待ちの履歴 1 件（前処理を背景タスクへ渡すための Sendable コンテナ）
private struct HistoryImportEntry: Sendable {
    let content: CapturedContent
    let createdAt: Date
    let copiedAt: Date
}
